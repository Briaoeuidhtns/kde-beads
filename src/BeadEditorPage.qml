// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "components" as Components

Kirigami.ScrollablePage {
    id: editor
    objectName: "editorPage"

    required property var backend
    required property var clipboard
    required property var layerStack

    signal closeRequested()
    signal createChildRequested(string parentId)
    signal openIssueRequested(string issueId)
    signal copyIssueIdRequested(string issueId)

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

    title: creating
        ? qsTr("Create ticket")
        : (titleField.text.length > 0 ? titleField.text : issueId)

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => editor.handlePasteEvent(event)

    function statusOptions() {
        const options = [
            { "text": qsTr("Open"), "value": "open" },
            { "text": qsTr("In progress"), "value": "in_progress" },
            { "text": qsTr("Deferred"), "value": "deferred" },
            { "text": qsTr("Closed"), "value": "closed" }
        ];
        if (!creating && String(localDetail.status || "") === "blocked") {
            options.splice(2, 0, {
                "text": qsTr("Blocked (legacy status)"),
                "value": "blocked"
            });
        }
        return options;
    }

    function statusIndex(status) {
        const index = statusOptions().findIndex(option => option.value === status);
        return Math.max(0, index);
    }

    function typeOptions() {
        const options = [
            { "text": qsTr("Bug"), "value": "bug" },
            { "text": qsTr("Feature"), "value": "feature" },
            { "text": qsTr("Task"), "value": "task" },
            { "text": qsTr("Epic"), "value": "epic" },
            { "text": qsTr("Chore"), "value": "chore" },
            { "text": qsTr("Decision"), "value": "decision" }
        ];
        const currentType = String(localDetail.issue_type || "");
        if (!creating
                && currentType.length > 0
                && !options.some(option => option.value === currentType)) {
            options.push({ "text": currentType, "value": currentType });
        }
        return options;
    }

    function typeIndex(issueType) {
        const index = typeOptions().findIndex(option => option.value === issueType);
        return Math.max(0, index);
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
        typeField.currentIndex = typeIndex(issue.issue_type || "task");
        assigneeField.text = issue.assignee || "";
        labelsField.text = issue.labels ? issue.labels.join(", ") : "";
    }

    function initializeCreate() {
        statusField.currentIndex = 0;
        priorityField.currentIndex = 2;
        typeField.currentIndex = 2;
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
        editor.backend.previewAttachment(issueId, attachmentId);
    }

    function localFileUrls(urls) {
        return Array.from(urls || [])
            .map(url => String(url))
            .filter(url => url.toLowerCase().startsWith("file:"));
    }

    function canAttachFiles() {
        return persisted && detailReady && !editor.backend.loading;
    }

    function attachFileUrls(urls) {
        const localUrls = localFileUrls(urls);
        if (!canAttachFiles() || localUrls.length === 0)
            return false;
        preserveFieldsWhileLoading = true;
        editor.backend.addAttachments(issueId, localUrls);
        return true;
    }

    function clipboardFileUrls() {
        if (!editor.clipboard.formats.includes("text/uri-list"))
            return [];
        return localFileUrls(editor.clipboard.contentFormat("text/uri-list"));
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
        return (editor.backend.issues || [])
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
        const issue = (editor.backend.issues || []).find(candidate => {
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
        editor.backend.addDependency(issueId, targetId, relationshipTypeField.currentValue);
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
        if (text.length === 0 || editor.backend.loading || !detailReady)
            return;
        preserveFieldsWhileLoading = true;
        commentSubmitting = true;
        editor.backend.addComment(issueId, text);
    }

    function requestDetail() {
        if (creating || editor.backend.loading || detailLoadRequested)
            return false;
        detailLoadRequested = true;
        detailReady = false;
        editor.backend.loadIssue(issueId);
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
            "issueType": typeField.currentValue,
            "assignee": assigneeField.text,
            "labels": labelsField.text,
            "parentId": parentId
        };
        if (creating)
            editor.backend.createIssue(request);
        else
            editor.backend.saveIssue(request);
    }

    actions: [
        Kirigami.Action {
            text: editor.creating ? qsTr("Create") : qsTr("Save")
            icon.name: editor.creating ? "list-add" : "document-save"
            enabled: !editor.backend.loading && titleField.text.trim().length > 0
            shortcut: StandardKey.Save
            onTriggered: editor.save()
        },
        Kirigami.Action {
            objectName: "createChildAction"
            text: qsTr("Create child ticket")
            icon.name: "list-add"
            visible: !editor.creating && typeField.currentValue === "epic"
            enabled: !editor.backend.loading
            onTriggered: editor.createChildRequested(editor.issueId)
        }
    ]

    Shortcut {
        sequence: "Escape"
        onActivated: editor.closeRequested()
    }

    Shortcut {
        objectName: "attachmentPasteShortcut"
        sequences: [StandardKey.Paste]
        enabled: editor.layerStack.currentItem === editor
            && editor.canAttachFiles()
            && editor.clipboardFileUrls().length > 0
        onActivated: editor.attachFileUrls(editor.clipboardFileUrls())
    }

    Component.onCompleted: {
        if (editor.creating)
            editor.initializeCreate();
        else {
            if (String(editor.backend.detail.id || "") === editor.issueId)
                editor.localDetail = editor.backend.detail;
            editor.populate();
            editor.requestDetail();
        }
    }

    Connections {
        target: editor.backend

        function onAttachmentReady(issueId, path) {
            if (issueId === editor.issueId)
                Qt.openUrlExternally(editor.localFileUrl(path));
        }

        function onAttachmentPreviewReady(issueId, attachmentId, path) {
            if (issueId !== editor.issueId)
                return;
            const previews = Object.assign({}, editor.attachmentPreviews);
            previews[attachmentId] = path;
            editor.attachmentPreviews = previews;
        }

        function onDetailChanged() {
            if (String(editor.backend.detail.id || "") !== editor.issueId)
                return;
            editor.localDetail = editor.backend.detail;
            if (!editor.backend.loading) {
                editor.populate();
                if (!editor.detailLoadRequested)
                    editor.detailReady = true;
            }
        }

        function onLoadingChanged() {
            if (!editor.backend.loading) {
                if (String(editor.backend.detail.id || "") === editor.issueId) {
                    editor.localDetail = editor.backend.detail;
                    editor.detailReady = true;
                }
                editor.detailLoadRequested = false;
                editor.hydratingCreatedIssue = false;
                if (editor.commentSubmitting) {
                    if (editor.backend.errorMessage.length === 0)
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
                    && editor.layerStack.currentItem === editor) {
                editor.issueId = savedId;
                editor.creating = false;
                editor.parentId = "";
                editor.localDetail = editor.backend.detail;
                editor.populate();
                editor.hydratingCreatedIssue = true;
                editor.requestDetail();
            } else if (savedId === editor.issueId) {
                editor.closeRequested();
            } else if (editor.layerStack.currentItem === editor) {
                editor.backend.loadIssue(editor.issueId);
            } else {
                editor.refreshWhenCurrent = true;
            }
        }
    }

    Connections {
        target: editor.layerStack

        function onCurrentItemChanged() {
            if (editor.layerStack.currentItem === editor
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
            visible: editor.backend.errorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: editor.backend.errorMessage
            actions: Kirigami.Action {
                text: qsTr("Dismiss")
                icon.name: "dialog-close"
                onTriggered: editor.backend.clearError()
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
            Components.IssueCopyButton {
                objectName: "editorIssueCopyButton"
                visible: !editor.creating
                issueId: editor.issueId
                onCopyRequested: issueId => editor.copyIssueIdRequested(issueId)
            }
            Controls.Label {
                visible: editor.creating && editor.parentId.length > 0
                text: qsTr("Child of %1").arg(editor.parentId)
                color: Kirigami.Theme.disabledTextColor
                font.family: "monospace"
            }
            Item { Layout.fillWidth: true }
            Controls.BusyIndicator {
                running: editor.backend.loading
                visible: running
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            enabled: !editor.backend.loading || editor.detailLoadRequested

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
                model: editor.statusOptions()
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
                textRole: "text"
                valueRole: "value"
                model: editor.typeOptions()
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
                                    ? editor.localFileUrl(attachmentRow.previewState)
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
                                source: editor.attachmentIcon(attachmentRow.modelData.mime_type)
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: implicitWidth
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                visible: !attachmentRow.previewable
                                source: editor.attachmentIcon(attachmentRow.modelData.mime_type)
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
                                            ? qsTr("Knecklace local")
                                            : qsTr("Beads");
                                        const missing = attachmentRow.modelData.missing
                                            ? ` · ${qsTr("missing locally")}`
                                            : "";
                                        return `${editor.formatBytes(attachmentRow.modelData.byte_size)} · ${provider}${missing}`;
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
                                enabled: !editor.backend.loading && !attachmentRow.modelData.missing
                                Controls.ToolTip.text: text
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    editor.preserveFieldsWhileLoading = true;
                                    editor.backend.openAttachment(
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
                                enabled: !editor.backend.loading
                                Controls.ToolTip.text: text
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    editor.preserveFieldsWhileLoading = true;
                                    editor.backend.removeAttachment(
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
                        enabled: editor.persisted && !editor.backend.loading
                        onClicked: {
                            editor.preserveFieldsWhileLoading = true;
                            editor.backend.addAttachment(editor.issueId);
                        }
                    }

                    Controls.Button {
                        id: migrateAttachmentsButton
                        objectName: "migrateAttachmentsButton"
                        visible: Boolean(editor.localDetail.native_attachments_supported)
                            && Number(editor.localDetail.polyfill_attachment_count || 0) > 0
                        text: qsTr("Move to Beads storage")
                        icon.name: "document-import"
                        enabled: !editor.backend.loading
                        onClicked: {
                            editor.preserveFieldsWhileLoading = true;
                            editor.backend.migrateAttachments(editor.issueId);
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
                        onClicked: editor.openIssueRequested(String(modelData.id))
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
                        onClicked: editor.openIssueRequested(String(modelData.id))
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: editor.persisted && editor.detailReady && !editor.backend.loading

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
                            enabled: !editor.backend.loading
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
                    enabled: editor.persisted && editor.detailReady && !editor.backend.loading
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
                        enabled: !editor.backend.loading
                            && editor.detailReady
                            && commentField.text.trim().length > 0
                        onClicked: editor.submitComment()
                    }
                }
            }

        }
    }
}
