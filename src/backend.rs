// SPDX-License-Identifier: MIT

use std::path::PathBuf;
use std::str::FromStr;
use std::thread;

use bd_client::{Issue, Status};
use qtbridge::{QObjectHolder, invoke_method, qobject};
use serde_json::{Value, json};

use crate::dialogs::{choose_attachment_with_kdialog, choose_workspace_with_kdialog};
use crate::editor_request::{
    attachment_paths_from_urls, issue_update_from_value, new_issue_from_value,
};
use crate::operations::{
    DetailMutationResult, MutationResult, add_attachment_to_issue, add_attachments_to_issue,
    add_comment_and_list, add_dependency_and_list, canonical_workspace, create_issue_and_list,
    encode_result, list_issues, load_issue_detail, materialize_attachment, migrate_attachments,
    move_issue_and_list, remove_attachment_from_issue, update_issue_and_list,
};

pub(crate) struct Backend {
    issues: Vec<Value>,
    detail: Value,
    workspace: String,
    startup_workspace_explicit: bool,
    error_message: String,
    loading: bool,
    polling: bool,
    discard_poll: bool,
    preview_paths: Vec<PreviewPath>,
}

impl Default for Backend {
    fn default() -> Self {
        let (workspace, startup_workspace_explicit) = initial_workspace();
        Self {
            issues: Vec::new(),
            detail: json!({}),
            workspace: workspace.to_string_lossy().into_owned(),
            startup_workspace_explicit,
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
        "startupWorkspaceExplicit",
        Member = startup_workspace_explicit,
        Constant
    );
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
            let (payload, error) = encode_result(list_issues(workspace));
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
            let (payload, error) = encode_result(list_issues(workspace));
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
            let (payload, error) = encode_result(load_issue_detail(workspace, &id));
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
            let (payload, error) = encode_result(move_issue_and_list(workspace, &id, status));
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
            let (payload, error) = encode_result(update_issue_and_list(workspace, &update));
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
            let (payload, error) = encode_result(create_issue_and_list(workspace, &issue));
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
            let result = add_attachment_to_issue(workspace, &issue_id, path);
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
            let result = remove_attachment_from_issue(workspace, &issue_id, &attachment_id);
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
            let result = migrate_attachments(workspace, &issue_id);
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
    fn switch_workspace(&mut self, workspace: String) {
        if self.loading || workspace.is_empty() {
            return;
        }
        let workspace = match canonical_workspace(&workspace) {
            Ok(workspace) => workspace,
            Err(error) => {
                self.set_error(error.to_string());
                return;
            }
        };
        if self.workspace == workspace {
            return;
        }

        self.polling = false;
        self.discard_poll = true;
        self.workspace = workspace;
        self.workspace_changed();
        self.issues.clear();
        self.issues_changed();
        self.detail = json!({});
        self.detail_changed();
        self.set_error(String::new());
        self.reload();
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
        self.switch_workspace(workspace);
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

fn initial_workspace() -> (PathBuf, bool) {
    let explicit = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .filter(|path| path.is_dir());
    let workspace = explicit
        .clone()
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."))
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from("."));
    (workspace, explicit.is_some())
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
