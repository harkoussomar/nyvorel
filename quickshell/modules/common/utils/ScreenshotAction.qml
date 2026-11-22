pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    readonly property string outputMode: {
        const mode = Config.options.screenSnip.destination;
        return ["copy", "save", "both"].includes(mode)
            ? mode : Config.options.screenSnip.savePath ? "both" : "copy";
    }

    function fileAction(path, action) {
        switch (action) {
        case "copy":
            return ["bash", "-c", 'wl-copy --type image/png < "$1"', "nyvorel-screenshot", path];
        case "annotate":
            return [Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy", "-f", path];
        case "lens":
            return [Quickshell.shellPath("scripts/system/google-lens-search"), path];
        case "folder":
            return [Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", path.slice(0, path.lastIndexOf("/")) || "/"];
        case "ocr":
            return ["bash", "-o", "pipefail", "-c", `
                langs=$(tesseract --list-langs | awk 'NR>1 && $0!="osd"' | paste -sd+)
                if [[ -n "$langs" ]] && result=$(tesseract "$1" stdout -l "$langs" 2>/dev/null) &&
                    [[ "$result" =~ [^[:space:]] ]] && printf '%s' "$result" | wl-copy; then
                    notify-send -a Nyvorel 'Screenshot' 'Recognized text copied to the clipboard.'
                else
                    notify-send -a Nyvorel 'Screenshot' 'No text could be copied from this capture.'
                fi
            `, "nyvorel-screenshot", path];
        }
        return [];
    }

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "", cornerRadius = 0, options = null) {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        const rr =
            Math.max(
                0,
                Math.min(
                    Math.round(cornerRadius),
                    Math.floor(Math.min(rw, rh) / 2)
                )
            );

        const shape = rr > 0 ? `roundrectangle 0,0 ${rw - 1},${rh - 1} ${rr},${rr}` : "";
        const mask = shape
            ? ` +repage -alpha set \\( -size ${rw}x${rh} xc:none -fill white -draw '${shape}' \\) -compose DstIn -composite`
            : " +repage";

        const quotedPath = `'${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const cropBase =
            `magick ${quotedPath} `
            + `-crop ${rw}x${rh}+${rx}+${ry}`
            + mask
        const cropToStdout = `${cropBase} -`
        const cropInPlace = `${cropBase} ${quotedPath}`
        const cleanup = `rm -f -- ${quotedPath}`
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        const annotationCommand = `${Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"} -f -`;
        switch (action) {
            case ScreenshotAction.Action.Copy: {
                const destination = root.outputMode;
                const folder = saveDir || FileUtils.trimFileProtocol(Directories.pictures) + "/Screenshots";
                return ["bash", "-c", `
                    umask 077
                    crop=
                    cleanup_capture() {
                        ${cleanup}
                        if [[ -n "$crop" ]]; then rm -f -- "$crop" "$crop.log"; fi
                    }
                    trap cleanup_capture EXIT
                    notify_failure() { notify-send -a Nyvorel 'Screenshot' "$1"; }
                    if [[ -n "$5" ]]; then
                        if (( $6 > 0 )); then
                            notify-send -a Nyvorel -t "$(($6 * 700))" 'Screenshot' "Taking the screenshot in $6 seconds."
                            sleep "$6"
                        else
                            sleep .15
                        fi
                        if ! mkdir -p -- "$(dirname -- "$1")" || ! grim -t png -o "$5" "$1"; then
                            notify_failure 'Could not take a screenshot of the selected display.'
                            exit 1
                        fi
                    fi
                    crop=$(mktemp -- "$1.crop.XXXXXX") || {
                        notify_failure 'Could not prepare the screenshot.'
                        exit 1
                    }
                    if ! ${cropBase} "png:$crop" 2>"$crop.log" || [[ ! -s "$crop" ]]; then
                        logger -t nyvorel-screenshot < "$crop.log"
                        notify_failure 'Could not crop the selected screenshot.'
                        exit 1
                    fi
                    copied=false
                    saved=
                    if [[ "$3" != save ]] && wl-copy --type image/png < "$crop"; then
                        copied=true
                    fi
                    if [[ "$3" != copy ]] && mkdir -p -- "$2"; then
                        if path=$(mktemp --suffix=.png "$2/screenshot-$(date '+%Y-%m-%d_%H.%M.%S')-XXXXXX"); then
                            if cp -- "$crop" "$path"; then
                                saved=$path
                            else
                                rm -f -- "$path"
                            fi
                        fi
                    fi
                    if [[ -n "$4" ]]; then
                        if ! mkdir -p -- "$(dirname -- "$4")" || ! mv -- "$crop" "$4"; then
                            notify_failure 'Could not open the screenshot preview.'
                            exit 1
                        fi
                        jq -cn --arg path "$4" --arg savedPath "$saved" --arg mode "$3" --argjson copied "$copied" \\
                            '{path:$path,savedPath:$savedPath,mode:$mode,copied:$copied}'
                    else
                        if [[ "$3" != save && "$copied" == false ]]; then
                            notify_failure 'Could not copy the screenshot to the clipboard.'
                        fi
                        if [[ "$3" != copy && -z "$saved" ]]; then
                            notify_failure 'Could not save the screenshot to the selected folder.'
                        fi
                    fi
                `, "nyvorel-screenshot", screenshotPath, folder, destination, options?.previewPath ?? "",
                    options?.refreshScreen ?? "", String(options?.delay ?? 0)]
            }
            case ScreenshotAction.Action.Edit:
                return ["bash", "-c", `${cropToStdout} | ${annotationCommand} && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Search: {
                const helper = StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/system/google-lens-search"))
                return ["bash", "-c", `if ${cropInPlace}; then exec '${helper}' --consume-capture ${quotedPath}; fi; ${cleanup}; notify-send -a Nyvorel 'Google Lens' 'Could not crop the selected region.'`]
            }
            case ScreenshotAction.Action.CharRecognition:
                return ["bash", "-c", `${cropInPlace} && tesseract '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Record:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'`]
                break;
            case ScreenshotAction.Action.RecordWithSound:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound`]
                break;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
