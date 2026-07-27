// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: workspacePage
    objectName: "workspacePage"

    required property var issues
    required property bool backendLoading
    required property bool backendRefreshing
    required property string backendErrorMessage
    required property string workspace

    signal addTodoRequested(string title)
    signal createIssueRequested()
    signal openIssueRequested(string issueId)
    signal moveIssueRequested(string issueId, string status)
    signal copyIssueIdRequested(string issueId)
    signal dismissErrorRequested()

    title: workspaceTabs.currentIndex === 0 ? qsTr("Board") : qsTr("Todo")
    padding: 0

    actions: [
        Kirigami.Action {
            objectName: "createTicketAction"
            text: qsTr("Create Bead")
            icon.name: "list-add"
            visible: workspaceTabs.currentIndex === 0
            enabled: !workspacePage.backendLoading
            shortcut: "Ctrl+N"
            onTriggered: workspacePage.createIssueRequested()
        },
        Kirigami.Action {
            objectName: "focusAddTodoAction"
            text: qsTr("Add Todo")
            icon.name: "list-add"
            visible: workspaceTabs.currentIndex === 1
            enabled: !workspacePage.backendLoading
            shortcut: "Ctrl+N"
            onTriggered: todoPage.focusAdd()
        }
    ]

    header: Controls.TabBar {
        id: workspaceTabs
        objectName: "workspaceTabs"

        Controls.TabButton {
            objectName: "boardTab"
            text: qsTr("Board")
            icon.name: "view-grid"
        }
        Controls.TabButton {
            objectName: "todoTab"
            text: qsTr("Todo")
            icon.name: "view-task"
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: workspaceTabs.currentIndex

        BoardPage {
            id: boardPage
            issues: workspacePage.issues
            backendLoading: workspacePage.backendLoading
            backendRefreshing: workspacePage.backendRefreshing
            backendErrorMessage: workspacePage.backendErrorMessage
            workspace: workspacePage.workspace
            onCreateIssueRequested: workspacePage.createIssueRequested()
            onOpenIssueRequested: issueId => workspacePage.openIssueRequested(issueId)
            onMoveIssueRequested: (issueId, status) => workspacePage.moveIssueRequested(issueId, status)
            onCopyIssueIdRequested: issueId => workspacePage.copyIssueIdRequested(issueId)
            onDismissErrorRequested: workspacePage.dismissErrorRequested()
        }

        TodoPage {
            id: todoPage
            issues: workspacePage.issues
            backendLoading: workspacePage.backendLoading
            backendRefreshing: workspacePage.backendRefreshing
            backendErrorMessage: workspacePage.backendErrorMessage
            onAddTodoRequested: title => workspacePage.addTodoRequested(title)
            onOpenIssueRequested: issueId => workspacePage.openIssueRequested(issueId)
            onMoveIssueRequested: (issueId, status) => workspacePage.moveIssueRequested(issueId, status)
            onCopyIssueIdRequested: issueId => workspacePage.copyIssueIdRequested(issueId)
            onDismissErrorRequested: workspacePage.dismissErrorRequested()
        }
    }
}
