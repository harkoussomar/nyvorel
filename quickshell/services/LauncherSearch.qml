pragma Singleton

import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string query: ""

    readonly property var parsedQuery: parseQuery(query)
    readonly property string mode: parsedQuery.mode
    readonly property string queryText: parsedQuery.text

    readonly property var modeDescriptors: [
        { mode: "action", prefix: Config.options.search.prefix.action },
        { mode: "app", prefix: Config.options.search.prefix.app },
        { mode: "clipboard", prefix: Config.options.search.prefix.clipboard },
        { mode: "emoji", prefix: Config.options.search.prefix.emojis },
        { mode: "math", prefix: Config.options.search.prefix.math },
        { mode: "shell", prefix: Config.options.search.prefix.shellCommand },
        { mode: "web", prefix: Config.options.search.prefix.webSearch }
    ].filter(item => item.prefix).sort((a, b) => b.prefix.length - a.prefix.length)

    function parseQuery(input) {
        const provider = modeDescriptors.find(item => input.startsWith(item.prefix))
        return provider ? { mode: provider.mode, text: input.slice(provider.prefix.length) }
            : { mode: "all", text: input }
    }

    function ensurePrefix(prefix) {
        const nextPrefix = prefix ?? ""
        if (nextPrefix !== "" || mode !== "all")
            query = nextPrefix + queryText
    }

    onModeChanged: {
        if (mode === "clipboard")
            Cliphist.refresh()
        else if (mode === "emoji" && !Emojis.loaded)
            Emojis.load()
    }

    // Load user action scripts from ~/.config/nyvorel/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--", ...[path, ...(args ? args.split(" ") : [])]]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                GlobalStates.openExclusiveSurface(
                    "wallpaperPicker"
                );
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    readonly property string mathRequest: {
        const parsed = parsedQuery
        const text = parsed.text.trim()
        if (parsed.mode === "math")
            return text
        // An unprefixed title such as "7-Zip" should still be an app search.
        const calculation = /^[\d\s.,()+*/%^×÷−-]+$/.test(text) && /\d/.test(text) && /[+*/%^×÷−-]/.test(text)
        return parsed.mode === "all" && calculation ? text : ""
    }

    readonly property string emptyMessage: {
        if (mode === "clipboard") {
            if (Cliphist.refreshing && !Cliphist.loaded)
                return Translation.tr("Loading clipboard history…")
            if (Cliphist.refreshFailed)
                return Translation.tr("Could not read clipboard history")
            return queryText.trim() ? Translation.tr("No matching clipboard entries") : Translation.tr("Clipboard history is empty")
        }
        if (mode === "emoji")
            return Emojis.loaded ? Translation.tr("No matching emoji") : Translation.tr("Loading emoji…")
        if (mode === "app" && !AppSearch.launcherReady)
            return Translation.tr("Loading applications…")
        if (mode === "math" && mathRequest)
            return mathTimer.running || mathProc.running ? Translation.tr("Calculating…") : Translation.tr("No calculation result")
        return Translation.tr("No results")
    }

    onMathRequestChanged: {
        mathResult = ""
        if (mathRequest)
            mathTimer.restart()
        else
            mathTimer.stop()
    }

    Timer {
        id: mathTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: mathProc.calculate()
    }

    Process {
        id: mathProc
        property string expression
        function calculate() {
            if (running || !root.mathRequest)
                return
            expression = root.mathRequest
            command = ["timeout", "5s", "qalc", "-t", "--", expression]
            running = true
        }
        stdout: StdioCollector { id: answer }
        onExited: (code, status) => {
            if (expression === root.mathRequest) {
                const value = answer.text.trim()
                root.mathResult = code === 0 && status === 0 && value && !/^error\b/im.test(value) ? value : ""
            } else if (root.mathRequest && !mathTimer.running) {
                Qt.callLater(mathProc.calculate)
            }
        }
    }

    function createResult(role, values) {
        return resultComp.createObject(null, Object.assign({ provider: role }, values))
    }

    function clipboardResults(text) {
        return Cliphist.queryEntries({ text, limit: 0 }).map(entry => createResult("clipboard", {
            key: Cliphist.entryKey(entry),
            rawValue: entry,
            name: StringUtils.cleanCliphistEntry(entry),
            type: `#${Cliphist.entryKind(entry)}`,
            execute: () => Cliphist.copy(entry),
            actions: [
                { name: Translation.tr("Copy"), iconName: "content_copy",
                    iconType: LauncherSearchResult.IconType.Material, execute: () => Cliphist.copy(entry) },
                { name: Translation.tr("Delete"), iconName: "delete",
                    iconType: LauncherSearchResult.IconType.Material, execute: () => Cliphist.deleteEntry(entry) }
            ],
            blurImage: Cliphist.entryShouldBlur(entry, clipboardWorkSafetyActive)
        }))
    }

    function emojiResults(text) {
        return Emojis.fuzzyQuery(text).map(entry => {
            const [glyph, ...keywords] = entry.split(/\s+/)
            return createResult("emoji", {
                key: `emoji:${glyph}`,
                rawValue: entry,
                name: keywords.join(" "),
                iconName: glyph,
                iconType: LauncherSearchResult.IconType.Text,
                verb: Translation.tr("Copy"),
                type: Translation.tr("Emoji"),
                execute: () => { Quickshell.clipboardText = glyph }
            })
        })
    }

    function appResults(text) {
        return AppSearch.launcherQuery(text).map(entry => createResult("app", {
            type: Translation.tr("App"),
            id: entry.id,
            name: entry.name,
            iconName: entry.icon,
            iconType: LauncherSearchResult.IconType.System,
            verb: Translation.tr("Open"),
            execute: () => launchApp(entry, entry),
            comment: entry.comment,
            runInTerminal: entry.runInTerminal,
            genericName: entry.genericName,
            keywords: entry.keywords,
            actions: entry.actions.map(action => ({
                name: action.name,
                iconName: action.icon,
                iconType: LauncherSearchResult.IconType.System,
                execute: () => launchApp(entry, action)
            }))
        }))
    }

    function launchApp(entry, action) {
        const launcher = Quickshell.shellPath("scripts/system/nyvorel-app-launch")
        if (!action.runInTerminal) {
            Quickshell.execDetached([launcher, "--cwd", entry.workingDirectory, "--", ...action.command])
            return
        }
        const args = action.command.map(part => "'" + StringUtils.shellSingleQuoteEscape(part) + "'").join(" ")
        Quickshell.execDetached([launcher, "--cwd", entry.workingDirectory, "--", "bash", "-c",
            `${Config.options.apps.terminal} -e ${args}`])
    }

    function actionResults(text) {
        const term = text.toLowerCase()
        return allActions.filter(action =>
            action.action.toLowerCase().startsWith(term)
            || term.startsWith(action.action.toLowerCase() + " ")
        ).map(action => {
            const args = text.slice(action.action.length).trim()
            return createResult("action", {
                name: Config.options.search.prefix.action + action.action + (args ? " " + args : ""),
                verb: Translation.tr("Run"),
                type: Translation.tr("Action"),
                iconName: "settings_suggest",
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => action.execute(args)
            })
        })
    }

    function shellResult(text) {
        const command = text.replace(/^file:\/\//, "")
        return createResult("shell", {
            name: command,
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: "terminal",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                const launcher = Quickshell.shellPath("scripts/system/nyvorel-app-launch")
                if (/^sudo\s/.test(command))
                    Quickshell.execDetached([launcher, "--", "bash", "-c",
                        `${Config.options.apps.terminal} -e bash -lc '${StringUtils.shellSingleQuoteEscape(command)}'`])
                else
                    Quickshell.execDetached([launcher, "--", "bash", "-c", command])
            }
        })
    }

    function webResult(text) {
        const exclusions = Config.options.search.excludedSites.map(site => " -site:" + site).join("")
        const directUrl = /^(https?:\/\/[^\s]+)$/i.test(text)
        const url = directUrl ? text : Config.options.search.engineBaseUrl + encodeURIComponent(text + exclusions)
        return createResult("web", {
            name: text,
            verb: directUrl ? Translation.tr("Open") : Translation.tr("Search"),
            type: directUrl ? Translation.tr("Web address") : Translation.tr("Web search"),
            iconName: "travel_explore",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", url])
        })
    }

    function calculationResults() {
        const answer = mathResult
        return answer ? [createResult("math", {
            name: answer,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: "calculate",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => { Quickshell.clipboardText = answer }
        })] : []
    }

    readonly property var results: {
        const parsed = parsedQuery
        const text = parsed.text.trim()
        switch (parsed.mode) {
        case "clipboard": return clipboardResults(text)
        case "emoji": return emojiResults(text)
        case "math": return calculationResults()
        case "app": return appResults(text)
        case "action": return actionResults(text)
        case "shell": return text ? [shellResult(text)] : []
        case "web": return text ? [webResult(text)] : []
        default:
            if (!text)
                return []
            const answers = calculationResults()
            const apps = appResults(text)
            const web = Config.options.search.prefix.showDefaultActionsWithoutPrefix
                && (!mathRequest || !answers.length && !mathTimer.running && !mathProc.running) ? [webResult(text)] : []
            return [...answers, ...apps, ...web]
        }
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
