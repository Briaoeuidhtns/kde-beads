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
    }
}
