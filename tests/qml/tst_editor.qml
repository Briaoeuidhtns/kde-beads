// SPDX-License-Identifier: MIT

import QtQuick
import QtTest
import knecklace
import "../../src" as App

Item {
    id: testRoot
    width: 1280
    height: 760

    Component {
        id: appComponent
        App.Main { projectPersistenceEnabled: false }
    }

    TestCase {
        id: testCase
        name: "Editor"
        when: windowShown

        property var app: null

        function issue(issueId, status) {
            return {
                "id": issueId,
                "title": `Issue ${issueId}`,
                "description": "",
                "status": status,
                "priority": 2,
                "issue_type": "task",
                "assignee": "",
                "labels": []
            };
        }

        function createApp(properties) {
            const initialProperties = Object.assign({
                "visible": true
            }, properties || {});
            app = createTemporaryObject(appComponent, testRoot, initialProperties);
            verify(app, "application window should load");
            app.requestActivate();
            tryCompare(app, "active", true);
            verify(waitForRendering(app.contentItem));
            wait(50);
        }

        function openCreateEditor() {
            app.openCreate();
            tryVerify(() => findChild(app, "editorPage") !== null);
            const editor = findChild(app, "editorPage");
            tryVerify(() => editor.Window.window.active);
            return editor;
        }

        function init() {
            Backend.reset();
            app = null;
        }

        function cleanup() {
            if (app) {
                app.destroy();
                app = null;
                wait(0);
            }
        }

        function test_create_editor_submits_fields() {
            createApp();
            const editor = openCreateEditor();
            const titleField = findChild(editor, "titleField");
            const statusField = findChild(editor, "statusField");
            const typeField = findChild(editor, "typeField");
            const saveButton = findChild(editor, "bottomSaveButton");
            const deleteAction = findChild(editor, "deleteIssueAction");
            compare(editor.title, "Create bead");
            compare(titleField.placeholderText, "Bead title");
            compare(editor.dirty, false);
            compare(saveButton.text, "Create");
            compare(deleteAction.visible, false);
            titleField.text = "Test-created issue";
            findChild(editor, "descriptionField").text = "Created in Qt Quick Test";
            findChild(editor, "labelsField").text = "qml, kde";

            compare(statusField.count, 4);
            for (let index = 0; index < statusField.count; ++index)
                verify(statusField.valueAt(index) !== "blocked");
            compare(typeField.editable, false);
            compare(typeField.count, 6);
            compare(typeField.currentValue, "task");

            tryCompare(editor, "dirty", true);
            saveButton.clicked();

            compare(Backend.createIssueCallCount, 1);
            compare(Backend.lastCreatedRequest.title, "Test-created issue");
            compare(Backend.lastCreatedRequest.description, "Created in Qt Quick Test");
            compare(Backend.lastCreatedRequest.labels, "qml, kde");
            compare(Backend.lastCreatedRequest.status, "open");
            compare(Backend.lastCreatedRequest.priority, "2");
            compare(Backend.lastCreatedRequest.issueType, "task");
            compare(Backend.lastCreatedRequest.parentId, "");
        }

        function test_existing_custom_type_is_preserved_as_a_static_option() {
            Backend.issues = [issue("test-custom-type", "open")];
            Backend.detail = {
                "id": "test-custom-type",
                "title": "Custom type issue",
                "status": "open",
                "priority": 2,
                "issue_type": "incident",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            createApp();
            app.openEditor("test-custom-type");
            const editor = findChild(app, "editorPage");
            const typeField = findChild(editor, "typeField");

            compare(typeField.editable, false);
            compare(typeField.count, 7);
            compare(typeField.currentValue, "incident");
            editor.save();

            compare(Backend.lastSavedRequest.issueType, "incident");
        }

        function test_existing_editor_disables_form_until_detail_loads() {
            Backend.issues = [issue("test-loading", "open")];
            createApp();
            app.openEditor("test-loading");
            const editor = findChild(app, "editorPage");
            const form = findChild(editor, "editorForm");
            const titleField = findChild(editor, "titleField");

            compare(editor.detailLoadRequested, true);
            compare(form.enabled, false);
            compare(titleField.enabled, false);

            Backend.loading = true;
            Backend.detail = {
                "id": "test-loading",
                "title": "Loaded bead",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            compare(form.enabled, false);

            Backend.loading = false;

            compare(editor.detailReady, true);
            compare(form.enabled, true);
            compare(titleField.enabled, true);
            compare(titleField.text, "Loaded bead");
        }

        function test_existing_editor_tracks_and_preserves_dirty_fields() {
            Backend.issues = [issue("test-dirty", "open")];
            Backend.detail = {
                "id": "test-dirty",
                "title": "Original title",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            createApp();
            app.openEditor("test-dirty");
            const editor = findChild(app, "editorPage");
            const titleField = findChild(editor, "titleField");
            const saveButton = findChild(editor, "bottomSaveButton");
            const createOptionsButton = findChild(editor, "createOptionsButton");
            editor.detailReady = true;

            compare(editor.dirty, false);
            compare(saveButton.text, "Save");
            compare(createOptionsButton.visible, false);
            titleField.text = "Changed title";
            tryCompare(editor, "dirty", true);
            titleField.text = "Original title";
            tryCompare(editor, "dirty", false);

            titleField.text = "Retry this title";
            editor.save();
            compare(editor.preserveFieldsWhileLoading, true);
            Backend.loading = true;
            Backend.errorMessage = "Save failed";
            Backend.loading = false;

            compare(titleField.text, "Retry this title");
            compare(editor.dirty, true);
            compare(editor.preserveFieldsWhileLoading, false);
        }

        function test_legacy_blocked_status_is_preserved_on_save() {
            Backend.issues = [issue("test-legacy-blocked", "blocked")];
            Backend.detail = {
                "id": "test-legacy-blocked",
                "title": "Legacy blocked issue",
                "status": "blocked",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            createApp();
            app.openEditor("test-legacy-blocked");
            const editor = findChild(app, "editorPage");
            const statusField = findChild(editor, "statusField");

            compare(statusField.currentValue, "blocked");
            compare(statusField.count, 5);
            editor.save();

            compare(Backend.saveIssueCallCount, 1);
            compare(Backend.lastSavedRequest.status, "blocked");
        }

        function test_created_issue_stays_open_as_persisted_editor() {
            createApp();
            const editor = openCreateEditor();
            compare(editor.persisted, false);
            compare(findChild(editor, "attachmentsSection").visible, true);
            compare(findChild(editor, "relationshipsSection").visible, true);
            compare(findChild(editor, "commentsSection").visible, false);
            compare(findChild(editor, "addAttachmentButton").enabled, false);
            Backend.detail = {
                "id": "test-created",
                "title": "Created issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };

            Backend.issueSaved("test-created");

            compare(editor.creating, false);
            compare(editor.persisted, true);
            compare(editor.issueId, "test-created");
            compare(findChild(editor, "commentsSection").visible, true);
            compare(Backend.lastLoadedId, "test-created");
            compare(editor.isCurrent, true);
        }

        function test_child_editor_submits_epic_parent() {
            createApp();
            app.openCreate("test-epic");
            tryVerify(() => findChild(app, "editorPage") !== null);
            const editor = findChild(app, "editorPage");
            findChild(editor, "titleField").text = "Epic child";

            editor.save();

            compare(Backend.createIssueCallCount, 1);
            compare(Backend.lastCreatedRequest.parentId, "test-epic");
        }

        function test_existing_issue_adds_relationship() {
            const searchableIssue = issue("test-other", "open");
            searchableIssue.title = "Another searchable issue";
            Backend.issues = [
                issue("test-existing", "open"),
                issue("test-blocker", "open"),
                searchableIssue
            ];
            Backend.detail = {
                "id": "test-existing",
                "title": "Existing issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "dependencies": [],
                "dependents": []
            };
            createApp();
            app.openEditor("test-existing");
            tryVerify(() => findChild(app, "editorPage") !== null);
            const editor = findChild(app, "editorPage");
            editor.detailReady = true;
            const targetField = findChild(editor, "relationshipTargetField");
            const suggestions = findChild(app, "relationshipSuggestions");
            const suggestionList = findChild(app, "relationshipSuggestionList");
            const addButton = findChild(editor, "addRelationshipButton");
            compare(targetField.placeholderText, "Search bead ID or title");

            targetField.forceActiveFocus();
            targetField.text = "searchable";
            compare(targetField.candidates.length, 1);
            compare(targetField.candidates[0].id, "test-other");
            tryCompare(suggestions, "opened", true);
            compare(suggestions.parent, targetField);
            compare(suggestions.x, 0);
            compare(suggestions.y, targetField.height);
            compare(suggestionList.currentIndex, 0);
            compare(addButton.enabled, false);

            targetField.text = "missing-issue";
            compare(targetField.candidates.length, 0);
            compare(addButton.enabled, false);

            targetField.text = "test-blocker";
            tryCompare(suggestions, "opened", false);
            compare(addButton.enabled, true);

            editor.addRelationship();

            compare(Backend.addDependencyCallCount, 1);
            compare(Backend.lastDependencyIssueId, "test-existing");
            compare(Backend.lastDependsOnId, "test-blocker");
            compare(Backend.lastDependencyType, "blocks");
        }

        function test_existing_issue_displays_and_submits_comments() {
            Backend.detail = {
                "id": "test-existing",
                "title": "Existing issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": [{
                    "id": "comment-1",
                    "issue_id": "test-existing",
                    "author": "Test User",
                    "text": "Existing comment",
                    "created_at": "2026-07-21T12:00:00Z"
                }]
            };
            createApp();
            app.openEditor("test-existing");
            const editor = findChild(app, "editorPage");
            compare(editor.comments.length, 1);
            editor.detailReady = true;
            compare(editor.comments[0].text, "Existing comment");

            editor.commentDraft = "  \n";
            editor.submitComment();
            compare(Backend.addCommentCallCount, 0);

            findChild(editor, "titleField").text = "Unsaved title";
            editor.commentDraft = "A new comment";
            editor.submitComment();
            compare(Backend.addCommentCallCount, 1);
            compare(Backend.lastCommentIssueId, "test-existing");
            compare(Backend.lastCommentText, "A new comment");
            compare(editor.commentDraft, "A new comment");

            Backend.loading = true;
            Backend.detail = {
                "id": "test-existing",
                "title": "Existing issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            Backend.loading = false;

            compare(editor.commentDraft, "");
            compare(findChild(editor, "titleField").text, "Unsaved title");
        }

        function test_back_from_linked_issue_retains_parent_detail() {
            Backend.detail = {
                "id": "test-parent",
                "title": "Parent issue",
                "status": "open",
                "priority": 1,
                "issue_type": "epic",
                "labels": [],
                "dependencies": [],
                "dependents": [{
                    "id": "test-child",
                    "title": "Child issue",
                    "dependency_type": "parent-child"
                }]
            };
            createApp();
            app.openEditor("test-parent");
            tryCompare(Backend, "lastLoadedId", "test-parent");
            const parentEditor = findChild(app, "editorPage");
            compare(parentEditor.dependents.length, 1);
            parentEditor.openIssueRequested("test-child");
            tryCompare(Backend, "lastLoadedId", "test-child");
            const childEditor = app.activeEditorPage;
            verify(childEditor !== parentEditor);
            verify(childEditor.Window.window !== parentEditor.Window.window);
            tryCompare(childEditor, "isCurrent", true);
            tryCompare(parentEditor, "isCurrent", false);
            Backend.detail = {
                "id": "test-child",
                "title": "Child issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "dependencies": [],
                "dependents": []
            };

            childEditor.closeRequested();

            compare(Backend.lastLoadedId, "test-child");
            compare(Backend.loadIssueCallCount, 2);
            compare(parentEditor.dependents.length, 1);
            tryVerify(() => app.activeEditorPage === parentEditor);
        }

        function test_narrow_window_uses_editor_window() {
            createApp({ "width": 800 });
            const editor = openCreateEditor();

            verify(editor.Window.window !== app);
            compare(app.pageStack.layers.depth, 1);
            compare(app.editorLayerOpen, true);
        }

        function test_wide_window_uses_editor_window() {
            createApp({ "width": 1280 });
            const editor = openCreateEditor();
            const issueWindow = editor.Window.window;

            verify(issueWindow);
            verify(issueWindow !== app);
            verify(issueWindow.width < app.width);
            compare(issueWindow.modality, Qt.NonModal);
            compare(app.pageStack.layers.depth, 1);
            compare(app.editorLayerOpen, true);
            compare(editor.isCurrent, true);
        }

        function test_escape_closes_editor() {
            createApp();
            openCreateEditor();

            keyClick(Qt.Key_Escape);

            tryVerify(() => findChild(app, "editorPage") === null);
        }

        function test_dirty_editor_prompts_to_save_discard_or_cancel() {
            createApp();
            const editor = openCreateEditor();
            const issueWindow = editor.Window.window;
            const dialog = findChild(issueWindow, "unsavedChangesDialog");
            const titleField = findChild(editor, "titleField");
            const cancelButton = findChild(issueWindow, "cancelCloseButton");
            const discardButton = findChild(issueWindow, "discardChangesButton");

            titleField.text = "Unsaved bead";
            tryCompare(editor, "dirty", true);
            keyClick(Qt.Key_Escape);

            tryCompare(dialog, "opened", true);
            compare(issueWindow.visible, true);
            cancelButton.clicked();
            tryCompare(dialog, "opened", false);
            compare(issueWindow.visible, true);

            issueWindow.close();
            tryCompare(dialog, "opened", true);
            discardButton.clicked();

            tryVerify(() => findChild(app, "editorPage") === null);
        }

        function test_prompt_save_creates_bead_before_closing() {
            createApp();
            const editor = openCreateEditor();
            const issueWindow = editor.Window.window;
            const dialog = findChild(issueWindow, "unsavedChangesDialog");
            const saveButton = findChild(issueWindow, "saveChangesButton");
            findChild(editor, "titleField").text = "Save before closing";

            editor.closeRequested();
            tryCompare(dialog, "opened", true);
            saveButton.clicked();

            compare(Backend.createIssueCallCount, 1);
            compare(issueWindow.visible, true);
            Backend.detail = {
                "id": "test-saved-on-close",
                "title": "Save before closing",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            Backend.issueSaved("test-saved-on-close");

            tryVerify(() => findChild(app, "editorPage") === null);
        }

        function test_create_and_close_waits_for_created_bead() {
            createApp();
            const editor = openCreateEditor();
            const issueWindow = editor.Window.window;
            const createOptionsButton = findChild(editor, "createOptionsButton");
            const createOptionsMenu = findChild(editor, "createOptionsMenu");
            const createAndCloseButton = findChild(editor, "createAndCloseButton");
            findChild(editor, "titleField").text = "Create and close";

            compare(createOptionsButton.visible, true);
            createOptionsButton.clicked();
            tryCompare(createOptionsMenu, "opened", true);
            createAndCloseButton.triggered();

            compare(Backend.createIssueCallCount, 1);
            compare(editor.closeAfterSave, true);
            compare(issueWindow.visible, true);
            Backend.detail = {
                "id": "test-create-and-close",
                "title": "Create and close",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            Backend.issueSaved("test-create-and-close");

            tryVerify(() => findChild(app, "editorPage") === null);
        }

        function test_opening_existing_issue_loads_detail() {
            createApp();
            app.openEditor("test-existing");

            tryCompare(Backend, "loadIssueCallCount", 1);
            compare(Backend.lastLoadedId, "test-existing");
            verify(findChild(app, "editorPage"));
        }

        function test_existing_editor_confirms_permanent_delete() {
            Backend.issues = [issue("test-delete", "open")];
            Backend.detail = {
                "id": "test-delete",
                "title": "Delete this bead",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            createApp();
            app.openEditor("test-delete");
            const editor = findChild(app, "editorPage");
            const issueWindow = editor.Window.window;
            const deleteAction = findChild(editor, "deleteIssueAction");
            const dialog = findChild(issueWindow, "deleteIssueDialog");
            const warning = findChild(issueWindow, "deleteIssueWarning");
            const cancelButton = findChild(issueWindow, "cancelDeleteButton");
            const confirmButton = findChild(issueWindow, "confirmDeleteButton");
            const unsavedDialog = findChild(issueWindow, "unsavedChangesDialog");
            editor.detailReady = true;
            findChild(editor, "titleField").text = "Dirty title";

            compare(deleteAction.visible, true);
            deleteAction.triggered();
            tryCompare(dialog, "opened", true);
            verify(warning.text.includes("cannot be undone"));
            compare(Backend.deleteIssueCallCount, 0);

            cancelButton.clicked();
            tryCompare(dialog, "opened", false);
            compare(Backend.deleteIssueCallCount, 0);

            deleteAction.triggered();
            tryCompare(dialog, "opened", true);
            confirmButton.clicked();

            compare(Backend.deleteIssueCallCount, 1);
            compare(Backend.lastDeletedId, "test-delete");
            compare(issueWindow.visible, true);
            compare(unsavedDialog.opened, false);
            Backend.issueDeleted("test-delete");

            tryVerify(() => findChild(app, "editorPage") === null);
        }

        function test_opening_an_open_issue_raises_its_existing_window() {
            Backend.issues = [issue("test-single-window", "open")];
            Backend.detail = {
                "id": "test-single-window",
                "title": "Single window issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [],
                "dependents": [],
                "comments": []
            };
            createApp();
            app.openEditor("test-single-window");
            tryVerify(() => app.editorPages.length === 1);
            const editor = app.activeEditorPage;
            const attentionAnimation = findChild(
                editor.Window.window,
                "attentionAnimation"
            );
            verify(attentionAnimation);
            compare(attentionAnimation.loops, 1);

            app.openEditor("test-single-window");

            compare(app.editorPages.length, 1);
            compare(app.activeEditorPage, editor);
            compare(Backend.loadIssueCallCount, 1);
            tryCompare(attentionAnimation, "running", true);
        }

        function test_existing_issue_id_can_be_copied() {
            mouseMove(testRoot, testRoot.width - 1, testRoot.height - 1);
            createApp();
            app.openEditor("test-existing");
            const copyButton = findChild(app, "editorIssueCopyButton");
            const clipboard = findChild(app, "attachmentClipboard");
            verify(copyButton);
            verify(clipboard);
            compare(copyButton.hovered, false);

            copyButton.clicked();

            compare(clipboard.content, "test-existing");
            compare(copyButton.icon.name, "dialog-ok");
            wait(750);
            compare(copyButton.icon.name, "dialog-ok");
            tryCompare(copyButton.icon, "name", "edit-copy");
        }

        function test_existing_issue_exposes_attachment_actions() {
            Backend.detail = {
                "id": "test-existing",
                "title": "Issue with attachment",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "attachments": [{
                    "id": "polyfill:abc",
                    "original_filename": "screenshot.png",
                    "mime_type": "image/png",
                    "byte_size": 2048,
                    "missing": false,
                    "provider": "polyfill"
                }],
                "native_attachments_supported": true,
                "polyfill_attachment_count": 1
            };
            createApp();
            app.openEditor("test-existing");
            const editor = findChild(app, "editorPage");
            const repeater = findChild(app, "attachmentsRepeater");
            verify(repeater);
            tryCompare(repeater, "count", 1);
            const attachmentRow = repeater.itemAt(0);
            verify(attachmentRow);
            verify(findChild(attachmentRow, "attachmentName"));
            tryCompare(Backend, "previewAttachmentCallCount", 1);
            compare(Backend.lastAttachmentId, "polyfill:abc");
            Backend.attachmentPreviewReady(
                "test-existing",
                "polyfill:abc",
                "/tmp/preview.png"
            );
            compare(
                editor.attachmentPreviewState("polyfill:abc"),
                "/tmp/preview.png"
            );
            verify(findChild(attachmentRow, "attachmentPreview").visible);
            findChild(app, "descriptionField").text = "Unsaved description";

            findChild(attachmentRow, "openAttachmentButton").clicked();
            compare(Backend.openAttachmentCallCount, 1);
            compare(Backend.lastAttachmentIssueId, "test-existing");
            compare(Backend.lastAttachmentId, "polyfill:abc");
            Backend.loading = true;
            Backend.loading = false;
            compare(findChild(app, "descriptionField").text, "Unsaved description");

            findChild(attachmentRow, "removeAttachmentButton").clicked();
            compare(Backend.removeAttachmentCallCount, 1);

            findChild(app, "addAttachmentButton").clicked();
            compare(Backend.addAttachmentCallCount, 1);

            findChild(app, "migrateAttachmentsButton").clicked();
            compare(Backend.migrateAttachmentsCallCount, 1);
            compare(app.localFileUrl("/tmp/a b#c"), "file:///tmp/a%20b%23c");
        }

        function test_existing_issue_attaches_file_urls() {
            Backend.detail = {
                "id": "test-existing",
                "title": "Issue with dropped files",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "attachments": []
            };
            createApp();
            app.openEditor("test-existing");
            const editor = findChild(app, "editorPage");
            const dropArea = findChild(editor, "attachmentDropArea");
            verify(dropArea);
            compare(dropArea.enabled, false);
            editor.detailReady = true;
            compare(dropArea.enabled, true);

            verify(editor.attachFileUrls([
                "file:///tmp/one.png",
                "https://example.com/not-local",
                "file:///tmp/two%20words.txt"
            ]));

            compare(Backend.addAttachmentsCallCount, 1);
            compare(Backend.lastAttachmentIssueId, "test-existing");
            compare(Backend.lastAttachmentUrls.length, 2);
            compare(Backend.lastAttachmentUrls[0], "file:///tmp/one.png");
            compare(Backend.lastAttachmentUrls[1], "file:///tmp/two%20words.txt");
            compare(editor.preserveFieldsWhileLoading, true);

            verify(!editor.attachFileUrls(["https://example.com/not-local"]));
            compare(Backend.addAttachmentsCallCount, 1);
        }

        function test_pasting_files_attaches_them() {
            Backend.detail = {
                "id": "test-existing",
                "title": "Issue with pasted files",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "attachments": []
            };
            createApp();
            app.openEditor("test-existing");
            const editor = findChild(app, "editorPage");
            const clipboard = findChild(app, "attachmentClipboard");
            const shortcut = findChild(editor, "attachmentPasteShortcut");
            editor.detailReady = true;
            clipboard.content = [
                Qt.resolvedUrl("file:///tmp/pasted-one.png"),
                Qt.resolvedUrl("file:///tmp/pasted-two.txt")
            ];
            tryCompare(shortcut, "enabled", true);

            findChild(editor, "titleField").forceActiveFocus();
            keyClick(Qt.Key_V, Qt.ControlModifier);

            tryCompare(Backend, "addAttachmentsCallCount", 1);
            compare(Backend.lastAttachmentUrls.length, 2);
            compare(Backend.lastAttachmentUrls[0], "file:///tmp/pasted-one.png");
            compare(Backend.lastAttachmentUrls[1], "file:///tmp/pasted-two.txt");
        }
    }
}
