pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everything perch knows: config, live Claude Code sessions, open permission
// requests and usage limits. hook/perch-hook feeds it over a Unix socket.
Singleton {
    id: root

    // ---------------------------------------------------------------- config
    readonly property string configPath: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/perch/config.json`
    readonly property var defaults: ({
            position: "top-right",   // top-left top top-right left right bottom-left bottom bottom-right
            marginX: 12,
            marginY: 8,
            screen: "",              // output name, "" = first screen
            scale: 1,
            color: "#e2683c",        // Maple's fur
            hideWhenIdle: true,      // only a small nub while nothing runs
            autoOpenOnPermission: true,
            celebrate: true,         // pop open when a session finishes
            collapseDelay: 1200,     // ms after the cursor leaves
            trackCursor: true,       // eyes follow the cursor everywhere (Hyprland)
            limitWarn: 80,           // % of a usage window that triggers a warning
            askModel: "",            // claude -p --model, "" = your default
            focusCommand: []         // argv; {window} {pid} {cwd} are filled in
        })
    property var cfg: defaults

    FileView {
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.cfg = Object.assign({}, root.defaults, JSON.parse(text()));
            } catch (e) {
                console.warn(`perch: ignoring ${root.configPath}: ${e}`);
                root.cfg = root.defaults;
            }
        }
        onLoadFailed: root.cfg = root.defaults
    }

    // -------------------------------------------------------------- sessions
    // sid -> { sid, name, cwd, state, ts, pid, win, ticker: [...], text }
    property var map: ({})
    property var sessions: []
    // open permission requests, oldest first: { sid, id, tool, full, always, name, sock }
    property var pending: []
    property var limits: ({})
    property real lastActivity: Date.now()

    signal finished(string sid)
    signal permissionAsked
    signal limitWarning(string window, int percent)

    readonly property var stateColours: ({
            idle: "#8b9099",
            thinking: "#8b5cf6",
            working: "#3b9eff",
            waiting: "#f5a524",
            done: "#34d399"
        })

    function publish() {
        sessions = Object.values(map).sort((a, b) => (b.state === "waiting") - (a.state === "waiting") || b.ts - a.ts);
    }

    function handle(sock, line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.ev === "Limits")
            return updateLimits(m);
        if (!m.sid || !/^[A-Za-z0-9_-]{1,128}$/.test(m.sid))
            return;
        lastActivity = Date.now();

        // Anything but these means the terminal moved on: whatever we were
        // still offering for this session has been answered there.
        if (m.ev !== "PermissionRequest" && m.ev !== "Notification")
            cancelPending(p => p.sid === m.sid);

        if (m.ev === "SessionEnd") {
            delete map[m.sid];
            return publish();
        }

        const s = map[m.sid] ?? {
            sid: m.sid,
            ticker: [],
            text: ""
        };
        s.cwd = m.cwd || s.cwd || "";
        s.name = s.cwd.split("/").filter(x => x).pop() || "~";
        s.pid = s.pid || m.pid;
        s.win = m.win || s.win || "";
        s.ts = Date.now();

        const push = line => {
            if (line)
                s.ticker = s.ticker.concat([line]).slice(-6);
        };

        switch (m.ev) {
        case "SessionStart":
            s.state = "idle";
            break;
        case "UserPromptSubmit":
            s.state = "thinking";
            push(`› ${m.target}`);
            break;
        case "PreToolUse":
            s.state = "working";
            push(`${m.tool} ${m.target}`.trim());
            break;
        case "Notification":
            if (/waiting for your input/i.test(m.text ?? ""))
                s.state = "idle";
            break;
        case "Stop":
            s.state = "done";
            s.text = m.text ?? "";
            root.finished(m.sid);
            break;
        case "PermissionRequest":
            if (!m.id || !/^[A-Za-z0-9_-]{1,128}$/.test(m.id))
                return;
            s.state = "waiting";
            pending = pending.concat([{
                    sid: m.sid,
                    id: m.id,
                    tool: m.tool,
                    full: m.full || m.target,
                    always: !!m.always,
                    rule: m.rule ?? "",
                    name: s.name,
                    sock: sock
                }]);
            sock.pendingId = m.id;
            root.permissionAsked();
            break;
        }
        map[m.sid] = s;
        publish();
    }

    // Answer the hook waiting on this request. behavior: allow | deny
    function decide(id, behavior, always) {
        const req = pending.find(p => p.id === id);
        if (!req)
            return;
        pending = pending.filter(p => p !== req);
        if (req.sock?.connected) {
            req.sock.write(JSON.stringify({
                behavior: behavior,
                always: !!always
            }) + "\n");
            req.sock.flush();
        }
        const s = map[req.sid];
        if (s) {
            s.state = behavior === "allow" ? "working" : "thinking";
            publish();
        }
    }

    // Drop requests without answering: the hook sees EOF and prints nothing,
    // which leaves the decision to the terminal.
    function cancelPending(match) {
        const gone = pending.filter(match);
        if (!gone.length)
            return;
        pending = pending.filter(p => !gone.includes(p));
        for (const p of gone)
            if (p.sock?.connected)
                p.sock.connected = false;
    }

    function socketClosed(sock) {
        // the hook gave up or Claude Code killed it after a terminal answer
        if (sock.pendingId)
            pending = pending.filter(p => p.id !== sock.pendingId);
    }

    function updateLimits(m) {
        const next = {
            model: m.model || limits.model || ""
        };
        for (const w of ["five_hour", "seven_day"]) {
            const r = m[w];
            const pct = r ? Math.round(r.used_percentage ?? r.utilization ?? r.used ?? -1) : -1;
            next[w] = pct >= 0 ? {
                used: pct,
                resets: r.resets_at ?? 0
            } : limits[w];
            const was = limits[w]?.used ?? 0;
            if (pct >= cfg.limitWarn && was < cfg.limitWarn)
                root.limitWarning(w, pct);
        }
        limits = next;
    }

    SocketServer {
        active: true
        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/perch.sock`

        handler: Socket {
            id: conn

            property string pendingId

            onConnectedChanged: if (!connected)
                root.socketClosed(conn)

            parser: SplitParser {
                onRead: data => root.handle(conn, data)
            }
        }
    }

    // -------------------------------------------------------------- upkeep
    // A killed terminal never sends SessionEnd; check the pids instead.
    Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: {
            const now = Date.now();
            let changed = false;
            for (const s of Object.values(root.map)) {
                // "done" settles back to idle; long-quiet sessions are dropped
                if (s.state === "done" && now - s.ts > 20000) {
                    s.state = "idle";
                    changed = true;
                }
                if (s.state === "working" && now - s.ts > 180000) {
                    s.state = "idle";
                    changed = true;
                }
            }
            if (changed)
                root.publish();
            const pids = Object.values(root.map).map(s => String(s.pid)).filter(p => /^\d+$/.test(p));
            if (pids.length && !reaper.running) {
                reaper.command = ["sh", "-c", 'for p; do [ -d "/proc/$p" ] || echo "$p"; done', "sh"].concat(pids);
                reaper.running = true;
            }
        }
    }

    Process {
        id: reaper

        stdout: SplitParser {
            onRead: pid => {
                for (const s of Object.values(root.map))
                    if (String(s.pid) === pid.trim()) {
                        root.cancelPending(p => p.sid === s.sid);
                        delete root.map[s.sid];
                    }
                root.publish();
            }
        }
    }

    // ---------------------------------------------------------------- focus
    function focus(sid) {
        const s = map[sid];
        if (!s)
            return;
        let cmd = cfg.focusCommand?.length ? cfg.focusCommand : (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && s.win ? ["hyprctl", "dispatch", "focuswindow", "address:{window}"] : []);
        if (!cmd.length)
            return;
        Quickshell.execDetached(cmd.map(a => String(a).replace("{window}", s.win ?? "").replace("{pid}", s.pid ?? "").replace("{cwd}", s.cwd ?? "")));
    }

    // ------------------------------------------------------------------ ask
    // Runs on the user's own Claude plan through the CLI: no API key.
    property bool asking: false
    property string answer: ""
    property string askError: ""

    function ask(prompt, files) {
        if (!prompt.trim() || asking)
            return;
        const dirs = [...new Set((files ?? []).map(f => f.replace(/\/[^/]*$/, "") || "/"))];
        const text = files?.length ? `Files:\n${files.join("\n")}\n\n${prompt}` : prompt;
        let cmd = ["claude", "-p", text];
        if (cfg.askModel)
            cmd = cmd.concat(["--model", cfg.askModel]);
        for (const d of dirs)
            cmd = cmd.concat(["--add-dir", d]);
        if (files?.length)
            cmd = cmd.concat(["--allowedTools", "Read"]);
        answer = "";
        askError = "";
        asking = true;
        askProc.command = cmd;
        askProc.workingDirectory = sessions[0]?.cwd || Quickshell.env("HOME");
        askProc.running = true;
    }

    function cancelAsk() {
        askProc.running = false;
        asking = false;
    }

    Process {
        id: askProc

        stdout: StdioCollector {
            onStreamFinished: root.answer = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim())
                root.askError = text.trim().split("\n").pop()
        }
        onExited: code => {
            root.asking = false;
            if (code !== 0 && !root.askError)
                root.askError = `claude exited with ${code}`;
        }
    }

    // ------------------------------------------------------------------ ipc
    signal toggleRequested
    signal askRequested

    IpcHandler {
        target: "perch"

        function toggle(): void {
            root.toggleRequested();
        }
        function ask(): void {
            root.askRequested();
        }
        function allow(): void {
            if (root.pending.length)
                root.decide(root.pending[0].id, "allow", false);
        }
        function deny(): void {
            if (root.pending.length)
                root.decide(root.pending[0].id, "deny", false);
        }
        function state(): string {
            return JSON.stringify({
                sessions: root.sessions,
                pending: root.pending.map(p => ({
                            id: p.id,
                            tool: p.tool,
                            name: p.name
                        }))
            });
        }
    }
}
