// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQuickControlsAddons
import kde_beads

Kirigami.ApplicationWindow {
    id: root
    objectName: "applicationWindow"

    width: 1280
    height: 760
    minimumWidth: 680
    minimumHeight: 520
    visible: true
    title: qsTr("Beads")

    property bool projectPersistenceEnabled: true
    property var knownProjects: []
    property bool projectsInitialized: false
    readonly property bool editorLayerOpen: Boolean(pageStack.layers.currentItem
        && pageStack.layers.currentItem.objectName === "editorPage")

    Settings {
        id: projectSettings
        category: "Projects"
        location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation)
            + "/projects.ini"
        property string knownProjectsJson: ""
        property string activeProject: ""
    }

    Timer {
        objectName: "changePollTimer"
        interval: 2000
        running: true
        repeat: true
        onTriggered: Backend.poll()
    }

    KQuickControlsAddons.Clipboard {
        id: attachmentClipboard
        objectName: "attachmentClipboard"
    }

    function normalizedProjects(projects) {
        const result = [];
        for (const project of projects || []) {
            const path = String(project || "").trim();
            if (path.length > 0 && !result.includes(path))
                result.push(path);
        }
        return result;
    }

    function storedProjects() {
        if (!projectPersistenceEnabled || projectSettings.knownProjectsJson.length === 0)
            return [];
        try {
            const stored = JSON.parse(projectSettings.knownProjectsJson);
            return normalizedProjects(stored && stored.version === 1 ? stored.paths : []);
        } catch (error) {
            return [];
        }
    }

    function persistProjects(activeProject) {
        if (!projectPersistenceEnabled)
            return;
        projectSettings.knownProjectsJson = JSON.stringify({
            "version": 1,
            "paths": knownProjects
        });
        projectSettings.activeProject = String(activeProject || "");
        projectSettings.sync();
    }

    function rememberProject(path) {
        const projects = normalizedProjects(knownProjects.concat([path]));
        if (projects.length !== knownProjects.length)
            knownProjects = projects;
        if (projectsInitialized)
            persistProjects(Backend.workspace);
    }

    function selectProject(path) {
        if (editorLayerOpen || path === Backend.workspace)
            return;
        Backend.switchWorkspace(path);
        if (projectSidebar.modal)
            projectSidebar.close();
    }

    function initializeProjects() {
        const startupProject = String(Backend.workspace);
        const projects = storedProjects();
        const savedProject = String(projectSettings.activeProject || "");
        const preferredProject = !Backend.startupWorkspaceExplicit
                && projects.includes(savedProject)
            ? savedProject
            : startupProject;
        knownProjects = normalizedProjects(projects.concat([preferredProject]));
        projectsInitialized = true;

        persistProjects(preferredProject);
        if (preferredProject !== startupProject) {
            Backend.switchWorkspace(preferredProject);
            if (Backend.workspace === startupProject) {
                persistProjects(startupProject);
                Backend.reload();
            }
        } else {
            Backend.reload();
        }
    }

    function localFileUrl(path) {
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function copyIssueId(issueId) {
        attachmentClipboard.content = String(issueId || "");
    }

    function openEditor(issueId) {
        if (Backend.loading)
            return;
        pageStack.layers.push(editorPageComponent, { "issueId": issueId });
    }

    function openCreate(parentId) {
        if (Backend.loading)
            return;
        pageStack.layers.push(editorPageComponent, {
            "creating": true,
            "parentId": String(parentId || "")
        });
    }

    Component.onCompleted: initializeProjects()

    Connections {
        target: Backend

        function onWorkspaceChanged() {
            root.rememberProject(Backend.workspace);
        }
    }

    Component {
        id: editorPageComponent

        BeadEditorPage {
            backend: Backend
            clipboard: attachmentClipboard
            layerStack: root.pageStack.layers
            onCloseRequested: root.pageStack.layers.pop()
            onCreateChildRequested: parentId => root.openCreate(parentId)
            onOpenIssueRequested: issueId => root.openEditor(issueId)
            onCopyIssueIdRequested: issueId => root.copyIssueId(issueId)
        }
    }

    pageStack.leftSidebar: ProjectDrawer {
        id: projectSidebar
        projects: root.knownProjects
        currentWorkspace: Backend.workspace
        backendLoading: Backend.loading
        editorOpen: root.editorLayerOpen
        windowWidth: root.width
        onProjectSelected: path => root.selectProject(path)
        onAddProjectRequested: Backend.chooseWorkspace()
    }

    pageStack.initialPage: BoardPage {
        issues: Backend.issues || []
        backendLoading: Backend.loading
        backendRefreshing: Backend.refreshing
        backendErrorMessage: Backend.errorMessage
        workspace: Backend.workspace
        onCreateIssueRequested: root.openCreate()
        onOpenIssueRequested: issueId => root.openEditor(issueId)
        onMoveIssueRequested: (issueId, status) => Backend.moveIssue(issueId, status)
        onCopyIssueIdRequested: issueId => root.copyIssueId(issueId)
        onDismissErrorRequested: Backend.clearError()
    }
}
