// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import kde_beads

Kirigami.ApplicationWindow {
    id: root

    width: 1120
    height: 720
    minimumWidth: 420
    minimumHeight: 520
    visible: true
    title: qsTr("Beads")

    readonly property bool compactMode: width < Kirigami.Units.gridUnit * 42
    readonly property var visibleIssues: filterIssues(Backend.issues || [])

    function filterIssues(issues) {
        const query = searchField.text.trim().toLowerCase();
        const selectedStatus = statusFilter.currentIndex;
        return issues.filter(issue => {
            const statusMatches = selectedStatus === 0
                || (selectedStatus === 1 && issue.status === "open")
                || (selectedStatus === 2 && issue.status === "in_progress")
                || (selectedStatus === 3 && issue.status === "blocked")
                || (selectedStatus === 4 && issue.status === "deferred")
                || (selectedStatus === 5 && issue.status === "closed");
            if (!statusMatches)
                return false;
            if (query.length === 0)
                return true;
            const labels = issue.labels ? issue.labels.join(" ") : "";
            const haystack = `${issue.id || ""} ${issue.title || ""} ${issue.description || ""} ${labels}`.toLowerCase();
            return haystack.includes(query);
        });
    }

    function countStatus(status) {
        return (Backend.issues || []).filter(issue => issue.status === status).length;
    }

    function statusLabel(status) {
        switch (status) {
        case "in_progress": return qsTr("In progress");
        case "blocked": return qsTr("Blocked");
        case "deferred": return qsTr("Deferred");
        case "closed": return qsTr("Closed");
        default: return qsTr("Open");
        }
    }

    function statusColor(status) {
        switch (status) {
        case "in_progress": return Kirigami.Theme.highlightColor;
        case "blocked": return Kirigami.Theme.negativeTextColor;
        case "deferred": return Kirigami.Theme.neutralTextColor;
        case "closed": return Kirigami.Theme.disabledTextColor;
        default: return Kirigami.Theme.positiveTextColor;
        }
    }

    function priorityColor(priority) {
        if (priority === 0)
            return Kirigami.Theme.negativeTextColor;
        if (priority === 1)
            return Kirigami.Theme.neutralTextColor;
        if (priority === 2)
            return Kirigami.Theme.highlightColor;
        return Kirigami.Theme.disabledTextColor;
    }

    function formatDate(value) {
        return value ? Qt.formatDateTime(new Date(value), "yyyy-MM-dd  hh:mm") : qsTr("Not set");
    }

    component MetricCard: Rectangle {
        required property string label
        required property int value
        required property color accent

        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 7
        implicitHeight: Kirigami.Units.gridUnit * 4
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(accent, 0.09)
        border.color: Qt.alpha(accent, 0.32)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 0

            Kirigami.Heading {
                text: parent.parent.value
                level: 2
                color: parent.parent.accent
                Layout.alignment: Qt.AlignHCenter
            }
            Controls.Label {
                text: parent.parent.label
                color: Kirigami.Theme.disabledTextColor
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    component DetailText: ColumnLayout {
        required property string label
        required property string value

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: parent.label
            color: Kirigami.Theme.disabledTextColor
            font.weight: Font.DemiBold
        }
        Controls.Label {
            text: parent.value
            visible: text.length > 0
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Layout.fillWidth: true
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Open a Beads workspace")
        onAccepted: Backend.setWorkspace(selectedFolder.toString())
    }

    Connections {
        target: Backend

        function onLoadingChanged() {
            if (!Backend.loading && Backend.errorMessage.length === 0
                    && !root.compactMode && Backend.selectedId.length === 0
                    && Backend.issues.length > 0) {
                Backend.showIssue(String(Backend.issues[0].id));
            }
        }
    }

    pageStack.initialPage: Kirigami.Page {
        id: overviewPage
        title: qsTr("Beads")
        padding: 0

        actions: [
            Kirigami.Action {
                text: qsTr("Open Workspace")
                icon.name: "folder-open"
                enabled: !Backend.loading
                onTriggered: folderDialog.open()
            },
            Kirigami.Action {
                text: qsTr("Refresh")
                icon.name: "view-refresh"
                enabled: !Backend.loading
                shortcut: StandardKey.Refresh
                onTriggered: Backend.reload()
            }
        ]

        Component.onCompleted: Backend.reload()

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Controls.ProgressBar {
                Layout.fillWidth: true
                implicitHeight: Backend.loading ? Kirigami.Units.smallSpacing : 0
                indeterminate: true
                visible: Backend.loading
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                visible: Backend.errorMessage.length > 0
                type: Kirigami.MessageType.Error
                text: Backend.errorMessage
                actions: Kirigami.Action {
                    text: qsTr("Dismiss")
                    icon.name: "dialog-close"
                    onTriggered: Backend.clearError()
                }
            }

            Controls.Pane {
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true

                        Kirigami.Heading {
                            text: Backend.workspace.split("/").pop() || Backend.workspace
                            level: 2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Controls.Label {
                            text: qsTr("%1 beads").arg((Backend.issues || []).length)
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }

                    Controls.Label {
                        text: Backend.workspace
                        color: Kirigami.Theme.disabledTextColor
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    GridLayout {
                        columns: root.width < Kirigami.Units.gridUnit * 32 ? 2 : 4
                        rowSpacing: Kirigami.Units.smallSpacing
                        columnSpacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        MetricCard {
                            label: qsTr("Open")
                            value: root.countStatus("open")
                            accent: Kirigami.Theme.positiveTextColor
                        }
                        MetricCard {
                            label: qsTr("In progress")
                            value: root.countStatus("in_progress")
                            accent: Kirigami.Theme.highlightColor
                        }
                        MetricCard {
                            label: qsTr("Blocked")
                            value: root.countStatus("blocked")
                            accent: Kirigami.Theme.negativeTextColor
                        }
                        MetricCard {
                            label: qsTr("Closed")
                            value: root.countStatus("closed")
                            accent: Kirigami.Theme.disabledTextColor
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Controls.TextField {
                            id: searchField
                            placeholderText: qsTr("Search title, ID, description, or label")
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
                        Controls.ComboBox {
                            id: statusFilter
                            model: [qsTr("All"), qsTr("Open"), qsTr("In progress"), qsTr("Blocked"), qsTr("Deferred"), qsTr("Closed")]
                            Accessible.name: qsTr("Filter by status")
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Controls.Frame {
                    visible: !root.compactMode || Backend.selectedId.length === 0
                    Layout.preferredWidth: root.compactMode ? overviewPage.width : Kirigami.Units.gridUnit * 23
                    Layout.fillWidth: root.compactMode
                    Layout.fillHeight: true
                    padding: 0

                    background: Rectangle {
                        color: Kirigami.Theme.backgroundColor
                    }

                    ListView {
                        id: issueList
                        anchors.fill: parent
                        clip: true
                        model: root.visibleIssues
                        currentIndex: -1
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Controls.ItemDelegate {
                            id: issueDelegate
                            required property var modelData

                            width: ListView.view.width
                            highlighted: Backend.selectedId === String(modelData.id)
                            onClicked: Backend.showIssue(String(modelData.id))

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Rectangle {
                                    Layout.preferredWidth: Kirigami.Units.smallSpacing
                                    Layout.fillHeight: true
                                    radius: width / 2
                                    color: root.priorityColor(issueDelegate.modelData.priority)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Controls.Label {
                                            text: issueDelegate.modelData.id || ""
                                            font.family: "monospace"
                                            font.weight: Font.DemiBold
                                            color: Kirigami.Theme.highlightColor
                                        }
                                        Controls.Label {
                                            text: `P${issueDelegate.modelData.priority ?? 2}`
                                            color: root.priorityColor(issueDelegate.modelData.priority)
                                        }
                                        Item { Layout.fillWidth: true }
                                        Controls.Label {
                                            text: root.statusLabel(issueDelegate.modelData.status)
                                            color: root.statusColor(issueDelegate.modelData.status)
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Controls.Label {
                                        text: issueDelegate.modelData.title || qsTr("Untitled bead")
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Controls.Label {
                                        text: issueDelegate.modelData.labels ? issueDelegate.modelData.labels.join("  |  ") : ""
                                        visible: text.length > 0
                                        color: Kirigami.Theme.disabledTextColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }

                        Kirigami.PlaceholderMessage {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, implicitWidth)
                            visible: issueList.count === 0 && !Backend.loading
                            icon.name: searchField.text.length > 0 || statusFilter.currentIndex > 0 ? "edit-find" : "view-task"
                            text: searchField.text.length > 0 || statusFilter.currentIndex > 0 ? qsTr("No matching beads") : qsTr("No beads yet")
                            explanation: searchField.text.length > 0 || statusFilter.currentIndex > 0
                                ? qsTr("Try a different search or status.")
                                : qsTr("This workspace did not return any issues from bd.")
                        }
                    }
                }

                Kirigami.Separator {
                    visible: !root.compactMode
                    Layout.fillHeight: true
                }

                Controls.Frame {
                    visible: !root.compactMode || Backend.selectedId.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: 0

                    background: Rectangle {
                        color: Kirigami.Theme.alternateBackgroundColor
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, implicitWidth)
                        visible: Backend.selectedId.length === 0
                        icon.name: "view-task"
                        text: qsTr("Select a bead")
                        explanation: qsTr("Choose an issue to inspect its details.")
                    }

                    Controls.ScrollView {
                        id: detailScroll
                        anchors.fill: parent
                        visible: Backend.selectedId.length > 0
                        contentWidth: availableWidth

                        ColumnLayout {
                            readonly property var issue: Backend.detail || ({})

                            width: detailScroll.availableWidth
                            spacing: Kirigami.Units.largeSpacing

                            Controls.ToolButton {
                                visible: root.compactMode
                                text: qsTr("Back to beads")
                                icon.name: "arrow-left"
                                onClicked: Backend.clearSelection()
                                Layout.leftMargin: Kirigami.Units.largeSpacing
                                Layout.topMargin: Kirigami.Units.largeSpacing
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.margins: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing

                                RowLayout {
                                    Layout.fillWidth: true

                                    Controls.Label {
                                        text: parent.parent.parent.issue.id || Backend.selectedId
                                        font.family: "monospace"
                                        font.weight: Font.Bold
                                        color: Kirigami.Theme.highlightColor
                                    }
                                    Rectangle {
                                        implicitWidth: statusText.implicitWidth + Kirigami.Units.largeSpacing
                                        implicitHeight: statusText.implicitHeight + Kirigami.Units.smallSpacing
                                        radius: height / 2
                                        color: Qt.alpha(root.statusColor(parent.parent.parent.issue.status), 0.13)
                                        border.color: Qt.alpha(root.statusColor(parent.parent.parent.issue.status), 0.4)

                                        Controls.Label {
                                            id: statusText
                                            anchors.centerIn: parent
                                            text: root.statusLabel(parent.parent.parent.parent.issue.status)
                                            color: root.statusColor(parent.parent.parent.parent.issue.status)
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Controls.Label {
                                        text: `P${parent.parent.parent.issue.priority ?? 2}`
                                        color: root.priorityColor(parent.parent.parent.issue.priority)
                                        font.weight: Font.Bold
                                    }
                                }

                                Kirigami.Heading {
                                    text: parent.parent.issue.title || qsTr("Untitled bead")
                                    level: 1
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                Controls.Label {
                                    text: parent.parent.issue.issue_type || qsTr("task")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.capitalization: Font.Capitalize
                                }

                                Kirigami.Separator { Layout.fillWidth: true }

                                DetailText {
                                    label: qsTr("Description")
                                    value: parent.parent.issue.description || qsTr("No description provided.")
                                }
                                DetailText {
                                    visible: value.length > 0
                                    label: qsTr("Acceptance criteria")
                                    value: parent.parent.issue.acceptance_criteria || ""
                                }
                                DetailText {
                                    visible: value.length > 0
                                    label: qsTr("Design")
                                    value: parent.parent.issue.design || ""
                                }
                                DetailText {
                                    visible: value.length > 0
                                    label: qsTr("Notes")
                                    value: parent.parent.issue.notes || ""
                                }

                                Kirigami.Separator { Layout.fillWidth: true }

                                GridLayout {
                                    columns: detailScroll.availableWidth > Kirigami.Units.gridUnit * 32 ? 2 : 1
                                    columnSpacing: Kirigami.Units.gridUnit * 3
                                    rowSpacing: Kirigami.Units.largeSpacing
                                    Layout.fillWidth: true

                                    DetailText {
                                        label: qsTr("Assignee")
                                        value: parent.parent.parent.issue.assignee || qsTr("Unassigned")
                                    }
                                    DetailText {
                                        label: qsTr("Owner")
                                        value: parent.parent.parent.issue.owner || qsTr("Not set")
                                    }
                                    DetailText {
                                        label: qsTr("Created")
                                        value: root.formatDate(parent.parent.parent.issue.created_at)
                                    }
                                    DetailText {
                                        label: qsTr("Updated")
                                        value: root.formatDate(parent.parent.parent.issue.updated_at)
                                    }
                                    DetailText {
                                        label: qsTr("Labels")
                                        value: parent.parent.parent.issue.labels ? parent.parent.parent.issue.labels.join(", ") : qsTr("None")
                                    }
                                    DetailText {
                                        label: qsTr("Dependencies")
                                        value: qsTr("%1 blocking | %2 blocked by")
                                            .arg(parent.parent.parent.issue.dependent_count || 0)
                                            .arg(parent.parent.parent.issue.dependency_count || 0)
                                    }
                                }

                                DetailText {
                                    visible: value.length > 0
                                    label: qsTr("Close reason")
                                    value: parent.parent.issue.close_reason || ""
                                }

                                Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
                            }
                        }
                    }
                }
            }
        }
    }
}
