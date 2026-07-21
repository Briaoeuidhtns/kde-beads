// SPDX-License-Identifier: MIT

use std::process::Command;

use bd_client::{Client, IssueUpdate, NewIssue, Status};
use tempfile::TempDir;

fn workspace() -> TempDir {
    let directory = TempDir::new().expect("create temporary workspace");
    let git = Command::new("git")
        .args(["init", "--quiet"])
        .current_dir(directory.path())
        .output()
        .expect("start git init");
    assert!(
        git.status.success(),
        "git init failed: {}",
        String::from_utf8_lossy(&git.stderr)
    );

    let bd = Command::new("bd")
        .args([
            "init",
            "--quiet",
            "--non-interactive",
            "--skip-hooks",
            "--skip-agents",
            "--prefix",
            "test",
        ])
        .current_dir(directory.path())
        .output()
        .expect("start bd init");
    assert!(
        bd.status.success(),
        "bd init failed: {}",
        String::from_utf8_lossy(&bd.stderr)
    );
    directory
}

fn new_issue(title: &str, status: Status) -> NewIssue {
    NewIssue {
        title: title.to_string(),
        description: "Created by an integration test".to_string(),
        acceptance_criteria: "The client round-trips every field".to_string(),
        design: "Use the real bd CLI".to_string(),
        notes: "Isolated temporary workspace".to_string(),
        status,
        priority: 1,
        issue_type: "feature".to_string(),
        assignee: "test-user".to_string(),
        labels: vec!["kde".to_string(), "rust".to_string()],
    }
}

#[test]
fn creates_lists_and_shows_an_issue() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");

    assert!(client.list().expect("list empty workspace").is_empty());
    let created = client
        .create(&new_issue("Create integration issue", Status::Open))
        .expect("create issue");
    let listed = client.list().expect("list created issue");
    let shown = client.show(&created.id).expect("show created issue");

    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, created.id);
    assert_eq!(shown.title, "Create integration issue");
    assert_eq!(shown.description, "Created by an integration test");
    assert_eq!(shown.labels, ["kde", "rust"]);
}

#[test]
fn creates_an_issue_with_a_non_default_status() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");

    let created = client
        .create(&new_issue("Blocked integration issue", Status::Blocked))
        .expect("create blocked issue");

    assert_eq!(created.status, Status::Blocked);
    assert_eq!(
        client.show(&created.id).expect("show blocked issue").status,
        Status::Blocked
    );
}

#[test]
fn updates_issue_fields_and_status() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let created = client
        .create(&new_issue("Issue before update", Status::Open))
        .expect("create issue");

    let updated = client
        .update(&IssueUpdate {
            id: created.id,
            title: "Issue after update".to_string(),
            description: String::new(),
            acceptance_criteria: "Updated acceptance".to_string(),
            design: "Updated design".to_string(),
            notes: "Updated notes".to_string(),
            status: Status::InProgress,
            priority: 2,
            issue_type: "task".to_string(),
            assignee: String::new(),
            labels: vec!["updated".to_string()],
        })
        .expect("update issue");

    assert_eq!(updated.title, "Issue after update");
    assert_eq!(updated.description, "");
    assert_eq!(updated.status, Status::InProgress);
    assert_eq!(updated.priority, 2);
    assert_eq!(updated.labels, ["updated"]);
}
