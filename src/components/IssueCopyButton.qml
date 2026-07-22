// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls

Controls.ToolButton {
    id: copyButton

    required property string issueId
    property bool copied: false
    property bool minimumFeedbackElapsed: false

    signal copyRequested(string issueId)

    text: qsTr("Copy %1").arg(issueId)
    icon.name: copied ? "dialog-ok" : "edit-copy"
    display: Controls.AbstractButton.IconOnly
    Controls.ToolTip.text: copied ? qsTr("Copied") : qsTr("Copy issue ID")
    Controls.ToolTip.visible: hovered

    function finishFeedbackIfReady() {
        if (minimumFeedbackElapsed && !hovered)
            copied = false;
    }

    onClicked: {
        copyRequested(issueId);
        copied = true;
        minimumFeedbackElapsed = false;
        feedbackTimer.restart();
    }
    onHoveredChanged: finishFeedbackIfReady()

    Timer {
        id: feedbackTimer
        interval: 1000
        onTriggered: {
            copyButton.minimumFeedbackElapsed = true;
            copyButton.finishFeedbackIfReady();
        }
    }
}
