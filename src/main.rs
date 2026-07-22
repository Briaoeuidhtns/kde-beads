// SPDX-License-Identifier: MIT

mod backend;
mod dialogs;
mod editor_request;
mod operations;

use qtbridge::QApp;

use crate::backend::Backend;

fn main() {
    QApp::new()
        .application_name("kde-beads")
        .register::<Backend>()
        .load_qml(include_bytes!("Main.qml"))
        .run();
}
