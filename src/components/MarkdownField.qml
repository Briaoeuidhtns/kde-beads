// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

FocusScope {
    id: field

    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property bool editing: false
    property bool focusRequested: false

    signal keyPressed(var event)

    function beginEditing() {
        if (!enabled || editing)
            return;
        focusRequested = true;
        editing = true;
        Qt.callLater(() => {
            input.forceActiveFocus();
            focusRequested = false;
        });
    }

    function showPreview() {
        editing = false;
    }

    function moveFocus(forward) {
        const next = nextItemInFocusChain(forward);
        showPreview();
        if (next && next !== field) {
            next.forceActiveFocus(forward
                ? Qt.TabFocusReason
                : Qt.BacktabFocusReason);
        }
    }

    implicitWidth: Math.max(preview.implicitWidth, input.implicitWidth)
    implicitHeight: Math.max(
        preview.contentHeight + preview.topPadding + preview.bottomPadding,
        input.contentHeight + input.topPadding + input.bottomPadding,
        preview.implicitHeight,
        input.implicitHeight
    )
    activeFocusOnTab: true
    Accessible.name: input.placeholderText
    Keys.onReturnPressed: event => {
        beginEditing();
        event.accepted = true;
    }
    Keys.onSpacePressed: event => {
        beginEditing();
        event.accepted = true;
    }
    onActiveFocusChanged: {
        if (activeFocus && !editing)
            beginEditing();
        else if (!activeFocus && editing && !focusRequested)
            showPreview();
    }

    Controls.TextArea {
        id: preview
        objectName: `${field.objectName}-preview`
        anchors.fill: parent
        text: input.text
        textFormat: TextEdit.MarkdownText
        readOnly: true
        activeFocusOnTab: false
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        color: Kirigami.Theme.textColor
        visible: !field.editing
        placeholderText: input.placeholderText

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: field.beginEditing()
        }
    }

    Controls.TextArea {
        id: input
        objectName: `${field.objectName}-editor`
        anchors.fill: parent
        textFormat: TextEdit.PlainText
        activeFocusOnTab: false
        wrapMode: TextEdit.Wrap
        visible: field.editing
        Keys.priority: Keys.BeforeItem
        Keys.onTabPressed: event => {
            field.moveFocus(true);
            event.accepted = true;
        }
        Keys.onBacktabPressed: event => {
            field.moveFocus(false);
            event.accepted = true;
        }
        Keys.onPressed: event => field.keyPressed(event)
        onActiveFocusChanged: {
            if (!activeFocus && field.editing && !field.focusRequested)
                field.showPreview();
        }
    }
}
