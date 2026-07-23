// SPDX-License-Identifier: MIT

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::Command;

use bd_client::{Client, Error, IssueUpdate, NewIssue, Status};
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
        parent: None,
    }
}

fn attachment_wrapper(workspace: &TempDir) -> PathBuf {
    let path = workspace.path().join("fake-bd");
    fs::write(
        &path,
        r#"#!/bin/sh
readonly_flag=
if [ "$1" = "--readonly" ]; then
    readonly_flag=--readonly
    shift
fi
if [ "$1" = "attachment" ]; then
    if [ "$2" = "--help" ]; then
        if [ -f .fake-native-enabled ]; then
            exit 0
        fi
        echo 'Error: unknown command "attachment" for "bd"' >&2
        exit 1
    fi
    if [ "$2" = "list" ]; then
        if [ ! -s .fake-native-hash ]; then
            printf '[]\n'
            exit 0
        fi
        hash=$(cat .fake-native-hash)
        missing=false
        if [ ! -f ".fake-native-$hash" ]; then
            missing=true
        fi
        printf '[{"id":"native-1","issue_id":"%s","hash_algorithm":"sha256","content_hash":"%s","original_filename":"migration.txt","mime_type":"text/plain","byte_size":17,"storage_relpath":"attachments/%s/%s","missing":%s}]\n' "$3" "$hash" "$3" "$hash" "$missing"
        exit 0
    fi
    if [ "$2" = "add" ]; then
        hash=$(sha256sum "$4" | cut -d ' ' -f 1)
        cp "$4" ".fake-native-$hash"
        if [ -s .fake-native-hash ]; then
            echo 'duplicate attachment metadata' >&2
            exit 1
        fi
        printf '%s' "$hash" > .fake-native-hash
        printf '{}\n'
        exit 0
    fi
    if [ "$2" = "copy" ]; then
        hash=$(cat .fake-native-hash)
        cp ".fake-native-$hash" "$5"
        printf '{"status":"copied"}\n'
        exit 0
    fi
fi
exec bd $readonly_flag "$@"
"#,
    )
    .expect("write fake bd wrapper");
    let mut permissions = fs::metadata(&path).expect("stat wrapper").permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&path, permissions).expect("make wrapper executable");
    path
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
fn deletes_an_issue_and_its_polyfill_attachments() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let deleted = client
        .create(&new_issue("Delete this issue", Status::Open))
        .expect("create deleted issue");
    let survivor = client
        .create(&new_issue("Keep this issue", Status::Open))
        .expect("create surviving issue");
    let source = workspace.path().join("delete-me.txt");
    fs::write(&source, b"attachment to delete").expect("write attachment source");
    let attached = client
        .add_attachment(&deleted.id, &source)
        .expect("add polyfill attachment");
    let attachment_dir = workspace
        .path()
        .join(format!(".beads/knecklace/attachments/{}", deleted.id));
    assert_eq!(attached.polyfill_attachment_count, 1);
    assert!(attachment_dir.exists());

    let outcome = client.delete(&deleted.id).expect("delete issue");

    assert!(outcome.cleanup_warning.is_none());
    assert!(!attachment_dir.exists());
    assert!(matches!(
        client.show(&deleted.id),
        Err(Error::Command { .. })
    ));
    let listed = client.list().expect("list after deletion");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, survivor.id);
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
            parent: None,
        })
        .expect("update issue");

    assert_eq!(updated.title, "Issue after update");
    assert_eq!(updated.description, "");
    assert_eq!(updated.status, Status::InProgress);
    assert_eq!(updated.priority, 2);
    assert_eq!(updated.labels, ["updated"]);
}

#[test]
fn lists_dependency_blocking_separately_from_stored_status() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let blocker = client
        .create(&new_issue("Blocking issue", Status::Open))
        .expect("create blocker");
    let dependent = client
        .create(&new_issue("Dependent issue", Status::Open))
        .expect("create dependent");
    client
        .add_dependency(&dependent.id, &blocker.id, "blocks")
        .expect("add blocking dependency");

    let listed = client.list().expect("list blocked dependent");
    let listed_dependent = listed
        .iter()
        .find(|issue| issue.id == dependent.id)
        .expect("find dependent");
    assert_eq!(listed_dependent.status, Status::Open);
    assert!(listed_dependent.is_blocked);

    client
        .set_status(&blocker.id, Status::Closed)
        .expect("close blocker");
    let listed = client.list().expect("list unblocked dependent");
    let listed_dependent = listed
        .iter()
        .find(|issue| issue.id == dependent.id)
        .expect("find dependent");
    assert_eq!(listed_dependent.status, Status::Open);
    assert!(!listed_dependent.is_blocked);
}

#[test]
fn force_delete_preserves_dependents_and_removes_relationships() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let blocker = client
        .create(&new_issue("Delete blocker", Status::Open))
        .expect("create blocker");
    let dependent = client
        .create(&new_issue("Keep dependent", Status::Open))
        .expect("create dependent");
    client
        .add_dependency(&dependent.id, &blocker.id, "blocks")
        .expect("add blocking dependency");

    client.delete(&blocker.id).expect("force delete blocker");

    assert_eq!(
        client.show(&dependent.id).expect("show dependent").id,
        dependent.id
    );
    assert!(
        client
            .dependencies(&dependent.id)
            .expect("list dependencies")
            .iter()
            .all(|issue| issue.id != blocker.id)
    );
}

