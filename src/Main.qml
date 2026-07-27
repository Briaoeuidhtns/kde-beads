// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQuickControlsAddons
import knecklace

Kirigami.ApplicationWindow {
    id: root
    objectName: "applicationWindow"

    width: 1280
    height: 760
    minimumWidth: 680
    minimumHeight: 520
    visible: true
    title: qsTr("Knecklace")

    property bool projectPersistenceEnabled: true
    property var knownProjects: []
    property bool projectsInitialized: false
    property bool sidebarCollapsedPreference: false
    property var editorPages: []
    property string pendingProjectPath: ""
    property int nextEditorToken: 0
    readonly property bool editorLayerOpen: editorPages.length > 0
    readonly property var activeEditorPage: editorLayerOpen
        ? editorPages[editorPages.length - 1]
        : null

    Settings {
        id: projectSettings
        category: "Projects"
        location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation)
            + "/projects.ini"
        property string knownProjectsJson: ""
        property string activeProject: ""
        property bool sidebarCollapsed: false
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

    function rememberSidebarCollapsed(collapsed) {
        sidebarCollapsedPreference = collapsed;
        if (!projectPersistenceEnabled)
            return;
        projectSettings.sidebarCollapsed = collapsed;
        projectSettings.sync();
    }

    function rememberProject(path) {
        const projects = normalizedProjects(knownProjects.concat([path]));
        if (projects.length !== knownProjects.length)
            knownProjects = projects;
        if (projectsInitialized)
            persistProjects(Backend.workspace);
    }

    function removeProject(path) {
        const project = String(path || "").trim();
        if (project.length === 0 || project === Backend.workspace)
            return false;
        const projects = knownProjects.filter(candidate => candidate !== project);
        if (projects.length === knownProjects.length)
            return false;
        knownProjects = projects;
        persistProjects(Backend.workspace);
        return true;
    }

    function switchProject(path) {
        if (path === Backend.workspace)
            return;
        Backend.switchWorkspace(path);
        if (projectSidebar.modal)
            projectSidebar.close();
    }

    function selectProject(path) {
        if (path === Backend.workspace)
            return;
        if (editorLayerOpen) {
            pendingProjectPath = path;
            projectSwitchDialog.open();
            return;
        }
        switchProject(path);
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

    function registerEditor(editor) {
        editorPages = editorPages.concat([editor]);
    }

    function unregisterEditor(editor) {
        editorPages = editorPages.filter(candidate => candidate !== editor);
    }

    function activateEditor(editor) {
        if (!editorPages.includes(editor))
            return;
        editorPages = editorPages
            .filter(candidate => candidate !== editor)
            .concat([editor]);
    }

    function editorForIssue(issueId) {
        const id = String(issueId || "");
        for (const editor of editorPages) {
            if (!editor.creating
                    && editor.workspace === Backend.workspace
                    && String(editor.issueId) === id) {
                return editor;
            }
        }
        return null;
    }

    function raiseEditor(editor) {
        activateEditor(editor);
        const window = editor.Window.window;
        if (!window)
            return;
        if (window.visibility === Window.Minimized)
            window.showNormal();
        else
            window.show();
        window.raise();
        window.requestActivate();
        window.attractAttention();
    }

    function closeEditorWindows() {
        const editors = editorPages.slice();
        for (const editor of editors) {
            const window = editor.Window.window;
            if (window)
                window.discardAndClose();
        }
    }

    function confirmProjectSwitch() {
        const path = pendingProjectPath;
        pendingProjectPath = "";
        closeEditorWindows();
        switchProject(path);
    }

    function openEditor(issueId) {
        const existingEditor = editorForIssue(issueId);
        if (existingEditor) {
            raiseEditor(existingEditor);
            return;
        }
        if (Backend.loading)
            return;
        nextEditorToken += 1;
        editorWindowComponent.createObject(root, {
            "issueId": issueId,
            "workspace": Backend.workspace,
            "editorToken": `editor-${nextEditorToken}`
        });
    }

    function openCreate(parentId) {
        if (Backend.loading)
            return;
        nextEditorToken += 1;
        editorWindowComponent.createObject(root, {
            "creating": true,
            "parentId": String(parentId || ""),
            "workspace": Backend.workspace,
            "editorToken": `editor-${nextEditorToken}`
        });
    }

    Component.onCompleted: {
        if (projectPersistenceEnabled)
            sidebarCollapsedPreference = projectSettings.sidebarCollapsed;
        initializeProjects();
    }

    Connections {
        target: Backend

        function onWorkspaceChanged() {
            root.rememberProject(Backend.workspace);
        }

        function onWorkspaceChosen(path) {
            root.rememberProject(path);
            root.selectProject(path);
        }
    }

    Controls.ApplicationWindow {
        id: projectSwitchDialog
        objectName: "projectSwitchDialog"
        readonly property real dialogWidth: Kirigami.Units.gridUnit * 30
        readonly property real dialogHeight: Kirigami.Units.gridUnit * 9

        width: dialogWidth
        height: dialogHeight
        minimumWidth: dialogWidth
        maximumWidth: dialogWidth
        minimumHeight: dialogHeight
        maximumHeight: dialogHeight
        visible: false
        modality: Qt.ApplicationModal
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        transientParent: root
        title: qsTr("Close bead windows?")
        color: Kirigami.Theme.backgroundColor

        function open() {
            show();
            raise();
            requestActivate();
            closeAndSwitchButton.forceActiveFocus();
        }

        function accept() {
            root.confirmProjectSwitch();
            close();
        }

        function reject() {
            close();
        }

        onClosing: root.pendingProjectPath = ""

        Shortcut {
            sequence: "Escape"
            onActivated: projectSwitchDialog.reject()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 2

            Controls.Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: qsTr(
                    "Knecklace must close %n open bead window(s) before switching to %1. Any unsaved changes will be lost.",
                    "",
                    root.editorPages.length
                ).arg(root.pendingProjectPath)
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }

            Controls.DialogButtonBox {
                Layout.fillWidth: true

                Controls.Button {
                    text: qsTr("Cancel")
                    Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
                }

                Controls.Button {
                    id: closeAndSwitchButton
                    text: qsTr("Close Windows and Switch")
                    icon.name: "window-close"
                    highlighted: true
                    Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.AcceptRole
                }

                onAccepted: projectSwitchDialog.accept()
                onRejected: projectSwitchDialog.reject()
            }
        }
    }

    Component {
        id: editorWindowComponent

        EditorWindow {
            backend: Backend
            clipboard: attachmentClipboard
            activeEditor: root.activeEditorPage
            onEditorOpened: editor => root.registerEditor(editor)
            onEditorClosed: editor => root.unregisterEditor(editor)
            onEditorActivated: editor => root.activateEditor(editor)
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
        windowWidth: root.width
        preferredCollapsed: root.sidebarCollapsedPreference
        onProjectSelected: path => root.selectProject(path)
        onRemoveProjectRequested: path => root.removeProject(path)
        onAddProjectRequested: Backend.chooseWorkspace()
        onCollapsedPreferenceChanged: collapsed => root.rememberSidebarCollapsed(collapsed)
    }

    pageStack.initialPage: WorkspacePage {
        issues: Backend.issues || []
        backendLoading: Backend.loading
        backendRefreshing: Backend.refreshing
        backendErrorMessage: Backend.errorMessage
        workspace: Backend.workspace
        onAddTodoRequested: title => Backend.addTodo(title)
        onCreateIssueRequested: root.openCreate()
        onOpenIssueRequested: issueId => root.openEditor(issueId)
        onMoveIssueRequested: (issueId, status) => Backend.moveIssue(issueId, status)
        onCopyIssueIdRequested: issueId => root.copyIssueId(issueId)
        onDismissErrorRequested: Backend.clearError()
    }
}
