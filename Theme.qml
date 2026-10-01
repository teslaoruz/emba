pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours, borrowed from whatever themes the rest of the desktop.
//
// config "theme": "auto" (default) tries, in order:
//   custom    ~/.config/emba/theme.json, our own keys (point matugen/wallust here)
//   caelestia ~/.local/state/caelestia/scheme.json
//   pywal     ~/.cache/wal/colors.json
//   default   the built-in dark palette
// or name one of them to force it. Files are re-read every few seconds, so a
// wallpaper or scheme change shows up without a restart.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`
    readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`

    readonly property var fallback: ({
            base: "#0d0d10",
            surface: "#16171b",
            surfaceHigh: "#24262c",
            text: "#e8e9ec",
            dim: "#8b9099",
            faint: "#5f646d",
            border: "#2a2c33",
            primary: "#f5f6f8",
            onPrimary: "#0b0c0e",
            error: "#f4505e",
            ok: "#34d399",
            warn: "#f5a524",
            thinking: "#8b5cf6",
            working: "#3b9eff",
            limit: "#fb923c"
        })

    readonly property string want: App.cfg.theme ?? "auto"
    property var custom: null
    property var caelestia: null
    property var pywal: null

    readonly property string source: {
        for (const s of ["custom", "caelestia", "pywal"])
            if ((want === "auto" || want === s) && root[s])
                return s;
        return "default";
    }
    readonly property var palette: Object.assign({}, fallback, source === "default" ? {} : root[source])

    readonly property color base: palette.base
    readonly property color surface: palette.surface
    readonly property color surfaceHigh: palette.surfaceHigh
    readonly property color text: palette.text
    readonly property color dim: palette.dim
    readonly property color faint: palette.faint
    readonly property color border: palette.border
    readonly property color primary: palette.primary
    readonly property color onPrimary: palette.onPrimary
    readonly property color error: palette.error
    readonly property color ok: palette.ok
    readonly property color warn: palette.warn
    readonly property color thinking: palette.thinking
    readonly property color working: palette.working
    readonly property color limit: palette.limit

    function hex(v) {
        return typeof v === "string" && /^#?[0-9a-fA-F]{6,8}$/.test(v) ? (v.startsWith("#") ? v : `#${v}`) : undefined;
    }

    // drop keys we could not parse so the fallback fills them in
    function clean(o) {
        const out = {};
        for (const k in o)
            if (hex(o[k]))
                out[k] = hex(o[k]);
        return out;
    }

    function fromCaelestia(j) {
        const c = j.colours ?? {};
        return clean({
            base: c.surface,
            surface: c.surfaceContainer,
            surfaceHigh: c.surfaceContainerHigh,
            text: c.onSurface,
            dim: c.onSurfaceVariant,
            faint: c.outline,
            border: c.outlineVariant,
            primary: c.primary,
            onPrimary: c.onPrimary,
            error: c.error,
            ok: c.success ?? c.green,
            warn: c.yellow ?? c.tertiary,
            thinking: c.mauve ?? c.tertiary,
            working: c.blue ?? c.primary,
            limit: c.peach ?? c.tertiary
        });
    }

    function fromPywal(j) {
        const c = j.colors ?? {};
        const sp = j.special ?? {};
        return clean({
            base: sp.background,
            surface: c.color0,
            surfaceHigh: c.color8,
            text: sp.foreground,
            dim: c.color7,
            faint: c.color8,
            border: c.color8,
            primary: c.color4,
            onPrimary: sp.background,
            error: c.color1,
            ok: c.color2,
            warn: c.color3,
            thinking: c.color5,
            working: c.color4,
            limit: c.color3
        });
    }

    component Source: FileView {
        property var parse
        property string slot

        printErrors: false
        onLoaded: {
            try {
                const p = parse(JSON.parse(text()));
                root[slot] = Object.keys(p).length ? p : null;
            } catch (e) {
                root[slot] = null;
            }
        }
        onLoadFailed: root[slot] = null
    }

    Source {
        id: customFile

        path: `${root.configDir}/emba/theme.json`
        slot: "custom"
        parse: j => root.clean(j)
    }
    Source {
        id: caelestiaFile

        path: `${root.stateDir}/caelestia/scheme.json`
        slot: "caelestia"
        parse: j => root.fromCaelestia(j)
    }
    Source {
        id: pywalFile

        path: `${root.cacheDir}/wal/colors.json`
        slot: "pywal"
        parse: j => root.fromPywal(j)
    }

    // Polled rather than watched: these files are replaced by rename, which
    // leaves an inotify watch on the old inode.
    Timer {
        running: true
        repeat: true
        interval: 3000
        onTriggered: {
            customFile.reload();
            caelestiaFile.reload();
            pywalFile.reload();
        }
    }
}
