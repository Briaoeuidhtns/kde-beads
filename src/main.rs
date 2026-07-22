// SPDX-License-Identifier: MIT

use std::fmt::Display;
use std::path::PathBuf;
use std::process::Command;
use std::str::FromStr;
use std::thread;

use bd_client::{Client, Comment, Issue, IssueUpdate, LinkedIssue, NewIssue, Status};
use qtbridge::{QApp, QObjectHolder, invoke_method, qobject};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use url::Url;

struct Backend {
    issues: Vec<Value>,
    detail: Value,
    workspace: String,
    error_message: String,
    loading: bool,
    polling: bool,
    discard_poll: bool,
    preview_paths: Vec<PreviewPath>,
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
            polling: false,
            discard_poll: false,
            preview_paths: Vec::new(),
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

    #[qsignal(qml_name = "attachmentReady")]
    fn attachment_ready(&mut self, issue_id: &String, path: &String);

    #[qsignal(qml_name = "attachmentPreviewReady")]
    fn attachment_preview_ready(
        &mut self,
        issue_id: &String,
        attachment_id: &String,
        path: &String,
    );

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
    fn poll(&mut self) {
        if self.loading || self.polling {
            return;
        }

        self.polling = true;
        self.discard_poll = false;
        let workspace = self.workspace.clone();
        let result_workspace = workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = Client::new(workspace).and_then(|client| client.list());
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishPoll", payload, error, result_workspace);
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
            let result = Client::new(workspace).and_then(|client| load_issue_detail(&client, &id));
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
    fn create_issue(&mut self, request: Value) {
        if self.loading {
            return;
        }
        let issue = match new_issue_from_value(request) {
            Ok(issue) => issue,
            Err(error) => {
                self.set_error(error);
                return;
            }
        };

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = mutate_and_list(workspace, |client| client.create(&issue));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishCreateIssue", payload, error);
        });
    }

    #[qslot]
    fn add_attachment(&mut self, issue_id: String) {
        if self.loading || issue_id.is_empty() {
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (path, picker_error) = choose_attachment_with_kdialog(&workspace);
            if !picker_error.is_empty() || path.is_empty() {
                invoke_method!(
                    invoker,
                    "finishAttachmentMutation",
                    String::new(),
                    picker_error
                );
                return;
            }
            let result =
                Client::new(workspace).and_then(|client| client.add_attachment(&issue_id, path));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishAttachmentMutation", payload, error);
        });
    }

    #[qslot]
    fn add_attachments(&mut self, issue_id: String, urls: Vec<Value>) {
        if self.loading || issue_id.is_empty() {
            return;
        }
        let paths = match attachment_paths_from_urls(urls) {
            Ok(paths) => paths,
            Err(error) => {
                self.set_error(error);
                return;
            }
        };

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (issue, mut error) = add_attachments_to_issue(workspace, &issue_id, paths);
            let payload = issue
                .map(|issue| {
                    serde_json::to_string(&issue).unwrap_or_else(|encode_error| {
                        error = format!("Could not encode updated attachments: {encode_error}");
                        String::new()
                    })
                })
                .unwrap_or_default();
            invoke_method!(invoker, "finishAttachmentMutation", payload, error);
        });
    }

    #[qslot]
    fn remove_attachment(&mut self, issue_id: String, attachment_id: String) {
        if self.loading || issue_id.is_empty() || attachment_id.is_empty() {
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = Client::new(workspace)
                .and_then(|client| client.remove_attachment(&issue_id, &attachment_id));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishAttachmentMutation", payload, error);
        });
    }

    #[qslot]
    fn open_attachment(&mut self, issue_id: String, attachment_id: String) {
        if self.loading || issue_id.is_empty() || attachment_id.is_empty() {
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (path, temporary, error) =
                materialize_attachment(workspace, &issue_id, &attachment_id);
            invoke_method!(
                invoker,
                "finishOpenAttachment",
                issue_id,
                path,
                temporary,
                error
            );
        });
    }

    #[qslot]
    fn preview_attachment(&mut self, issue_id: String, attachment_id: String) {
        if issue_id.is_empty() || attachment_id.is_empty() {
            return;
        }

        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (path, temporary, error) =
                materialize_attachment(workspace, &issue_id, &attachment_id);
            invoke_method!(
                invoker,
                "finishPreviewAttachment",
                issue_id,
                attachment_id,
                path,
                temporary,
                error
            );
        });
    }

    #[qslot]
    fn migrate_attachments(&mut self, issue_id: String) {
        if self.loading || issue_id.is_empty() {
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = Client::new(workspace)
                .and_then(|client| client.migrate_polyfill_attachments(&issue_id));
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishAttachmentMutation", payload, error);
        });
    }

    #[qslot]
    fn add_dependency(&mut self, issue_id: String, depends_on_id: String, dependency_type: String) {
        if self.loading {
            return;
        }
        let issue_id = issue_id.trim().to_string();
        let depends_on_id = depends_on_id.trim().to_string();
        if issue_id.is_empty() || depends_on_id.is_empty() {
            self.set_error("Both relationship issue IDs are required".to_string());
            return;
        }
        if issue_id == depends_on_id {
            self.set_error("An issue cannot depend on itself".to_string());
            return;
        }
        if !matches!(dependency_type.as_str(), "blocks" | "parent-child") {
            self.set_error(format!("Unsupported relationship type: {dependency_type}"));
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result =
                add_dependency_and_list(workspace, &issue_id, &depends_on_id, &dependency_type);
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishAddDependency", payload, error);
        });
    }

    #[qslot]
    fn add_comment(&mut self, issue_id: String, text: String) {
        if self.loading {
            return;
        }
        let issue_id = issue_id.trim().to_string();
        let text = text.trim().to_string();
        if issue_id.is_empty() {
            self.set_error("Cannot comment on an issue without an ID".to_string());
            return;
        }
        if text.is_empty() {
            self.set_error("Comment cannot be empty".to_string());
            return;
        }

        self.set_error(String::new());
        self.set_loading(true);
        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = add_comment_and_list(workspace, &issue_id, &text);
            let (payload, error) = encode_result(result);
            invoke_method!(invoker, "finishAddComment", payload, error);
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
                    if replace_if_changed(&mut self.issues, issues) {
                        self.issues_changed();
                    }
                }
                Err(error) => self.set_error(format!("Could not decode issue list: {error}")),
            }
        } else {
            self.set_error(error);
        }
        self.set_loading(false);
    }

    #[qslot(qml_name = "finishPoll")]
    fn finish_poll(&mut self, payload: String, error: String, workspace: String) {
        let should_apply =
            error.is_empty() && !self.loading && !self.discard_poll && workspace == self.workspace;
        self.polling = false;
        self.discard_poll = false;

        if !should_apply {
            return;
        }
        if let Ok(issues) = serde_json::from_str::<Vec<Value>>(&payload)
            && replace_if_changed(&mut self.issues, issues)
        {
            self.issues_changed();
        }
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
        let _ = self.finish_mutation(payload, error);
    }

    #[qslot(qml_name = "finishSaveIssue")]
    fn finish_save_issue(&mut self, payload: String, error: String, saved_id: String) {
        if self.finish_mutation(payload, error).is_some() {
            self.issue_saved(&saved_id);
        }
    }

    #[qslot(qml_name = "finishCreateIssue")]
    fn finish_create_issue(&mut self, payload: String, error: String) {
        if let Some(created_id) = self.finish_mutation(payload, error) {
            self.issue_saved(&created_id);
        }
    }

    #[qslot(qml_name = "finishAttachmentMutation")]
    fn finish_attachment_mutation(&mut self, payload: String, error: String) {
        if !error.is_empty() {
            self.set_error(error);
        }
        if !payload.is_empty() {
            match serde_json::from_str::<Issue>(&payload) {
                Ok(issue) => match serde_json::to_value(issue) {
                    Ok(Value::Object(updated)) => {
                        if let Some(detail) = self.detail.as_object_mut() {
                            for key in [
                                "attachments",
                                "metadata",
                                "native_attachments_supported",
                                "polyfill_attachment_count",
                                "updated_at",
                            ] {
                                if let Some(value) = updated.get(key) {
                                    detail.insert(key.to_string(), value.clone());
                                }
                            }
                        } else {
                            self.detail = Value::Object(updated);
                        }
                        self.detail_changed();
                    }
                    Ok(_) => self.set_error("Could not encode updated attachments".to_string()),
                    Err(error) => {
                        self.set_error(format!("Could not encode updated attachments: {error}"))
                    }
                },
                Err(error) => self.set_error(format!("Could not decode issue: {error}")),
            }
        }
        self.set_loading(false);
    }

    #[qslot(qml_name = "finishOpenAttachment")]
    fn finish_open_attachment(
        &mut self,
        issue_id: String,
        path: String,
        temporary: bool,
        error: String,
    ) {
        if !error.is_empty() {
            self.set_error(error);
        } else if !path.is_empty() {
            if temporary {
                self.preview_paths.push(PreviewPath(PathBuf::from(&path)));
            }
            self.attachment_ready(&issue_id, &path);
        }
        self.set_loading(false);
    }

    #[qslot(qml_name = "finishPreviewAttachment")]
    fn finish_preview_attachment(
        &mut self,
        issue_id: String,
        attachment_id: String,
        path: String,
        temporary: bool,
        error: String,
    ) {
        if error.is_empty() && !path.is_empty() {
            if temporary {
                self.preview_paths.push(PreviewPath(PathBuf::from(&path)));
            }
            self.attachment_preview_ready(&issue_id, &attachment_id, &path);
        } else {
            self.attachment_preview_ready(&issue_id, &attachment_id, &String::new());
        }
    }

    #[qslot(qml_name = "finishAddDependency")]
    fn finish_add_dependency(&mut self, payload: String, error: String) {
        self.finish_detail_mutation(payload, error, "relationships");
    }

    #[qslot(qml_name = "finishAddComment")]
    fn finish_add_comment(&mut self, payload: String, error: String) {
        self.finish_detail_mutation(payload, error, "comments");
    }

    fn finish_detail_mutation(&mut self, payload: String, error: String, field: &str) {
        if !error.is_empty() {
            self.set_error(error);
            self.set_loading(false);
            return;
        }

        match serde_json::from_str::<DetailMutationResult>(&payload) {
            Ok(result) => {
                match serde_json::to_value(result.detail) {
                    Ok(detail) => {
                        self.detail = detail;
                        self.detail_changed();
                    }
                    Err(error) => {
                        self.set_error(format!("Could not encode updated {field}: {error}"))
                    }
                }
                match issues_to_values(result.issues) {
                    Ok(issues) => {
                        self.issues = issues;
                        self.issues_changed();
                    }
                    Err(error) => self.set_error(error),
                }
            }
            Err(error) => {
                self.set_error(format!("Could not decode updated {field}: {error}"));
            }
        }
        self.set_loading(false);
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

    fn finish_mutation(&mut self, payload: String, error: String) -> Option<String> {
        if !error.is_empty() {
            self.set_error(error);
            self.set_loading(false);
            return None;
        }

        match serde_json::from_str::<MutationResult>(&payload) {
            Ok(result) => {
                let issue_id = result.issue.id.clone();
                match serde_json::to_value(&result.issue) {
                    Ok(detail) => {
                        self.detail = detail;
                        self.detail_changed();
                    }
                    Err(error) => {
                        self.set_error(format!("Could not encode updated issue: {error}"));
                        self.set_loading(false);
                        return None;
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
                        return None;
                    }
                }
                self.set_loading(false);
                Some(issue_id)
            }
            Err(error) => {
                self.set_error(format!("Could not decode updated issues: {error}"));
                self.set_loading(false);
                None
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
        if loading && self.polling {
            self.discard_poll = true;
        }
        if self.loading != loading {
            self.loading = loading;
            self.loading_changed();
        }
    }
}

struct PreviewPath(PathBuf);

impl Drop for PreviewPath {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

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

#[derive(Deserialize, Serialize)]
struct MutationResult {
    issue: Issue,
    issues: Vec<Issue>,
}

#[derive(Deserialize, Serialize)]
struct IssueDetail {
    #[serde(flatten)]
    issue: Issue,
    dependencies: Vec<LinkedIssue>,
    dependents: Vec<LinkedIssue>,
    comments: Vec<Comment>,
}

#[derive(Deserialize, Serialize)]
struct DetailMutationResult {
    detail: IssueDetail,
    issues: Vec<Issue>,
}

fn issue_update_from_value(value: Value) -> Result<IssueUpdate, String> {
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

fn new_issue_from_value(value: Value) -> Result<NewIssue, String> {
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

fn mutate_and_list(
    workspace: String,
    mutate: impl FnOnce(&Client) -> Result<Issue, bd_client::Error>,
) -> Result<MutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    let issue = mutate(&client)?;
    let issues = client.list()?;
    Ok(MutationResult { issue, issues })
}

fn load_issue_detail(client: &Client, id: &str) -> Result<IssueDetail, bd_client::Error> {
    Ok(IssueDetail {
        issue: client.show(id)?,
        dependencies: client.dependencies(id)?,
        dependents: client.dependents(id)?,
        comments: client.comments(id)?,
    })
}

fn add_dependency_and_list(
    workspace: String,
    issue_id: &str,
    depends_on_id: &str,
    dependency_type: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.add_dependency(issue_id, depends_on_id, dependency_type)?;
    let detail = load_issue_detail(&client, issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

fn add_comment_and_list(
    workspace: String,
    issue_id: &str,
    text: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.add_comment(issue_id, text)?;
    let detail = load_issue_detail(&client, issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

fn materialize_attachment(
    workspace: String,
    issue_id: &str,
    attachment_id: &str,
) -> (String, bool, String) {
    match Client::new(workspace)
        .and_then(|client| client.materialize_attachment(issue_id, attachment_id))
    {
        Ok(materialized) => (
            materialized.path.to_string_lossy().into_owned(),
            materialized.temporary,
            String::new(),
        ),
        Err(error) => (String::new(), false, error.to_string()),
    }
}

fn attachment_paths_from_urls(urls: Vec<Value>) -> Result<Vec<PathBuf>, String> {
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

fn add_attachments_to_issue(
    workspace: String,
    issue_id: &str,
    paths: Vec<PathBuf>,
) -> (Option<Issue>, String) {
    let client = match Client::new(workspace) {
        Ok(client) => client,
        Err(error) => return (None, error.to_string()),
    };
    let mut issue = None;
    for path in paths {
        match client.add_attachment(issue_id, path) {
            Ok(updated) => issue = Some(updated),
            Err(error) => return (issue, error.to_string()),
        }
    }
    (issue, String::new())
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

fn choose_attachment_with_kdialog(workspace: &str) -> (String, String) {
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

fn issues_to_values(issues: Vec<Issue>) -> Result<Vec<Value>, String> {
    issues
        .into_iter()
        .map(|issue| {
            serde_json::to_value(issue)
                .map_err(|error| format!("Could not encode issue list: {error}"))
        })
        .collect()
}

fn replace_if_changed<T: PartialEq>(current: &mut T, replacement: T) -> bool {
    if *current == replacement {
        return false;
    }
    *current = replacement;
    true
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
    fn replaces_polled_issues_only_when_changed() {
        let mut issues = vec![json!({"id": "bd-1"})];

        assert!(!replace_if_changed(
            &mut issues,
            vec![json!({"id": "bd-1"})]
        ));
        assert!(replace_if_changed(&mut issues, vec![json!({"id": "bd-2"})]));
        assert_eq!(issues, vec![json!({"id": "bd-2"})]);
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
