// SPDX-License-Identifier: MIT

use std::fmt::Display;
use std::path::PathBuf;
use std::process::Command;
use std::str::FromStr;
use std::thread;

use bd_client::{Client, Issue, IssueUpdate, Status};
use qtbridge::{QApp, QObjectHolder, invoke_method, qobject};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

struct Backend {
    issues: Vec<Value>,
    detail: Value,
    workspace: String,
    error_message: String,
    loading: bool,
}

impl Default for Backend {
    fn default() -> Self {
        let workspace = initial_workspace();
        Self {
            issues: Vec::new(),
            detail: json!({}),
            workspace: workspace.to_string_lossy().into_owned(),
            error_message: String::new(),
            loading: false,
        }
    }
}

#[qobject(Singleton, ConvertToCamelCase)]
impl Backend {
    qproperty!("issues", Member = issues, Notify = issues_changed);
    qproperty!("detail", Member = detail, Notify = detail_changed);
    qproperty!("workspace", Member = workspace, Notify = workspace_changed);
    qproperty!(
        "errorMessage",
        Member = error_message,
        Notify = error_message_changed
    );
    qproperty!("loading", Member = loading, Notify = loading_changed);

    #[qsignal]
    fn issues_changed(&mut self);

    #[qsignal]
    fn detail_changed(&mut self);

    #[qsignal]
    fn workspace_changed(&mut self);

    #[qsignal]
    fn error_message_changed(&mut self);

    #[qsignal]
    fn loading_changed(&mut self);

    #[qsignal(qml_name = "issueSaved")]
    fn issue_saved(&mut self, id: &String);

    #[qslot]
    fn reload(&mut self) {
        if self.loading {
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);

        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = Client::new(workspace).and_then(|client| client.list());
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishReload", payload, error);
        });
    }

    #[qslot]
    fn load_issue(&mut self, id: String) {
        if self.loading || id.is_empty() {
            return;
        }

        if let Some(issue) = self
            .issues
            .iter()
            .find(|issue| issue.get("id").and_then(Value::as_str) == Some(id.as_str()))
        {
            self.detail = issue.clone();
            self.detail_changed();
        }
        self.set_error(String::new());
        self.set_loading(true);

        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = Client::new(workspace).and_then(|client| client.show(&id));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishLoadIssue", payload, error);
        });
    }

    #[qslot]
    fn move_issue(&mut self, id: String, status: String) {
        if self.loading || id.is_empty() {
            return;
        }
        let status = match Status::from_str(&status) {
            Ok(status) => status,
            Err(error) => {
                self.set_error(error.to_string());
                return;
            }
        };

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = mutate_and_list(workspace, |client| client.set_status(&id, status));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishMoveIssue", payload, error);
        });
    }

    #[qslot]
    fn save_issue(&mut self, request: Value) {
        if self.loading {
            return;
        }
        let update = match issue_update_from_value(request) {
            Ok(update) => update,
            Err(error) => {
                self.set_error(error);
                return;
            }
        };

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let saved_id = update.id.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = mutate_and_list(workspace, |client| client.update(&update));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishSaveIssue", payload, error, saved_id);
        });
    }

    #[qslot]
    fn choose_workspace(&mut self) {
        if self.loading {
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let current_workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (workspace, error) = choose_workspace_with_kdialog(&current_workspace);
            invoke_method!(invoker, "finishChooseWorkspace", workspace, error);
        });
    }

    #[qslot]
    fn clear_error(&mut self) {
        self.set_error(String::new());
    }

    #[qslot(qml_name = "finishReload")]
    fn finish_reload(&mut self, payload: String, error: String) {
        if error.is_empty() {
            match serde_json::from_str::<Vec<Value>>(&payload) {
                Ok(issues) => {
                    self.issues = issues;
                    self.issues_changed();
                }
                Err(error) => self.set_error(format!("Could not decode issue list: {error}")),
            }
        } else {
            self.set_error(error);
        }
        self.set_loading(false);
    }

    #[qslot(qml_name = "finishLoadIssue")]
    fn finish_load_issue(&mut self, payload: String, error: String) {
        if error.is_empty() {
            match serde_json::from_str::<Value>(&payload) {
                Ok(detail) => {
                    self.detail = detail;
                    self.detail_changed();
                }
                Err(error) => self.set_error(format!("Could not decode issue: {error}")),
            }
        } else {
            self.set_error(error);
        }
        self.set_loading(false);
    }

    #[qslot(qml_name = "finishMoveIssue")]
    fn finish_move_issue(&mut self, payload: String, error: String) {
        self.finish_mutation(payload, error);
    }

    #[qslot(qml_name = "finishSaveIssue")]
    fn finish_save_issue(&mut self, payload: String, error: String, saved_id: String) {
        if self.finish_mutation(payload, error) {
            self.issue_saved(&saved_id);
        }
    }

    #[qslot(qml_name = "finishChooseWorkspace")]
    fn finish_choose_workspace(&mut self, workspace: String, error: String) {
        self.set_loading(false);
        if !error.is_empty() {
            self.set_error(error);
            return;
        }
        if workspace.is_empty() {
            return;
        }

        match Client::new(&workspace) {
            Ok(client) => {
                let workspace = client.workspace().to_string_lossy().into_owned();
                if self.workspace != workspace {
                    self.workspace = workspace;
                    self.workspace_changed();
                }
                self.issues.clear();
                self.issues_changed();
                self.detail = json!({});
                self.detail_changed();
                self.reload();
            }
            Err(error) => self.set_error(error.to_string()),
        }
    }

    fn finish_mutation(&mut self, payload: String, error: String) -> bool {
        if !error.is_empty() {
            self.set_error(error);
            self.set_loading(false);
            return false;
        }

        match serde_json::from_str::<MutationResult>(&payload) {
            Ok(result) => {
                match serde_json::to_value(&result.issue) {
                    Ok(detail) => {
                        self.detail = detail;
                        self.detail_changed();
                    }
                    Err(error) => {
                        self.set_error(format!("Could not encode updated issue: {error}"));
                        self.set_loading(false);
                        return false;
                    }
                }
                match issues_to_values(result.issues) {
                    Ok(issues) => {
                        self.issues = issues;
                        self.issues_changed();
                    }
                    Err(error) => {
                        self.set_error(error);
                        self.set_loading(false);
                        return false;
                    }
                }
                self.set_loading(false);
                true
            }
            Err(error) => {
                self.set_error(format!("Could not decode updated issues: {error}"));
                self.set_loading(false);
                false
            }
        }
    }

    fn set_error(&mut self, error: String) {
        if self.error_message != error {
            self.error_message = error;
            self.error_message_changed();
        }
    }

    fn set_loading(&mut self, loading: bool) {
        if self.loading != loading {
            self.loading = loading;
            self.loading_changed();
        }
    }
}

