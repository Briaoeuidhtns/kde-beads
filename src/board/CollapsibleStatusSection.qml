// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: section
    objectName: `statusSection-${statusName}`

    required property string statusName
    required property string heading
    required property color accent
    required property var cards
    required property int totalCount
    required property bool backendLoading
    required property Item dragProxy
    property bool expanded: totalCount > 0

    signal moveIssueRequested(string issueId, string status)
    signal openIssueRequested(string issueId)
    signal createIssueRequested()
    signal copyIssueIdRequested(string issueId)

    implicitHeight: expanded
        ? Kirigami.Units.gridUnit * 14
        : toggleButton.implicitHeight + Kirigami.Units.smallSpacing * 2
    z: 20
    radius: Kirigami.Units.cornerRadius
    color: sectionDropArea.containsDrag
        ? Qt.alpha(accent, 0.12)
        : Kirigami.Theme.alternateBackgroundColor
    clip: true

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.InOutQuad
        }
    }

    DropArea {
        id: sectionDropArea
        anchors.fill: parent
        z: 10
        keys: ["bead-card"]

        onDropped: drop => {
            if (drop.source.issueStatus !== section.statusName)
                section.moveIssueRequested(drop.source.issueId, section.statusName);
            drop.acceptProposedAction();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Controls.ToolButton {
            id: toggleButton
            objectName: `statusToggle-${section.statusName}`
            Layout.fillWidth: true
            checkable: true
            checked: section.expanded
            onClicked: section.expanded = checked

            contentItem: RowLayout {
                Kirigami.Icon {
                    source: toggleButton.checked ? "arrow-down" : "arrow-right"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                }
                Controls.Label {
                    text: section.heading
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                Controls.Label {
                    text: section.totalCount
                    color: section.accent
                    font.weight: Font.Bold
                }
            }
        }

        KanbanColumn {
            visible: section.expanded
            Layout.fillWidth: true
            Layout.fillHeight: true
            statusName: section.statusName
            heading: section.heading
            accent: section.accent
            cards: section.cards
            totalCount: section.totalCount
            backendLoading: section.backendLoading
            dragProxy: section.dragProxy
            showHeader: false
            onMoveIssueRequested: (issueId, status) => section.moveIssueRequested(issueId, status)
            onOpenIssueRequested: issueId => section.openIssueRequested(issueId)
            onCreateIssueRequested: section.createIssueRequested()
            onCopyIssueIdRequested: issueId => section.copyIssueIdRequested(issueId)
        }
    }
}
