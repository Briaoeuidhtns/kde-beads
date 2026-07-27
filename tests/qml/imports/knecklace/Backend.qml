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
    property int addTodoCallCount: 0
    property int deleteIssueCallCount: 0
    property int addDependencyCallCount: 0
    property int removeDependencyCallCount: 0
    property int createGateCallCount: 0
    property int resolveGateCallCount: 0
    property int removeGateCallCount: 0
    property int addCommentCallCount: 0
    property int addAttachmentCallCount: 0
    property int addAttachmentsCallCount: 0
    property int openAttachmentCallCount: 0
    property int previewAttachmentCallCount: 0
    property int removeAttachmentCallCount: 0
    property int migrateAttachmentsCallCount: 0
    property int chooseWorkspaceCallCount: 0
    property int switchWorkspaceCallCount: 0
    property int createAttachmentDraftCallCount: 0
    property int addDraftAttachmentCallCount: 0
    property int addDraftAttachmentsCallCount: 0
    property int removeDraftAttachmentCallCount: 0
    property int discardAttachmentDraftCallCount: 0
    property int retryDraftAttachmentsCallCount: 0
    property string lastLoadedId: ""
    property string lastMovedId: ""
    property string lastMovedStatus: ""
    property var lastSavedRequest: ({})
    property var lastCreatedRequest: ({})
    property string lastTodoTitle: ""
    property string lastDeletedId: ""
    property string lastDependencyIssueId: ""
    property string lastDependsOnId: ""
    property string lastDependencyType: ""
    property string lastDependencyDetailId: ""
    property string lastGateIssueId: ""
    property string lastGateId: ""
    property string lastGateType: ""
    property string lastGateReason: ""
    property string lastGateTimeout: ""
    property string lastCommentIssueId: ""
    property string lastCommentText: ""
    property string lastAttachmentIssueId: ""
    property string lastAttachmentId: ""
    property var lastAttachmentUrls: []
    property string lastSwitchedWorkspace: ""
    property string lastDraftId: ""
    property string lastDraftAttachmentId: ""
    property var lastDraftAttachmentUrls: []
    property string lastCreatedDraftId: ""
    property int nextMutationGeneration: 0
    property var pendingOriginalStatuses: ({})

    signal issueDeleted(string deletedId)
    signal issueProjectionChanged(string workspace, string issueId, string status, bool pending)
    signal issueSaveStarted(string workspace, string issueId, string generation)
    signal issueSaveFinished(string workspace, string issueId, string generation, bool succeeded)
    signal attachmentDraftReady(string editorToken, string draftId)
    signal draftAttachmentsChanged(string draftId, string attachments)
    signal issueCreated(string workspace, string draftId, string issueId, bool attachmentsComplete)
    signal workspaceChosen(string path)
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
        addTodoCallCount = 0;
        deleteIssueCallCount = 0;
        addDependencyCallCount = 0;
        removeDependencyCallCount = 0;
        createGateCallCount = 0;
        resolveGateCallCount = 0;
        removeGateCallCount = 0;
        addCommentCallCount = 0;
        addAttachmentCallCount = 0;
        addAttachmentsCallCount = 0;
        openAttachmentCallCount = 0;
        previewAttachmentCallCount = 0;
        removeAttachmentCallCount = 0;
        migrateAttachmentsCallCount = 0;
        chooseWorkspaceCallCount = 0;
        switchWorkspaceCallCount = 0;
        createAttachmentDraftCallCount = 0;
        addDraftAttachmentCallCount = 0;
        addDraftAttachmentsCallCount = 0;
        removeDraftAttachmentCallCount = 0;
        discardAttachmentDraftCallCount = 0;
        retryDraftAttachmentsCallCount = 0;
        lastLoadedId = "";
        lastMovedId = "";
        lastMovedStatus = "";
        lastSavedRequest = {};
        lastCreatedRequest = {};
        lastTodoTitle = "";
        lastDeletedId = "";
        lastDependencyIssueId = "";
        lastDependsOnId = "";
        lastDependencyType = "";
        lastDependencyDetailId = "";
        lastGateIssueId = "";
        lastGateId = "";
        lastGateType = "";
        lastGateReason = "";
        lastGateTimeout = "";
        lastCommentIssueId = "";
        lastCommentText = "";
        lastAttachmentIssueId = "";
        lastAttachmentId = "";
        lastAttachmentUrls = [];
        lastSwitchedWorkspace = "";
        lastDraftId = "";
        lastDraftAttachmentId = "";
        lastDraftAttachmentUrls = [];
        lastCreatedDraftId = "";
        nextMutationGeneration = 0;
        pendingOriginalStatuses = {};
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

    function createAttachmentDraft(editorToken) {
        createAttachmentDraftCallCount += 1;
        lastDraftId = `test-draft-${createAttachmentDraftCallCount}`;
        attachmentDraftReady(editorToken, lastDraftId);
    }

    function addDraftAttachment(draftId) {
        addDraftAttachmentCallCount += 1;
        lastDraftId = draftId;
    }

    function addDraftAttachments(draftId, urls) {
        addDraftAttachmentsCallCount += 1;
        lastDraftId = draftId;
        lastDraftAttachmentUrls = urls;
    }

    function removeDraftAttachment(draftId, attachmentId) {
        removeDraftAttachmentCallCount += 1;
        lastDraftId = draftId;
        lastDraftAttachmentId = attachmentId;
    }

    function discardAttachmentDraft(draftId) {
        discardAttachmentDraftCallCount += 1;
        lastDraftId = draftId;
    }

    function retryDraftAttachments(issueId, draftId) {
        retryDraftAttachmentsCallCount += 1;
        lastAttachmentIssueId = issueId;
        lastDraftId = draftId;
    }

    function setDraftAttachments(draftId, attachments) {
        draftAttachmentsChanged(draftId, JSON.stringify(attachments));
    }

    function moveIssue(issueId, status) {
        moveIssueCallCount += 1;
        lastMovedId = issueId;
        lastMovedStatus = status;
        const originals = Object.assign({}, pendingOriginalStatuses);
        const current = issues.find(issue => issue.id === issueId);
        if (current && !Object.prototype.hasOwnProperty.call(originals, issueId))
            originals[issueId] = current.status;
        pendingOriginalStatuses = originals;
        issues = issues.map(issue => issue.id === issueId
            ? Object.assign({}, issue, {
                "status": status,
                "_pending": true,
                "_pending_move": true
            })
            : issue);
        issueProjectionChanged(workspace, issueId, status, true);
    }

    function saveIssue(request) {
        saveIssueCallCount += 1;
        lastSavedRequest = request;
        nextMutationGeneration += 1;
        const generation = String(nextMutationGeneration);
        issues = issues.map(issue => issue.id === request.id
            ? Object.assign({}, issue, {
                "title": request.title,
                "status": request.status,
                "priority": Number(request.priority),
                "issue_type": request.issueType,
                "assignee": request.assignee,
                "labels": request.labels
                    ? request.labels.split(",").map(label => label.trim()).filter(Boolean)
                    : [],
                "_pending": true,
                "_pending_save": true
            })
            : issue);
        issueProjectionChanged(workspace, request.id, request.status, true);
        issueSaveStarted(workspace, request.id, generation);
    }

    function finishMove(issueId, succeeded) {
        const original = pendingOriginalStatuses[issueId];
        let status = "";
        issues = issues.map(issue => {
            if (issue.id !== issueId)
                return issue;
            status = succeeded ? issue.status : original;
            const updated = Object.assign({}, issue, { "status": status });
            delete updated._pending;
            delete updated._pending_move;
            return updated;
        });
        const originals = Object.assign({}, pendingOriginalStatuses);
        delete originals[issueId];
        pendingOriginalStatuses = originals;
        issueProjectionChanged(workspace, issueId, status, false);
    }

    function finishSave(issueId, generation, succeeded) {
        let status = "";
        issues = issues.map(issue => {
            if (issue.id !== issueId)
                return issue;
            status = issue.status;
            const updated = Object.assign({}, issue);
            delete updated._pending;
            delete updated._pending_save;
            return updated;
        });
        issueProjectionChanged(workspace, issueId, status, false);
        issueSaveFinished(workspace, issueId, String(generation), succeeded);
    }

    function createIssue(request, draftId) {
        createIssueCallCount += 1;
        lastCreatedRequest = request;
        lastCreatedDraftId = draftId;
    }

    function addTodo(title) {
        addTodoCallCount += 1;
        lastTodoTitle = title;
    }

    function deleteIssue(issueId) {
        deleteIssueCallCount += 1;
        lastDeletedId = issueId;
    }

    function addDependency(issueId, dependsOnId, dependencyType, detailIssueId) {
        addDependencyCallCount += 1;
        lastDependencyIssueId = issueId;
        lastDependsOnId = dependsOnId;
        lastDependencyType = dependencyType;
        lastDependencyDetailId = detailIssueId;
    }

    function removeDependency(issueId, dependsOnId, detailIssueId) {
        removeDependencyCallCount += 1;
        lastDependencyIssueId = issueId;
        lastDependsOnId = dependsOnId;
        lastDependencyDetailId = detailIssueId;
    }

    function createGate(issueId, gateType, reason, timeout) {
        createGateCallCount += 1;
        lastGateIssueId = issueId;
        lastGateType = gateType;
        lastGateReason = reason;
        lastGateTimeout = timeout;
    }

    function resolveGate(issueId, gateId) {
        resolveGateCallCount += 1;
        lastGateIssueId = issueId;
        lastGateId = gateId;
    }

    function removeGate(issueId, gateId) {
        removeGateCallCount += 1;
        lastGateIssueId = issueId;
        lastGateId = gateId;
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