#[derive(Deserialize)]
struct EditorRequest {
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
}

#[derive(Deserialize, Serialize)]
struct MutationResult {
    issue: Issue,
    issues: Vec<Issue>,
}

fn issue_update_from_value(value: Value) -> Result<IssueUpdate, String> {
    let request: EditorRequest =
        serde_json::from_value(value).map_err(|error| format!("Invalid editor values: {error}"))?;
    if request.id.trim().is_empty() {
        return Err("Cannot save an issue without an ID".to_string());
    }
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
    })
}

fn mutate_and_list(
    workspace: String,
    mutate: impl FnOnce(&Client) -> Result<Issue, bd_client::Error>,
) -> Result<MutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    let issue = mutate(&client)?;
    let issues = client.list()?;
    Ok(MutationResult { issue, issues })
}

fn choose_workspace_with_kdialog(current_workspace: &str) -> (String, String) {
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

fn issues_to_values(issues: Vec<Issue>) -> Result<Vec<Value>, String> {
    issues
        .into_iter()
        .map(|issue| {
            serde_json::to_value(issue)
                .map_err(|error| format!("Could not encode issue list: {error}"))
        })
        .collect()
}

fn initial_workspace() -> PathBuf {
    std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .filter(|path| path.is_dir())
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."))
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn encode_result<T: Serialize, E: Display>(result: Result<T, E>) -> (String, String) {
    match result {
        Ok(value) => match serde_json::to_string(&value) {
            Ok(payload) => (payload, String::new()),
            Err(error) => (
                String::new(),
                format!("Could not encode client result: {error}"),
            ),
        },
        Err(error) => (String::new(), error.to_string()),
    }
}

fn main() {
    QApp::new()
        .register::<Backend>()
        .load_qml(include_bytes!("Main.qml"))
        .run();
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
