// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as Controls
import QtTest
import kde_beads
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

        function test_change_poll_timer_requests_background_poll() {
            createApp([]);
            const timer = findChild(app, "changePollTimer");

            verify(timer);
            verify(timer.running);
            timer.triggered();
            compare(Backend.pollCallCount, 1);
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
            wait(300);
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
            compare(sourceList.clip, true);
        }

        function test_scrolled_cards_stay_inside_list_and_scrollbar_gutter() {
            const issues = [];
            for (let index = 0; index < 20; ++index)
                issues.push(issue(`test-scroll-${index}`, "open"));
            createApp(issues);

            const list = findChild(app, "cardList-open");
            const scrollBar = findChild(app, "cardScrollBar-open");
            verify(list);
            verify(scrollBar);
            compare(list.clip, true);
            tryCompare(list, "count", issues.length);
            list.positionViewAtIndex(10, ListView.Beginning);
            tryVerify(() => list.itemAtIndex(10) !== null);
            const card = list.itemAtIndex(10);

            verify(card.width + scrollBar.width < list.width);
        }

        function test_project_sidebar_lists_adds_and_switches_projects() {
            createApp([]);
            const sidebar = findChild(app, "projectSidebar");
            const list = findChild(app, "projectList");
            const addButton = findChild(app, "addProjectButton");
            verify(sidebar);
            verify(list);
            verify(addButton);
            compare(sidebar.modal, false);
            compare(sidebar.drawerOpen, true);
            compare(sidebar.collapsible, true);
            compare(list.count, 1);
            compare(list.itemAt(0).text, "kde-beads-tests");
            compare(list.itemAt(0).highlighted, true);

            addButton.clicked();
            compare(Backend.chooseWorkspaceCallCount, 1);

            app.rememberProject("/tmp/another-project");
            tryCompare(list, "count", 2);
            tryVerify(() => list.itemAt(1) !== null);
            list.itemAt(1).clicked();

            compare(Backend.switchWorkspaceCallCount, 1);
            compare(Backend.lastSwitchedWorkspace, "/tmp/another-project");
            compare(Backend.workspace, "/tmp/another-project");
            compare(list.itemAt(1).highlighted, true);
        }

        function test_project_sidebar_becomes_modal_on_narrow_windows() {
            createApp([]);
            const sidebar = findChild(app, "projectSidebar");

            app.width = app.minimumWidth;

            tryCompare(sidebar, "modal", true);
            tryCompare(sidebar, "drawerOpen", false);
            compare(sidebar.collapsible, false);
            verify(sidebar.handleVisible);

            app.width = 1280;

            tryCompare(sidebar, "modal", false);
            tryCompare(sidebar, "drawerOpen", true);
            tryCompare(sidebar, "collapsible", true);
        }

        function test_project_sidebar_supports_collapsed_rail() {
            createApp([]);
            const sidebar = findChild(app, "projectSidebar");
            const list = findChild(app, "projectList");
            tryVerify(() => sidebar.implicitWidth > sidebar.collapsedSize);
            const expandedWidth = sidebar.implicitWidth;

            sidebar.collapsed = true;

            tryCompare(sidebar, "collapsed", true);
            tryVerify(() => sidebar.implicitWidth < expandedWidth);
            compare(
                list.itemAt(0).display,
                Controls.AbstractButton.IconOnly
            );
        }

        function test_project_switching_is_blocked_while_editing() {
            createApp([]);
            app.rememberProject("/tmp/another-project");
            app.openCreate();
            tryCompare(app, "editorLayerOpen", true);

            app.selectProject("/tmp/another-project");

            compare(Backend.switchWorkspaceCallCount, 0);
        }

        function test_project_paths_are_deduplicated() {
            createApp([]);

            compare(
                JSON.stringify(app.normalizedProjects([
                    "/tmp/one",
                    "/tmp/one",
                    "",
                    " /tmp/two "
                ])),
                JSON.stringify(["/tmp/one", "/tmp/two"])
            );
        }
    }
}
