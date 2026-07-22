// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: openColumn

    required property var openCards
    required property int openCount
    required property var blockedCards
    required property int blockedCount
    required property var deferredCards
    required property int deferredCount
    required property bool backendLoading
    required property Item dragProxy

    signal moveIssueRequested(string issueId, string status)
    signal openIssueRequested(string issueId)
    signal createIssueRequested()
    signal copyIssueIdRequested(string issueId)

    radius: Kirigami.Units.cornerRadius
    color: Kirigami.Theme.backgroundColor

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        KanbanColumn {
            Layout.fillWidth: true
            Layout.fillHeight: true
            statusName: "open"
            heading: qsTr("Open")
            accent: Kirigami.Theme.positiveTextColor
            cards: openColumn.openCards
            totalCount: openColumn.openCount
            backendLoading: openColumn.backendLoading
            dragProxy: openColumn.dragProxy
            showCreateWhenEmpty: true
            onMoveIssueRequested: (issueId, status) => openColumn.moveIssueRequested(issueId, status)
            onOpenIssueRequested: issueId => openColumn.openIssueRequested(issueId)
            onCreateIssueRequested: openColumn.createIssueRequested()
            onCopyIssueIdRequested: issueId => openColumn.copyIssueIdRequested(issueId)
        }

        CollapsibleStatusSection {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            statusName: "blocked"
            heading: qsTr("Blocked")
            accent: Kirigami.Theme.negativeTextColor
            cards: openColumn.blockedCards
            totalCount: openColumn.blockedCount
            backendLoading: openColumn.backendLoading
            dragProxy: openColumn.dragProxy
            onMoveIssueRequested: (issueId, status) => openColumn.moveIssueRequested(issueId, status)
            onOpenIssueRequested: issueId => openColumn.openIssueRequested(issueId)
            onCreateIssueRequested: openColumn.createIssueRequested()
            onCopyIssueIdRequested: issueId => openColumn.copyIssueIdRequested(issueId)
        }

        CollapsibleStatusSection {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            statusName: "deferred"
            heading: qsTr("Deferred")
            accent: Kirigami.Theme.neutralTextColor
            cards: openColumn.deferredCards
            totalCount: openColumn.deferredCount
            backendLoading: openColumn.backendLoading
            dragProxy: openColumn.dragProxy
            onMoveIssueRequested: (issueId, status) => openColumn.moveIssueRequested(issueId, status)
            onOpenIssueRequested: issueId => openColumn.openIssueRequested(issueId)
            onCreateIssueRequested: openColumn.createIssueRequested()
            onCopyIssueIdRequested: issueId => openColumn.copyIssueIdRequested(issueId)
        }
    }
}
