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
            compare(Backend.lastCreatedDraftId, editor.draftId);
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
            compare(editor.savePending, true);
            compare(findChild(editor, "editorForm").enabled, true);
            Backend.errorMessage = "Save failed";
            Backend.finishSave("test-dirty", "1", false);

            compare(titleField.text, "Retry this title");
            compare(editor.dirty, true);
            compare(editor.savePending, false);
        }

        function test_board_move_updates_editor_status_without_losing_dirty_fields() {
            Backend.issues = [issue("test-moved", "open")];
            Backend.detail = {
                "id": "test-moved",
                "title": "Original title",
                "description": "Original description",
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
            app.openEditor("test-moved");
            const editor = findChild(app, "editorPage");
            const titleField = findChild(editor, "titleField");
            const statusField = findChild(editor, "statusField");
            editor.detailReady = true;
            titleField.text = "Unsaved title";

            Backend.moveIssue("test-moved", "in_progress");

            compare(statusField.currentValue, "in_progress");
            compare(titleField.text, "Unsaved title");
            compare(editor.dirty, true);
            Backend.finishMove("test-moved", false);
            compare(statusField.currentValue, "open");
            compare(titleField.text, "Unsaved title");
            compare(editor.dirty, true);
        }

        function test_external_status_change_is_scoped_to_workspace_and_issue() {
            Backend.issues = [issue("test-scoped", "open")];
            Backend.detail = {
                "id": "test-scoped",
                "title": "Scoped issue",
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
            app.openEditor("test-scoped");
            const editor = findChild(app, "editorPage");
            const statusField = findChild(editor, "statusField");
            editor.detailReady = true;

            Backend.issueProjectionChanged(
                "/tmp/another-workspace",
                "test-scoped",
                "closed",
                true
            );
            Backend.issueProjectionChanged(
                Backend.workspace,
                "another-issue",
                "closed",
                true
            );

            compare(statusField.currentValue, "open");
            compare(editor.dirty, false);
        }

        function test_save_success_keeps_newer_editor_changes_dirty() {
            Backend.issues = [issue("test-save-newer", "open")];
            Backend.detail = {
                "id": "test-save-newer",
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
            app.openEditor("test-save-newer");
            const editor = findChild(app, "editorPage");
            const titleField = findChild(editor, "titleField");
            editor.detailReady = true;
            titleField.text = "Submitted title";
            editor.save();
            titleField.text = "Newer local title";

            Backend.finishSave("test-save-newer", "1", true);

            compare(editor.savePending, false);
            compare(titleField.text, "Newer local title");
            compare(editor.dirty, true);
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
            compare(Backend.createAttachmentDraftCallCount, 1);
            compare(editor.draftId, "test-draft-1");
            compare(findChild(editor, "addAttachmentButton").enabled, true);
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

            Backend.issueCreated(
                Backend.workspace,
                editor.draftId,
                "test-created",
                true
            );

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
            const typeField = findChild(editor, "relationshipTypeField");
            const targetField = findChild(editor, "relationshipTargetField");
            const suggestions = findChild(app, "relationshipSuggestions");
            const suggestionList = findChild(app, "relationshipSuggestionList");
            const addButton = findChild(editor, "addRelationshipButton");
            compare(targetField.placeholderText, "Search bead ID or title");
            compare(typeField.count, 4);
            compare(typeField.valueAt(0), "blocked-by");
            compare(typeField.valueAt(1), "blocks");
            compare(typeField.valueAt(2), "parent");
            compare(typeField.valueAt(3), "child");

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
            compare(Backend.lastDependencyDetailId, "test-existing");

            typeField.currentIndex = 1;
            targetField.text = "test-blocker";
            editor.addRelationship();
            compare(Backend.addDependencyCallCount, 2);
            compare(Backend.lastDependencyIssueId, "test-blocker");
            compare(Backend.lastDependsOnId, "test-existing");
            compare(Backend.lastDependencyType, "blocks");
            compare(Backend.lastDependencyDetailId, "test-existing");

            typeField.currentIndex = 2;
            targetField.text = "test-blocker";
            editor.addRelationship();
            compare(Backend.addDependencyCallCount, 3);
            compare(Backend.lastDependencyIssueId, "test-existing");
            compare(Backend.lastDependsOnId, "test-blocker");
            compare(Backend.lastDependencyType, "parent-child");
            compare(Backend.lastDependencyDetailId, "test-existing");

            typeField.currentIndex = 3;
            targetField.text = "test-blocker";
            editor.addRelationship();
            compare(Backend.addDependencyCallCount, 4);
            compare(Backend.lastDependencyIssueId, "test-blocker");
            compare(Backend.lastDependsOnId, "test-existing");
            compare(Backend.lastDependencyType, "parent-child");
            compare(Backend.lastDependencyDetailId, "test-existing");
        }

        function test_existing_issue_removes_relationships_in_either_direction() {
            Backend.issues = [
                issue("test-existing", "open"),
                issue("test-blocker", "open"),
                issue("test-child", "open")
            ];
            Backend.detail = {
                "id": "test-existing",
                "title": "Existing issue",
                "status": "open",
                "priority": 2,
                "issue_type": "epic",
                "labels": [],
                "attachments": [],
                "dependencies": [{
                    "id": "test-blocker",
                    "title": "Blocking bead",
                    "dependency_type": "blocks"
                }],
                "dependents": [{
                    "id": "test-child",
                    "title": "Child bead",
                    "dependency_type": "parent-child"
                }],
                "comments": []
            };
            createApp();
            app.openEditor("test-existing");
            const editor = findChild(app, "editorPage");
            editor.detailReady = true;
            const removeDependency = findChild(editor, "removeDependency-test-blocker");
            const removeDependent = findChild(editor, "removeDependent-test-child");

            verify(removeDependency);
            verify(removeDependent);
            removeDependency.clicked();
            compare(Backend.removeDependencyCallCount, 1);
            compare(Backend.lastDependencyIssueId, "test-existing");
            compare(Backend.lastDependsOnId, "test-blocker");
            compare(Backend.lastDependencyDetailId, "test-existing");

            removeDependent.clicked();
            compare(Backend.removeDependencyCallCount, 2);
            compare(Backend.lastDependencyIssueId, "test-child");
            compare(Backend.lastDependsOnId, "test-existing");
            compare(Backend.lastDependencyDetailId, "test-existing");
        }

        function test_existing_issue_manages_human_and_time_gates() {
            Backend.issues = [issue("test-existing", "open")];
            Backend.detail = {
                "id": "test-existing",
                "title": "Gated issue",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [],
                "dependencies": [{
                    "id": "gate-human",
                    "title": "Gate: human",
                    "description": "Ad-hoc gate blocking test-existing\n\nReason: Approve the design",
                    "status": "open",
                    "issue_type": "gate",
                    "dependency_type": "blocks",
                    "await_type": "human",
                    "created_at": "2026-07-23T04:00:00Z"
                }, {
                    "id": "gate-timer",
                    "title": "Gate: timer",
                    "description": "Ad-hoc gate blocking test-existing\n\nReason: Wait for rollout",
                    "status": "open",
                    "issue_type": "gate",
                    "dependency_type": "blocks",
                    "await_type": "timer",
                    "timeout": 7200000000000,
                    "created_at": "2026-07-23T04:00:00Z"
                }],
                "dependents": [],
                "comments": []
            };
            createApp();
            app.openEditor("test-existing");
            const editor = findChild(app, "editorPage");
            editor.detailReady = true;
            const typeField = findChild(editor, "gateTypeField");
            const reasonField = findChild(editor, "gateReasonField");
            const timeoutField = findChild(editor, "gateTimeoutField");
            const addButton = findChild(editor, "addGateButton");
            const resolveButton = findChild(editor, "resolveGate-gate-human");
            const removeButton = findChild(editor, "removeGate-gate-timer");

            compare(editor.gates.length, 2);
            compare(editor.linkedDependencies.length, 0);
            compare(editor.gateReason(editor.gates[0]), "Approve the design");
            verify(editor.gateDeadline(editor.gates[1]).length > 0);
            compare(typeField.count, 2);
            verify(resolveButton);
            verify(removeButton);

            reasonField.text = "Need product approval";
            addButton.clicked();
            compare(Backend.createGateCallCount, 1);
            compare(Backend.lastGateIssueId, "test-existing");
            compare(Backend.lastGateType, "human");
            compare(Backend.lastGateReason, "Need product approval");
            compare(Backend.lastGateTimeout, "");

            typeField.currentIndex = 1;
            timeoutField.currentIndex = 3;
            reasonField.text = "Wait for propagation";
            addButton.clicked();
            compare(Backend.createGateCallCount, 2);
            compare(Backend.lastGateType, "timer");
            compare(Backend.lastGateReason, "Wait for propagation");
            compare(Backend.lastGateTimeout, "2h");

            resolveButton.clicked();
            compare(Backend.resolveGateCallCount, 1);
            compare(Backend.lastGateIssueId, "test-existing");
            compare(Backend.lastGateId, "gate-human");

            removeButton.clicked();
            compare(Backend.removeGateCallCount, 1);
            compare(Backend.lastGateIssueId, "test-existing");
            compare(Backend.lastGateId, "gate-timer");
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
            Backend.issueCreated(
                Backend.workspace,
                editor.draftId,
                "test-saved-on-close",
                true
            );

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
            Backend.issueCreated(
                Backend.workspace,
                editor.draftId,
                "test-create-and-close",
                true
            );

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
            const attachmentRows = editor.displayedAttachments;
            Backend.detail = Object.assign({}, Backend.detail, { "comments": [] });
            wait(0);
            verify(editor.displayedAttachments === attachmentRows);
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

        function test_create_editor_stages_and_removes_attachments() {
            createApp();
            const editor = openCreateEditor();
            const repeater = findChild(editor, "attachmentsRepeater");
            const draft = {
                "id": "draft-1",
                "original_filename": "before save.png",
                "mime_type": "image/png",
                "byte_size": 512,
                "provider": "draft",
                "missing": false,
                "preview_path": "/tmp/staged-image"
            };

            compare(editor.dirty, false);
            Backend.setDraftAttachments(editor.draftId, [draft]);

            tryCompare(repeater, "count", 1);
            compare(editor.dirty, true);
            compare(repeater.model[0].provider, "draft");
            const row = repeater.itemAt(0);
            verify(row);
            verify(findChild(row, "attachmentPreview").visible);
            findChild(row, "removeAttachmentButton").clicked();
            compare(Backend.removeDraftAttachmentCallCount, 1);
            compare(Backend.lastDraftId, editor.draftId);
            compare(Backend.lastDraftAttachmentId, "draft-1");

            Backend.setDraftAttachments(editor.draftId, []);
            compare(editor.dirty, false);
        }

        function test_create_editor_attaches_local_urls_to_its_draft() {
            createApp();
            const editor = openCreateEditor();

            verify(editor.attachFileUrls([
                "file:///tmp/before-save.png",
                "https://example.com/not-local",
                "file:///tmp/two%20words.txt"
            ]));

            compare(Backend.addDraftAttachmentsCallCount, 1);
            compare(Backend.lastDraftId, editor.draftId);
            compare(Backend.lastDraftAttachmentUrls.length, 2);
            compare(Backend.lastDraftAttachmentUrls[1], "file:///tmp/two%20words.txt");
            compare(editor.draftBusy, true);
            Backend.setDraftAttachments(editor.draftId, []);
            compare(editor.draftBusy, false);
        }

        function test_create_completion_is_scoped_to_the_submitting_editor() {
            createApp();
            app.openCreate();
            app.openCreate();
            tryVerify(() => app.editorPages.length === 2);
            const first = app.editorPages[0];
            const second = app.editorPages[1];
            compare(first.draftId, "test-draft-1");
            compare(second.draftId, "test-draft-2");
            Backend.detail = {
                "id": "test-scoped-create",
                "title": "Scoped create",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": []
            };

            Backend.issueCreated(
                Backend.workspace,
                first.draftId,
                "test-scoped-create",
                true
            );

            compare(first.creating, false);
            compare(first.issueId, "test-scoped-create");
            compare(second.creating, true);
            compare(second.issueId, "");
        }

        function test_partial_create_keeps_unattached_drafts_for_retry() {
            createApp();
            const editor = openCreateEditor();
            const draftId = editor.draftId;
            Backend.setDraftAttachments(draftId, [{
                "id": "draft-failed",
                "original_filename": "retry.txt",
                "mime_type": "text/plain",
                "byte_size": 10,
                "provider": "draft",
                "missing": false,
                "preview_path": "/tmp/staged-text"
            }]);
            Backend.detail = {
                "id": "test-partial-create",
                "title": "Partial create",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": []
            };

            Backend.issueCreated(
                Backend.workspace,
                draftId,
                "test-partial-create",
                false
            );

            compare(editor.persisted, true);
            compare(editor.draftId, draftId);
            compare(editor.draftAttachments.length, 1);
            const retry = findChild(editor, "retryDraftAttachmentsButton");
            verify(retry.visible);
            retry.clicked();
            compare(Backend.retryDraftAttachmentsCallCount, 1);
            compare(Backend.lastAttachmentIssueId, "test-partial-create");
            compare(Backend.lastDraftId, draftId);
        }

        function test_successful_create_replaces_draft_row_atomically() {
            createApp();
            const editor = openCreateEditor();
            const draftId = editor.draftId;
            Backend.setDraftAttachments(draftId, [{
                "id": "draft-success",
                "original_filename": "created.png",
                "mime_type": "image/png",
                "byte_size": 20,
                "provider": "draft",
                "missing": false,
                "preview_path": "/tmp/staged-created-image"
            }]);
            const persistedAttachment = {
                "id": "polyfill:created",
                "original_filename": "created.png",
                "mime_type": "image/png",
                "byte_size": 20,
                "provider": "polyfill",
                "missing": false
            };
            Backend.detail = {
                "id": "test-created-with-attachment",
                "title": "Created with attachment",
                "status": "open",
                "priority": 2,
                "issue_type": "task",
                "labels": [],
                "attachments": [persistedAttachment]
            };

            Backend.issueCreated(
                Backend.workspace,
                draftId,
                "test-created-with-attachment",
                true
            );

            const repeater = findChild(editor, "attachmentsRepeater");
            tryCompare(repeater, "count", 1);
            compare(editor.displayedAttachments[0].provider, "polyfill");
            const attachmentRows = editor.displayedAttachments;
            Backend.detail = Object.assign({}, Backend.detail, {
                "comments": [],
                "attachments": [Object.assign({}, persistedAttachment)]
            });
            wait(0);
            verify(editor.displayedAttachments === attachmentRows);
            compare(repeater.count, 1);
        }

        function test_discarding_create_editor_releases_its_draft() {
            createApp();
            const editor = openCreateEditor();
            const draftId = editor.draftId;

            editor.Window.window.discardAndClose();

            tryVerify(() => app.editorPages.length === 0);
            compare(Backend.discardAttachmentDraftCallCount, 1);
            compare(Backend.lastDraftId, draftId);
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