#[test]
fn adds_opens_and_removes_an_attachment() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let issue = client
        .create(&new_issue("Issue with attachment", Status::Open))
        .expect("create issue");
    let source = workspace.path().join("screenshot.png");
    fs::write(&source, b"not really a png").expect("write attachment source");

    let attached = client
        .add_attachment(&issue.id, &source)
        .expect("add attachment");
    assert_eq!(attached.attachments.len(), 1);
    assert_eq!(attached.attachments[0].original_filename, "screenshot.png");

    let materialized = client
        .materialize_attachment(&issue.id, &attached.attachments[0].id)
        .expect("materialize attachment");
    assert!(!materialized.temporary);
    assert_eq!(
        fs::read(materialized.path).expect("read attachment"),
        b"not really a png"
    );

    let removed = client
        .remove_attachment(&issue.id, &attached.attachments[0].id)
        .expect("remove attachment");
    assert!(removed.attachments.is_empty());
}

#[test]
fn migrates_polyfill_after_repairing_missing_native_bytes() {
    let workspace = workspace();
    let wrapper = attachment_wrapper(&workspace);
    let client = Client::with_binary(workspace.path(), &wrapper).expect("create wrapped client");
    let issue = client
        .create(&new_issue("Attachment migration", Status::Open))
        .expect("create issue");
    let source = workspace.path().join("migration.txt");
    fs::write(&source, b"migration payload").expect("write migration source");

    let polyfill = client
        .add_attachment(&issue.id, &source)
        .expect("add polyfill attachment");
    let hash = polyfill.attachments[0].content_hash.clone();
    assert_eq!(
        polyfill.attachments[0].provider,
        bd_client::AttachmentProvider::Polyfill
    );

    // Simulate synced native metadata whose local bytes are missing.
    fs::write(workspace.path().join(".fake-native-hash"), &hash)
        .expect("write fake native metadata");
    fs::write(workspace.path().join(".fake-native-enabled"), b"")
        .expect("enable native attachments");

    let migrated = client
        .migrate_polyfill_attachments(&issue.id)
        .expect("migrate attachment");

    assert_eq!(migrated.polyfill_attachment_count, 0);
    assert_eq!(migrated.attachments.len(), 1);
    assert_eq!(
        migrated.attachments[0].provider,
        bd_client::AttachmentProvider::Native
    );
    assert!(
        !migrated
            .metadata
            .keys()
            .any(|key| key.starts_with("knecklace.attachment_"))
    );
    assert_eq!(
        fs::read(workspace.path().join(format!(".fake-native-{hash}")))
            .expect("read repaired native bytes"),
        b"migration payload"
    );
    assert!(
        !workspace
            .path()
            .join(format!(".beads/knecklace/attachments/{}/{hash}", issue.id))
            .exists()
    );
}

#[test]
fn creates_child_and_blocking_relationships() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let mut epic_request = new_issue("Parent epic", Status::Open);
    epic_request.issue_type = "epic".to_string();
    let epic = client.create(&epic_request).expect("create epic");

    let mut child_request = new_issue("Epic child", Status::Open);
    child_request.parent = Some(epic.id.clone());
    let child = client.create(&child_request).expect("create child");
    let blocker = client
        .create(&new_issue("Blocking issue", Status::Open))
        .expect("create blocker");
    client
        .add_dependency(&child.id, &blocker.id, "blocks")
        .expect("add blocking dependency");

    let dependencies = client.dependencies(&child.id).expect("list dependencies");
    let dependents = client.dependents(&epic.id).expect("list epic children");

    assert!(
        dependencies
            .iter()
            .any(|issue| issue.id == epic.id && issue.dependency_type == "parent-child")
    );
    assert!(
        dependencies
            .iter()
            .any(|issue| issue.id == blocker.id && issue.dependency_type == "blocks")
    );
    assert!(
        dependents
            .iter()
            .any(|issue| issue.id == child.id && issue.dependency_type == "parent-child")
    );
}

#[test]
fn adds_and_lists_comments() {
    let workspace = workspace();
    let client = Client::new(workspace.path()).expect("create client");
    let issue = client
        .create(&new_issue("Commented issue", Status::Open))
        .expect("create issue");

    let first = client
        .add_comment(&issue.id, "First comment")
        .expect("add first comment");
    let second = client
        .add_comment(&issue.id, "Second comment\nwith another line")
        .expect("add second comment");
    let comments = client.comments(&issue.id).expect("list comments");

    assert_eq!(first.issue_id, issue.id);
    assert_eq!(first.text, "First comment");
    assert!(!first.author.is_empty());
    assert!(!first.created_at.is_empty());
    assert_eq!(second.text, "Second comment\nwith another line");
    assert_eq!(comments.len(), 2);
    assert_eq!(comments[0].id, first.id);
    assert_eq!(comments[1].id, second.id);
}
