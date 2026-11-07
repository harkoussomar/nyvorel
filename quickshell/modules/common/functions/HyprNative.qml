pragma Singleton
import Quickshell

Singleton {
    // JSON's unicode escapes are not Lua string escapes.
    function luaString(value) {
        return '"' + String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')
            .replace(/[\x00-\x1f\x7f]/g, ch => "\\" + ch.charCodeAt(0).toString().padStart(3, "0")) + '"'
    }
    function evaluate(code) { Quickshell.execDetached(["hyprctl", "eval", code]) }
    function dispatch(expression) { evaluate("hl.dispatch(" + expression + ")") }
    function workspace(value) { dispatch("hl.dsp.focus({workspace=" + luaString(value) + "})") }
    function toggleSpecial() { dispatch('hl.dsp.workspace.toggle_special("")') }
    function windowSelector(address) {
        // Never act on the active window when the intended QML client expired.
        return address ? luaString("address:" + address) : null
    }
    function focusWindow(address) {
        const win = windowSelector(address)
        if (win) dispatch("hl.dsp.focus({window=" + win + "})")
    }
    function closeWindow(address) {
        const win = windowSelector(address)
        if (win) dispatch("hl.dsp.window.close({window=" + win + "})")
    }
    function pinWindow(address) {
        const win = windowSelector(address)
        if (win) dispatch("hl.dsp.window.pin({window=" + win + "})")
    }
    function moveToWorkspace(workspace, address) {
        const win = windowSelector(address)
        if (win) dispatch("hl.dsp.window.move({workspace=" + luaString(workspace) + ", follow=false, window=" + win + "})")
    }
    function moveWindowPercent(x, y, address) {
        const win = windowSelector(address)
        if (!win || !Number.isFinite(x) || !Number.isFinite(y)) return
        // Legacy exact-percent uses focused-monitor logical size, truncates toward
        // zero and does not add the monitor's global position.
        evaluate("local m=hl.get_active_monitor(); if m then "
            + "local w,h=m.width,m.height; if m.transform%2==1 then w,h=h,w end; "
            + "local function trunc(v) if v<0 then return math.ceil(v) else return math.floor(v) end end; "
            + "hl.dispatch(hl.dsp.window.move({x=trunc(" + x + "*0.01*w/m.scale), y=trunc(" + y
            + "*0.01*h/m.scale), relative=false, window=" + win + "})) end")
    }
    function execCommand(command) { dispatch("hl.dsp.exec_cmd(" + luaString(command) + ")") }
    function focusWorkspaceCode(monitor, workspace) {
        return "hl.dispatch(hl.dsp.focus({monitor=" + luaString(monitor) + "})); "
            + "hl.dispatch(hl.dsp.focus({workspace=" + luaString(workspace) + "})); "
    }
    function evalThenReload(code) {
        Quickshell.execDetached(["bash", "-c", 'hyprctl eval "$1"; hyprctl reload', "nyvorel-hypr-native", code])
    }
    function refocusAfterUnlock() {
        Quickshell.execDetached(["bash", "-c", 'sleep 0.2; hyprctl eval "$1"', "nyvorel-hypr-native",
            'hl.dispatch(hl.dsp.workspace.toggle_special("")); hl.dispatch(hl.dsp.workspace.toggle_special(""))'])
    }
    function enableGameMode() {
        evaluate('hl.config({animations={enabled=false}, decoration={shadow={enabled=false}, blur={enabled=false}, rounding=0}, '
            + 'general={gaps_in=0, gaps_out=0, border_size=1, allow_tearing=true}})')
    }
}
