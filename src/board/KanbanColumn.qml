// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components" as Components

Rectangle {
    id: column
    objectName: `statusColumn-${statusName}`

    required property string statusName
    required property string heading
    required property color accent
    required property var cards
    required property int totalCount
    required property bool backendLoading
    required property Item dragProxy
    property Component headerControl: null
    property real headerHeight: 0
    property bool compactHeader: false
    property bool showHeader: true
    property bool showCreateWhenEmpty: false
    property bool dropEnabled: true

    signal moveIssueRequested(string issueId, string status)
    signal openIssueRequested(string issueId)
    signal createIssueRequested()
    signal copyIssueIdRequested(string issueId)

    radius: Kirigami.Units.cornerRadius
    color: dropArea.containsDrag
        ? Qt.alpha(accent, 0.12)
        : Kirigami.Theme.backgroundColor

    function priorityColor(priority) {
        if (priority === 0)
            return Kirigami.Theme.negativeTextColor;
        if (priority === 1)
            return Kirigami.Theme.neutralTextColor;
        if (priority === 2)
            return Kirigami.Theme.highlightColor;
        return Kirigami.Theme.disabledTextColor;
    }

    DropArea {
        id: dropArea
        objectName: `columnDropArea-${column.statusName}`
        anchors.fill: parent
        enabled: column.dropEnabled
        keys: ["bead-card"]

        onDropped: drop => {
            if (drop.source.issueStatus !== column.statusName)
                column.moveIssueRequested(drop.source.issueId, column.statusName);
            drop.acceptProposedAction();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            objectName: `columnHeader-${column.statusName}`
            visible: column.showHeader
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            Layout.minimumHeight: column.headerHeight

            Rectangle {
                implicitWidth: Kirigami.Units.smallSpacing
                implicitHeight: Kirigami.Units.gridUnit
                radius: width / 2
                color: column.accent
            }
            Kirigami.Heading {
                text: column.heading
                level: column.compactHeader ? 4 : 3
                Layout.fillWidth: true
            }
            Loader {
                visible: active
                active: column.headerControl !== null
                sourceComponent: column.headerControl
            }
            Controls.Label {
                text: column.cards.length
                color: column.accent
                font.weight: Font.Bold
            }
        }

        Kirigami.Separator {
            visible: column.showHeader
            Layout.fillWidth: true
        }

        ListView {
            id: cardList
            objectName: `cardList-${column.statusName}`
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: column.cards
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar {
                id: cardListScrollBar
                objectName: `cardScrollBar-${column.statusName}`
            }

            delegate: Controls.ItemDelegate {
                id: card
                objectName: `issueCard-${issueId}`
                required property var modelData

                readonly property string issueId: String(modelData.id)
                readonly property string issueStatus: String(modelData.status)
                readonly property bool dragActive: dragArea.drag.active
                property alias gateIcon: gateBlockedIcon

                width: Math.max(
                    0,
                    ListView.view.width
                        - cardListScrollBar.width
                        - Kirigami.Units.smallSpacing
                )
                implicitHeight: cardContent.implicitHeight + topPadding + bottomPadding
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing
                topPadding: Kirigami.Units.largeSpacing
                bottomPadding: Kirigami.Units.largeSpacing
                hoverEnabled: true
                highlighted: dragArea.drag.active
                z: 1

                contentItem: ColumnLayout {
                    id: cardContent
                    spacing: Kirigami.Units.smallSpacing
                    z: 2

                    RowLayout {
                        Layout.fillWidth: true

                        Controls.Label {
                            text: card.modelData.id || ""
                            color: dragArea.drag.active
                                ? Kirigami.Theme.highlightedTextColor
                                : Kirigami.Theme.highlightColor
                            font.family: "monospace"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Components.IssueCopyButton {
                            objectName: `issueCopyButton-${card.issueId}`
                            issueId: card.issueId
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Layout.preferredWidth
                            z: 2
                            onCopyRequested: issueId => column.copyIssueIdRequested(issueId)
                        }
                        Controls.BusyIndicator {
                            objectName: `pendingIssue-${card.issueId}`
                            running: Boolean(card.modelData._pending)
                            visible: running
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth
                            Accessible.name: qsTr("Saving changes for %1").arg(card.issueId)
                        }
                        Kirigami.Icon {
                            id: gateBlockedIcon
                            objectName: `gateBlockedIcon-${card.issueId}`
                            visible: Boolean(card.modelData.blocked_by_gate)
                            source: "object-locked"
                            color: dragArea.drag.active
                                ? Kirigami.Theme.highlightedTextColor
                                : Kirigami.Theme.neutralTextColor
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth
                            Accessible.name: qsTr("Blocked by gate")

                            Controls.ToolTip.text: qsTr("Blocked by gate")
                            Controls.ToolTip.visible: gateIconHover.hovered
                            HoverHandler { id: gateIconHover }
                        }
                        Controls.Label {
                            text: `P${card.modelData.priority ?? 2}`
                            color: dragArea.drag.active
                                ? Kirigami.Theme.highlightedTextColor
                                : column.priorityColor(card.modelData.priority)
                            font.weight: Font.Bold
                        }
                        Kirigami.Icon {
                            source: "transform-move"
                            color: dragArea.drag.active
                                ? Kirigami.Theme.highlightedTextColor
                                : Kirigami.Theme.disabledTextColor
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth
                        }
                    }

                    Controls.Label {
                        text: card.modelData.title || qsTr("Untitled bead")
                        color: dragArea.drag.active
                            ? Kirigami.Theme.highlightedTextColor
                            : Kirigami.Theme.textColor
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: {
                            const parts = [];
                            if (card.modelData.issue_type)
                                parts.push(card.modelData.issue_type);
                            if (card.modelData.assignee)
                                parts.push(card.modelData.assignee);
                            return parts.join(" | ");
                        }
                        visible: text.length > 0
                        color: dragArea.drag.active
                            ? Kirigami.Theme.highlightedTextColor
                            : Kirigami.Theme.disabledTextColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Controls.Label {
                        text: card.modelData.labels ? card.modelData.labels.join(", ") : ""
                        visible: text.length > 0
                        color: dragArea.drag.active
                            ? Kirigami.Theme.highlightedTextColor
                            : column.accent
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    enabled: !column.backendLoading
                    hoverEnabled: true
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: column.dragProxy
                    drag.threshold: Kirigami.Units.gridUnit / 2

                    onPressed: mouse => {
                        const position = card.mapToItem(Controls.Overlay.overlay, 0, 0);
                        column.dragProxy.sourceCard = card;
                        column.dragProxy.x = position.x;
                        column.dragProxy.y = position.y;
                        mouse.accepted = true;
                    }
                    onClicked: column.openIssueRequested(card.issueId)
                    onReleased: {
                        column.dragProxy.Drag.drop();
                        column.dragProxy.sourceCard = null;
                    }
                    onCanceled: column.dragProxy.sourceCard = null
                }
            }

            Controls.Button {
                objectName: "emptyCreateButton"
                anchors.centerIn: parent
                visible: column.showCreateWhenEmpty
                    && column.totalCount === 0
                    && !column.backendLoading
                text: qsTr("Create bead")
                icon.name: "list-add"
                onClicked: column.createIssueRequested()
            }
        }
    }
}
