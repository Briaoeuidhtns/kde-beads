// SPDX-License-Identifier: MIT

mod backend;
mod dialogs;
mod editor_request;
mod operations;
mod workspace_cache;

use qtbridge::{QApp, include_bytes_qml};

use crate::backend::Backend;

fn main() {
    include_bytes_qml!("Main.qml", "qml");
    include_bytes_qml!("BeadEditorPage.qml", "qml");
    include_bytes_qml!("BoardPage.qml", "qml");
    include_bytes_qml!("ProjectDrawer.qml", "qml");
    include_bytes_qml!("components/IssueCopyButton.qml", "qml");
    include_bytes_qml!("board/CardDragProxy.qml", "qml");
    include_bytes_qml!("board/KanbanColumn.qml", "qml");
    include_bytes_qml!("board/CollapsibleStatusSection.qml", "qml");
    include_bytes_qml!("board/OpenColumn.qml", "qml");

    QApp::new()
        .application_name("knecklace")
        .register::<Backend>()
        .load_qml_from_file("qrc:/qml/Main.qml")
        .run();
}
