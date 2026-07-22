// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.GlobalDrawer {
    id: projectSidebar
    objectName: "projectSidebar"

    required property var projects
    required property string currentWorkspace
    required property bool backendLoading
    required property bool editorOpen
    required property real windowWidth

    signal projectSelected(string path)
    signal addProjectRequested()

    title: qsTr("Projects")
    titleIcon: "folder"
    modal: windowWidth < Kirigami.Units.gridUnit * 48
    preferredSize: Kirigami.Units.gridUnit * 15
    minimumSize: Kirigami.Units.gridUnit * 12
    maximumSize: Kirigami.Units.gridUnit * 22
    handleClosedToolTip: qsTr("Show projects")
    handleOpenToolTip: qsTr("Hide projects")
    isMenu: false
    collapsible: !modal
    showContentWhenCollapsed: true

    function projectName(path) {
        const parts = String(path || "").split("/").filter(part => part.length > 0);
        return parts.length > 0 ? parts[parts.length - 1] : String(path || "");
    }

    Component.onCompleted: {
        collapsible = !modal;
        drawerOpen = !modal;
    }
    onModalChanged: Qt.callLater(() => {
        collapsed = false;
        collapsible = !modal;
        drawerOpen = !modal;
    })

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        Repeater {
            id: projectList
            objectName: "projectList"
            model: projectSidebar.projects

            delegate: Controls.ItemDelegate {
                required property string modelData
                required property int index
                objectName: `projectItem-${index}`
                Layout.fillWidth: true
                text: projectSidebar.projectName(modelData)
                icon.name: modelData === projectSidebar.currentWorkspace ? "folder-open" : "folder"
                display: projectSidebar.collapsed
                    ? Controls.AbstractButton.IconOnly
                    : Controls.AbstractButton.TextBesideIcon
                highlighted: modelData === projectSidebar.currentWorkspace
                enabled: !projectSidebar.backendLoading && !projectSidebar.editorOpen
                Accessible.description: modelData
                Controls.ToolTip.text: modelData
                Controls.ToolTip.visible: hovered
                onClicked: projectSidebar.projectSelected(modelData)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    footer: Controls.ToolBar {
        contentItem: Controls.ToolButton {
            id: addProjectButton
            objectName: "addProjectButton"
            text: qsTr("Add Project")
            icon.name: "folder-new"
            display: projectSidebar.collapsed
                ? Controls.AbstractButton.IconOnly
                : Controls.AbstractButton.TextBesideIcon
            enabled: !projectSidebar.backendLoading && !projectSidebar.editorOpen
            onClicked: projectSidebar.addProjectRequested()
        }
    }
}
