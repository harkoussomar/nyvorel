pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions

import QtQuick

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root


    // =========================================================
    // Notification wrapper
    // =========================================================

    component Notif: QtObject {
        id: wrapper

        required property int notificationId

        property Notification notification

        property list<var> actions:
            notification?.actions.map((action) => ({
                "identifier": action.identifier,
                "text": action.text,
            })) ?? []

        property bool popup: false

        property bool isTransient:
            notification?.hints.transient ?? false

        property bool read: true

        property string appIcon:
            notification?.appIcon ?? ""

        property string appName:
            notification?.appName ?? ""

        property string body:
            notification?.body ?? ""

        property string image:
            notification?.image ?? ""

        property string summary:
            notification?.summary ?? ""

        property double time

        property string urgency:
            notification?.urgency.toString() ?? "normal"

        property Timer timer

        property int timeoutMs: 0
        property int remainingMs: 0
        property double timeoutStartedAt: 0
        property bool timeoutPaused: false


        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(
                    notificationId
                );
            }
        }
    }


    // =========================================================
    // Notification timeout timer
    // =========================================================

    component NotifTimer: Timer {
        required property int notificationId

        repeat: false
        running: true


        onTriggered: {
            const notif =
                root.notificationById(
                    notificationId
                );


            if (!notif) {
                destroy();
                return;
            }


            notif.remainingMs = 0;
            notif.timeoutStartedAt = 0;
            notif.timeoutPaused = false;

            // Break the reference before destroying.
            notif.timer = null;


            if (notif.isTransient) {
                root.discardNotification(
                    notificationId
                );

            } else {
                root.timeoutNotification(
                    notificationId
                );
            }


            destroy();
        }
    }


    Component {
        id: notifComponent

        Notif {}
    }


    Component {
        id: notifTimerComponent

        NotifTimer {}
    }


    // =========================================================
    // Global state
    // =========================================================

    property bool silent: false

    property var filePath:
        Directories.notificationsPath

    property list<Notif> list: []


    readonly property var popupList:
        list.filter(
            (notif) => notif.popup
        )


    // notification-architecture-v2
    // Popup presentation is a flat event queue, independent from the grouped
    // notification-center model. Newest first; replacements keep the same
    // wrapper/time and therefore the same logical queue position.
    property int popupMaxVisible:
        3


    readonly property var popupQueue:
        root.popupList
            .slice()
            .sort(
                (a, b) => {
                    if (b.time !== a.time)
                        return b.time - a.time;

                    return b.notificationId
                        - a.notificationId;
                }
            )


    readonly property int unread:
        list.reduce(
            (count, notif) =>
                count + (
                    notif.read ? 0 : 1
                ),

            0
        )


    readonly property bool sidebarOpen:
        GlobalStates?.sidebarRightOpen
        ?? false


    readonly property bool popupInhibited:
        root.sidebarOpen
        || root.silent


    // =========================================================
    // Sound configuration
    // =========================================================

    // Master switch.
    property bool soundsEnabled: true

    // Critical notifications may still make sound in DND.
    property bool criticalSoundInSilent: true

    // Prevent notification storms from playing a sound for
    // every single event.
    property int soundCooldownMs: 900

    property double lastSoundAt: 0


    // =========================================================
    // Notification lookup helpers
    // =========================================================

    function notificationById(id) {
        return root.list.find(
            (notif) =>
                notif.notificationId === id
        ) ?? null;
    }


    function urgencyString(value) {
        if (
            value === undefined
            || value === null
        ) {
            return "";
        }


        return value.toString();
    }


    function isCriticalUrgency(value) {
        return root.urgencyString(value)
            === NotificationUrgency
                .Critical
                .toString();
    }


    function isLowUrgency(value) {
        return root.urgencyString(value)
            === NotificationUrgency
                .Low
                .toString();
    }


    // =========================================================
    // Popup policy
    // =========================================================

    function shouldShowPopup(notification) {
        // Don't throw another toast over the notification
        // center while it is already open.
        if (root.sidebarOpen) {
            return false;
        }


        // DND suppresses ordinary notifications,
        // but critical notifications bypass it.
        if (
            root.silent
            && !root.isCriticalUrgency(
                notification?.urgency
            )
        ) {
            return false;
        }


        return true;
    }


    function enforcePopupCapacity() {
        const queue =
            root.list
                .filter(
                    (notif) => notif.popup
                )
                .slice()
                .sort(
                    (a, b) => {
                        if (b.time !== a.time)
                            return b.time - a.time;

                        return b.notificationId
                            - a.notificationId;
                    }
                );


        queue
            .slice(root.popupMaxVisible)
            .forEach(
                (notif) =>
                    root.timeoutNotification(
                        notif.notificationId
                    )
            );
    }


    onSidebarOpenChanged: {
        if (!root.sidebarOpen)
            return;


        root.markAllRead();
        root.timeoutAll();
    }


    onSilentChanged: {
        if (!root.silent)
            return;


        const ordinaryIds =
            root.popupList
                .filter(
                    (notif) =>
                        !root.isCriticalUrgency(
                            notif.urgency
                        )
                )
                .map(
                    (notif) =>
                        notif.notificationId
                );


        ordinaryIds.forEach(
            (id) =>
                root.timeoutNotification(id)
        );
    }


    // =========================================================
    // Notification sounds
    // =========================================================

    function notificationSoundProfile(notification) {
        if (!notification) {
            return null;
        }


        const critical =
            root.isCriticalUrgency(
                notification.urgency
            );


        if (critical) {
            return {
                "eventId": "dialog-error",
                "kind": "critical",
            };
        }


        // Low-priority notifications remain silent.
        if (
            root.isLowUrgency(
                notification.urgency
            )
        ) {
            return null;
        }


        const kind =
            NotificationUtils
                .getNotificationKind(
                    notification.summary ?? "",
                    notification.body ?? "",
                    notification.urgency ?? ""
                );


        switch (kind) {
        case "error":
            return {
                "eventId": "dialog-error",
                "kind": "error",
            };


        case "warning":
            return {
                "eventId": "dialog-warning",
                "kind": "warning",
            };


        case "success":
            return {
                "eventId": "complete",
                "kind": "success",
            };


        // Progress notifications can update repeatedly,
        // so don't make sound for each update.
        case "progress":
            return null;


        default:
            return {
                "eventId": "message",
                "kind": "info",
            };
        }
    }


    function playNotificationSound(notification) {
        if (!root.soundsEnabled) {
            return;
        }


        if (!notification) {
            return;
        }


        const critical =
            root.isCriticalUrgency(
                notification.urgency
            );


        // ---------------------------------------------
        // DND sound policy
        // ---------------------------------------------

        if (root.silent) {
            if (
                !critical
                || !root.criticalSoundInSilent
            ) {
                return;
            }
        }


        const profile =
            root.notificationSoundProfile(
                notification
            );


        if (!profile) {
            return;
        }


        const now =
            Date.now();


        // Critical alerts bypass rate limiting.
        if (
            !critical
            && (
                now - root.lastSoundAt
                < root.soundCooldownMs
            )
        ) {
            return;
        }


        root.lastSoundAt =
            now;


        Quickshell.execDetached([
            "canberra-gtk-play",
            "-i",
            profile.eventId,
        ]);
    }


    // =========================================================
    // Persistence
    // =========================================================

    function notifToJSON(notif) {
        return {
            "notificationId":
                notif.notificationId,

            "appIcon":
                notif.appIcon,

            "appName":
                notif.appName,

            "body":
                notif.body,

            "image":
                notif.image,

            "summary":
                notif.summary,

            "time":
                notif.time,

            "urgency":
                notif.urgency,

            "read":
                notif.read,
        };
    }


    function stringifyList(items) {
        // Transient notifications should not survive a
        // Quickshell restart.
        const persistentItems =
            items.filter(
                (notif) =>
                    !notif.isTransient
            );


        return JSON.stringify(
            persistentItems.map(
                (notif) =>
                    root.notifToJSON(notif)
            ),

            null,
            2
        );
    }


    function persist() {
        notifFileView.setText(
            root.stringifyList(
                root.list
            )
        );
    }


    // =========================================================
    // Grouping
    // =========================================================

    property var latestTimeForApp: ({})


    onListChanged: {
        root.latestTimeForApp = {};


        root.list.forEach(
            (notif) => {
                const key =
                    notif.appName.length > 0

                        ? notif.appName

                        : "System";


                root.latestTimeForApp[key] =
                    Math.max(
                        root.latestTimeForApp[key]
                        ?? 0,

                        notif.time
                    );
            }
        );
    }


    function groupsForList(items) {
        const groups = {};


        items.forEach(
            (notif) => {
                const groupName =
                    notif.appName.length > 0

                        ? notif.appName

                        : "System";


                if (!groups[groupName]) {
                    groups[groupName] = {
                        "appName":
                            groupName,

                        "appIcon":
                            notif.appIcon,

                        "notifications":
                            [],

                        "time":
                            0,
                    };
                }


                groups[
                    groupName
                ].notifications.push(
                    notif
                );


                groups[
                    groupName
                ].time =
                    root.latestTimeForApp[
                        groupName
                    ]
                    ?? notif.time;
            }
        );


        return groups;
    }


    function appNameListForGroups(groups) {
        return Object.keys(groups)
            .sort(
                (a, b) =>
                    groups[b].time
                    - groups[a].time
            );
    }


    readonly property var groupsByAppName:
        root.groupsForList(
            root.list
        )


    readonly property var popupGroupsByAppName:
        root.groupsForList(
            root.popupList
        )


    readonly property list<string> appNameList:
        root.appNameListForGroups(
            root.groupsByAppName
        )


    readonly property list<string> popupAppNameList:
        root.appNameListForGroups(
            root.popupGroupsByAppName
        )


    // =========================================================
    // IDs + signals
    // =========================================================

    property int idOffset


    signal initDone()

    signal notify(
        notification: var
    )

    signal discard(
        id: int
    )

    signal discardAll()

    signal timeout(
        id: var
    )


    // =========================================================
    // Timeout management
    // =========================================================

    function startTimeout(
        notif,
        timeoutMs
    ) {
        if (!notif) {
            return;
        }


        // Critical notifications remain visible until
        // explicitly dismissed.
        if (
            root.isCriticalUrgency(
                notif.urgency
            )
        ) {
            return;
        }


        if (timeoutMs <= 0) {
            return;
        }


        if (notif.timer) {
            notif.timer.stop();
            notif.timer.destroy();

            notif.timer = null;
        }


        notif.timeoutMs =
            timeoutMs;

        notif.remainingMs =
            timeoutMs;

        notif.timeoutStartedAt =
            Date.now();

        notif.timeoutPaused =
            false;


        notif.timer =
            notifTimerComponent
                .createObject(
                    root,
                    {
                        "notificationId":
                            notif.notificationId,

                        "interval":
                            timeoutMs,
                    }
                );
    }


    function pauseTimeout(id) {
        const notif =
            root.notificationById(id);


        if (
            !notif
            || !notif.timer
            || notif.timeoutPaused
            || !notif.popup
        ) {
            return;
        }


        if (notif.timer.running) {
            const elapsed =
                Date.now()
                - notif.timeoutStartedAt;


            notif.remainingMs =
                Math.max(
                    0,

                    notif.remainingMs
                    - elapsed
                );


            notif.timer.stop();
        }


        notif.timeoutPaused =
            true;
    }


    function resumeTimeout(id) {
        const notif =
            root.notificationById(id);


        if (
            !notif
            || !notif.timer
            || !notif.timeoutPaused
            || !notif.popup
        ) {
            return;
        }


        if (
            root.isCriticalUrgency(
                notif.urgency
            )
        ) {
            return;
        }


        notif.timeoutPaused =
            false;


        if (notif.remainingMs <= 0) {
            root.timeoutNotification(id);
            return;
        }


        // Avoid a notification disappearing immediately
        // after the pointer leaves.
        notif.timer.interval =
            Math.max(
                250,
                notif.remainingMs
            );


        notif.timeoutStartedAt =
            Date.now();


        notif.timer.restart();
    }


    // Compatibility with older callers.
    function cancelTimeout(id) {
        root.pauseTimeout(id);
    }


    function timeoutNotification(id) {
        const notif =
            root.notificationById(id);


        if (!notif) {
            return;
        }


        if (notif.timer) {
            notif.timer.stop();
            notif.timer.destroy();

            notif.timer = null;
        }


        notif.timeoutPaused =
            false;

        notif.remainingMs =
            0;

        notif.timeoutStartedAt =
            0;

        notif.popup =
            false;


        root.timeout(id);
    }


    function timeoutAll() {
        const ids =
            root.popupList.map(
                (notif) =>
                    notif.notificationId
            );


        ids.forEach(
            (id) =>
                root.timeoutNotification(id)
        );
    }


    // =========================================================
    // Read state
    // =========================================================

    function markAllRead() {
        let changed =
            false;


        root.list.forEach(
            (notif) => {
                if (!notif.read) {
                    notif.read =
                        true;

                    changed =
                        true;
                }
            }
        );


        if (!changed) {
            return;
        }


        root.triggerListChange();
        root.persist();
    }


    function markRead(id) {
        const notif =
            root.notificationById(id);


        if (
            !notif
            || notif.read
        ) {
            return;
        }


        notif.read =
            true;


        root.triggerListChange();
        root.persist();
    }


    // =========================================================
    // Freedesktop notification server
    // =========================================================

    NotificationServer {
        id: notifServer


        actionsSupported:
            true

        bodyHyperlinksSupported:
            true

        bodyImagesSupported:
            true

        bodyMarkupSupported:
            true

        bodySupported:
            true

        imageSupported:
            true


        keepOnReload:
            false

        persistenceSupported:
            true


        onNotification: (notification) => {
            notification.tracked =
                true;


            // -----------------------------------------
            // Sound
            // -----------------------------------------

            root.playNotificationSound(
                notification
            );


            const critical =
                root.isCriticalUrgency(
                    notification.urgency
                );


            const showPopup =
                root.shouldShowPopup(
                    notification
                );


            const newNotifObject =
                notifComponent
                    .createObject(
                        root,
                        {
                            "notificationId":
                                notification.id
                                + root.idOffset,

                            "notification":
                                notification,

                            "time":
                                Date.now(),

                            // If the sidebar is already open,
                            // treat the new notification as seen.
                            "read":
                                root.sidebarOpen,
                        }
                    );


            root.list = [
                ...root.list,
                newNotifObject,
            ];


            // -----------------------------------------
            // Popup
            // -----------------------------------------

            if (showPopup) {
                newNotifObject.popup =
                    true;


                // Keep popup capacity deterministic at the service layer so
                // overflow notifications cannot reappear later when a newer
                // toast disappears.
                root.enforcePopupCapacity();
            }


            // -----------------------------------------
            // Timeout
            // -----------------------------------------

            if (
                notification.expireTimeout !== 0
                && !critical
                && (
                    showPopup
                    || newNotifObject.isTransient
                )
            ) {
                const timeoutMs =
                    notification.expireTimeout < 0

                        ? (
                            Config
                                ?.options
                                .notifications
                                .timeout

                            ?? 7000
                        )

                        : notification
                            .expireTimeout;


                root.startTimeout(
                    newNotifObject,
                    timeoutMs
                );
            }


            root.notify(
                newNotifObject
            );


            root.persist();
        }
    }


    // =========================================================
    // Dismiss
    // =========================================================

    function discardNotification(id) {
        const index =
            root.list.findIndex(
                (notif) =>
                    notif.notificationId
                    === id
            );


        const notifServerIndex =
            notifServer
                .trackedNotifications
                .values
                .findIndex(
                    (notif) =>
                        notif.id
                        + root.idOffset
                        === id
                );


        if (index !== -1) {
            const notif =
                root.list[index];


            if (notif.timer) {
                notif.timer.stop();
                notif.timer.destroy();

                notif.timer =
                    null;
            }


            root.list.splice(
                index,
                1
            );


            root.triggerListChange();
            root.persist();
        }


        if (notifServerIndex !== -1) {
            notifServer
                .trackedNotifications
                .values[
                    notifServerIndex
                ]
                .dismiss();
        }


        root.discard(id);
    }


    function discardAllNotifications() {
        root.list.forEach(
            (notif) => {
                if (notif.timer) {
                    notif.timer.stop();
                    notif.timer.destroy();

                    notif.timer =
                        null;
                }
            }
        );


        root.list =
            [];


        root.persist();


        notifServer
            .trackedNotifications
            .values
            .forEach(
                (notif) =>
                    notif.dismiss()
            );


        root.discardAll();
    }


    // =========================================================
    // Notification actions
    // =========================================================

    function attemptInvokeAction(
        id,
        notifIdentifier
    ) {
        const serverIndex =
            notifServer
                .trackedNotifications
                .values
                .findIndex(
                    (notif) =>
                        notif.id
                        + root.idOffset
                        === id
                );


        if (serverIndex === -1) {
            return false;
        }


        const serverNotif =
            notifServer
                .trackedNotifications
                .values[
                    serverIndex
                ];


        const action =
            serverNotif.actions.find(
                (candidate) =>
                    candidate.identifier
                    === notifIdentifier
            );


        if (!action) {
            return false;
        }


        const keepResident =
            serverNotif.resident;


        action.invoke();


        if (keepResident) {
            const notif =
                root.notificationById(id);


            if (notif) {
                if (notif.timer) {
                    notif.timer.stop();
                    notif.timer.destroy();

                    notif.timer = null;
                }


                notif.popup =
                    false;

                notif.read =
                    true;

                notif.timeoutPaused =
                    false;

                notif.remainingMs =
                    0;

                notif.timeoutStartedAt =
                    0;


                root.triggerListChange();
                root.persist();
            }

        } else {
            root.discardNotification(id);
        }


        return true;
    }


    function attemptInvokeDefaultAction(id) {
        return root.attemptInvokeAction(
            id,
            "default"
        );
    }


    function triggerListChange() {
        root.list =
            root.list.slice(0);
    }


    // =========================================================
    // History loading
    // =========================================================

    function refresh() {
        notifFileView.reload();
    }


    Component.onCompleted: {
        refresh();
    }


    FileView {
        id: notifFileView


        path:
            Qt.resolvedUrl(
                root.filePath
            )


        onLoaded: {
            try {
                const fileContents =
                    notifFileView.text();


                const parsed =
                    JSON.parse(
                        fileContents
                    );


                root.list =
                    parsed.map(
                        (notif) => {
                            return notifComponent
                                .createObject(
                                    root,
                                    {
                                        "notificationId":
                                            notif.notificationId,

                                        // Restored notifications
                                        // can no longer invoke
                                        // actions from dead apps.
                                        "actions":
                                            [],

                                        "appIcon":
                                            notif.appIcon ?? "",

                                        "appName":
                                            notif.appName ?? "",

                                        "body":
                                            notif.body ?? "",

                                        "image":
                                            notif.image ?? "",

                                        "summary":
                                            notif.summary ?? "",

                                        "time":
                                            notif.time
                                            ?? Date.now(),

                                        "urgency":
                                            notif.urgency
                                            ?? "normal",

                                        // Old history should not
                                        // return as unread.
                                        "read":
                                            notif.read
                                            ?? true,
                                    }
                                );
                        }
                    );


                let maxId =
                    0;


                root.list.forEach(
                    (notif) => {
                        maxId =
                            Math.max(
                                maxId,
                                notif.notificationId
                            );
                    }
                );


                root.idOffset =
                    maxId;


                console.log(
                    "[Notifications] File loaded"
                );


                root.initDone();

            } catch (error) {
                console.log(
                    "[Notifications] Invalid history file: "
                    + error
                );


                root.list =
                    [];

                root.idOffset =
                    0;


                root.persist();
                root.initDone();
            }
        }


        onLoadFailed: (error) => {
            if (
                error
                === FileViewError.FileNotFound
            ) {
                root.list =
                    [];

                root.idOffset =
                    0;


                root.persist();
                root.initDone();

            } else {
                console.log(
                    "[Notifications] Error loading file: "
                    + error
                );
            }
        }
    }
}