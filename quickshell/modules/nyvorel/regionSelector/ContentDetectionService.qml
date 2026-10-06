pragma Singleton

import qs.modules.common
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    signal completed(string requestId, var regions)
    signal failed(string requestId, string message)

    property string currentRequestId: ""

    function detect(
        requestId,
        imagePath,
        screenWidth,
        screenHeight,
        falsePositiveRatio
    ) {
        if (detector.running) {
            root.failed(requestId, "Detector is already processing another request")
            return
        }

        root.currentRequestId = requestId

        const minWidth = Math.max(
            84,
            Math.round(screenWidth * 0.044)
        )
        const minHeight = Math.max(
            36,
            Math.round(screenHeight * 0.032)
        )

        detector.command = [
            `${Directories.scriptPath}/images/find-regions-venv.sh`,
            "--hyprctl",
            "--image", imagePath,
            "--resize-factor", "1.0",
            "--min-width", `${minWidth}`,
            "--min-height", `${minHeight}`,
            "--max-width", `${Math.round(screenWidth * falsePositiveRatio)}`,
            "--max-height", `${Math.round(screenHeight * falsePositiveRatio)}`
        ]
        detector.running = true
    }

    Process {
        id: detector
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.completed(
                        root.currentRequestId,
                        Array.isArray(parsed) ? parsed : []
                    )
                } catch (error) {
                    root.failed(
                        root.currentRequestId,
                        `Invalid detector output: ${error}`
                    )
                }
            }
        }
    }
}
