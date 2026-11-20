import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

Item {
    id: root

    required property var sections
    property string currentSection: sections[0].id
    property alias contentY: bodyScroll.contentY
    default property alias content: bodyScroll.data

    readonly property int pageMargin: width < 760 ? 12 : 16

    onCurrentSectionChanged: bodyScroll.contentY = 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pageMargin
        spacing: 0

        SettingsSectionTabs {
            visible: root.sections.length > 1
            sections: root.sections
            section: root.currentSection
            onSectionRequested: sectionId => root.currentSection = sectionId
        }

        ContentPage {
            id: bodyScroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            forceWidth: true
            minContentWidth: 0
            maxContentWidth: 960
            horizontalPadding: 2
            topPadding: root.sections.length > 1 ? 16 : 4
            bottomContentPadding: 36
        }
    }
}
