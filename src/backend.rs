// SPDX-License-Identifier: MIT

use std::collections::HashMap;
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
use crate::workspace_cache::WorkspaceCache;

#[derive(Clone)]
struct RequestTarget {
    workspace: String,
    generation: u64,
    issue_id: String,
}

struct PreviewRequest {
    target: RequestTarget,
    attachment_id: String,
}

pub(crate) struct Backend {
    issues: Vec<Value>,
    detail: Value,
    workspace: String,
    startup_workspace_explicit: bool,
    error_message: String,
    loading: bool,
    refreshing: bool,
    cache: WorkspaceCache,
    active_detail: Option<RequestTarget>,
    preview_requests: HashMap<u64, PreviewRequest>,
    workspace_choice: Option<(String, u64)>,
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
            refreshing: false,
            cache: WorkspaceCache::default(),
            active_detail: None,
            preview_requests: HashMap::new(),
            workspace_choice: None,
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
    qproperty!(
        "refreshing",
        Member = refreshing,
        Notify = refreshing_changed
    );

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

    #[qsignal]
    fn refreshing_changed(&mut self);

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
        self.start_refresh(true);
    }

    #[qslot]
    fn poll(&mut self) {
        self.start_refresh(false);
    }

    #[qslot]
    fn load_issue(&mut self, id: String) {
        if id.is_empty() {
            return;
        }

        let Some((workspace, generation)) = self.begin_foreground(false) else {
            return;
        };

        if let Some(issue) = self
            .issues
            .iter()
            .find(|issue| issue.get("id").and_then(Value::as_str) == Some(id.as_str()))
        {
            self.detail = issue.clone();
            self.detail_changed();
        }
        self.active_detail = Some(RequestTarget {
            workspace: workspace.clone(),
            generation,
            issue_id: id.clone(),
        });

        let result_workspace = workspace.clone();
        let result_id = id.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (payload, error) = encode_result(load_issue_detail(workspace, &id));
            invoke_method!(
                invoker,
                "finishLoadIssue",
                payload,
                error,
                result_workspace,
                generation,
                result_id
            );
        });
    }

    #[qslot]
    fn move_issue(&mut self, id: String, status: String) {
        if id.is_empty() {
            return;
        }
        let status = match Status::from_str(&status) {
            Ok(status) => status,
            Err(error) => {
                self.set_error(error.to_string());
                return;
            }
        };
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (payload, error) = encode_result(move_issue_and_list(workspace, &id, status));
            invoke_method!(
                invoker,
                "finishMoveIssue",
                payload,
                error,
                result_workspace,
                generation
            );
        });
    }

    #[qslot]
    fn save_issue(&mut self, request: Value) {
        let update = match issue_update_from_value(request) {
            Ok(update) => update,
            Err(error) => {
                self.set_error(error);
                return;
            }
        };
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let saved_id = update.id.clone();
        let result_workspace = workspace.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (payload, error) = encode_result(update_issue_and_list(workspace, &update));
            invoke_method!(
                invoker,
                "finishSaveIssue",
                payload,
                error,
                result_workspace,
                generation,
                saved_id
            );
        });
    }

    #[qslot]
    fn create_issue(&mut self, request: Value) {
        let issue = match new_issue_from_value(request) {
            Ok(issue) => issue,
            Err(error) => {
                self.set_error(error);
                return;
            }
        };
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (payload, error) = encode_result(create_issue_and_list(workspace, &issue));
            invoke_method!(
                invoker,
                "finishCreateIssue",
                payload,
                error,
                result_workspace,
                generation
            );
        });
    }

    #[qslot]
    fn add_attachment(&mut self, issue_id: String) {
        if issue_id.is_empty() {
            return;
        }
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let result_issue_id = issue_id.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (path, picker_error) = choose_attachment_with_kdialog(&workspace);
            if !picker_error.is_empty() || path.is_empty() {
                invoke_method!(
                    invoker,
                    "finishAttachmentMutation",
                    String::new(),
                    picker_error,
                    result_workspace,
                    generation,
                    result_issue_id
                );
                return;
            }
            let result = add_attachment_to_issue(workspace, &issue_id, path);
            let (payload, error) = encode_result(result);
            invoke_method!(
                invoker,
                "finishAttachmentMutation",
                payload,
                error,
                result_workspace,
                generation,
                result_issue_id
            );
        });
    }

    #[qslot]
    fn add_attachments(&mut self, issue_id: String, urls: Vec<Value>) {
        if issue_id.is_empty() {
            return;
        }
        let paths = match attachment_paths_from_urls(urls) {
            Ok(paths) => paths,
            Err(error) => {
                self.set_error(error);
                return;
            }
        };
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let result_issue_id = issue_id.clone();
        let generation = generation.to_string();
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
            invoke_method!(
                invoker,
                "finishAttachmentMutation",
                payload,
                error,
                result_workspace,
                generation,
                result_issue_id
            );
        });
    }

    #[qslot]
    fn remove_attachment(&mut self, issue_id: String, attachment_id: String) {
        if issue_id.is_empty() || attachment_id.is_empty() {
            return;
        }
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let result_issue_id = issue_id.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = remove_attachment_from_issue(workspace, &issue_id, &attachment_id);
            let (payload, error) = encode_result(result);
            invoke_method!(
                invoker,
                "finishAttachmentMutation",
                payload,
                error,
                result_workspace,
                generation,
                result_issue_id
            );
        });
    }

    #[qslot]
    fn open_attachment(&mut self, issue_id: String, attachment_id: String) {
        if issue_id.is_empty() || attachment_id.is_empty() {
            return;
        }
        let Some((workspace, generation)) = self.begin_foreground(false) else {
            return;
        };

        let result_workspace = workspace.clone();
        let generation = generation.to_string();
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
                error,
                result_workspace,
                generation
            );
        });
    }

    #[qslot]
    fn preview_attachment(&mut self, issue_id: String, attachment_id: String) {
        if issue_id.is_empty() || attachment_id.is_empty() {
            return;
        }

        let workspace = self.workspace.clone();
        let Some(target) = self
            .active_detail
            .as_ref()
            .filter(|target| target.workspace == workspace && target.issue_id == issue_id)
        else {
            return;
        };
        let generation = self.cache.allocate_generation();
        self.preview_requests.insert(
            generation,
            PreviewRequest {
                target: target.clone(),
                attachment_id: attachment_id.clone(),
            },
        );
        let generation = generation.to_string();
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
                error,
                generation
            );
        });
    }

    #[qslot]
    fn migrate_attachments(&mut self, issue_id: String) {
        if issue_id.is_empty() {
            return;
        }
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let result_issue_id = issue_id.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = migrate_attachments(workspace, &issue_id);
            let (payload, error) = encode_result(result);
            invoke_method!(
                invoker,
                "finishAttachmentMutation",
                payload,
                error,
                result_workspace,
                generation,
                result_issue_id
            );
        });
    }

    #[qslot]
    fn add_dependency(&mut self, issue_id: String, depends_on_id: String, dependency_type: String) {
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
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let result_issue_id = issue_id.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result =
                add_dependency_and_list(workspace, &issue_id, &depends_on_id, &dependency_type);
            let (payload, error) = encode_result(result);
            invoke_method!(
                invoker,
                "finishAddDependency",
                payload,
                error,
                result_workspace,
                generation,
                result_issue_id
            );
        });
    }

    #[qslot]
    fn add_comment(&mut self, issue_id: String, text: String) {
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
        let Some((workspace, generation)) = self.begin_foreground(true) else {
            return;
        };

        let result_workspace = workspace.clone();
        let result_issue_id = issue_id.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = add_comment_and_list(workspace, &issue_id, &text);
            let (payload, error) = encode_result(result);
            invoke_method!(
                invoker,
                "finishAddComment",
                payload,
                error,
                result_workspace,
                generation,
                result_issue_id
            );
        });
    }

    #[qslot]
    fn choose_workspace(&mut self) {
        if self.workspace_choice.is_some() {
            return;
        }

        self.set_error(String::new());
        let current_workspace = self.workspace.clone();
        let result_workspace = current_workspace.clone();
        let generation = self.cache.allocate_generation();
        self.workspace_choice = Some((current_workspace.clone(), generation));
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (workspace, error) = choose_workspace_with_kdialog(&current_workspace);
            invoke_method!(
                invoker,
                "finishChooseWorkspace",
                workspace,
                error,
                result_workspace,
                generation
            );
        });
    }

    #[qslot]
    fn switch_workspace(&mut self, workspace: String) {
        if workspace.is_empty() {
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

        self.workspace = workspace;
        self.workspace_changed();
        self.active_detail = None;
        self.set_detail(json!({}));
        self.publish_active_workspace();
        self.start_refresh(true);
    }

    #[qslot]
    fn clear_error(&mut self) {
        let workspace = self.workspace.clone();
        let generation = self.cache.allocate_generation();
        self.cache.set_error(&workspace, generation, String::new());
        self.publish_active_workspace();
    }

    #[qslot(qml_name = "finishRefresh")]
    fn finish_refresh_slot(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            return;
        };
        let Some(report_errors) = self.cache.refresh_reports_errors(&workspace, generation) else {
            return;
        };

        if !error.is_empty() {
            if report_errors {
                self.cache.set_error(&workspace, generation, error);
            }
        } else {
            match serde_json::from_str::<Vec<Value>>(&payload) {
                Ok(issues) => {
                    if self.cache.apply_snapshot(&workspace, generation, issues) && report_errors {
                        self.cache.set_error(&workspace, generation, String::new());
                    }
                }
                Err(error) if report_errors => {
                    self.cache.set_error(
                        &workspace,
                        generation,
                        format!("Could not decode issue list: {error}"),
                    );
                }
                Err(_) => {}
            }
        }
        self.complete_refresh(&workspace, generation);
    }

    #[qslot(qml_name = "finishLoadIssue")]
    fn finish_load_issue(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        issue_id: String,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            return;
        };
        if !self.cache.foreground_is_current(&workspace, generation) {
            return;
        }
        let target_is_current = self.active_detail.as_ref().is_some_and(|target| {
            target.workspace == workspace
                && target.generation == generation
                && target.issue_id == issue_id
        });

        if target_is_current {
            if !error.is_empty() {
                self.cache.set_error(&workspace, generation, error);
            } else {
                match serde_json::from_str::<Value>(&payload) {
                    Ok(detail) => self.set_detail(detail),
                    Err(error) => {
                        self.cache.set_error(
                            &workspace,
                            generation,
                            format!("Could not decode issue: {error}"),
                        );
                    }
                }
            }
        }
        self.complete_foreground(&workspace, generation);
    }

    #[qslot(qml_name = "finishMoveIssue")]
    fn finish_move_issue(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
    ) {
        let _ = self.finish_mutation(payload, error, workspace, generation, false);
    }

    #[qslot(qml_name = "finishSaveIssue")]
    fn finish_save_issue(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        _saved_id: String,
    ) {
        if let Some(saved_id) = self.finish_mutation(payload, error, workspace, generation, true) {
            self.issue_saved(&saved_id);
        }
    }

    #[qslot(qml_name = "finishCreateIssue")]
    fn finish_create_issue(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
    ) {
        if let Some(created_id) = self.finish_mutation(payload, error, workspace, generation, true)
        {
            self.issue_saved(&created_id);
        }
    }

    #[qslot(qml_name = "finishAttachmentMutation")]
    fn finish_attachment_mutation(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        issue_id: String,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            return;
        };
        if !self.cache.foreground_is_current(&workspace, generation) {
            return;
        }

        let mut payload_error = None;
        if !payload.is_empty() {
            match serde_json::from_str::<Issue>(&payload).and_then(serde_json::to_value) {
                Ok(Value::Object(updated)) => {
                    self.cache.apply_issue_update(
                        &workspace,
                        generation,
                        Value::Object(updated.clone()),
                    );
                    if self.detail_matches(&workspace, &issue_id) {
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
                            self.detail_changed();
                        } else {
                            self.set_detail(Value::Object(updated));
                        }
                    }
                }
                Ok(_) => {
                    payload_error = Some("Could not encode updated attachments".to_string());
                }
                Err(error) => {
                    payload_error = Some(format!("Could not decode updated attachments: {error}"));
                }
            }
        }
        if !error.is_empty() {
            self.cache.set_error(&workspace, generation, error);
        } else if let Some(error) = payload_error {
            self.cache.set_error(&workspace, generation, error);
        }
        self.complete_foreground(&workspace, generation);
    }

    #[qslot(qml_name = "finishOpenAttachment")]
    fn finish_open_attachment(
        &mut self,
        issue_id: String,
        path: String,
        temporary: bool,
        error: String,
        workspace: String,
        generation: String,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            remove_temporary_path(&path, temporary);
            return;
        };
        if !self.cache.foreground_is_current(&workspace, generation) {
            remove_temporary_path(&path, temporary);
            return;
        }

        if !error.is_empty() {
            self.cache.set_error(&workspace, generation, error);
        } else if !path.is_empty() && self.detail_matches(&workspace, &issue_id) {
            if temporary {
                self.preview_paths.push(PreviewPath(PathBuf::from(&path)));
            }
            self.attachment_ready(&issue_id, &path);
        } else {
            remove_temporary_path(&path, temporary);
        }
        self.complete_foreground(&workspace, generation);
    }

    #[qslot(qml_name = "finishPreviewAttachment")]
    fn finish_preview_attachment(
        &mut self,
        issue_id: String,
        attachment_id: String,
        path: String,
        temporary: bool,
        error: String,
        generation: String,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            remove_temporary_path(&path, temporary);
            return;
        };
        let Some(request) = self.preview_requests.remove(&generation) else {
            remove_temporary_path(&path, temporary);
            return;
        };
        let target_is_current = request.attachment_id == attachment_id
            && request.target.issue_id == issue_id
            && self.active_detail.as_ref().is_some_and(|target| {
                target.workspace == request.target.workspace
                    && target.generation == request.target.generation
                    && target.issue_id == request.target.issue_id
            })
            && self.workspace == request.target.workspace;
        if !target_is_current {
            remove_temporary_path(&path, temporary);
            return;
        }

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
    fn finish_add_dependency(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        issue_id: String,
    ) {
        self.finish_detail_mutation(
            payload,
            error,
            workspace,
            generation,
            issue_id,
            "relationships",
        );
    }

    #[qslot(qml_name = "finishAddComment")]
    fn finish_add_comment(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        issue_id: String,
    ) {
        self.finish_detail_mutation(payload, error, workspace, generation, issue_id, "comments");
    }

    fn finish_detail_mutation(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        issue_id: String,
        field: &str,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            return;
        };
        if !self.cache.foreground_is_current(&workspace, generation) {
            return;
        }
        if !error.is_empty() {
            self.fail_foreground(&workspace, generation, error);
            return;
        }

        let result = match serde_json::from_str::<DetailMutationResult>(&payload) {
            Ok(result) => result,
            Err(error) => {
                self.fail_foreground(
                    &workspace,
                    generation,
                    format!("Could not decode updated {field}: {error}"),
                );
                return;
            }
        };
        let detail = match serde_json::to_value(result.detail) {
            Ok(detail) => detail,
            Err(error) => {
                self.fail_foreground(
                    &workspace,
                    generation,
                    format!("Could not encode updated {field}: {error}"),
                );
                return;
            }
        };
        let issues = match issues_to_values(result.issues) {
            Ok(issues) => issues,
            Err(error) => {
                self.fail_foreground(&workspace, generation, error);
                return;
            }
        };

        self.cache.apply_snapshot(&workspace, generation, issues);
        if self.detail_matches(&workspace, &issue_id) {
            self.set_detail(detail);
        }
        self.complete_foreground(&workspace, generation);
    }

    #[qslot(qml_name = "finishChooseWorkspace")]
    fn finish_choose_workspace(
        &mut self,
        workspace: String,
        error: String,
        origin_workspace: String,
        generation: String,
    ) {
        let Some(generation) = parse_generation(&generation) else {
            return;
        };
        if self.workspace_choice.as_ref() != Some(&(origin_workspace.clone(), generation)) {
            return;
        }
        self.workspace_choice = None;
        if !error.is_empty() {
            self.cache.set_error(&origin_workspace, generation, error);
            self.publish_active_workspace();
            return;
        }
        if !workspace.is_empty() && self.workspace == origin_workspace {
            self.switch_workspace(workspace);
        }
    }

    fn finish_mutation(
        &mut self,
        payload: String,
        error: String,
        workspace: String,
        generation: String,
        update_detail: bool,
    ) -> Option<String> {
        let generation = parse_generation(&generation)?;
        if !self.cache.foreground_is_current(&workspace, generation) {
            return None;
        }
        if !error.is_empty() {
            self.fail_foreground(&workspace, generation, error);
            return None;
        }

        let result = match serde_json::from_str::<MutationResult>(&payload) {
            Ok(result) => result,
            Err(error) => {
                self.fail_foreground(
                    &workspace,
                    generation,
                    format!("Could not decode updated issues: {error}"),
                );
                return None;
            }
        };
        let issue_id = result.issue.id.clone();
        let detail = match serde_json::to_value(&result.issue) {
            Ok(detail) => detail,
            Err(error) => {
                self.fail_foreground(
                    &workspace,
                    generation,
                    format!("Could not encode updated issue: {error}"),
                );
                return None;
            }
        };
        let issues = match issues_to_values(result.issues) {
            Ok(issues) => issues,
            Err(error) => {
                self.fail_foreground(&workspace, generation, error);
                return None;
            }
        };

        self.cache.apply_snapshot(&workspace, generation, issues);
        let is_active = self.workspace == workspace;
        if is_active && update_detail {
            self.set_detail(detail);
        }
        self.complete_foreground(&workspace, generation);
        is_active.then_some(issue_id)
    }

    fn start_refresh(&mut self, report_errors: bool) {
        self.start_workspace_refresh(self.workspace.clone(), report_errors);
    }

    fn start_workspace_refresh(&mut self, workspace: String, report_errors: bool) {
        let Some(generation) = self.cache.begin_refresh(&workspace, report_errors) else {
            self.publish_active_workspace();
            return;
        };
        self.publish_active_workspace();

        let result_workspace = workspace.clone();
        let generation = generation.to_string();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let (payload, error) = encode_result(list_issues(workspace));
            invoke_method!(
                invoker,
                "finishRefresh",
                payload,
                error,
                result_workspace,
                generation
            );
        });
    }

    fn begin_foreground(&mut self, updates_issues: bool) -> Option<(String, u64)> {
        let workspace = self.workspace.clone();
        let generation = self.cache.begin_foreground(&workspace, updates_issues)?;
        self.publish_active_workspace();
        Some((workspace, generation))
    }

    fn fail_foreground(&mut self, workspace: &str, generation: u64, error: String) {
        if !self.cache.foreground_is_current(workspace, generation) {
            return;
        }
        self.cache.set_error(workspace, generation, error);
        self.complete_foreground(workspace, generation);
    }

    fn complete_foreground(&mut self, workspace: &str, generation: u64) {
        if !self.cache.finish_foreground(workspace, generation) {
            return;
        }
        let pending_refresh = self.cache.take_pending_refresh(workspace);
        self.publish_active_workspace();
        if let Some(report_errors) = pending_refresh {
            self.start_workspace_refresh(workspace.to_string(), report_errors);
        }
    }

    fn complete_refresh(&mut self, workspace: &str, generation: u64) {
        if !self.cache.finish_refresh(workspace, generation) {
            return;
        }
        let pending_refresh = self.cache.take_pending_refresh(workspace);
        self.publish_active_workspace();
        if let Some(report_errors) = pending_refresh {
            self.start_workspace_refresh(workspace.to_string(), report_errors);
        }
    }

    fn detail_matches(&self, workspace: &str, issue_id: &str) -> bool {
        self.workspace == workspace
            && self.detail.get("id").and_then(Value::as_str) == Some(issue_id)
    }

    fn publish_active_workspace(&mut self) {
        let view = self.cache.view(&self.workspace);
        if replace_if_changed(&mut self.issues, view.issues) {
            self.issues_changed();
        }
        self.set_visible_error(view.error);
        self.set_loading(view.loading);
        self.set_refreshing(view.refreshing);
    }

    fn set_detail(&mut self, detail: Value) {
        if replace_if_changed(&mut self.detail, detail) {
            self.detail_changed();
        }
    }

    fn set_error(&mut self, error: String) {
        let workspace = self.workspace.clone();
        let generation = self.cache.allocate_generation();
        self.cache.set_error(&workspace, generation, error);
        self.publish_active_workspace();
    }

    fn set_visible_error(&mut self, error: String) {
        if replace_if_changed(&mut self.error_message, error) {
            self.error_message_changed();
        }
    }

    fn set_loading(&mut self, loading: bool) {
        if replace_if_changed(&mut self.loading, loading) {
            self.loading_changed();
        }
    }

    fn set_refreshing(&mut self, refreshing: bool) {
        if replace_if_changed(&mut self.refreshing, refreshing) {
            self.refreshing_changed();
        }
    }
}

fn parse_generation(generation: &str) -> Option<u64> {
    generation.parse().ok()
}

fn remove_temporary_path(path: &str, temporary: bool) {
    if temporary && !path.is_empty() {
        let _ = std::fs::remove_file(path);
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
