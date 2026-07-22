// SPDX-License-Identifier: MIT

use std::path::PathBuf;
use std::str::FromStr;

use bd_client::{IssueUpdate, NewIssue, Status};
use serde::Deserialize;
use serde_json::Value;
use url::Url;

#[derive(Deserialize)]
struct EditorRequest {
    #[serde(default)]
    id: String,
    title: String,
    description: String,
    #[serde(rename = "acceptanceCriteria")]
    acceptance_criteria: String,
    design: String,
    notes: String,
    status: String,
    priority: String,
    #[serde(rename = "issueType")]
    issue_type: String,
    assignee: String,
    labels: String,
    #[serde(default, rename = "parentId")]
    parent_id: String,
}

pub(crate) fn issue_update_from_value(value: Value) -> Result<IssueUpdate, String> {
    let (request, status, priority, labels) = parse_editor_request(value)?;
    if request.id.trim().is_empty() {
        return Err("Cannot save an issue without an ID".to_string());
    }

    Ok(IssueUpdate {
        id: request.id,
        title: request.title,
        description: request.description,
        acceptance_criteria: request.acceptance_criteria,
        design: request.design,
        notes: request.notes,
        status,
        priority,
        issue_type: request.issue_type,
        assignee: request.assignee,
        labels,
        parent: (!request.parent_id.trim().is_empty()).then_some(request.parent_id),
    })
}

pub(crate) fn new_issue_from_value(value: Value) -> Result<NewIssue, String> {
    let (request, status, priority, labels) = parse_editor_request(value)?;
    Ok(NewIssue {
        title: request.title,
        description: request.description,
        acceptance_criteria: request.acceptance_criteria,
        design: request.design,
        notes: request.notes,
        status,
        priority,
        issue_type: request.issue_type,
        assignee: request.assignee,
        labels,
        parent: (!request.parent_id.trim().is_empty()).then_some(request.parent_id),
    })
}

fn parse_editor_request(value: Value) -> Result<(EditorRequest, Status, u8, Vec<String>), String> {
    let request: EditorRequest =
        serde_json::from_value(value).map_err(|error| format!("Invalid editor values: {error}"))?;
    if request.title.trim().is_empty() {
        return Err("Title cannot be empty".to_string());
    }
    let status = Status::from_str(&request.status).map_err(|error| error.to_string())?;
    let priority = request
        .priority
        .parse::<u8>()
        .map_err(|_| "Priority must be between 0 and 4".to_string())?;
    if priority > 4 {
        return Err("Priority must be between 0 and 4".to_string());
    }
    let labels = request
        .labels
        .split(',')
        .map(str::trim)
        .filter(|label| !label.is_empty())
        .map(str::to_string)
        .collect();
    Ok((request, status, priority, labels))
}

pub(crate) fn attachment_paths_from_urls(urls: Vec<Value>) -> Result<Vec<PathBuf>, String> {
    if urls.is_empty() {
        return Err("No files were selected for attachment".to_string());
    }

    urls.into_iter()
        .map(|value| {
            let value = value
                .as_str()
                .ok_or_else(|| "Attachment URLs must be strings".to_string())?;
            let url = Url::parse(value)
                .map_err(|error| format!("Could not read attachment URL: {error}"))?;
            if url.scheme() != "file" {
                return Err("Only local files can be attached".to_string());
            }
            url.to_file_path()
                .map_err(|_| format!("Could not convert attachment URL to a local path: {value}"))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn converts_editor_request_to_update() {
        let request = json!({
            "id": "bd-1",
            "title": "Updated",
            "description": "Description",
            "acceptanceCriteria": "It works",
            "design": "Use the CLI",
            "notes": "A note",
            "status": "in_progress",
            "priority": "1",
            "issueType": "feature",
            "assignee": "brian",
            "labels": "kde, rust"
        });

        let update = issue_update_from_value(request).unwrap();
        assert_eq!(update.status, Status::InProgress);
        assert_eq!(update.priority, 1);
        assert_eq!(update.labels, ["kde", "rust"]);
    }

    #[test]
    fn rejects_empty_titles() {
        let request = json!({
            "id": "bd-1",
            "title": "",
            "description": "",
            "acceptanceCriteria": "",
            "design": "",
            "notes": "",
            "status": "open",
            "priority": "2",
            "issueType": "task",
            "assignee": "",
            "labels": ""
        });
        assert_eq!(
            issue_update_from_value(request).unwrap_err(),
            "Title cannot be empty"
        );
    }

    #[test]
    fn converts_editor_request_to_new_issue() {
        let request = json!({
            "title": "New bead",
            "description": "Description",
            "acceptanceCriteria": "It works",
            "design": "Use the CLI",
            "notes": "",
            "status": "open",
            "priority": "2",
            "issueType": "task",
            "assignee": "",
            "labels": "kde, rust",
            "parentId": "bd-epic"
        });

        let issue = new_issue_from_value(request).unwrap();
        assert_eq!(issue.title, "New bead");
        assert_eq!(issue.status, Status::Open);
        assert_eq!(issue.labels, ["kde", "rust"]);
        assert_eq!(issue.parent.as_deref(), Some("bd-epic"));
    }

    #[test]
    fn converts_local_attachment_urls_to_paths() {
        let paths = attachment_paths_from_urls(vec![
            Value::String("file:///tmp/a%20file%23one.png".to_string()),
            Value::String("file:///tmp/two.txt".to_string()),
        ])
        .unwrap();

        assert_eq!(
            paths,
            [
                PathBuf::from("/tmp/a file#one.png"),
                PathBuf::from("/tmp/two.txt")
            ]
        );
    }

    #[test]
    fn rejects_non_file_attachment_urls() {
        assert_eq!(
            attachment_paths_from_urls(vec![Value::String(
                "https://example.com/file.png".to_string()
            )])
            .unwrap_err(),
            "Only local files can be attached"
        );
    }
}
