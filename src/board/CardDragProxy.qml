// SPDX-License-Identifier: MIT

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: cardDragProxy
    parent: Controls.Overlay.overlay

    property var sourceCard: null
    readonly property string issueId: sourceCard ? sourceCard.issueId : ""
    readonly property string issueStatus: sourceCard ? sourceCard.issueStatus : ""

    width: sourceCard ? sourceCard.width : 0
    height: sourceCard ? sourceCard.height : 0
    visible: Drag.active
    z: 1000

    Drag.active: Boolean(sourceCard && sourceCard.dragActive)
    Drag.source: cardDragProxy
    Drag.keys: ["bead-card"]
    Drag.supportedActions: Qt.MoveAction
    Drag.proposedAction: Qt.MoveAction
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: Kirigami.Units.gridUnit

    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: cardDragProxy.sourceCard
        hideSource: cardDragProxy.Drag.active
        live: true
    }
}
