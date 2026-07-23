// SPDX-License-Identifier: MIT

pragma Singleton

import QtQml

QtObject {
    property var issues: []
    property var detail: ({})
    property string workspace: "/tmp/knecklace-tests"
    property bool startupWorkspaceExplicit: false
    property string errorMessage: ""
    property bool loading: false
    property bool refreshing: false

    property int reloadCallCount: 0
    property int pollCallCount: 0
    property int loadIssueCallCount: 0
    property int moveIssueCallCount: 0
    property int saveIssueCallCount: 0
    property int createIssueCallCount: 0
    property int addDependencyCallCount: 0
    property int addCommentCallCount: 0
    property int addAttachmentCallCount: 0
    property int addAttachmentsCallCount: 0
    property int openAttachmentCallCount: 0
    property int previewAttachmentCallCount: 0
    property int removeAttachmentCallCount: 0
    property int migrateAttachmentsCallCount: 0
    property int chooseWorkspaceCallCount: 0
    property int switchWorkspaceCallCount: 0
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
    property var lastAttachmentUrls: []
    property string lastSwitchedWorkspace: ""

    signal issueSaved(string savedId)
    signal attachmentReady(string issueId, string path)
    signal attachmentPreviewReady(string issueId, string attachmentId, string path)

    function reset() {
        issues = [];
        detail = {};
        workspace = "/tmp/knecklace-tests";
        startupWorkspaceExplicit = false;
        errorMessage = "";
        loading = false;
        refreshing = false;
        reloadCallCount = 0;
        pollCallCount = 0;
        loadIssueCallCount = 0;
        moveIssueCallCount = 0;
        saveIssueCallCount = 0;
        createIssueCallCount = 0;
        addDependencyCallCount = 0;
        addCommentCallCount = 0;
        addAttachmentCallCount = 0;
        addAttachmentsCallCount = 0;
        openAttachmentCallCount = 0;
        previewAttachmentCallCount = 0;
        removeAttachmentCallCount = 0;
        migrateAttachmentsCallCount = 0;
        chooseWorkspaceCallCount = 0;
        switchWorkspaceCallCount = 0;
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
        lastAttachmentUrls = [];
        lastSwitchedWorkspace = "";
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

    function addAttachments(issueId, urls) {
        addAttachmentsCallCount += 1;
        lastAttachmentIssueId = issueId;
        lastAttachmentUrls = urls;
    }

    function openAttachment(issueId, attachmentId) {
        openAttachmentCallCount += 1;
        lastAttachmentIssueId = issueId;
        lastAttachmentId = attachmentId;
    }

    function previewAttachment(issueId, attachmentId) {
        previewAttachmentCallCount += 1;
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

    function chooseWorkspace() {
        chooseWorkspaceCallCount += 1;
    }

    function switchWorkspace(path) {
        switchWorkspaceCallCount += 1;
        lastSwitchedWorkspace = path;
        workspace = path;
        reload();
    }

    function clearError() {
        errorMessage = "";
    }
}
