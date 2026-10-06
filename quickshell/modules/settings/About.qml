import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    readonly property int wideBreakpoint: 700
    readonly property int cardPadding: 16
    readonly property int sectionGap: 12
    readonly property int compactControlHeight: 38

    readonly property string projectName: "Nyvorel"
    readonly property string projectRepository:
        "https://github.com/end-4/dots-hyprland"
    readonly property string projectDocumentation:
        "https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/"
    readonly property string projectIssues:
        "https://github.com/end-4/dots-hyprland/issues"
    readonly property string projectDiscussions:
        "https://github.com/end-4/dots-hyprland/discussions"
    readonly property string projectSponsors:
        "https://github.com/sponsors/end-4"

    property string quickshellBuild: Translation.tr("Loading…")
    property string qtVersion: Translation.tr("Loading…")
    property string hyprlandBuild: Translation.tr("Loading…")
    property string kernelVersion: Translation.tr("Loading…")
    property string architecture: Translation.tr("Loading…")

    function shortVersion(text: string, product: string): string {
        if (!text || text === Translation.tr("Loading…"))
            return text

        const pattern = new RegExp("^" + product + "\\s+([^\\s]+)")
        const match = text.match(pattern)
        return match && match.length > 1 ? match[1] : text
    }

    function cleanOutput(text: string): string {
        const value = (text || "").trim()
        return value.length > 0 ? value : Translation.tr("Unavailable")
    }

    function refreshRuntimeInfo(): void {
        quickshellProbe.running = true
        qtProbe.running = true
        hyprlandProbe.running = true
        kernelProbe.running = true
        architectureProbe.running = true
    }

    function diagnosticsText(): string {
        return [
            projectName,
            Translation.tr("Distribution: %1").arg(SystemInfo.distroName),
            Translation.tr("Quickshell: %1").arg(quickshellBuild),
            Translation.tr("Qt: %1").arg(qtVersion),
            Translation.tr("Hyprland: %1").arg(hyprlandBuild),
            Translation.tr("Kernel: %1").arg(kernelVersion),
            Translation.tr("Architecture: %1").arg(architecture)
        ].join("\n")
    }

    Process {
        id: quickshellProbe
        command: ["bash", "-lc", "qs --version 2>/dev/null | head -n 1"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.quickshellBuild = root.cleanOutput(text)
            }
        }

        Component.onCompleted: running = true
    }

    Process {
        id: qtProbe
        command: [
            "bash",
            "-lc",
            "(qmake6 -query QT_VERSION 2>/dev/null || qmake -query QT_VERSION 2>/dev/null) | head -n 1"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                root.qtVersion = root.cleanOutput(text)
            }
        }

        Component.onCompleted: running = true
    }

    Process {
        id: hyprlandProbe
        command: ["bash", "-lc", "hyprctl version 2>/dev/null | head -n 1"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.hyprlandBuild = root.cleanOutput(text)
            }
        }

        Component.onCompleted: running = true
    }

    Process {
        id: kernelProbe
        command: ["uname", "-r"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.kernelVersion = root.cleanOutput(text)
            }
        }

        Component.onCompleted: running = true
    }

    Process {
        id: architectureProbe
        command: ["uname", "-m"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.architecture = root.cleanOutput(text)
            }
        }

        Component.onCompleted: running = true
    }

    component InfoCard: Rectangle {
        id: card

        property string title: ""
        property string subtitle: ""
        property string iconName: ""
        property bool showHeader: true

        readonly property real naturalHeight:
            cardColumn.implicitHeight + root.cardPadding * 2

        default property alias content: contentColumn.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: naturalHeight

        radius:
            Appearance.prismMode
                ? Appearance.prism.radiusPersistent
                : Appearance.radius.card
        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.colors.colLayer2
        border.width: 1
        border.color:
            Appearance.prismMode
                ? Appearance.prism.borderSubtle
                : Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            id: cardColumn

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: root.cardPadding
                leftMargin: root.cardPadding
                rightMargin: root.cardPadding
            }

            spacing: root.sectionGap

            RowLayout {
                visible: card.showHeader
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    visible: card.iconName.length > 0
                    text: card.iconName
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: card.title
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        visible: card.subtitle.length > 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: card.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                spacing: 8
            }
        }
    }

    component ActionButton: RippleButtonWithIcon {
        id: action

        required property string label
        required property string iconName

        implicitHeight: root.compactControlHeight
        buttonRadius: Appearance.radius.control
        materialIcon: iconName
        mainText: label

        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
    }

    component RuntimeRow: Rectangle {
        id: runtimeRow

        required property string label
        required property string value
        required property string iconName

        Layout.fillWidth: true
        implicitHeight: runtimeContent.implicitHeight + 18

        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1

        RowLayout {
            id: runtimeContent

            anchors {
                fill: parent
                margins: 9
            }

            spacing: 9

            MaterialSymbol {
                text: runtimeRow.iconName
                iconSize: 17
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: runtimeRow.label
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.maximumWidth: Math.max(120, runtimeRow.width * 0.52)
                text: runtimeRow.value
                color: Appearance.colors.colSubtext
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smallest
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
            }
        }
    }

    component LinkRow: Rectangle {
        id: linkRow

        required property string title
        required property string subtitle
        required property string iconName
        required property string url

        Layout.fillWidth: true
        implicitHeight: linkContent.implicitHeight + 18

        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        clip: true

        RowLayout {
            id: linkContent

            anchors {
                fill: parent
                margins: 9
            }

            spacing: 10

            MaterialSymbol {
                text: linkRow.iconName
                iconSize: 18
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: linkRow.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: linkRow.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                }
            }

            RippleButtonWithIcon {
                implicitHeight: root.compactControlHeight
                buttonRadius: Appearance.radius.control
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open")

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active

                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", linkRow.url])
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: heroColumn.implicitHeight + root.cardPadding * 2

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            id: heroColumn

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: root.cardPadding
            }

            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                IconImage {
                    implicitSize: 88
                    source: Quickshell.iconPath("nyvorel")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 3

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.projectName
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.title
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Translation.tr("A Quickshell desktop shell and dotfiles experience for Hyprland.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: qsBadgeText.implicitWidth + 18
                            implicitHeight: 28
                            radius: Appearance.radius.control
                            color: Appearance.colors.colPrimaryContainer

                            StyledText {
                                id: qsBadgeText
                                anchors.centerIn: parent
                                text: Translation.tr("Quickshell")
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            implicitWidth: hyprBadgeText.implicitWidth + 18
                            implicitHeight: 28
                            radius: Appearance.radius.control
                            color: Appearance.colors.colLayer1

                            StyledText {
                                id: hyprBadgeText
                                anchors.centerIn: parent
                                text: Translation.tr("Hyprland")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 7

                ActionButton {
                    label: Translation.tr("Documentation")
                    iconName: "auto_stories"
                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", root.projectDocumentation])
                }

                ActionButton {
                    label: Translation.tr("Repository")
                    iconName: "code"
                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", root.projectRepository])
                }

                ActionButton {
                    label: Translation.tr("Report issue")
                    iconName: "bug_report"
                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", root.projectIssues])
                }

                ActionButton {
                    label: Translation.tr("Discussions")
                    iconName: "forum"
                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", root.projectDiscussions])
                }
            }
        }
    }

    ContentSection {
        icon: "deployed_code"
        title: Translation.tr("Runtime")
        Layout.fillWidth: true

        InfoCard {
            title: Translation.tr("Runtime versions")
            subtitle: Translation.tr("Read live from the tools installed on this system when the About page opens.")
            iconName: "deployed_code"

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                RuntimeRow {
                    label: Translation.tr("Quickshell")
                    value: root.shortVersion(
                        root.quickshellBuild,
                        "Quickshell"
                    )
                    iconName: "widgets"
                }

                RuntimeRow {
                    label: Translation.tr("Qt")
                    value: root.qtVersion
                    iconName: "apps"
                }

                RuntimeRow {
                    label: Translation.tr("Hyprland")
                    value: root.shortVersion(
                        root.hyprlandBuild,
                        "Hyprland"
                    )
                    iconName: "desktop_windows"
                }

                RuntimeRow {
                    label: Translation.tr("Kernel")
                    value: root.kernelVersion
                    iconName: "memory"
                }

                RuntimeRow {
                    label: Translation.tr("Architecture")
                    value: root.architecture
                    iconName: "developer_board"
                }

                RuntimeRow {
                    label: Translation.tr("Distribution")
                    value: SystemInfo.distroName
                    iconName: "deployed_code"
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 7

                ActionButton {
                    label: Translation.tr("Refresh")
                    iconName: "refresh"

                    onClicked: root.refreshRuntimeInfo()
                }

                ActionButton {
                    label: Translation.tr("Copy diagnostics")
                    iconName: "content_copy"

                    onClicked: {
                        Quickshell.clipboardText = root.diagnosticsText()
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Quickshell build: %1")
                    .arg(root.quickshellBuild)
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Hyprland build: %1")
                    .arg(root.hyprlandBuild)
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        icon: "info"
        title: Translation.tr("System & project")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            InfoCard {
                title: Translation.tr("Distribution")
                subtitle: Translation.tr("Links provided by your current Linux distribution.")
                iconName: "box"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    IconImage {
                        implicitSize: 58
                        source: Quickshell.iconPath(SystemInfo.logo)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: SystemInfo.distroName
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: SystemInfo.homeUrl
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            elide: Text.ElideRight
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 7

                    ActionButton {
                        label: Translation.tr("Website")
                        iconName: "language"
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", SystemInfo.homeUrl])
                    }

                    ActionButton {
                        label: Translation.tr("Documentation")
                        iconName: "auto_stories"
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", SystemInfo.documentationUrl])
                    }

                    ActionButton {
                        label: Translation.tr("Support")
                        iconName: "support"
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", SystemInfo.supportUrl])
                    }

                    ActionButton {
                        label: Translation.tr("Report distro bug")
                        iconName: "bug_report"
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", SystemInfo.bugReportUrl])
                    }

                    ActionButton {
                        label: Translation.tr("Privacy")
                        iconName: "policy"
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", SystemInfo.privacyPolicyUrl])
                    }
                }
            }

            InfoCard {
                title: Translation.tr("Project & community")
                subtitle: Translation.tr("Source, help, discussion, and project support for Nyvorel.")
                iconName: "hub"

                LinkRow {
                    title: Translation.tr("Source repository")
                    subtitle: Translation.tr("Browse the end-4/dots-hyprland source on GitHub.")
                    iconName: "code"
                    url: root.projectRepository
                }

                LinkRow {
                    title: Translation.tr("Documentation")
                    subtitle: Translation.tr("Usage documentation for the Nyvorel Quickshell setup.")
                    iconName: "auto_stories"
                    url: root.projectDocumentation
                }

                LinkRow {
                    title: Translation.tr("Community discussions")
                    subtitle: Translation.tr("Ask questions and discuss the project with the community.")
                    iconName: "forum"
                    url: root.projectDiscussions
                }

                LinkRow {
                    title: Translation.tr("Support the project")
                    subtitle: Translation.tr("Open the existing GitHub Sponsors page.")
                    iconName: "favorite"
                    url: root.projectSponsors
                }
            }
        }
    }

    ContentSection {
        icon: "verified"
        title: Translation.tr("About this page")
        Layout.fillWidth: true

        InfoCard {
            title: Translation.tr("Useful, privacy-conscious diagnostics")
            subtitle: Translation.tr("This page intentionally shows software/runtime information without exposing username, hostname, IP address, hardware serials, or home-directory paths.")
            iconName: "privacy_tip"

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The project source exposed by the current settings does not provide a verified license or contributor list here, so this page does not invent either. Use the repository for authoritative project metadata.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ActionButton {
                Layout.fillWidth: true
                label: Translation.tr("Open source repository")
                iconName: "open_in_new"
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", root.projectRepository])
            }
        }
    }
}
