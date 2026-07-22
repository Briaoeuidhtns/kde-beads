// SPDX-License-Identifier: MIT

import QtQuick
import QtTest
import kde_beads
import "../../src" as App

Item {
    id: testRoot
    width: 1280
    height: 760

    Component {
        id: appComponent
        App.Main {}
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

        function createApp() {
            app = createTemporaryObject(appComponent, testRoot, { "visible": true });
            verify(app, "application window should load");
            app.requestActivate();
            tryCompare(app, "active", true);
            verify(waitForRendering(app.contentItem));
            wait(50);
        }

        function openCreateEditor() {
            app.openCreate();
            tryVerify(() => findChild(app, "editorPage") !== null);
            return findChild(app, "editorPage");
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
            findChild(editor, "titleField").text = "Test-created issue";
            findChild(editor, "descriptionField").text = "Created in Qt Quick Test";
            findChild(editor, "labelsField").text = "qml, kde";

            editor.save();

            compare(Backend.createIssueCallCount, 1);
            compare(Backend.lastCreatedRequest.title, "Test-created issue");
            compare(Backend.lastCreatedRequest.description, "Created in Qt Quick Test");
            compare(Backend.lastCreatedRequest.labels, "qml, kde");
            compare(Backend.lastCreatedRequest.status, "open");
            compare(Backend.lastCreatedRequest.priority, "2");
            compare(Backend.lastCreatedRequest.parentId, "");
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
            compare(app.pageStack.layers.currentItem, editor);
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
            app.openEditor("test-child");
            tryCompare(Backend, "lastLoadedId", "test-child");
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

            app.pageStack.layers.pop();

            compare(Backend.lastLoadedId, "test-child");
            compare(Backend.loadIssueCallCount, 2);
            compare(parentEditor.dependents.length, 1);
        }

        function test_escape_closes_editor() {
            createApp();
            openCreateEditor();

            keyClick(Qt.Key_Escape);

            tryVerify(() => findChild(app, "editorPage") === null);
        }

        function test_opening_existing_issue_loads_detail() {
            createApp();
            app.openEditor("test-existing");

            tryCompare(Backend, "loadIssueCallCount", 1);
            compare(Backend.lastLoadedId, "test-existing");
            verify(findChild(app, "editorPage"));
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
