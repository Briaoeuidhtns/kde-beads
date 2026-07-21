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
            findChild(editor, "relationshipTargetField").text = "test-blocker";

            editor.addRelationship();

            compare(Backend.addDependencyCallCount, 1);
            compare(Backend.lastDependencyIssueId, "test-existing");
            compare(Backend.lastDependsOnId, "test-blocker");
            compare(Backend.lastDependencyType, "blocks");
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
            const repeater = findChild(app, "attachmentsRepeater");
            verify(repeater);
            tryCompare(repeater, "count", 1);
            const attachmentRow = repeater.itemAt(0);
            verify(attachmentRow);
            verify(findChild(attachmentRow, "attachmentName"));
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
    }
}
