// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "components" as Components

Kirigami.Page {
    id: todoPage
    objectName: "todoPage"

    required property var issues
    required property bool backendLoading
    required property bool backendRefreshing
    required property string backendErrorMessage

    signal addTodoRequested(string title)
    signal openIssueRequested(string issueId)
    signal moveIssueRequested(string issueId, string status)
    signal copyIssueIdRequested(string issueId)
    signal dismissErrorRequested()

    readonly property var todoItems: (issues || [])
        .filter(issue => issue.issue_type === "task"
            && (issue.status === "open" || issue.status === "in_progress"))
        .sort((left, right) => {
            if (left.status !== right.status)
                return left.status === "in_progress" ? -1 : 1;
            const priorityDifference = Number(left.priority ?? 2)
                - Number(right.priority ?? 2);
            if (priorityDifference !== 0)
                return priorityDifference;
            return String(left.created_at || "").localeCompare(
                String(right.created_at || "")
            );
        })

    title: qsTr("Todo")
    padding: 0

    function focusAdd() {
        todoTitleField.forceActiveFocus();
    }

    function addTodo() {
        const title = todoTitleField.text.trim();
        if (title.length === 0 || backendLoading)
            return false;
        addTodoRequested(title);
        todoTitleField.clear();
        return true;
    }

    Controls.ProgressBar {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Kirigami.Units.smallSpacing
        indeterminate: true
        visible: todoPage.backendLoading || todoPage.backendRefreshing
        z: 1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: todoPage.backendErrorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: todoPage.backendErrorMessage
            actions: Kirigami.Action {
                text: qsTr("Dismiss")
                icon.name: "dialog-close"
                onTriggered: todoPage.dismissErrorRequested()
            }
        }

        Controls.Pane {
            Layout.fillWidth: true

            RowLayout {
                anchors.fill: parent

                Controls.TextField {
                    id: todoTitleField
                    objectName: "todoTitleField"
                    Layout.fillWidth: true
                    placeholderText: qsTr("Add a todo")
                    enabled: !todoPage.backendLoading
                    onAccepted: todoPage.addTodo()
                }
                Controls.Button {
                    objectName: "addTodoButton"
                    text: qsTr("Add")
                    icon.name: "list-add"
                    enabled: !todoPage.backendLoading
                        && todoTitleField.text.trim().length > 0
                    onClicked: todoPage.addTodo()
                }
            }
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: todoPage.todoItems.length === 0
            text: qsTr("Nothing to do")
            explanation: qsTr("Add a todo above or move a task back from Closed.")
            icon.name: "checkmark"
        }

        ListView {
            id: todoList
            objectName: "todoList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            visible: todoPage.todoItems.length > 0
            model: todoPage.todoItems
            spacing: Kirigami.Units.smallSpacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar {}

            delegate: Controls.Frame {
                id: todoRow
                objectName: `todoRow-${issueId}`
                required property var modelData
                readonly property string issueId: String(modelData.id || "")
                width: ListView.view.width
                enabled: !todoPage.backendLoading
                padding: Kirigami.Units.smallSpacing

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Controls.CheckBox {
                        objectName: `completeTodo-${todoRow.issueId}`
                        checked: false
                        text: ""
                        Accessible.name: qsTr("Complete %1").arg(
                            todoRow.modelData.title || todoRow.issueId
                        )
                        Controls.ToolTip.text: Accessible.name
                        Controls.ToolTip.visible: hovered
                        onClicked: todoPage.moveIssueRequested(todoRow.issueId, "closed")
                    }

                    Controls.ItemDelegate {
                        Layout.fillWidth: true
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: Kirigami.Units.smallSpacing
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        onClicked: todoPage.openIssueRequested(todoRow.issueId)

                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Controls.Label {
                                text: todoRow.modelData.title || qsTr("Untitled todo")
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing

                                Controls.Label {
                                    text: todoRow.issueId
                                    color: Kirigami.Theme.disabledTextColor
                                    font.family: "monospace"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Controls.Label {
                                    text: todoRow.modelData.status === "in_progress"
                                        ? qsTr("In progress")
                                        : qsTr("Todo")
                                    color: todoRow.modelData.status === "in_progress"
                                        ? Kirigami.Theme.highlightColor
                                        : Kirigami.Theme.disabledTextColor
                                }
                                Controls.Label {
                                    text: qsTr("Priority %1").arg(todoRow.modelData.priority ?? 2)
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }
                        }
                    }
                    Controls.Button {
                        objectName: `toggleTodoProgress-${todoRow.issueId}`
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                        text: todoRow.modelData.status === "in_progress"
                            ? qsTr("Move to todo")
                            : qsTr("Start")
                        icon.name: todoRow.modelData.status === "in_progress"
                            ? "go-previous"
                            : "media-playback-start"
                        onClicked: todoPage.moveIssueRequested(
                            todoRow.issueId,
                            todoRow.modelData.status === "in_progress"
                                ? "open"
                                : "in_progress"
                        )
                    }
                    Controls.BusyIndicator {
                        running: Boolean(todoRow.modelData._pending)
                        visible: running
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                        Accessible.name: qsTr("Saving changes for %1").arg(todoRow.issueId)
                    }
                    Components.IssueCopyButton {
                        issueId: todoRow.issueId
                        onCopyRequested: issueId => todoPage.copyIssueIdRequested(issueId)
                    }
                }
            }
        }
    }
}
