// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQuickControlsAddons
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

    property bool projectPersistenceEnabled: true
    property var knownProjects: []
    property bool projectsInitialized: false
    readonly property bool editorLayerOpen: Boolean(pageStack.layers.currentItem
        && pageStack.layers.currentItem.objectName === "editorPage")

    Settings {
        id: projectSettings
        category: "Projects"
        location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation)
            + "/projects.ini"
        property string knownProjectsJson: ""
        property string activeProject: ""
    }

    Timer {
        objectName: "changePollTimer"
        interval: 2000
        running: true
        repeat: true
        onTriggered: Backend.poll()
    }

    KQuickControlsAddons.Clipboard {
        id: attachmentClipboard
        objectName: "attachmentClipboard"
    }

    function normalizedProjects(projects) {
        const result = [];
        for (const project of projects || []) {
            const path = String(project || "").trim();
            if (path.length > 0 && !result.includes(path))
                result.push(path);
        }
        return result;
    }

    function storedProjects() {
        if (!projectPersistenceEnabled || projectSettings.knownProjectsJson.length === 0)
            return [];
        try {
            const stored = JSON.parse(projectSettings.knownProjectsJson);
            return normalizedProjects(stored && stored.version === 1 ? stored.paths : []);
        } catch (error) {
            return [];
        }
    }

    function persistProjects(activeProject) {
        if (!projectPersistenceEnabled)
            return;
        projectSettings.knownProjectsJson = JSON.stringify({
            "version": 1,
            "paths": knownProjects
        });
        projectSettings.activeProject = String(activeProject || "");
        projectSettings.sync();
    }

    function rememberProject(path) {
        const projects = normalizedProjects(knownProjects.concat([path]));
        if (projects.length !== knownProjects.length)
            knownProjects = projects;
        if (projectsInitialized)
            persistProjects(Backend.workspace);
    }

    function projectName(path) {
        const parts = String(path || "").split("/").filter(part => part.length > 0);
        return parts.length > 0 ? parts[parts.length - 1] : String(path || "");
    }

    function selectProject(path) {
        if (Backend.loading || editorLayerOpen || path === Backend.workspace)
            return;
        Backend.switchWorkspace(path);
        if (projectSidebar.modal)
            projectSidebar.close();
    }

    function initializeProjects() {
        const startupProject = String(Backend.workspace);
        const projects = storedProjects();
        const savedProject = String(projectSettings.activeProject || "");
        const preferredProject = !Backend.startupWorkspaceExplicit
                && projects.includes(savedProject)
            ? savedProject
            : startupProject;
        knownProjects = normalizedProjects(projects.concat([preferredProject]));
        projectsInitialized = true;

        persistProjects(preferredProject);
        if (preferredProject !== startupProject) {
            Backend.switchWorkspace(preferredProject);
            if (Backend.workspace === startupProject) {
                persistProjects(startupProject);
                Backend.reload();
            }
        } else {
            Backend.reload();
        }
    }

    Component.onCompleted: initializeProjects()

    Connections {
        target: Backend

        function onWorkspaceChanged() {
            root.rememberProject(Backend.workspace);
        }
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

    function copyIssueId(issueId) {
        attachmentClipboard.content = String(issueId || "");
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

    component IssueCopyButton: Controls.ToolButton {
        id: copyButton

        required property string issueId
        property bool copied: false
        property bool minimumFeedbackElapsed: false

        text: qsTr("Copy %1").arg(issueId)
        icon.name: copied ? "dialog-ok" : "edit-copy"
        display: Controls.AbstractButton.IconOnly
        Controls.ToolTip.text: copied ? qsTr("Copied") : qsTr("Copy issue ID")
        Controls.ToolTip.visible: hovered

        function finishFeedbackIfReady() {
            if (minimumFeedbackElapsed && !hovered)
                copied = false;
        }

        onClicked: {
            root.copyIssueId(issueId);
            copied = true;
            minimumFeedbackElapsed = false;
            feedbackTimer.restart();
        }
        onHoveredChanged: finishFeedbackIfReady()

        Timer {
            id: feedbackTimer
            interval: 1000
            onTriggered: {
                copyButton.minimumFeedbackElapsed = true;
                copyButton.finishFeedbackIfReady();
            }
        }
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
                            IssueCopyButton {
                                objectName: `issueCopyButton-${card.issueId}`
                                issueId: card.issueId
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Layout.preferredWidth
                                z: 2
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
        property var attachmentPreviews: ({})
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

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => editor.handlePasteEvent(event)

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

        function attachmentPreviewState(attachmentId) {
            return Object.prototype.hasOwnProperty.call(attachmentPreviews, attachmentId)
                ? attachmentPreviews[attachmentId]
                : undefined;
        }

        function requestAttachmentPreview(attachment) {
            const mimeType = String(attachment.mime_type || "");
            const attachmentId = String(attachment.id || "");
            if (!mimeType.startsWith("image/")
                    || attachment.missing
                    || attachmentId.length === 0
                    || attachmentPreviewState(attachmentId) !== undefined) {
                return;
            }
            const previews = Object.assign({}, attachmentPreviews);
            previews[attachmentId] = null;
            attachmentPreviews = previews;
            Backend.previewAttachment(issueId, attachmentId);
        }

        function localFileUrls(urls) {
            return Array.from(urls || [])
                .map(url => String(url))
                .filter(url => url.toLowerCase().startsWith("file:"));
        }

        function canAttachFiles() {
            return persisted && detailReady && !Backend.loading;
        }

        function attachFileUrls(urls) {
            const localUrls = localFileUrls(urls);
            if (!canAttachFiles() || localUrls.length === 0)
                return false;
            preserveFieldsWhileLoading = true;
            Backend.addAttachments(issueId, localUrls);
            return true;
        }

        function clipboardFileUrls() {
            if (!attachmentClipboard.formats.includes("text/uri-list"))
                return [];
            return localFileUrls(attachmentClipboard.contentFormat("text/uri-list"));
        }

        function handlePasteEvent(event) {
            if (event.matches(StandardKey.Paste)
                    && attachFileUrls(clipboardFileUrls())) {
                event.accepted = true;
            }
        }

        function relationshipTargetAllowed(targetId) {
            if (targetId.length === 0 || targetId === issueId)
                return false;
            return !dependencies.some(issue => String(issue.id) === targetId)
                && !dependents.some(issue => String(issue.id) === targetId);
        }

        function relationshipChoiceLabel(issue) {
            const title = String(issue.title || "").trim();
            return title.length > 0 ? `${issue.id} - ${title}` : String(issue.id);
        }

        function relationshipCandidates(query) {
            const normalized = String(query || "").trim().toLowerCase();
            return (Backend.issues || [])
                .filter(issue => {
                    const targetId = String(issue.id || "");
                    if (!relationshipTargetAllowed(targetId))
                        return false;
                    if (normalized.length === 0)
                        return true;
                    return targetId.toLowerCase().includes(normalized)
                        || String(issue.title || "").toLowerCase().includes(normalized);
                })
                .slice(0, 8)
                .map(issue => ({
                    "id": String(issue.id),
                    "label": relationshipChoiceLabel(issue)
                }));
        }

        function relationshipTargetId() {
            const value = relationshipTargetField.text.trim();
            const issue = (Backend.issues || []).find(candidate => {
                const targetId = String(candidate.id || "");
                return targetId === value || relationshipChoiceLabel(candidate) === value;
            });
            const targetId = issue ? String(issue.id) : "";
            return relationshipTargetAllowed(targetId) ? targetId : "";
        }

        function addRelationship() {
            const targetId = relationshipTargetId();
            if (targetId.length === 0)
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

        Shortcut {
            objectName: "attachmentPasteShortcut"
            sequences: [StandardKey.Paste]
            enabled: root.pageStack.layers.currentItem === editor
                && editor.canAttachFiles()
                && editor.clipboardFileUrls().length > 0
            onActivated: editor.attachFileUrls(editor.clipboardFileUrls())
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

            function onAttachmentPreviewReady(issueId, attachmentId, path) {
                if (issueId !== editor.issueId)
                    return;
                const previews = Object.assign({}, editor.attachmentPreviews);
                previews[attachmentId] = path;
                editor.attachmentPreviews = previews;
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

        DropArea {
            id: attachmentDropArea
            objectName: "attachmentDropArea"
            parent: editor
            anchors.fill: parent
            z: 1000
            enabled: editor.canAttachFiles()

            onEntered: drag => {
                if (editor.localFileUrls(drag.urls).length > 0)
                    drag.accept(Qt.CopyAction);
                else
                    drag.accepted = false;
            }
            onDropped: drop => {
                if (editor.attachFileUrls(drop.urls))
                    drop.accept(Qt.CopyAction);
                else
                    drop.accepted = false;
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                visible: attachmentDropArea.containsDrag
                radius: Kirigami.Units.cornerRadius
                color: Kirigami.Theme.alternateBackgroundColor
                border.width: Kirigami.Units.smallSpacing
                border.color: Kirigami.Theme.highlightColor

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignHCenter
                        source: "mail-attachment"
                        implicitWidth: Kirigami.Units.iconSizes.huge
                        implicitHeight: implicitWidth
                        color: Kirigami.Theme.highlightColor
                    }
                    Controls.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Drop files to attach")
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.35
                        font.weight: Font.DemiBold
                    }
                    Controls.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Release to add them to %1").arg(editor.issueId)
                        color: Kirigami.Theme.disabledTextColor
                    }
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
                IssueCopyButton {
                    objectName: "editorIssueCopyButton"
                    visible: !editor.creating
                    issueId: editor.issueId
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
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => editor.handlePasteEvent(event)
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
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => editor.handlePasteEvent(event)
                }

                Controls.TextField {
                    id: assigneeField
                    objectName: "assigneeField"
                    Kirigami.FormData.label: qsTr("Assignee:")
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    placeholderText: qsTr("Unassigned")
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => editor.handlePasteEvent(event)
                }

                Controls.TextField {
                    id: labelsField
                    objectName: "labelsField"
                    Kirigami.FormData.label: qsTr("Labels:")
                    implicitWidth: editor.formFieldWidth
                    Layout.fillWidth: true
                    placeholderText: qsTr("Comma-separated labels")
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => editor.handlePasteEvent(event)
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

                        delegate: ColumnLayout {
                            id: attachmentRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            readonly property var previewState: editor.attachmentPreviewState(
                                String(modelData.id || "")
                            )
                            readonly property bool previewable: String(modelData.mime_type || "")
                                .startsWith("image/")

                            Component.onCompleted: editor.requestAttachmentPreview(modelData)

                            Rectangle {
                                objectName: "attachmentPreview"
                                visible: attachmentRow.previewable
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(
                                    editor.formFieldWidth * (
                                        previewImage.sourceSize.width > 0
                                            ? previewImage.sourceSize.height
                                                / previewImage.sourceSize.width
                                            : 0.65
                                    ),
                                    Kirigami.Units.gridUnit * 36
                                )
                                radius: Kirigami.Units.cornerRadius
                                color: Kirigami.Theme.alternateBackgroundColor
                                clip: true

                                Image {
                                    id: previewImage
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    source: typeof attachmentRow.previewState === "string"
                                        && attachmentRow.previewState.length > 0
                                        ? root.localFileUrl(attachmentRow.previewState)
                                        : ""
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }

                                Controls.BusyIndicator {
                                    anchors.centerIn: parent
                                    visible: attachmentRow.previewState === null
                                    running: visible
                                    implicitWidth: Kirigami.Units.iconSizes.large
                                    implicitHeight: implicitWidth
                                }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    visible: attachmentRow.previewState === ""
                                        || previewImage.status === Image.Error
                                    source: root.attachmentIcon(attachmentRow.modelData.mime_type)
                                    implicitWidth: Kirigami.Units.iconSizes.medium
                                    implicitHeight: implicitWidth
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    visible: !attachmentRow.previewable
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
                            property var candidates: editor.relationshipCandidates(text)
                            placeholderText: qsTr("Search issue ID or title")
                            Accessible.description: qsTr("Search issues by ID or title")
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: event => editor.handlePasteEvent(event)

                            function updateSuggestions() {
                                relationshipSuggestionList.currentIndex = 0;
                                if (activeFocus
                                        && text.trim().length > 0
                                        && candidates.length > 0
                                        && editor.relationshipTargetId().length === 0) {
                                    relationshipSuggestions.open();
                                } else {
                                    relationshipSuggestions.close();
                                }
                            }

                            onTextChanged: Qt.callLater(updateSuggestions)
                            onActiveFocusChanged: Qt.callLater(updateSuggestions)
                            onAccepted: {
                                if (editor.relationshipTargetId().length > 0) {
                                    editor.addRelationship();
                                } else if (candidates.length > 0) {
                                    const index = Math.max(0, relationshipSuggestionList.currentIndex);
                                    text = candidates[index].id;
                                    relationshipSuggestions.close();
                                }
                            }

                            Keys.onDownPressed: event => {
                                if (candidates.length === 0)
                                    return;
                                relationshipSuggestionList.currentIndex = Math.min(
                                    candidates.length - 1,
                                    relationshipSuggestionList.currentIndex + 1
                                );
                                relationshipSuggestions.open();
                                event.accepted = true;
                            }
                            Keys.onUpPressed: event => {
                                if (candidates.length === 0)
                                    return;
                                relationshipSuggestionList.currentIndex = Math.max(
                                    0,
                                    relationshipSuggestionList.currentIndex - 1
                                );
                                relationshipSuggestions.open();
                                event.accepted = true;
                            }

                            TapHandler {
                                onTapped: Qt.callLater(relationshipTargetField.updateSuggestions)
                            }
                        }

                        Item {
                            Layout.preferredWidth: addRelationshipButton.implicitWidth
                            Layout.preferredHeight: addRelationshipButton.implicitHeight
                            Controls.ToolTip.visible: addRelationshipHover.hovered
                                && !addRelationshipButton.enabled
                            Controls.ToolTip.text: relationshipTargetField.candidates.length > 0
                                ? qsTr("Select an issue from the suggestions")
                                : qsTr("No unlinked issue matches this search")

                            HoverHandler {
                                id: addRelationshipHover
                            }

                            Controls.Button {
                                id: addRelationshipButton
                                objectName: "addRelationshipButton"
                                anchors.fill: parent
                                text: qsTr("Add")
                                icon.name: "list-add"
                                enabled: !Backend.loading
                                    && editor.relationshipTargetId().length > 0
                                onClicked: editor.addRelationship()
                            }
                        }
                    }

                    Controls.Popup {
                        id: relationshipSuggestions
                        objectName: "relationshipSuggestions"
                        parent: relationshipTargetField
                        x: 0
                        y: relationshipTargetField.height
                        width: relationshipTargetField.width
                        padding: 0
                        focus: false
                        modal: false
                        closePolicy: Controls.Popup.CloseOnEscape
                            | Controls.Popup.CloseOnPressOutsideParent

                        contentItem: ListView {
                            id: relationshipSuggestionList
                            objectName: "relationshipSuggestionList"
                            implicitHeight: Math.min(
                                contentHeight,
                                Kirigami.Units.gridUnit * 16
                            )
                            model: relationshipTargetField.candidates
                            currentIndex: 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Controls.ScrollBar.vertical: Controls.ScrollBar {}

                            delegate: Controls.ItemDelegate {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                text: modelData.label
                                icon.name: "task-complete"
                                highlighted: ListView.isCurrentItem

                                onClicked: {
                                    relationshipSuggestionList.currentIndex = index;
                                    relationshipTargetField.text = modelData.id;
                                    relationshipSuggestions.close();
                                    relationshipTargetField.forceActiveFocus();
                                }
                            }
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
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => editor.handlePasteEvent(event)
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
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => editor.handlePasteEvent(event)
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
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => editor.handlePasteEvent(event)
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
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => editor.handlePasteEvent(event)
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
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => editor.handlePasteEvent(event)
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

    pageStack.leftSidebar: Kirigami.GlobalDrawer {
        id: projectSidebar
        objectName: "projectSidebar"
        title: qsTr("Projects")
        titleIcon: "folder"
        modal: root.width < Kirigami.Units.gridUnit * 48
        preferredSize: Kirigami.Units.gridUnit * 15
        minimumSize: Kirigami.Units.gridUnit * 12
        maximumSize: Kirigami.Units.gridUnit * 22
        handleClosedToolTip: qsTr("Show projects")
        handleOpenToolTip: qsTr("Hide projects")
        isMenu: false
        collapsible: !modal
        showContentWhenCollapsed: true

        Component.onCompleted: {
            collapsible = !modal;
            drawerOpen = !modal;
        }
        onModalChanged: Qt.callLater(() => {
            collapsed = false;
            collapsible = !modal;
            drawerOpen = !modal;
        })

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Repeater {
                id: projectList
                objectName: "projectList"
                model: root.knownProjects

                delegate: Controls.ItemDelegate {
                    required property string modelData
                    required property int index
                    objectName: `projectItem-${index}`
                    Layout.fillWidth: true
                    text: root.projectName(modelData)
                    icon.name: modelData === Backend.workspace ? "folder-open" : "folder"
                    display: projectSidebar.collapsed
                        ? Controls.AbstractButton.IconOnly
                        : Controls.AbstractButton.TextBesideIcon
                    highlighted: modelData === Backend.workspace
                    enabled: !Backend.loading && !root.editorLayerOpen
                    Accessible.description: modelData
                    Controls.ToolTip.text: modelData
                    Controls.ToolTip.visible: hovered
                    onClicked: root.selectProject(modelData)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        footer: Controls.ToolBar {
            contentItem: Controls.ToolButton {
                id: addProjectButton
                objectName: "addProjectButton"
                text: qsTr("Add Project")
                icon.name: "folder-new"
                display: projectSidebar.collapsed
                    ? Controls.AbstractButton.IconOnly
                    : Controls.AbstractButton.TextBesideIcon
                enabled: !Backend.loading && !root.editorLayerOpen
                onClicked: Backend.chooseWorkspace()
            }
        }
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
                text: qsTr("Refresh")
                icon.name: "view-refresh"
                enabled: !Backend.loading
                shortcut: StandardKey.Refresh
                onTriggered: Backend.reload()
            }
        ]

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
