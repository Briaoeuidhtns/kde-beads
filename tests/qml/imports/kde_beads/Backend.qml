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
    property int pollCallCount: 0
    property int loadIssueCallCount: 0
    property int moveIssueCallCount: 0
    property int saveIssueCallCount: 0
    property int createIssueCallCount: 0
    property int addDependencyCallCount: 0
    property int addCommentCallCount: 0
    property int addAttachmentCallCount: 0
    property int openAttachmentCallCount: 0
    property int removeAttachmentCallCount: 0
    property int migrateAttachmentsCallCount: 0
    property string lastLoadedId: ""
    property string lastMovedId: ""
    property string lastMovedStatus: ""
    property var lastSavedRequest: ({})
    property var lastCreatedRequest: ({})
    property string lastDependencyIssueId: ""
    property string lastDependsOnId: ""
    property string lastDependencyType: ""
    property string lastCommentIssueId: ""
    property string lastCommentText: ""
    property string lastAttachmentIssueId: ""
    property string lastAttachmentId: ""

    signal issueSaved(string savedId)
    signal attachmentReady(string issueId, string path)

    function reset() {
        issues = [];
        detail = {};
        workspace = "/tmp/kde-beads-tests";
        errorMessage = "";
        loading = false;
        reloadCallCount = 0;
        pollCallCount = 0;
        loadIssueCallCount = 0;
        moveIssueCallCount = 0;
        saveIssueCallCount = 0;
        createIssueCallCount = 0;
        addDependencyCallCount = 0;
        addCommentCallCount = 0;
        addAttachmentCallCount = 0;
        openAttachmentCallCount = 0;
        removeAttachmentCallCount = 0;
        migrateAttachmentsCallCount = 0;
        lastLoadedId = "";
        lastMovedId = "";
        lastMovedStatus = "";
        lastSavedRequest = {};
        lastCreatedRequest = {};
        lastDependencyIssueId = "";
        lastDependsOnId = "";
        lastDependencyType = "";
        lastCommentIssueId = "";
        lastCommentText = "";
        lastAttachmentIssueId = "";
        lastAttachmentId = "";
    }

    function reload() {
        reloadCallCount += 1;
    }

    function poll() {
        pollCallCount += 1;
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

    function addDependency(issueId, dependsOnId, dependencyType) {
        addDependencyCallCount += 1;
        lastDependencyIssueId = issueId;
        lastDependsOnId = dependsOnId;
        lastDependencyType = dependencyType;
    }

    function addComment(issueId, text) {
        addCommentCallCount += 1;
        lastCommentIssueId = issueId;
        lastCommentText = text;
    }

    function addAttachment(issueId) {
        addAttachmentCallCount += 1;
        lastAttachmentIssueId = issueId;
    }

    function openAttachment(issueId, attachmentId) {
        openAttachmentCallCount += 1;
        lastAttachmentIssueId = issueId;
        lastAttachmentId = attachmentId;
    }

    function removeAttachment(issueId, attachmentId) {
        removeAttachmentCallCount += 1;
        lastAttachmentIssueId = issueId;
        lastAttachmentId = attachmentId;
    }

    function migrateAttachments(issueId) {
        migrateAttachmentsCallCount += 1;
        lastAttachmentIssueId = issueId;
    }

    function chooseWorkspace() {}

    function clearError() {
        errorMessage = "";
    }
}
