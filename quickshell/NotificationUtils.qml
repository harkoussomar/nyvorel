pragma Singleton

import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root


    // =========================================================
    // Semantic classification
    // =========================================================

    function getNotificationKind(
        summary = "",
        body = "",
        urgency = ""
    ) {
        const urgencyString =
            urgency?.toString?.()
            ?? String(urgency);

        if (
            urgencyString
            === NotificationUrgency
                .Critical
                .toString()
        ) {
            return "critical";
        }


        const text =
            `${summary} ${body}`
                .toLowerCase();


        if (
            /\b(error|failed|failure|exception|crash|fatal|denied|unable|cannot|couldn't)\b/
                .test(text)
        ) {
            return "error";
        }


        if (
            /\b(warning|warn|attention|caution)\b/
                .test(text)
        ) {
            return "warning";
        }


        if (
            /\b(success|successful|ready|completed|complete|finished|done|passed)\b/
                .test(text)
        ) {
            return "success";
        }


        if (
            /\b(progress|downloading|uploading|installing|building|compiling|processing)\b/
                .test(text)
        ) {
            return "progress";
        }


        return "info";
    }


    function getNotificationKindIcon(kind) {
        switch (kind) {
        case "critical":
            return "priority_high";

        case "error":
            return "error";

        case "warning":
            return "warning";

        case "success":
            return "check_circle";

        case "progress":
            return "progress_activity";

        default:
            return "notifications";
        }
    }


    // =========================================================
    // Icon guesser
    // =========================================================

    function findSuitableMaterialSymbol(
        summary = ""
    ) {
        const defaultType = "chat";

        if (summary.length === 0)
            return defaultType;


        const keywordsToTypes = {
            "error": "error",
            "failed": "error",
            "failure": "error",
            "ready": "check_circle",
            "success": "check_circle",
            "complete": "check_circle",
            "finished": "check_circle",
            "warning": "warning",
            "reboot": "restart_alt",
            "record": "screen_record",
            "battery": "power",
            "power": "power",
            "screenshot": "screenshot_monitor",
            "welcome": "waving_hand",
            "time": "schedule",
            "installed": "download",
            "configuration reloaded": "reset_wrench",
            "unable": "question_mark",
            "couldn't": "question_mark",
            "config": "reset_wrench",
            "update": "update",
            "ai response": "neurology",
            "control": "settings",
            "upsca": "compare",
            "music": "queue_music",
            "install": "deployed_code_update",
            "input": "keyboard_alt",
            "preedit": "keyboard_alt",
            "startswith:file": "folder_copy",
        };


        const lowerSummary =
            summary.toLowerCase();


        for (
            const [keyword, type]
            of Object.entries(
                keywordsToTypes
            )
        ) {
            if (
                keyword.startsWith(
                    "startswith:"
                )
            ) {
                const startsWithKeyword =
                    keyword.replace(
                        "startswith:",
                        ""
                    );

                if (
                    lowerSummary.startsWith(
                        startsWithKeyword
                    )
                ) {
                    return type;
                }

            } else if (
                lowerSummary.includes(
                    keyword
                )
            ) {
                return type;
            }
        }


        return defaultType;
    }


    // =========================================================
    // Time
    // =========================================================

    function getFriendlyNotifTimeString(
        timestamp
    ) {
        if (!timestamp)
            return "";


        const messageTime =
            new Date(timestamp);

        const now =
            new Date();

        const diffMs =
            now.getTime()
            - messageTime.getTime();


        if (diffMs < 60000)
            return "Now";


        if (
            messageTime.toDateString()
            === now.toDateString()
        ) {
            const diffMinutes =
                Math.floor(
                    diffMs / 60000
                );

            const diffHours =
                Math.floor(
                    diffMs / 3600000
                );


            if (diffHours > 0)
                return `${diffHours}h`;

            return `${diffMinutes}m`;
        }


        if (
            messageTime.toDateString()
            === new Date(
                now.getTime()
                - 86400000
            ).toDateString()
        ) {
            return "Yesterday";
        }


        return Qt.formatDateTime(
            messageTime,
            "MMMM dd"
        );
    }


    // =========================================================
    // Body sanitisation
    // =========================================================

    function processNotificationBody(
        body,
        appName
    ) {
        let processedBody =
            body ?? "";


        if (appName) {
            const lowerApp =
                appName.toLowerCase();

            const chromiumBrowsers = [
                "brave",
                "chrome",
                "chromium",
                "vivaldi",
                "opera",
                "microsoft edge",
            ];


            if (
                chromiumBrowsers.some(
                    (name) =>
                        lowerApp.includes(name)
                )
            ) {
                const lines =
                    processedBody.split(
                        "\n\n"
                    );

                if (
                    lines.length > 1
                    && lines[0].startsWith(
                        "<a"
                    )
                ) {
                    processedBody =
                        lines
                            .slice(1)
                            .join("\n\n");
                }
            }
        }


        processedBody =
            processedBody.replace(
                /<img/gi,
                "\n\n<img"
            );


        return processedBody;
    }
}