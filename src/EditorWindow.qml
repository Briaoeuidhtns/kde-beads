// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: editorWindow
    objectName: "editorWindow"

    required property var backend
    required property var clipboard
    required property var activeEditor
    property alias issueId: editor.issueId
    property alias creating: editor.creating
    property alias parentId: editor.parentId
    property bool initialized: false

    signal editorOpened(var editor)
    signal editorClosed(var editor)
    signal editorActivated(var editor)
    signal createChildRequested(string parentId)
    signal openIssueRequested(string issueId)
    signal copyIssueIdRequested(string issueId)

    function attractAttention() {
        attentionAnimation.restart();
    }

    width: Kirigami.Units.gridUnit * 50
    height: Kirigami.Units.gridUnit * 36
    minimumWidth: Kirigami.Units.gridUnit * 32
    minimumHeight: Kirigami.Units.gridUnit * 24
    modality: Qt.NonModal
    title: editor.title

    Component.onCompleted: {
        initialized = true;
        editorOpened(editor);
        show();
        requestActivate();
    }
    Component.onDestruction: editorClosed(editor)
    onActiveChanged: {
        if (initialized && active)
            editorActivated(editor);
    }
    onVisibleChanged: {
        if (initialized && !visible)
            destroy();
    }

    pageStack.initialPage: BeadEditorPage {
        id: editor
        backend: editorWindow.backend
        clipboard: editorWindow.clipboard
        selected: editorWindow.activeEditor === editor
        onCloseRequested: editorWindow.close()
        onCreateChildRequested: parentId => editorWindow.createChildRequested(parentId)
        onOpenIssueRequested: issueId => editorWindow.openIssueRequested(issueId)
        onCopyIssueIdRequested: issueId => editorWindow.copyIssueIdRequested(issueId)
    }

    Item {
        id: attentionOverlay
        objectName: "attentionOverlay"
        anchors.fill: parent
        z: 1000
        opacity: 0
        visible: opacity > 0

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.highlightColor
            opacity: 0.12
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Kirigami.Theme.highlightColor
            border.width: Kirigami.Units.smallSpacing
        }
    }

    SequentialAnimation {
        id: attentionAnimation
        objectName: "attentionAnimation"
        loops: 1

        NumberAnimation {
            target: attentionOverlay
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: Kirigami.Units.shortDuration / 2 }
        NumberAnimation {
            target: attentionOverlay
            property: "opacity"
            from: 1
            to: 0
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InCubic
        }
    }
}
