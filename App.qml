pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Everything emba knows: config, live Claude Code sessions, open permission
// requests and usage limits. hook/emba-hook feeds it over a Unix socket.
Singleton {
    id: root

    // ---------------------------------------------------------------- config
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (Qt.platform.os === "windows" ? Quickshell.env("APPDATA") : Quickshell.env("HOME") + "/.config")
    readonly property string configPath: `${configDir}/emba/config.json`
    readonly property var defaults: ({
            position: "top-right",   // top-left top top-right left right bottom-left bottom bottom-right
            marginX: 0,              // 0 = flush with the screen edge, notch style
            marginY: 0,
            screen: "",              // output name, "" = first screen
            scale: 1,
            color: "#e2683c",        // Emba's fur
            hideWhenIdle: true,      // only a small nub while nothing runs
            danceToMusic: true,      // pop out and dance while music plays
            sounds: false,           // little sound effects (off until the set is chosen)
            soundVolume: 0.5,
            autoOpenOnPermission: true,
            celebrate: true,         // pop open when a session finishes
            collapseDelay: 1200,     // ms after the cursor leaves
            trackCursor: true,       // eyes follow the cursor everywhere (Hyprland)
            limitWarn: 80,           // % of a usage window that triggers a warning
            askWith: "auto",         // claude gemini opencode codex ollama; auto = first installed
            askModel: "",            // model for the ask box, "" = the tool's default
            focusCommand: [],        // argv; {window} {pid} {cwd} are filled in
            theme: "auto",           // auto caelestia pywal custom default
            voice: false,            // talk to Emba (needs: pip install faster-whisper sounddevice piper-tts)
            voiceShake: true,        // shake the cursor to start listening
            voiceWake: false,        // "Hey Emba": keeps the microphone open
            voiceReply: true,        // read answers aloud
            voiceModel: "base",      // whisper size: tiny base small medium
            voiceName: "en_US-amy-medium", // any Piper voice
            wakeWords: "emba,ember,amba",
            plugins: [],             // names of enabled plugins
            pet: true                // Emba gets hungry, sleepy and lonely, and likes attention
        })
    property var cfg: defaults
    // what the user actually wrote, so saving keeps keys we do not know
    property var userCfg: ({})

    FileView {
        id: configFile

        printErrors: false
        path: root.configPath
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.userCfg = JSON.parse(text());
                root.cfg = Object.assign({}, root.defaults, root.userCfg);
            } catch (e) {
                console.warn(`emba: ignoring ${root.configPath}: ${e}`);
                root.cfg = root.defaults;
            }
        }
        onLoadFailed: root.cfg = root.defaults
    }

    // Change settings: merged into the user's file and written back. The
    // watcher above then reloads it, so the whole app follows.
    function setCfg(patch) {
        const next = Object.assign({}, userCfg, patch);
        userCfg = next;
        cfg = Object.assign({}, defaults, next);
        mkdirProc.text = JSON.stringify(next, null, 2) + "\n";
        mkdirProc.running = true;
    }

    Process {
        id: mkdirProc

        property string text

        command: ["mkdir", "-p", root.configPath.replace(/\/[^/]*$/, "")]
        onExited: configFile.setText(text)
    }

    // ------------------------------------------------------------ app control
    // `bin/emba` does the real work (hooks, autostart); settings call it.
    readonly property string emba: `${Quickshell.shellDir}/bin/emba`
    property var status: ({})
    readonly property string python: Qt.platform.os === "windows" ? "python" : "python3"
    // any agent hooked up yet? (undefined until the first status arrives)
    readonly property var connected: status.agents ? Object.values(status.agents).some(a => a.connected) : undefined
    property bool busy: false
    property bool settingsOpen: false

    function refreshStatus() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function run(args) {
        if (busy)
            return;
        busy = true;
        actionProc.command = [python, emba].concat(args);
        actionProc.running = true;
    }

    Process {
        id: statusProc

        command: [root.python, root.emba, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Process {
        id: actionProc

        onExited: {
            root.busy = false;
            root.refreshStatus();
        }
    }

    Component.onCompleted: refreshStatus()

    // -------------------------------------------------------------- sessions
    // sid -> { sid, name, cwd, state, ts, pid, win, ticker: [...], text }
    property var map: ({})
    property var sessions: []
    // open permission requests, oldest first: { sid, id, tool, full, always, name, sock }
    property var pending: []
    property var limits: ({})
    // the song playing now ("" when none); set by the host (MPRIS on Linux)
    property string music: ""
    property real lastActivity: Date.now()

    signal finished(string sid)
    signal permissionAsked
    signal limitWarning(string window, int percent)

    // one colour per agent, so their sessions are told apart at a glance
    readonly property var agentColours: ({
            claude: "#f2c38f",   // sand: Emba's own fur is already orange
            codex: "#3ecf8e",
            gemini: "#5b9cf6",
            opencode: "#c084fc"
        })
    function agentColour(agent) {
        return agentColours[agent ?? "claude"] ?? "#9ca3af";
    }

    readonly property var stateColours: ({
            idle: Theme.dim,
            thinking: Theme.thinking,
            working: Theme.working,
            waiting: Theme.warn,
            done: Theme.ok
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
        if (m.ev === "ipc") {
            sock.write(JSON.stringify({
                reply: String(command(m.cmd, m.args))
            }) + "\n");
            sock.flush();
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
        // a session started in the home folder is "~", not the user's name
        const home = Quickshell.env("HOME") || Quickshell.env("USERPROFILE") || "";
        s.name = s.cwd.replace(/[\\/]+$/, "") === home.replace(/[\\/]+$/, "") ? "~" : s.cwd.split(/[\\/]/).filter(x => x).pop() || "~";
        s.agent = m.agent || s.agent || "claude";
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
            s.started = s.started || Date.now();
            root.fire("session_start", {
                name: s.name,
                cwd: s.cwd,
                agent: s.agent
            });
            break;
        case "UserPromptSubmit":
            s.state = "thinking";
            push(`› ${m.target}`);
            break;
        case "PreToolUse":
            s.state = "working";
            push(`${m.tool} ${m.target}`.trim());
            break;
        case "Attention":
            // the agent asked in its own terminal and cannot be answered from here
            s.state = "waiting";
            s.text = m.text ?? "";
            push(`needs you: ${m.text ?? ""}`);
            root.fire("permission", {
                name: s.name,
                cwd: s.cwd,
                agent: s.agent,
                tool: "",
                command: m.text ?? ""
            });
            break;
        case "Notification":
            if (/waiting for your input/i.test(m.text ?? ""))
                s.state = "idle";
            break;
        case "Stop":
            s.state = "done";
            s.text = m.text ?? "";
            root.finished(m.sid);
            root.fire("finished", {
                name: s.name,
                cwd: s.cwd,
                agent: s.agent,
                text: s.text || "Finished."
            });
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
                    // a question for you rather than a permission: [{question, header, options, multi}]
                    questions: Array.isArray(m.questions) ? m.questions.slice(0, 4) : [],
                    answerable: !!m.answerable,
                    name: s.name,
                    agent: s.agent,
                    sock: sock
                }]);
            sock.pendingId = m.id;
            root.permissionAsked();
            root.fire("permission", {
                name: s.name,
                cwd: s.cwd,
                agent: s.agent,
                tool: m.tool,
                command: m.full || m.target
            });
            break;
        }
        map[m.sid] = s;
        publish();
    }

    // Answer the hook waiting on this request. behavior: allow | deny
    // answers: {question text: chosen label(s)}, for a question rather than a permission
    function decide(id, behavior, always, answers) {
        const req = pending.find(p => p.id === id);
        if (!req)
            return;
        pending = pending.filter(p => p !== req);
        if (req.sock?.connected) {
            req.sock.write(JSON.stringify({
                behavior: behavior,
                always: !!always,
                answers: answers ?? undefined
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

    // m.windows: [{ label, used (0-100), resets (unix s) }] for one agent;
    // Claude's statusline sends five_hour / seven_day instead
    function updateLimits(m) {
        const agent = /^[a-z]{1,20}$/.test(m.agent ?? "") ? m.agent : "claude";
        const windows = (m.windows ?? [["Right now", m.five_hour], ["This week", m.seven_day]].filter(x => x[1]).map(([label, r]) => ({
                        label: label,
                        used: r.used_percentage ?? r.utilization ?? r.used,
                        resets: r.resets_at ?? 0
                    }))).filter(w => typeof w.used === "number").map(w => ({
                    label: String(w.label),
                    used: Math.round(w.used),
                    resets: Number(w.resets) || 0
                }));
        const old = limits[agent] ?? {};
        for (const w of windows) {
            const was = (old.windows ?? []).find(o => o.label === w.label)?.used ?? 0;
            if (w.used >= cfg.limitWarn && was < cfg.limitWarn) {
                root.limitWarning(`${agent} ${w.label}`, w.used);
                root.fire("limit", {
                    agent: agent,
                    window: w.label,
                    percent: w.used
                });
            }
        }
        const next = Object.assign({}, limits);
        next[agent] = {
            model: m.model || old.model || "",
            windows: windows.length ? windows : (old.windows ?? [])
        };
        limits = next;
    }
    readonly property int maxUsed: Object.values(limits).reduce((a, l) => Math.max(a, ...l.windows.map(w => w.used)), 0)
    // "claude 42% · codex 85%": the fullest window of each agent
    readonly property string usageLine: Object.keys(limits).filter(k => limits[k].windows.length).map(k => `${k} ${Math.max(...limits[k].windows.map(w => w.used))}%`).join(" · ")

    // Quickshell ignores Qt.quit(), so there Emba ends its own process; the Qt
    // host (no processId) quits normally.
    function leave() {
        if (typeof Quickshell.processId === "number" && Qt.platform.os !== "windows")
            Quickshell.execDetached(["kill", String(Quickshell.processId)]);
        else
            Qt.quit();
    }

    // the desktop host passes its own address (named pipe on Windows)
    readonly property string socketPath: Quickshell.env("EMBA_SOCKET") || `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/emba.sock`
    property bool listening: false

    // One Emba at a time: if another one already answers on the socket, this
    // one bows out instead of stealing the socket from under it. Unless the one
    // answering is this same process: Quickshell reloading Emba's files keeps
    // the old copy running until the new one is up, and that is not a rival.
    readonly property string myPid: typeof Quickshell.processId === "number" ? String(Quickshell.processId) : ""
    Socket {
        id: probe

        path: root.socketPath
        onConnectedChanged: if (connected) {
            write(JSON.stringify({
                ev: "ipc",
                cmd: "pid"
            }) + "\n");
            flush();
            rivalTimer.restart();
        }
        parser: SplitParser {
            onRead: line => {
                let pid = "";
                try {
                    pid = JSON.parse(line).reply ?? "";
                } catch (e) {}
                rivalTimer.stop();
                probe.connected = false;
                if (root.myPid && pid === root.myPid) {
                    root.listening = true;  // ourselves, from before a reload: take over
                } else {
                    console.log("emba: already running, leaving");
                    root.leave();
                }
            }
        }
        onError: root.listening = true  // nobody there: our turn
        Component.onCompleted: connected = true
    }
    // an older Emba that doesn't answer "pid" is still another Emba
    Timer {
        id: rivalTimer

        interval: 1000
        onTriggered: {
            console.log("emba: already running, leaving");
            root.leave();
        }
    }
    Timer {
        interval: 500
        running: !root.listening
        onTriggered: if (!probe.connected)
            root.listening = true
    }

    SocketServer {
        active: root.listening
        path: root.socketPath

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
        let cmd = cfg.focusCommand?.length ? cfg.focusCommand : (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && s.win ? [python, emba, "focus", "{window}"] : []);
        if (!cmd.length)
            return;
        Quickshell.execDetached(cmd.map(a => String(a).replace("{window}", s.win ?? "").replace("{pid}", s.pid ?? "").replace("{cwd}", s.cwd ?? "")));
    }

    // ------------------------------------------------------------------ ask
    // Runs through a CLI the user already has, on their own account: no API
    // keys here. Free choices: gemini (free tier), opencode (free models),
    // ollama (local).
    property bool asking: false
    property string answer: ""
    property string partial: ""   // the answer so far, while it streams in
    property string rawOut: ""    // everything the tool printed, for tools that don't stream JSON
    property string askError: ""
    property string errText: ""
    property var askCode: null

    readonly property var askTools: ["claude", "gemini", "opencode", "codex", "ollama"]
    readonly property string askTool: {
        const want = cfg.askWith ?? "auto";
        const have = status.ask ?? [];
        if (want !== "auto")
            return want;
        return askTools.find(t => have.includes(t)) ?? "claude";
    }
    readonly property string askLabel: ({
            claude: "Claude",
            gemini: "Gemini",
            opencode: "opencode",
            codex: "Codex",
            ollama: "Ollama"
        })[askTool] ?? askTool

    function askCommand(tool, text, files) {
        const m = cfg.askModel;
        const dirs = [...new Set((files ?? []).map(f => f.replace(/[\\/][^\\/]*$/, "") || "/"))];
        switch (tool) {
        case "gemini":
            return ["gemini", "-p", text].concat(m ? ["-m", m] : [], dirs.length ? ["--include-directories", dirs.join(",")] : []);
        case "opencode":
            return ["opencode", "run", text].concat(m ? ["-m", m] : []);
        case "codex":
            return ["codex", "exec", "--skip-git-repo-check", text].concat(m ? ["-m", m] : []);
        case "ollama":
            return ["ollama", "run", m || "llama3.2", text];
        default:
            return ["claude", "-p", text].concat(m ? ["--model", m] : [], [].concat(...dirs.map(d => ["--add-dir", d])), files?.length ? ["--allowedTools", "Read"] : []);
        }
    }

    // The conversation so far, so a follow-up continues it, and so it can be
    // picked up in the agent's own terminal. { tool, id, cwd, turns: [{q, a}] }
    property var chat: null
    property bool followUp: false
    property real answeredAt: 0
    readonly property string modelLabel: limits.claude?.model ?? ""
    readonly property bool canContinue: !!chat && chat.tool !== "ollama" && (chat.tool !== "claude" || !!chat.id)

    // a fresh conversation: the next question starts over
    function newChat() {
        cancelAsk();
        chat = null;
        answer = "";
        askError = "";
    }

    function ask(prompt, files) {
        if (!prompt.trim() || asking)
            return;
        // in a conversation, every question follows on from the last answer (same agent, same chat)
        const cont = !!chat && chat.tool === askTool && (followUp || chat.turns.length > 0) && !files?.length;
        followUp = false;
        if (!cont)
            chat = {
                tool: askTool,
                id: "",
                cwd: files?.length === 1 ? files[0].replace(/[\\/][^\\/]*$/, "") : (sessions[0]?.cwd || Quickshell.env("HOME") || Quickshell.env("USERPROFILE")),
                turns: []
            };
        let text = files?.length ? `Files:\n${files.join("\n")}\n\n${prompt}` : prompt;
        let cmd;
        if (cont && askTool === "claude" && chat.id)
            cmd = askCommand("claude", text, files).concat(["--resume", chat.id]);
        else if (cont && askTool === "opencode")
            cmd = askCommand("opencode", text, files).concat(["--continue"]);
        else {
            // tools without a resume flag get the conversation so far as context
            if (cont && chat.turns.length)
                text = chat.turns.map(t => `Me: ${t.q}\nYou: ${t.a}`).join("\n\n") + `\n\nMe: ${text}`;
            cmd = askCommand(askTool, text, files);
        }
        if (askTool === "claude")
            // streamed: the answer appears as it is written; the last line has the session id
            cmd = cmd.concat(["--output-format", "stream-json", "--verbose", "--include-partial-messages"]);
        chat.pending = prompt;
        chat = Object.assign({}, chat);  // show the question at once
        answer = "";
        partial = "";
        rawOut = "";
        askError = "";
        errText = "";
        askCode = null;
        asking = true;
        askProc.command = cmd;
        askProc.workingDirectory = chat.cwd;
        askProc.running = true;
    }

    // one line of output while the answer is being written
    function gotLine(line) {
        if (chat?.tool !== "claude") {
            rawOut += line + "\n";
            partial = rawOut.trim();
            return;
        }
        let j;
        try {
            j = JSON.parse(line);
        } catch (e) {
            return;
        }
        const d = j.event?.delta;
        if (j.type === "stream_event" && d?.type === "text_delta")
            partial += d.text;
        else if (j.type === "rate_limit_event" && j.rate_limit_info?.unifiedWindows) {
            // the answer also says how much of each usage window is used
            const w = j.rate_limit_info.unifiedWindows;
            updateLimits({
                agent: "claude",
                windows: [["Right now", w.five_hour], ["This week", w.seven_day]].filter(x => x[1]?.utilization !== undefined).map(([label, x]) => ({
                            label: label,
                            used: x.utilization * 100,
                            resets: x.resetsAt ?? 0
                        }))
            });
        } else if (j.result !== undefined && j.session_id) {
            chat.id = j.session_id;
            rawOut = String(j.result);
            if (j.is_error)
                askError = rawOut.trim() || "Claude returned an error";
        }
    }

    function gotAnswer() {
        if (cancelled) {  // stopped: the half-written answer is dropped with its question
            cancelled = false;
            if (chat) {
                chat.pending = "";
                chat = Object.assign({}, chat);
            }
            partial = "";
            return;
        }
        // Claude: what was streamed is the answer (its final "result" can carry CLI notices)
        const text = (chat?.tool === "claude" ? partial || rawOut : rawOut).trim();
        if (chat && text && !askError) {
            chat.turns = chat.turns.concat([{
                    q: chat.pending,
                    a: text
                }]).slice(-20);
        }
        if (chat) {
            chat.pending = "";
            chat = Object.assign({}, chat);  // notify bindings
        }
        answer = text;
        partial = "";
        answeredAt = Date.now();
    }

    // Open the agent's own terminal UI on this same conversation.
    function continueInTerminal() {
        if (!canContinue)
            return;
        const argv = ({
                claude: ["claude", "--resume", chat.id],
                codex: ["codex", "resume", "--last"],
                opencode: ["opencode", "--continue"],
                gemini: ["gemini", "--resume", "latest"]
            })[chat.tool];
        if (argv)
            run(["terminal", chat.cwd].concat(argv));
    }

    property bool cancelled: false
    function cancelAsk() {
        if (asking)
            cancelled = true;
        askProc.running = false;
        asking = false;
    }

    Process {
        id: askProc

        // runs started by Emba are not sessions to watch
        environment: ({
                EMBA_QUIET: "1"
            })

        stdout: SplitParser {
            onRead: line => root.gotLine(line)
        }
        // stderr is only an error if the tool failed; many print progress there
        stderr: StdioCollector {
            onStreamFinished: {
                root.errText = text.trim().split("\n").pop() ?? "";
                if (root.askCode !== null && root.askCode !== 0 && root.errText)
                    root.askError = root.errText;
            }
        }
        onExited: code => {
            root.askCode = code;
            root.gotAnswer();
            root.asking = false;
            if (code !== 0)
                root.askError = root.errText || `${root.askTool} exited with ${code}`;
        }
    }

    // ---------------------------------------------------------------- look
    // Drag a rectangle on screen; the picture goes to the ask box.
    signal captured(string path)

    function look() {
        if (!captureProc.running)
            captureProc.running = true;
    }

    Process {
        id: captureProc

        command: [root.status.python || root.python, root.emba, "capture"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim())
                root.captured(text.trim())
        }
    }

    // ---------------------------------------------------------------- voice
    // All local (voice/voice.py): Whisper hears, Piper speaks. Voice can
    // point at Allow or Deny, but only a click ever answers a permission.
    readonly property string voiceScript: `${Quickshell.shellDir}/voice/voice.py`
    // for agents Emba doesn't know: their hooks can call this
    readonly property string hookPath: `${Quickshell.shellDir}/hook/emba-hook`
    property string voiceState: ""    // listening thinking speaking ""
    property real voiceLevel: 0       // mic level while listening, loudness while speaking
    property string heard: ""
    property string voiceHint: ""     // allow | deny, for the approval view to highlight
    property string voiceError: ""
    property bool speakAnswer: false

    signal listenRequested

    function listen() {
        if (!cfg.voice || listenProc.running)
            return;
        sayProc.running = false;
        heard = "";
        voiceError = "";
        voiceHint = "";
        // talking right after an answer continues that conversation
        followUp = !!chat && Date.now() - answeredAt < 300000;
        listenProc.command = [status.python || python, voiceScript, "listen", "--model", cfg.voiceModel];
        listenProc.running = true;
        root.listenRequested();
    }

    function say(text) {
        // talking back is its own switch: it works with or without listening
        if (!status.voice || !cfg.voiceReply || !text.trim())
            return;
        sayProc.running = false;
        sayProc.command = [status.python || python, voiceScript, "say", text.slice(0, 1200), "--voice", cfg.voiceName];
        sayProc.running = true;
    }

    function onVoiceLine(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.state)
            voiceState = m.state === "done" || m.state === "ready" ? "" : m.state;
        if (m.level !== undefined)
            voiceLevel = m.level;
        if (m.error) {
            voiceError = m.error;
            voiceState = "";
        }
        if (m.wake)
            listen();
        if (m.text !== undefined)
            gotSpeech(m.text);
    }

    // Short spoken commands for Emba itself; anything else goes to the agent.
    // Only short phrases count, so "how do I fix the play button" is a question.
    readonly property var voiceCommands: [
        [/\b(eat|food|feed|snack|bamboo|hungry)\b/, () => {
                root.careRequested();
                Pet.feed();
            }, "Yum!"],
        [/\b(play|ball|fetch)\b/, () => {
                root.careRequested();
                Pet.play();
            }, "Catch!"],
        [/\b(wake up|good morning)\b/, () => {
                if (Pet.napping)
                    Pet.nap();
            }, "I'm up!"],
        [/\b(sleep|nap|bed|rest|good night)\b/, () => {
                if (!Pet.napping)
                    Pet.nap();
            }, "Night night."],
        [/\b(good (boy|girl|panda)|love you|cute|pet)\b/, () => Pet.pet(), "Hehe."],
        [/\b(look|screen|screenshot)\b/, () => root.look(), ""],
        [/\b(settings|preferences)\b/, () => root.command("settings"), ""],
        [/\b(hide|go away|close)\b/, () => root.toggleRequested(), ""]
    ]

    function voiceCommand(text) {
        const t = text.toLowerCase().replace(/^\W*(hey|hi|ok|okay)?\W*(emba|ember|amba)\b\W*/, "");
        if (t.split(/\s+/).length > 5)
            return false;
        for (const [re, act, reply] of voiceCommands)
            if (re.test(t)) {
                act();
                if (reply)
                    say(reply);
                return true;
            }
        return false;
    }

    function gotSpeech(text) {
        heard = text;
        voiceState = "";
        if (!text)
            return;
        // with a permission open, "allow"/"deny" only points at the button
        if (pending.length) {
            if (/^\s*(allow|yes|approve|okay|ok|go ahead|do it)\b/i.test(text))
                voiceHint = "allow";
            else if (/^\s*(deny|no|don't|stop|cancel|reject)\b/i.test(text))
                voiceHint = "deny";
            return;
        }
        if (voiceCommand(text))
            return;
        speakAnswer = true;
        ask(text, []);
    }

    onAnswerChanged: if (speakAnswer && answer) {
        speakAnswer = false;
        say(answer);
    }
    onAskErrorChanged: if (askError)
        speakAnswer = false

    Process {
        id: listenProc

        stdout: SplitParser {
            onRead: line => root.onVoiceLine(line)
        }
        onExited: if (root.voiceState === "listening" || root.voiceState === "thinking")
            root.voiceState = ""
    }

    Process {
        id: sayProc

        stdout: SplitParser {
            onRead: line => root.onVoiceLine(line)
        }
        onExited: {
            if (root.voiceState === "speaking")
                root.voiceState = "";
            root.voiceLevel = 0;
        }
    }

    // "Hey Emba": opt-in, the microphone stays open while this runs
    Process {
        running: !!root.cfg.voice && !!root.cfg.voiceWake && !!root.status.voice
        command: [root.status.python || root.python, root.voiceScript, "wake", "--words", root.cfg.wakeWords]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes('"wake"'))
                    root.listen();
            }
        }
    }

    // -------------------------------------------------------------- plugins
    // Folders with a plugin.json (see plugins/ and `emba plugins new`).
    // Commands are argv lists: placeholders fill whole arguments and nothing
    // goes through a shell, so agent output cannot inject commands.
    readonly property var plugins: (status.plugins ?? []).filter(p => !p.error && (cfg.plugins ?? []).includes(p.id))
    readonly property string osKey: Qt.platform.os === "osx" ? "darwin" : Qt.platform.os

    function pluginArgv(spec, vars) {
        const argv = Array.isArray(spec) ? spec : spec?.[osKey];
        if (!Array.isArray(argv) || !argv.length)
            return null;
        return argv.map(a => String(a).replace(/\{(\w+)\}/g, (all, k) => k in vars ? String(vars[k] ?? "") : all));
    }

    function fire(event, vars) {
        for (const p of plugins) {
            const argv = pluginArgv(p.events?.[event], Object.assign({
                plugin: p.dir
            }, vars));
            if (argv)
                Quickshell.execDetached(argv);
        }
    }

    // buttons the enabled plugins add for a session
    function actionsFor(sid) {
        const s = map[sid];
        if (!s)
            return [];
        // no Array.flatMap in this JS engine
        return [].concat(...plugins.map(p => (p.actions ?? []).map(a => ({
                        label: a.label,
                        argv: pluginArgv(a.run, {
                            plugin: p.dir,
                            cwd: s.cwd,
                            name: s.name,
                            agent: s.agent
                        })
                    })))).filter(a => a.argv);
    }

    // somewhere for QML plugins to keep things between openings: pluginData.<plugin id>
    property var pluginData: ({})
    readonly property var pluginViews: plugins.filter(p => p.qml).map(p => (p.dir.startsWith("/") ? "file://" : "file:///") + `${p.dir}/${p.qml}`.replace(/\\/g, "/"))

    // ------------------------------------------------------------------ ipc
    signal toggleRequested
    signal askRequested
    signal careRequested
    signal openRequested(bool open)
    signal answerRequested
    signal snapshotRequested(string path)

    // One entry point for every remote command, whether it arrives over the
    // socket (the `emba` CLI, any OS) or Quickshell's IPC (keybinds on Linux).
    function command(cmd, args) {
        switch (cmd) {
        case "open":
        case "close":
            root.openRequested(cmd === "open");
            return "ok";
        case "toggle":
            root.toggleRequested();
            return "ok";
        case "ask":
            // `emba ask` opens the box; `emba ask some question` asks it right away
            if (args?.length) {
                root.ask(args.join(" "), []);
                root.answerRequested();
            } else
                root.askRequested();
            return "ok";
        case "followup":
            root.followUp = true;
            root.ask((args ?? []).join(" "), []);
            root.answerRequested();
            return "ok";
        case "continue":
            root.continueInTerminal();
            return root.canContinue ? "ok" : "nothing to continue";
        case "settings":
            root.settingsOpen = true;
            root.refreshStatus();
            return "ok";
        case "answer": {
            // emba answer LABEL: answers every open question of the first request with LABEL
            const q = root.pending[0];
            if (!q?.questions?.length)
                return "no question is waiting";
            if (!q.answerable)
                return "answer it in the agent's terminal";
            const label = (args ?? []).join(" ");
            const a = {};
            for (const x of q.questions)
                a[x.question] = label;
            root.decide(q.id, "allow", false, a);
            return "ok";
        }
        case "allow":
        case "deny":
            if (!root.pending.length)
                return "nothing is waiting";
            root.decide(root.pending[0].id, cmd, false);
            return "ok";
        case "set":
            {
                const [key, value] = args ?? [];
                if (!(key in root.defaults))
                    return `unknown setting: ${key}`;
                let v = value;
                try {
                    v = JSON.parse(value);
                } catch (e) {}
                root.setCfg({
                    [key]: v
                });
                return "ok";
            }
        case "pid":
            return root.myPid;
        case "state":
            return JSON.stringify({
                sessions: root.sessions,
                limits: root.limits,
                pending: root.pending.map(p => ({
                            id: p.id,
                            tool: p.tool,
                            name: p.name
                        }))
            });
        case "look":
            root.look();
            return "ok";
        case "listen":
            if (!root.cfg.voice)
                return "voice is off: turn it on in emba settings";
            root.listen();
            return "ok";
        case "say":
            root.say((args ?? []).join(" "));
            return "ok";
        case "care":
            root.careRequested();
            return "ok";
        case "feed":
            Pet.feed();
            root.careRequested();
            return "ok";
        case "play":
            Pet.play();
            root.careRequested();
            return "ok";
        case "nap":
            Pet.nap();
            return "ok";
        case "pet":
            Pet.pet();
            return "ok";
        case "snapshot":
            // render the island to a PNG (used to check how it looks on other systems)
            root.snapshotRequested(String((args ?? [])[0] ?? ""));
            return "ok";
        case "quit":
            Qt.callLater(root.leave);
            return "ok";
        }
        return `unknown command: ${cmd}`;
    }

    IpcHandler {
        target: "emba"

        function toggle(): string {
            return root.command("toggle");
        }
        function settings(): string {
            return root.command("settings");
        }
        // emba set position top-left · emba set scale 1.2 · emba set celebrate false
        function set(key: string, value: string): string {
            return root.command("set", [key, value]);
        }
        function ask(): string {
            return root.command("ask");
        }
        function allow(): string {
            return root.command("allow");
        }
        function deny(): string {
            return root.command("deny");
        }
        function state(): string {
            return root.command("state");
        }
    }
}
