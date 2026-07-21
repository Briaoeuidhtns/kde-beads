// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import kde_beads

Kirigami.ApplicationWindow {
    id: root

    width: 1280
    height: 760
    minimumWidth: 680
    minimumHeight: 520
    visible: true
    title: qsTr("Beads")

    function issuesForStatus(status) {
        const query = searchField.text.trim().toLowerCase();
        return (Backend.issues || []).filter(issue => {
            if (issue.status !== status)
                return false;
            if (query.length === 0)
                return true;
            const labels = issue.labels ? issue.labels.join(" ") : "";
            const haystack = `${issue.id || ""} ${issue.title || ""} ${issue.description || ""} ${labels} ${issue.assignee || ""}`.toLowerCase();
            return haystack.includes(query);
        });
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

    function openEditor(issueId) {
        if (Backend.loading)
            return;
        Backend.loadIssue(issueId);
        pageStack.push(editorPageComponent, { "issueId": issueId });
    }

    component KanbanColumn: Rectangle {
        id: column

        required property string statusName
        required property string heading
        required property color accent
        readonly property var cards: root.issuesForStatus(statusName)

        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(accent, dropArea.containsDrag ? 0.17 : 0.055)
        border.color: Qt.alpha(accent, dropArea.containsDrag ? 0.75 : 0.24)

        DropArea {
            id: dropArea
            anchors.fill: parent
            keys: ["bead-card"]

            onDropped: drop => {
                if (drop.source.issueStatus !== column.statusName)
                    Backend.moveIssue(drop.source.issueId, column.statusName);
                drop.acceptProposedAction();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing

                Rectangle {
                    implicitWidth: Kirigami.Units.smallSpacing
                    implicitHeight: Kirigami.Units.gridUnit
                    radius: width / 2
                    color: column.accent
                }
                Kirigami.Heading {
                    text: column.heading
                    level: 3
                    Layout.fillWidth: true
                }
                Controls.Label {
                    text: column.cards.length
                    color: column.accent
                    font.weight: Font.Bold
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            ListView {
                id: cardList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: column.cards
                spacing: Kirigami.Units.smallSpacing
                clip: false
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar {}

                delegate: Rectangle {
                    id: card
                    required property var modelData

                    readonly property string issueId: String(modelData.id)
                    readonly property string issueStatus: String(modelData.status)
                    property real restingX: 0
                    property real restingY: 0

                    width: ListView.view.width
                    implicitHeight: cardContent.implicitHeight + Kirigami.Units.largeSpacing
                    radius: Kirigami.Units.cornerRadius
                    color: dragArea.drag.active
                        ? Kirigami.Theme.highlightColor
                        : Kirigami.Theme.backgroundColor
                    border.color: dragArea.containsMouse || dragArea.drag.active
                        ? Kirigami.Theme.highlightColor
                        : Qt.alpha(Kirigami.Theme.textColor, 0.16)
                    z: dragArea.drag.active ? 100 : 1

                    Drag.active: dragArea.drag.active
                    Drag.source: card
                    Drag.keys: ["bead-card"]
                    Drag.supportedActions: Qt.MoveAction
                    Drag.proposedAction: Qt.MoveAction
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: Kirigami.Units.gridUnit

                    ColumnLayout {
                        id: cardContent
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: 2

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
                            Controls.Label {
                                text: `P${card.modelData.priority ?? 2}`
                                color: dragArea.drag.active
                                    ? Kirigami.Theme.highlightedTextColor
                                    : root.priorityColor(card.modelData.priority)
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
                        enabled: !Backend.loading
                        hoverEnabled: true
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: card
                        drag.threshold: Kirigami.Units.gridUnit / 2

                        onPressed: mouse => {
                            card.restingX = card.x;
                            card.restingY = card.y;
                            mouse.accepted = true;
                        }
                        onClicked: root.openEditor(card.issueId)
                        onReleased: {
                            card.Drag.drop();
                            card.x = card.restingX;
                            card.y = card.restingY;
                            Qt.callLater(() => cardList.forceLayout());
                        }
                        onCanceled: {
                            card.x = card.restingX;
                            card.y = card.restingY;
                            Qt.callLater(() => cardList.forceLayout());
                        }
                    }
                }

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Kirigami.Units.gridUnit, implicitWidth)
                    visible: cardList.count === 0 && !Backend.loading
                    icon.name: searchField.text.length > 0 ? "edit-find" : "view-task"
                    text: searchField.text.length > 0 ? qsTr("No matches") : qsTr("No beads")
                }
            }
        }
    }

    component BeadEditorPage: Kirigami.ScrollablePage {
        id: editor

        required property string issueId

        title: titleField.text.length > 0 ? titleField.text : issueId

        function statusIndex(status) {
            const statuses = ["open", "in_progress", "blocked", "deferred", "closed"];
            return Math.max(0, statuses.indexOf(status));
        }

        function populate() {
            const issue = Backend.detail || {};
            if (String(issue.id || "") !== issueId)
                return;
            titleField.text = issue.title || "";
            descriptionField.text = issue.description || "";
            acceptanceField.text = issue.acceptance_criteria || "";
            designField.text = issue.design || "";
            notesField.text = issue.notes || "";
            statusField.currentIndex = statusIndex(issue.status);
            priorityField.currentIndex = issue.priority ?? 2;
            typeField.editText = issue.issue_type || "task";
            assigneeField.text = issue.assignee || "";
            labelsField.text = issue.labels ? issue.labels.join(", ") : "";
        }

        function save() {
            Backend.saveIssue({
                "id": issueId,
                "title": titleField.text,
                "description": descriptionField.text,
                "acceptanceCriteria": acceptanceField.text,
                "design": designField.text,
                "notes": notesField.text,
                "status": statusField.currentValue,
                "priority": String(priorityField.currentIndex),
                "issueType": typeField.editText,
                "assignee": assigneeField.text,
                "labels": labelsField.text
            });
        }

        actions: [
            Kirigami.Action {
                text: qsTr("Save")
                icon.name: "document-save"
                enabled: !Backend.loading && titleField.text.trim().length > 0
                shortcut: StandardKey.Save
                onTriggered: editor.save()
            }
        ]

        Component.onCompleted: {
            editor.populate();
            Backend.loadIssue(issueId);
        }

        Connections {
            target: Backend

            function onDetailChanged() {
                if (!Backend.loading)
                    editor.populate();
            }

            function onLoadingChanged() {
                if (!Backend.loading)
                    editor.populate();
            }

            function onIssueSaved(savedId) {
                if (savedId === editor.issueId)
                    root.pageStack.pop();
            }
        }

        ColumnLayout {
            width: editor.availableWidth
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: Backend.errorMessage.length > 0
                type: Kirigami.MessageType.Error
                text: Backend.errorMessage
                actions: Kirigami.Action {
                    text: qsTr("Dismiss")
                    icon.name: "dialog-close"
                    onTriggered: Backend.clearError()
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Controls.Label {
                    text: editor.issueId
                    color: Kirigami.Theme.highlightColor
                    font.family: "monospace"
                    font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                Controls.BusyIndicator {
                    running: Backend.loading
                    visible: running
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                }
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                enabled: !Backend.loading

                Controls.TextField {
                    id: titleField
                    Kirigami.FormData.label: qsTr("Title:")
                    Layout.fillWidth: true
                    placeholderText: qsTr("Issue title")
                }

                Controls.ComboBox {
                    id: statusField
                    Kirigami.FormData.label: qsTr("Status:")
                    textRole: "text"
                    valueRole: "value"
                    model: [
                        { "text": qsTr("Open"), "value": "open" },
                        { "text": qsTr("In progress"), "value": "in_progress" },
                        { "text": qsTr("Blocked"), "value": "blocked" },
                        { "text": qsTr("Deferred"), "value": "deferred" },
                        { "text": qsTr("Closed"), "value": "closed" }
                    ]
                }

                Controls.ComboBox {
                    id: priorityField
                    Kirigami.FormData.label: qsTr("Priority:")
                    model: ["P0 - Critical", "P1 - High", "P2 - Medium", "P3 - Low", "P4 - Backlog"]
                }

                Controls.ComboBox {
                    id: typeField
                    Kirigami.FormData.label: qsTr("Type:")
                    editable: true
                    model: ["bug", "feature", "task", "epic", "chore", "decision"]
                }

                Controls.TextField {
                    id: assigneeField
                    Kirigami.FormData.label: qsTr("Assignee:")
                    Layout.fillWidth: true
                    placeholderText: qsTr("Unassigned")
                }

                Controls.TextField {
                    id: labelsField
                    Kirigami.FormData.label: qsTr("Labels:")
                    Layout.fillWidth: true
                    placeholderText: qsTr("Comma-separated labels")
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Description:")
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 7

                    Controls.TextArea {
                        id: descriptionField
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Describe the work")
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Acceptance:")
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5

                    Controls.TextArea {
                        id: acceptanceField
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Acceptance criteria")
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Design:")
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5

                    Controls.TextArea {
                        id: designField
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Implementation notes")
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Notes:")
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5

                    Controls.TextArea {
                        id: notesField
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Additional notes")
                    }
                }
            }
        }
    }

    Component {
        id: editorPageComponent
        BeadEditorPage {}
    }

    pageStack.initialPage: Kirigami.Page {
        id: boardPage
        title: qsTr("Beads")
        padding: 0

        actions: [
            Kirigami.Action {
                text: qsTr("Open Workspace")
                icon.name: "folder-open"
                enabled: !Backend.loading
                onTriggered: Backend.chooseWorkspace()
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

                RowLayout {
                    anchors.fill: parent

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Kirigami.Heading {
                            text: Backend.workspace.split("/").pop() || Backend.workspace
                            level: 2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Controls.Label {
                            text: Backend.workspace
                            color: Kirigami.Theme.disabledTextColor
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }

                    Controls.Label {
                        text: qsTr("%1 beads").arg((Backend.issues || []).length)
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
                    spacing: Kirigami.Units.smallSpacing
                    readonly property real columnWidth: Math.max(
                        Kirigami.Units.gridUnit * 13,
                        (boardFlick.width - spacing * 4) / 5
                    )

                    KanbanColumn {
                        width: boardRow.columnWidth
                        height: boardRow.height
                        statusName: "open"
                        heading: qsTr("Open")
                        accent: Kirigami.Theme.positiveTextColor
                    }
                    KanbanColumn {
                        width: boardRow.columnWidth
                        height: boardRow.height
                        statusName: "in_progress"
                        heading: qsTr("In progress")
                        accent: Kirigami.Theme.highlightColor
                    }
                    KanbanColumn {
                        width: boardRow.columnWidth
                        height: boardRow.height
                        statusName: "blocked"
                        heading: qsTr("Blocked")
                        accent: Kirigami.Theme.negativeTextColor
                    }
                    KanbanColumn {
                        width: boardRow.columnWidth
                        height: boardRow.height
                        statusName: "deferred"
                        heading: qsTr("Deferred")
                        accent: Kirigami.Theme.neutralTextColor
                    }
                    KanbanColumn {
                        width: boardRow.columnWidth
                        height: boardRow.height
                        statusName: "closed"
                        heading: qsTr("Closed")
                        accent: Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }
    }
}
