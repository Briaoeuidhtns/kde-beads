// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import kde_beads

Kirigami.ApplicationWindow {
    id: root
    objectName: "applicationWindow"

    width: 1280
    height: 760
    minimumWidth: 680
    minimumHeight: 520
    visible: true
    title: qsTr("Beads")

    Timer {
        objectName: "changePollTimer"
        interval: 2000
        running: true
        repeat: true
        onTriggered: Backend.poll()
    }

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

    function statusCount(status) {
        return (Backend.issues || []).filter(issue => issue.status === status).length;
    }

    function attachmentIcon(mimeType) {
        if (String(mimeType || "").startsWith("image/"))
            return "image-x-generic";
        if (mimeType === "application/pdf")
            return "application-pdf";
        if (String(mimeType || "").startsWith("text/"))
            return "text-x-generic";
        return "application-x-generic";
    }

    function formatBytes(byteSize) {
        const size = Number(byteSize || 0);
        if (size < 1024)
            return `${size} B`;
        if (size < 1024 * 1024)
            return `${(size / 1024).toFixed(1)} KB`;
        if (size < 1024 * 1024 * 1024)
            return `${(size / (1024 * 1024)).toFixed(1)} MB`;
        return `${(size / (1024 * 1024 * 1024)).toFixed(1)} GB`;
    }

    function localFileUrl(path) {
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function openEditor(issueId) {
        if (Backend.loading)
            return;
        pageStack.layers.push(editorPageComponent, { "issueId": issueId });
    }

    function openCreate(parentId) {
        if (Backend.loading)
            return;
        pageStack.layers.push(editorPageComponent, {
            "creating": true,
            "parentId": String(parentId || "")
        });
    }

    Item {
        id: cardDragProxy
        parent: Controls.Overlay.overlay

        property var sourceCard: null
        readonly property string issueId: sourceCard ? sourceCard.issueId : ""
        readonly property string issueStatus: sourceCard ? sourceCard.issueStatus : ""

        width: sourceCard ? sourceCard.width : 0
        height: sourceCard ? sourceCard.height : 0
        visible: Drag.active
        z: 1000

        Drag.active: Boolean(sourceCard && sourceCard.dragActive)
        Drag.source: cardDragProxy
        Drag.keys: ["bead-card"]
        Drag.supportedActions: Qt.MoveAction
        Drag.proposedAction: Qt.MoveAction
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: Kirigami.Units.gridUnit

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: cardDragProxy.sourceCard
            hideSource: cardDragProxy.Drag.active
            live: true
        }
    }

    component KanbanColumn: Rectangle {
        id: column
        objectName: `statusColumn-${statusName}`

        required property string statusName
        required property string heading
        required property color accent
        property bool compactHeader: false
        property bool showHeader: true
        property bool showCreateWhenEmpty: false
        readonly property var cards: root.issuesForStatus(statusName)

        radius: Kirigami.Units.cornerRadius
        color: dropArea.containsDrag
            ? Qt.alpha(accent, 0.12)
            : Kirigami.Theme.backgroundColor

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
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                visible: column.showHeader
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
                    level: column.compactHeader ? 4 : 3
                    Layout.fillWidth: true
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
                        drag.target: cardDragProxy
                        drag.threshold: Kirigami.Units.gridUnit / 2

                        onPressed: mouse => {
                            const position = card.mapToItem(Controls.Overlay.overlay, 0, 0);
                            cardDragProxy.sourceCard = card;
                            cardDragProxy.x = position.x;
                            cardDragProxy.y = position.y;
                            mouse.accepted = true;
                        }
                        onClicked: root.openEditor(card.issueId)
                        onReleased: {
                            cardDragProxy.Drag.drop();
                            cardDragProxy.sourceCard = null;
                        }
                        onCanceled: cardDragProxy.sourceCard = null
                    }
                }

                Controls.Button {
                    objectName: "emptyCreateButton"
                    anchors.centerIn: parent
                    visible: column.showCreateWhenEmpty
                        && root.statusCount(column.statusName) === 0
                        && !Backend.loading
                    text: qsTr("Create ticket")
                    icon.name: "list-add"
                    onClicked: root.openCreate()
                }
            }
        }
    }

    component CollapsibleStatusSection: Rectangle {
        id: section
        objectName: `statusSection-${statusName}`

        required property string statusName
        required property string heading
        required property color accent
        property bool expanded: root.statusCount(statusName) > 0

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
                    Backend.moveIssue(drop.source.issueId, section.statusName);
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
                        text: root.statusCount(section.statusName)
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
                showHeader: false
            }
        }
    }

    component OpenColumn: Rectangle {
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
                showCreateWhenEmpty: true
            }

            CollapsibleStatusSection {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                statusName: "blocked"
                heading: qsTr("Blocked")
                accent: Kirigami.Theme.negativeTextColor
            }

            CollapsibleStatusSection {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                statusName: "deferred"
                heading: qsTr("Deferred")
                accent: Kirigami.Theme.neutralTextColor
            }
        }
    }

    component BeadEditorPage: Kirigami.ScrollablePage {
        id: editor
        objectName: "editorPage"

        property string issueId: ""
        property bool creating: false
        property string parentId: ""
        property bool preserveFieldsWhileLoading: false
        property bool detailLoadRequested: false
        property bool detailReady: false
        property bool commentSubmitting: false
        property bool refreshWhenCurrent: false
        property bool hydratingCreatedIssue: false
        property var localDetail: ({})
        property alias commentDraft: commentField.text
        readonly property bool persisted: !creating && issueId.length > 0
        readonly property var relationshipDetail: localDetail
        readonly property var dependencies: relationshipDetail.dependencies || []
        readonly property var dependents: relationshipDetail.dependents || []
        readonly property var comments: localDetail.comments || []
        readonly property real formFieldWidth: Math.max(
            Kirigami.Units.gridUnit * 16,
            Math.min(
                Kirigami.Units.gridUnit * 40,
                editor.availableWidth - Kirigami.Units.gridUnit * 8
            )
        )

        title: creating
            ? qsTr("Create ticket")
            : (titleField.text.length > 0 ? titleField.text : issueId)

        function statusIndex(status) {
            const statuses = ["open", "in_progress", "blocked", "deferred", "closed"];
            return Math.max(0, statuses.indexOf(status));
        }

        function populate() {
            if (creating)
                return;
            const issue = localDetail || {};
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

        function initializeCreate() {
            statusField.currentIndex = 0;
            priorityField.currentIndex = 2;
            typeField.currentIndex = 2;
            typeField.editText = "task";
            titleField.forceActiveFocus();
        }

        function relationshipLabel(relation, incoming) {
            if (relation.dependency_type === "parent-child")
                return incoming ? qsTr("Child") : qsTr("Parent epic");
            if (relation.dependency_type === "blocks")
                return incoming ? qsTr("Blocks") : qsTr("Blocked by");
            return incoming ? qsTr("Dependent") : qsTr("Depends on");
        }

        function addRelationship() {
            const targetId = relationshipTargetField.text.trim();
            if (targetId.length === 0 || targetId === issueId)
                return;
            preserveFieldsWhileLoading = true;
            Backend.addDependency(issueId, targetId, relationshipTypeField.currentValue);
            relationshipTargetField.clear();
        }

        function formatCommentDate(value) {
            if (!value)
                return "";
            const date = new Date(value);
            if (isNaN(date.getTime()))
                return String(value);
            return date.toLocaleString(Qt.locale(), Locale.ShortFormat);
        }

        function submitComment() {
            const text = commentField.text.trim();
            if (text.length === 0 || Backend.loading || !detailReady)
                return;
            preserveFieldsWhileLoading = true;
            commentSubmitting = true;
            Backend.addComment(issueId, text);
        }

        function requestDetail() {
            if (creating || Backend.loading || detailLoadRequested)
                return false;
            detailLoadRequested = true;
            detailReady = false;
            Backend.loadIssue(issueId);
            return true;
        }

        function save() {
            const request = {
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
                "labels": labelsField.text,
                "parentId": parentId
            };
            if (creating)
                Backend.createIssue(request);
            else
                Backend.saveIssue(request);
        }

        actions: [
            Kirigami.Action {
                text: editor.creating ? qsTr("Create") : qsTr("Save")
                icon.name: editor.creating ? "list-add" : "document-save"
                enabled: !Backend.loading && titleField.text.trim().length > 0
                shortcut: StandardKey.Save
                onTriggered: editor.save()
            },
            Kirigami.Action {
                objectName: "createChildAction"
                text: qsTr("Create child ticket")
                icon.name: "list-add"
                visible: !editor.creating && typeField.editText === "epic"
                enabled: !Backend.loading
                onTriggered: root.openCreate(editor.issueId)
            }
        ]

        Shortcut {
            sequence: "Escape"
            onActivated: root.pageStack.layers.pop()
        }

        Component.onCompleted: {
            if (editor.creating)
                editor.initializeCreate();
            else {
                if (String(Backend.detail.id || "") === editor.issueId)
                    editor.localDetail = Backend.detail;
                editor.populate();
                editor.requestDetail();
            }
        }

        Connections {
            target: Backend

            function onAttachmentReady(issueId, path) {
                if (issueId === editor.issueId)
                    Qt.openUrlExternally(root.localFileUrl(path));
            }

            function onDetailChanged() {
                if (String(Backend.detail.id || "") !== editor.issueId)
                    return;
                editor.localDetail = Backend.detail;
                if (!Backend.loading) {
                    editor.populate();
                    if (!editor.detailLoadRequested)
                        editor.detailReady = true;
                }
            }

            function onLoadingChanged() {
                if (!Backend.loading) {
                    if (String(Backend.detail.id || "") === editor.issueId) {
                        editor.localDetail = Backend.detail;
                        editor.detailReady = true;
                    }
                    editor.detailLoadRequested = false;
                    editor.hydratingCreatedIssue = false;
                    if (editor.commentSubmitting) {
                        if (Backend.errorMessage.length === 0)
                            commentField.clear();
                        editor.commentSubmitting = false;
                    }
                    if (editor.preserveFieldsWhileLoading)
                        editor.preserveFieldsWhileLoading = false;
                    else
                        editor.populate();
                }
            }

            function onIssueSaved(savedId) {
                if (editor.creating
                        && root.pageStack.layers.currentItem === editor) {
                    editor.issueId = savedId;
                    editor.creating = false;
                    editor.parentId = "";
                    editor.localDetail = Backend.detail;
                    editor.populate();
                    editor.hydratingCreatedIssue = true;
                    editor.requestDetail();
                } else if (savedId === editor.issueId) {
                    root.pageStack.layers.pop();
                } else if (root.pageStack.layers.currentItem === editor) {
                    Backend.loadIssue(editor.issueId);
                } else {
                    editor.refreshWhenCurrent = true;
                }
            }
        }

        Connections {
            target: root.pageStack.layers

            function onCurrentItemChanged() {
                if (root.pageStack.layers.currentItem === editor
                        && editor.refreshWhenCurrent) {
                    editor.refreshWhenCurrent = false;
                    editor.requestDetail();
                }
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
                    text: editor.creating ? qsTr("New bead") : editor.issueId
                    color: Kirigami.Theme.highlightColor
                    font.family: "monospace"
                    font.weight: Font.Bold
                }
                Controls.Label {
                    visible: editor.creating && editor.parentId.length > 0
                    text: qsTr("Child of %1").arg(editor.parentId)
                    color: Kirigami.Theme.disabledTextColor
                    font.family: "monospace"
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
                enabled: !Backend.loading || editor.detailLoadRequested

                Controls.TextField {
                    id: titleField
                    objectName: "titleField"
                    Kirigami.FormData.label: qsTr("Title:")
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    placeholderText: qsTr("Issue title")
                }

                Controls.ComboBox {
                    id: statusField
                    objectName: "statusField"
                    Kirigami.FormData.label: qsTr("Status:")
                    implicitWidth: editor.formFieldWidth
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
                    objectName: "priorityField"
                    Kirigami.FormData.label: qsTr("Priority:")
                    implicitWidth: editor.formFieldWidth
                    model: ["P0 - Critical", "P1 - High", "P2 - Medium", "P3 - Low", "P4 - Backlog"]
                }

                Controls.ComboBox {
                    id: typeField
                    objectName: "typeField"
                    Kirigami.FormData.label: qsTr("Type:")
                    implicitWidth: editor.formFieldWidth
                    editable: true
                    model: ["bug", "feature", "task", "epic", "chore", "decision"]
                }

                Controls.TextField {
                    id: assigneeField
                    objectName: "assigneeField"
                    Kirigami.FormData.label: qsTr("Assignee:")
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    placeholderText: qsTr("Unassigned")
                }

                Controls.TextField {
                    id: labelsField
                    objectName: "labelsField"
                    Kirigami.FormData.label: qsTr("Labels:")
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    placeholderText: qsTr("Comma-separated labels")
                }

                ColumnLayout {
                    id: attachmentsSection
                    objectName: "attachmentsSection"
                    Kirigami.FormData.label: qsTr("Attachments:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Controls.ToolTip.visible: editor.creating && attachmentHover.hovered
                    Controls.ToolTip.text: qsTr("Create the ticket before attaching files")

                    HoverHandler {
                        id: attachmentHover
                        enabled: editor.creating
                    }

                    Repeater {
                        objectName: "attachmentsRepeater"
                        model: editor.localDetail && editor.localDetail.attachments
                            ? editor.localDetail.attachments
                            : []

                        delegate: RowLayout {
                            id: attachmentRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: root.attachmentIcon(attachmentRow.modelData.mime_type)
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: implicitWidth
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Controls.Label {
                                    objectName: "attachmentName"
                                    text: attachmentRow.modelData.original_filename || qsTr("Unnamed attachment")
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                Controls.Label {
                                    text: {
                                        const provider = attachmentRow.modelData.provider === "polyfill"
                                            ? qsTr("KDE Beads local")
                                            : qsTr("Beads");
                                        const missing = attachmentRow.modelData.missing
                                            ? ` · ${qsTr("missing locally")}`
                                            : "";
                                        return `${root.formatBytes(attachmentRow.modelData.byte_size)} · ${provider}${missing}`;
                                    }
                                    color: attachmentRow.modelData.missing
                                        ? Kirigami.Theme.negativeTextColor
                                        : Kirigami.Theme.disabledTextColor
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    Layout.fillWidth: true
                                }
                            }

                            Controls.ToolButton {
                                objectName: "openAttachmentButton"
                                icon.name: "document-open"
                                text: qsTr("Open")
                                display: Controls.AbstractButton.IconOnly
                                enabled: !Backend.loading && !attachmentRow.modelData.missing
                                Controls.ToolTip.text: text
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    editor.preserveFieldsWhileLoading = true;
                                    Backend.openAttachment(
                                        editor.issueId,
                                        attachmentRow.modelData.id
                                    );
                                }
                            }

                            Controls.ToolButton {
                                objectName: "removeAttachmentButton"
                                icon.name: "edit-delete-remove"
                                text: qsTr("Remove")
                                display: Controls.AbstractButton.IconOnly
                                enabled: !Backend.loading
                                Controls.ToolTip.text: text
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    editor.preserveFieldsWhileLoading = true;
                                    Backend.removeAttachment(
                                        editor.issueId,
                                        attachmentRow.modelData.id
                                    );
                                }
                            }
                        }
                    }

                    Controls.BusyIndicator {
                        visible: editor.persisted
                            && !editor.detailReady
                            && !editor.hydratingCreatedIssue
                        running: visible
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                    }

                    Controls.Label {
                        visible: (editor.detailReady || editor.hydratingCreatedIssue)
                            && (!editor.localDetail.attachments
                                || editor.localDetail.attachments.length === 0)
                        text: qsTr("No attachments")
                        color: Kirigami.Theme.disabledTextColor
                    }

                    RowLayout {
                        Controls.Button {
                            id: addAttachmentButton
                            objectName: "addAttachmentButton"
                            text: qsTr("Attach file")
                            icon.name: "mail-attachment"
                            enabled: editor.persisted && !Backend.loading
                            onClicked: {
                                editor.preserveFieldsWhileLoading = true;
                                Backend.addAttachment(editor.issueId);
                            }
                        }

                        Controls.Button {
                            id: migrateAttachmentsButton
                            objectName: "migrateAttachmentsButton"
                            visible: Boolean(editor.localDetail.native_attachments_supported)
                                && Number(editor.localDetail.polyfill_attachment_count || 0) > 0
                            text: qsTr("Move to Beads storage")
                            icon.name: "document-import"
                            enabled: !Backend.loading
                            onClicked: {
                                editor.preserveFieldsWhileLoading = true;
                                Backend.migrateAttachments(editor.issueId);
                            }
                        }
                    }
                }

                ColumnLayout {
                    id: relationshipsSection
                    objectName: "relationshipsSection"
                    Kirigami.FormData.label: qsTr("Relationships:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Controls.ToolTip.visible: editor.creating && relationshipHover.hovered
                    Controls.ToolTip.text: qsTr("Create the ticket before linking issues")

                    HoverHandler {
                        id: relationshipHover
                        enabled: editor.creating
                    }

                    Controls.BusyIndicator {
                        visible: editor.persisted
                            && !editor.detailReady
                            && !editor.hydratingCreatedIssue
                        running: visible
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                    }

                    Controls.Label {
                        visible: (editor.detailReady || editor.hydratingCreatedIssue)
                            && editor.dependencies.length === 0
                            && editor.dependents.length === 0
                        text: qsTr("No linked issues")
                        color: Kirigami.Theme.disabledTextColor
                    }

                    Repeater {
                        model: editor.dependencies

                        delegate: Controls.ItemDelegate {
                            required property var modelData
                            Layout.fillWidth: true
                            icon.name: modelData.dependency_type === "parent-child"
                                ? "view-list-tree"
                                : "link"
                            text: `${editor.relationshipLabel(modelData, false)}  ${modelData.id}  ${modelData.title || ""}`
                            onClicked: root.openEditor(String(modelData.id))
                        }
                    }

                    Repeater {
                        model: editor.dependents

                        delegate: Controls.ItemDelegate {
                            required property var modelData
                            Layout.fillWidth: true
                            icon.name: modelData.dependency_type === "parent-child"
                                ? "view-list-tree"
                                : "link"
                            text: `${editor.relationshipLabel(modelData, true)}  ${modelData.id}  ${modelData.title || ""}`
                            onClicked: root.openEditor(String(modelData.id))
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        enabled: editor.persisted && editor.detailReady && !Backend.loading

                        Controls.ComboBox {
                            id: relationshipTypeField
                            objectName: "relationshipTypeField"
                            textRole: "text"
                            valueRole: "value"
                            model: [
                                { "text": qsTr("Blocked by"), "value": "blocks" },
                                { "text": qsTr("Parent epic"), "value": "parent-child" }
                            ]
                        }
                        Controls.TextField {
                            id: relationshipTargetField
                            objectName: "relationshipTargetField"
                            Layout.fillWidth: true
                            placeholderText: qsTr("Issue ID")
                            onAccepted: editor.addRelationship()
                        }
                        Controls.Button {
                            objectName: "addRelationshipButton"
                            text: qsTr("Add")
                            icon.name: "list-add"
                            enabled: !Backend.loading
                                && relationshipTargetField.text.trim().length > 0
                                && relationshipTargetField.text.trim() !== editor.issueId
                            onClicked: editor.addRelationship()
                        }
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Description:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    implicitWidth: editor.formFieldWidth
                    implicitHeight: Kirigami.Units.gridUnit * 8
                    Layout.fillWidth: true

                    Controls.TextArea {
                        id: descriptionField
                        objectName: "descriptionField"
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Describe the work")
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Acceptance:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    implicitWidth: editor.formFieldWidth
                    implicitHeight: Kirigami.Units.gridUnit * 6
                    Layout.fillWidth: true

                    Controls.TextArea {
                        id: acceptanceField
                        objectName: "acceptanceField"
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Acceptance criteria")
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Design:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    implicitWidth: editor.formFieldWidth
                    implicitHeight: Kirigami.Units.gridUnit * 6
                    Layout.fillWidth: true

                    Controls.TextArea {
                        id: designField
                        objectName: "designField"
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Implementation notes")
                    }
                }

                Controls.ScrollView {
                    Kirigami.FormData.label: qsTr("Notes:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    implicitWidth: editor.formFieldWidth
                    implicitHeight: Kirigami.Units.gridUnit * 6
                    Layout.fillWidth: true

                    Controls.TextArea {
                        id: notesField
                        objectName: "notesField"
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Additional notes")
                    }
                }

                ColumnLayout {
                    id: commentsSection
                    objectName: "commentsSection"
                    Kirigami.FormData.label: qsTr("Comments:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    visible: editor.persisted
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Kirigami.Units.largeSpacing
                    }

                    Controls.BusyIndicator {
                        visible: editor.persisted && !editor.detailReady
                        running: visible
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                    }

                    Controls.Label {
                        visible: editor.detailReady && editor.comments.length === 0
                        text: qsTr("No comments yet")
                        color: Kirigami.Theme.disabledTextColor
                    }

                    Repeater {
                        model: editor.comments

                        delegate: Controls.Frame {
                            id: commentCard
                            objectName: "commentCard"
                            required property var modelData
                            Layout.fillWidth: true
                            padding: Kirigami.Units.largeSpacing

                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing

                                RowLayout {
                                    Layout.fillWidth: true

                                    Controls.Label {
                                        text: commentCard.modelData.author || qsTr("Unknown author")
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    Controls.Label {
                                        text: editor.formatCommentDate(commentCard.modelData.created_at)
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                }
                                Controls.Label {
                                    objectName: "commentText"
                                    text: commentCard.modelData.text || ""
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    Controls.TextArea {
                        id: commentField
                        objectName: "commentField"
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 5
                        wrapMode: TextEdit.Wrap
                        placeholderText: qsTr("Add a comment")
                        enabled: editor.persisted && editor.detailReady && !Backend.loading
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Item { Layout.fillWidth: true }
                        Controls.Button {
                            objectName: "addCommentButton"
                            text: qsTr("Comment")
                            icon.name: "mail-send"
                            enabled: !Backend.loading
                                && editor.detailReady
                                && commentField.text.trim().length > 0
                            onClicked: editor.submitComment()
                        }
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
        objectName: "boardPage"
        title: qsTr("Beads")
        padding: 0

        actions: [
            Kirigami.Action {
                objectName: "createTicketAction"
                text: qsTr("Create Ticket")
                icon.name: "list-add"
                enabled: !Backend.loading
                shortcut: "Ctrl+N"
                onTriggered: root.openCreate()
            },
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
                    spacing: Kirigami.Units.largeSpacing
                    readonly property real compactWidth: Kirigami.Units.gridUnit * 16
                    readonly property real focusWidth: Math.max(
                        Kirigami.Units.gridUnit * 20,
                        (boardFlick.width - compactWidth - spacing * 2) / 2
                    )

                    OpenColumn {
                        width: boardRow.focusWidth
                        height: boardRow.height
                    }
                    KanbanColumn {
                        width: boardRow.focusWidth
                        height: boardRow.height
                        statusName: "in_progress"
                        heading: qsTr("In progress")
                        accent: Kirigami.Theme.highlightColor
                    }
                    KanbanColumn {
                        width: boardRow.compactWidth
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
