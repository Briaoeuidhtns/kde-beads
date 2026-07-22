// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "board" as Board

Kirigami.Page {
    id: boardPage
    objectName: "boardPage"

    required property var issues
    required property bool backendLoading
    required property string backendErrorMessage
    required property string workspace

    signal createIssueRequested()
    signal openIssueRequested(string issueId)
    signal moveIssueRequested(string issueId, string status)
    signal copyIssueIdRequested(string issueId)
    signal refreshRequested()
    signal dismissErrorRequested()

    title: qsTr("Beads")
    padding: 0

    function issuesForStatus(status) {
        const query = searchField.text.trim().toLowerCase();
        return (issues || []).filter(issue => {
            if (issue.status !== status)
                return false;
            if (query.length === 0)
                return true;
            const labels = issue.labels ? issue.labels.join(" ") : "";
            const haystack = `${issue.id || ""} ${issue.title || ""} ${issue.description || ""} ${labels} ${issue.assignee || ""}`.toLowerCase();
            return haystack.includes(query);
        });
    }

    function statusCount(status) {
        return (issues || []).filter(issue => issue.status === status).length;
    }

    actions: [
        Kirigami.Action {
            objectName: "createTicketAction"
            text: qsTr("Create Ticket")
            icon.name: "list-add"
            enabled: !boardPage.backendLoading
            shortcut: "Ctrl+N"
            onTriggered: boardPage.createIssueRequested()
        },
        Kirigami.Action {
            text: qsTr("Refresh")
            icon.name: "view-refresh"
            enabled: !boardPage.backendLoading
            shortcut: StandardKey.Refresh
            onTriggered: boardPage.refreshRequested()
        }
    ]

    Board.CardDragProxy {
        id: cardDragProxy
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Controls.ProgressBar {
            Layout.fillWidth: true
            implicitHeight: boardPage.backendLoading ? Kirigami.Units.smallSpacing : 0
            indeterminate: true
            visible: boardPage.backendLoading
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: boardPage.backendErrorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: boardPage.backendErrorMessage
            actions: Kirigami.Action {
                text: qsTr("Dismiss")
                icon.name: "dialog-close"
                onTriggered: boardPage.dismissErrorRequested()
            }
        }

        Controls.Pane {
            Layout.fillWidth: true

            RowLayout {
                anchors.fill: parent

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Kirigami.Heading {
                        text: boardPage.workspace.split("/").pop() || boardPage.workspace
                        level: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        text: boardPage.workspace
                        color: Kirigami.Theme.disabledTextColor
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                Controls.Label {
                    text: qsTr("%1 beads").arg((boardPage.issues || []).length)
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing

            Controls.TextField {
                id: searchField
                placeholderText: qsTr("Search title, ID, description, label, or assignee")
                leftPadding: Kirigami.Units.gridUnit * 2
                Layout.fillWidth: true

                Kirigami.Icon {
                    source: "search"
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Flickable {
            id: boardFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.smallSpacing
            contentWidth: boardRow.width
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            Controls.ScrollBar.horizontal: Controls.ScrollBar {}

            Row {
                id: boardRow
                height: boardFlick.height - Kirigami.Units.gridUnit
                spacing: Kirigami.Units.largeSpacing
                readonly property real compactWidth: Kirigami.Units.gridUnit * 16
                readonly property real focusWidth: Math.max(
                    Kirigami.Units.gridUnit * 20,
                    (boardFlick.width - compactWidth - spacing * 2) / 2
                )

                Board.OpenColumn {
                    width: boardRow.focusWidth
                    height: boardRow.height
                    openCards: boardPage.issuesForStatus("open")
                    openCount: boardPage.statusCount("open")
                    blockedCards: boardPage.issuesForStatus("blocked")
                    blockedCount: boardPage.statusCount("blocked")
                    deferredCards: boardPage.issuesForStatus("deferred")
                    deferredCount: boardPage.statusCount("deferred")
                    backendLoading: boardPage.backendLoading
                    dragProxy: cardDragProxy
                    onMoveIssueRequested: (issueId, status) => boardPage.moveIssueRequested(issueId, status)
                    onOpenIssueRequested: issueId => boardPage.openIssueRequested(issueId)
                    onCreateIssueRequested: boardPage.createIssueRequested()
                    onCopyIssueIdRequested: issueId => boardPage.copyIssueIdRequested(issueId)
                }
                Board.KanbanColumn {
                    width: boardRow.focusWidth
                    height: boardRow.height
                    statusName: "in_progress"
                    heading: qsTr("In progress")
                    accent: Kirigami.Theme.highlightColor
                    cards: boardPage.issuesForStatus("in_progress")
                    totalCount: boardPage.statusCount("in_progress")
                    backendLoading: boardPage.backendLoading
                    dragProxy: cardDragProxy
                    onMoveIssueRequested: (issueId, status) => boardPage.moveIssueRequested(issueId, status)
                    onOpenIssueRequested: issueId => boardPage.openIssueRequested(issueId)
                    onCreateIssueRequested: boardPage.createIssueRequested()
                    onCopyIssueIdRequested: issueId => boardPage.copyIssueIdRequested(issueId)
                }
                Board.KanbanColumn {
                    width: boardRow.compactWidth
                    height: boardRow.height
                    statusName: "closed"
                    heading: qsTr("Closed")
                    accent: Kirigami.Theme.disabledTextColor
                    cards: boardPage.issuesForStatus("closed")
                    totalCount: boardPage.statusCount("closed")
                    backendLoading: boardPage.backendLoading
                    dragProxy: cardDragProxy
                    onMoveIssueRequested: (issueId, status) => boardPage.moveIssueRequested(issueId, status)
                    onOpenIssueRequested: issueId => boardPage.openIssueRequested(issueId)
                    onCreateIssueRequested: boardPage.createIssueRequested()
                    onCopyIssueIdRequested: issueId => boardPage.copyIssueIdRequested(issueId)
                }
            }
        }
    }
}
