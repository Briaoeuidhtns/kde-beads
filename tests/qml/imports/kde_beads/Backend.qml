// SPDX-License-Identifier: MIT

pragma Singleton

import QtQml

QtObject {
    property var issues: []
    property var detail: ({})
    property string workspace: "/tmp/kde-beads-tests"
    property string errorMessage: ""
    property bool loading: false

    property int reloadCallCount: 0
    property int loadIssueCallCount: 0
    property int moveIssueCallCount: 0
    property int saveIssueCallCount: 0
    property int createIssueCallCount: 0
    property string lastLoadedId: ""
    property string lastMovedId: ""
    property string lastMovedStatus: ""
    property var lastSavedRequest: ({})
    property var lastCreatedRequest: ({})

    signal issueSaved(string savedId)

    function reset() {
        issues = [];
        detail = {};
        workspace = "/tmp/kde-beads-tests";
        errorMessage = "";
        loading = false;
        reloadCallCount = 0;
        loadIssueCallCount = 0;
        moveIssueCallCount = 0;
        saveIssueCallCount = 0;
        createIssueCallCount = 0;
        lastLoadedId = "";
        lastMovedId = "";
        lastMovedStatus = "";
        lastSavedRequest = {};
        lastCreatedRequest = {};
    }

    function reload() {
        reloadCallCount += 1;
    }

    function loadIssue(issueId) {
        loadIssueCallCount += 1;
        lastLoadedId = issueId;
    }

    function moveIssue(issueId, status) {
        moveIssueCallCount += 1;
        lastMovedId = issueId;
        lastMovedStatus = status;
    }

    function saveIssue(request) {
        saveIssueCallCount += 1;
        lastSavedRequest = request;
    }

    function createIssue(request) {
        createIssueCallCount += 1;
        lastCreatedRequest = request;
    }

    function chooseWorkspace() {}

    function clearError() {
        errorMessage = "";
    }
}
