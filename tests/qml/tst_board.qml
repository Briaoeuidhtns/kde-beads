// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as Controls
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
                "labels": [],
                "closed_at": "",
                "is_blocked": false
            };
        }

        function createApp(issues, properties) {
            Backend.issues = issues;
            const initialProperties = properties || {};
            initialProperties.visible = true;
            app = createTemporaryObject(appComponent, testRoot, initialProperties);
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
            const blocked = issue("test-blocked", "open");
            blocked.is_blocked = true;
            createApp([blocked]);

            compare(findChild(app, "statusSection-blocked").expanded, true);
            compare(findChild(app, "statusSection-deferred").expanded, false);
            compare(findChild(app, "cardList-open").count, 0);
            compare(findChild(app, "cardList-blocked").count, 1);
            compare(findChild(app, "cardList-blocked").model[0].id, "test-blocked");
        }

        function test_blocked_category_is_not_a_drop_target() {
            createApp([]);

            compare(findChild(app, "statusSection-blocked").dropEnabled, false);
            compare(findChild(app, "statusColumn-blocked").dropEnabled, false);
            compare(findChild(app, "sectionDropArea-blocked").enabled, false);
            compare(findChild(app, "columnDropArea-blocked").enabled, false);
        }

        function test_deferred_and_closed_override_dependency_blocking() {
            const deferred = issue("test-blocked-deferred", "deferred");
            deferred.is_blocked = true;
            const inProgress = issue("test-blocked-progress", "in_progress");
            inProgress.is_blocked = true;
            const closed = issue("test-blocked-closed", "closed");
            closed.is_blocked = true;
            closed.closed_at = new Date().toISOString();
            createApp([deferred, inProgress, closed]);

            compare(findChild(app, "cardList-blocked").count, 1);
            compare(findChild(app, "cardList-deferred").count, 1);
            compare(findChild(app, "cardList-in_progress").count, 0);
            compare(findChild(app, "cardList-closed").count, 1);
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

        function test_closed_issues_are_sorted_and_filterable_by_close_date() {
            const now = new Date();
            const recent = issue("closed-recent", "closed");
            recent.closed_at = now.toISOString();
            const threeDay = issue("closed-three-day", "closed");
            threeDay.closed_at = new Date(
                now.getTime() - 2 * 24 * 60 * 60 * 1000
            ).toISOString();
            const old = issue("closed-old", "closed");
            old.closed_at = new Date(
                now.getTime() - 8 * 24 * 60 * 60 * 1000
            ).toISOString();
            createApp([old, recent, threeDay]);
            const list = findChild(app, "cardList-closed");
            const rangeField = findChild(app, "closedRangeField");
            verify(list);
            verify(rangeField);
            tryCompare(list, "count", 3);
            compare(list.model[0].id, "closed-recent");
            compare(list.model[1].id, "closed-three-day");
            compare(list.model[2].id, "closed-old");

            rangeField.currentIndex = 1;
            tryCompare(list, "count", 1);
            compare(list.model[0].id, "closed-recent");

            rangeField.currentIndex = 2;
            tryCompare(list, "count", 2);
            compare(list.model[1].id, "closed-three-day");

            rangeField.currentIndex = 3;
            tryCompare(list, "count", 2);

            rangeField.currentIndex = 0;
            tryCompare(list, "count", 3);
        }

        function test_top_level_column_headers_share_the_tallest_height() {
            createApp([]);
            const openHeader = findChild(app, "columnHeader-open");
            const progressHeader = findChild(app, "columnHeader-in_progress");
            const closedHeader = findChild(app, "columnHeader-closed");
            verify(openHeader);
            verify(progressHeader);
            verify(closedHeader);
            tryVerify(() => closedHeader.height > 0);
            tryCompare(openHeader, "height", closedHeader.height);
            tryCompare(progressHeader, "height", closedHeader.height);
        }

        function test_card_issue_id_can_be_copied_without_opening_editor() {
            createApp([issue("test-copy", "open")]);
            const list = findChild(app, "cardList-open");
            const clipboard = findChild(app, "attachmentClipboard");
            verify(list);
            verify(clipboard);
            tryVerify(() => list.itemAtIndex(0) !== null);
            const copyButton = findChild(
                list.itemAtIndex(0),
                "issueCopyButton-test-copy"
            );
            verify(copyButton);

            mouseClick(copyButton);

            compare(clipboard.content, "test-copy");
            compare(copyButton.icon.name, "dialog-ok");
            compare(findChild(app, "editorPage"), null);
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
            compare(list.itemAt(0).text, "knecklace-tests");
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

        function test_project_switching_remains_available_while_loading() {
            createApp([]);
            app.rememberProject("/tmp/another-project");
            const list = findChild(app, "projectList");
            Backend.loading = true;

            compare(list.itemAt(1).enabled, true);
            app.selectProject("/tmp/another-project");

            compare(Backend.switchWorkspaceCallCount, 1);
            compare(Backend.workspace, "/tmp/another-project");
        }

        function test_background_refresh_keeps_cached_board_interactive() {
            createApp([issue("cached-issue", "open")]);
            const progress = findChild(app, "boardProgress");
            const createAction = findChild(app, "createTicketAction");
            const searchField = findChild(app, "searchField");
            const list = findChild(app, "cardList-open");
            const searchY = searchField.mapToItem(app.contentItem, 0, 0).y;
            Backend.refreshing = true;

            compare(list.count, 1);
            compare(progress.visible, true);
            compare(createAction.enabled, true);
            compare(findChild(app, "refreshAction"), null);
            compare(searchField.mapToItem(app.contentItem, 0, 0).y, searchY);
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
            compare(app.sidebarCollapsedPreference, true);
            tryVerify(() => sidebar.implicitWidth < expandedWidth);
            compare(
                list.itemAt(0).display,
                Controls.AbstractButton.IconOnly
            );
        }

        function test_project_sidebar_restores_saved_state_outside_narrow_mode() {
            createApp([], { "sidebarCollapsedPreference": true });
            const sidebar = findChild(app, "projectSidebar");

            tryCompare(sidebar, "collapsed", true);

            app.width = app.minimumWidth;

            tryCompare(sidebar, "modal", true);
            tryCompare(sidebar, "collapsed", false);
            tryCompare(sidebar, "drawerOpen", false);

            app.width = 1280;

            tryCompare(sidebar, "modal", false);
            tryCompare(sidebar, "collapsed", true);
            tryCompare(sidebar, "drawerOpen", true);
        }

        function test_project_switching_can_be_cancelled_while_editing() {
            createApp([]);
            app.rememberProject("/tmp/another-project");
            app.openCreate();
            tryCompare(app, "editorLayerOpen", true);
            const list = findChild(app, "projectList");
            const dialog = findChild(app, "projectSwitchDialog");
            const addButton = findChild(app, "addProjectButton");

            compare(list.itemAt(1).enabled, true);
            compare(addButton.enabled, true);
            app.selectProject("/tmp/another-project");

            tryCompare(dialog, "visible", true);
            compare(dialog.modality, Qt.ApplicationModal);
            compare(dialog.transientParent, app);
            compare(dialog.minimumWidth, dialog.maximumWidth);
            compare(dialog.minimumHeight, dialog.maximumHeight);
            compare(Backend.switchWorkspaceCallCount, 0);
            dialog.reject();
            tryCompare(dialog, "visible", false);
            compare(Backend.switchWorkspaceCallCount, 0);
            compare(app.editorLayerOpen, true);
            compare(Backend.workspace, "/tmp/knecklace-tests");
        }

        function test_project_switching_closes_editors_after_confirmation() {
            createApp([]);
            app.rememberProject("/tmp/another-project");
            app.openCreate();
            tryCompare(app, "editorLayerOpen", true);
            const dialog = findChild(app, "projectSwitchDialog");

            app.selectProject("/tmp/another-project");
            tryCompare(dialog, "visible", true);
            dialog.accept();

            tryCompare(app, "editorLayerOpen", false);
            compare(Backend.switchWorkspaceCallCount, 1);
            compare(Backend.workspace, "/tmp/another-project");
        }

        function test_chosen_project_uses_editor_confirmation() {
            createApp([]);
            app.openCreate();
            tryCompare(app, "editorLayerOpen", true);
            const dialog = findChild(app, "projectSwitchDialog");

            Backend.workspaceChosen("/tmp/chosen-project");

            tryCompare(dialog, "visible", true);
            compare(Backend.switchWorkspaceCallCount, 0);
            verify(app.knownProjects.includes("/tmp/chosen-project"));
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
