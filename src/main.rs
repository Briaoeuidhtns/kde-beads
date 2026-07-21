// SPDX-License-Identifier: MIT

use std::fmt::Display;
use std::path::PathBuf;
use std::thread;

use bd_client::Client;
use qtbridge::{QApp, QObjectHolder, invoke_method, qobject};
use serde::Serialize;
use serde_json::{Value, json};
use url::Url;

struct Backend {
    issues: Vec<Value>,
    detail: Value,
    workspace: String,
    selected_id: String,
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
            selected_id: String::new(),
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
        "selectedId",
        Member = selected_id,
        Notify = selected_id_changed
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
    fn selected_id_changed(&mut self);

    #[qsignal]
    fn error_message_changed(&mut self);

    #[qsignal]
    fn loading_changed(&mut self);

    #[qslot]
    fn reload(&mut self) {
        if self.loading {
            return;
        }

        self.clear_selection();
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
    fn show_issue(&mut self, id: String) {
        if self.loading || id.is_empty() {
            return;
        }

        self.selected_id = id.clone();
        self.selected_id_changed();
        self.detail = self
            .issues
            .iter()
            .find(|issue| issue.get("id").and_then(Value::as_str) == Some(id.as_str()))
            .cloned()
            .unwrap_or_else(|| json!({}));
        self.detail_changed();
        self.set_error(String::new());
        self.set_loading(true);

        let workspace = self.workspace.clone();
        let invoker = self.get_qml_method_invoker();
        thread::spawn(move || {
            let result = Client::new(workspace).and_then(|client| client.show(&id));
            let (payload, error) = encode_result(result.map(|issue| vec![issue]));
            invoke_method!(invoker, "finishShowIssue", payload, error);
        });
    }

    #[qslot]
    fn clear_selection(&mut self) {
        if !self.selected_id.is_empty() {
            self.selected_id.clear();
            self.selected_id_changed();
        }
        if self.detail != json!({}) {
            self.detail = json!({});
            self.detail_changed();
        }
    }

    #[qslot]
    fn clear_error(&mut self) {
        self.set_error(String::new());
    }

    #[qslot]
    fn set_workspace(&mut self, input: String) {
        if self.loading {
            return;
        }

        match normalize_workspace(&input) {
            Ok(path) => {
                let workspace = path.to_string_lossy().into_owned();
                if self.workspace != workspace {
                    self.workspace = workspace;
                    self.workspace_changed();
                }
                self.reload();
            }
            Err(error) => self.set_error(error),
        }
    }

    #[qslot(qml_name = "finishReload")]
    fn finish_reload(&mut self, payload: String, error: String) {
        if error.is_empty() {
            match parse_issue_list(&payload) {
                Ok(issues) => {
                    self.issues = issues;
                    self.issues_changed();
                }
                Err(error) => self.set_error(error),
            }
        } else {
            self.set_error(error);
        }
        self.set_loading(false);
    }

    #[qslot(qml_name = "finishShowIssue")]
    fn finish_show_issue(&mut self, payload: String, error: String) {
        if error.is_empty() {
            match parse_issue_detail(&payload) {
                Ok(detail) => {
                    self.detail = detail;
                    self.detail_changed();
                }
                Err(error) => self.set_error(error),
            }
        } else {
            self.set_error(error);
        }
        self.set_loading(false);
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

fn normalize_workspace(input: &str) -> Result<PathBuf, String> {
    let path = if input.starts_with("file:") {
        Url::parse(input)
            .map_err(|error| format!("Invalid workspace URL: {error}"))?
            .to_file_path()
            .map_err(|_| "The selected URL is not a local folder".to_string())?
    } else {
        PathBuf::from(input)
    };

    let path = path
        .canonicalize()
        .map_err(|error| format!("Cannot open {}: {error}", path.display()))?;
    if !path.is_dir() {
        return Err(format!("{} is not a folder", path.display()));
    }
    Ok(path)
}

fn encode_result<T: Serialize, E: Display>(result: Result<T, E>) -> (String, String) {
    match result {
        Ok(value) => match serde_json::to_string(&value) {
            Ok(payload) => (payload, String::new()),
            Err(error) => (
                String::new(),
                format!("Could not encode bd result: {error}"),
            ),
        },
        Err(error) => (String::new(), error.to_string()),
    }
}

fn parse_issue_list(payload: &str) -> Result<Vec<Value>, String> {
    serde_json::from_str(payload).map_err(|error| format!("bd list returned invalid JSON: {error}"))
}

fn parse_issue_detail(payload: &str) -> Result<Value, String> {
    let mut issues: Vec<Value> = serde_json::from_str(payload)
        .map_err(|error| format!("bd show returned invalid JSON: {error}"))?;
    if issues.len() != 1 {
        return Err(format!(
            "bd show returned {} issues instead of one",
            issues.len()
        ));
    }
    Ok(issues.remove(0))
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
    fn accepts_file_urls_for_workspaces() {
        let path = normalize_workspace("file:///tmp").unwrap();
        assert_eq!(path, PathBuf::from("/tmp").canonicalize().unwrap());
    }
}
