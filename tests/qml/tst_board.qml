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
        name: "Board"
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

        function createApp(issues) {
            Backend.issues = issues;
            app = createTemporaryObject(appComponent, testRoot, { "visible": true });
            verify(app, "application window should load");
            app.requestActivate();
            tryCompare(app, "active", true);
            verify(waitForRendering(app.contentItem));
            wait(50);
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

        function test_empty_open_lane_offers_create() {
            createApp([]);
            const button = findChild(app, "emptyCreateButton");

            verify(button);
            verify(button.visible);
            mouseClick(button);
            tryVerify(() => findChild(app, "editorPage") !== null);
        }

        function test_empty_secondary_statuses_start_collapsed() {
            createApp([]);

            compare(findChild(app, "statusSection-blocked").expanded, false);
            compare(findChild(app, "statusSection-deferred").expanded, false);
        }

        function test_populated_secondary_status_starts_expanded() {
            createApp([issue("test-blocked", "blocked")]);

            compare(findChild(app, "statusSection-blocked").expanded, true);
            compare(findChild(app, "statusSection-deferred").expanded, false);
        }

        function test_secondary_status_can_be_expanded() {
            createApp([]);
            const section = findChild(app, "statusSection-blocked");
            const toggle = findChild(app, "statusToggle-blocked");

            mouseClick(toggle);
            tryCompare(section, "expanded", true);
        }

        function test_drag_requests_status_change() {
            createApp([issue("test-drag", "open")]);
            const sourceList = findChild(app, "cardList-open");
            const destination = findChild(app, "statusColumn-in_progress");
            verify(sourceList);
            verify(destination);
            tryCompare(sourceList, "count", 1);
            sourceList.positionViewAtIndex(0, ListView.Beginning);
            tryVerify(() => sourceList.itemAtIndex(0) !== null);
            const card = sourceList.itemAtIndex(0);
            verify(waitForRendering(card));

            const eventTarget = app.contentItem;
            const startPoint = card.mapToItem(
                eventTarget,
                card.width / 2,
                card.height / 2
            );
            const destinationPoint = destination.mapToItem(
                eventTarget,
                destination.width / 2,
                destination.height / 3
            );
            mouseDrag(
                eventTarget,
                startPoint.x,
                startPoint.y,
                destinationPoint.x - startPoint.x,
                destinationPoint.y - startPoint.y,
                Qt.LeftButton,
                Qt.NoModifier,
                200
            );

            tryCompare(Backend, "moveIssueCallCount", 1);
            compare(Backend.lastMovedId, "test-drag");
            compare(Backend.lastMovedStatus, "in_progress");
        }
    }
}
