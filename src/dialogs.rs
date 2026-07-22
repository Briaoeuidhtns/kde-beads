// SPDX-License-Identifier: MIT

use std::process::Command;

pub(crate) fn choose_workspace_with_kdialog(current_workspace: &str) -> (String, String) {
    let output = match Command::new("kdialog")
        .args([
            "--title",
            "Open a Beads workspace",
            "--getexistingdirectory",
            current_workspace,
        ])
        .output()
    {
        Ok(output) => output,
        Err(error) => {
            return (
                String::new(),
                format!("Could not open the KDE folder picker: {error}"),
            );
        }
    };

    if output.status.success() {
        return (
            String::from_utf8_lossy(&output.stdout).trim().to_string(),
            String::new(),
        );
    }
    if output.status.code() == Some(1) {
        return (String::new(), String::new());
    }

    let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if error.is_empty() {
        (
            String::new(),
            format!("The KDE folder picker failed with {}", output.status),
        )
    } else {
        (
            String::new(),
            format!("The KDE folder picker failed: {error}"),
        )
    }
}

pub(crate) fn choose_attachment_with_kdialog(workspace: &str) -> (String, String) {
    let output = match Command::new("kdialog")
        .args(["--title", "Attach a file", "--getopenfilename", workspace])
        .output()
    {
        Ok(output) => output,
        Err(error) => {
            return (
                String::new(),
                format!("Could not open the KDE file picker: {error}"),
            );
        }
    };

    if output.status.success() {
        return (
            String::from_utf8_lossy(&output.stdout).trim().to_string(),
            String::new(),
        );
    }
    if output.status.code() == Some(1) {
        return (String::new(), String::new());
    }

    let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if error.is_empty() {
        (
            String::new(),
            format!("The KDE file picker failed with {}", output.status),
        )
    } else {
        (
            String::new(),
            format!("The KDE file picker failed: {error}"),
        )
    }
}
