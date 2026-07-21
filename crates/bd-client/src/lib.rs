// SPDX-License-Identifier: MIT

use std::ffi::{OsStr, OsString};
use std::fmt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Issue {
    pub id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub acceptance_criteria: String,
    #[serde(default)]
    pub design: String,
    #[serde(default)]
    pub notes: String,
    pub status: Status,
    #[serde(default = "default_priority")]
    pub priority: u8,
    #[serde(default = "default_issue_type")]
    pub issue_type: String,
    #[serde(default)]
    pub assignee: String,
    #[serde(default)]
    pub owner: String,
    #[serde(default)]
    pub labels: Vec<String>,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub closed_at: String,
    #[serde(default)]
    pub close_reason: String,
    #[serde(default)]
    pub dependency_count: u64,
    #[serde(default)]
    pub dependent_count: u64,
    #[serde(default)]
    pub comment_count: u64,
}

fn default_priority() -> u8 {
    2
}

fn default_issue_type() -> String {
    "task".to_string()
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Open,
    InProgress,
    Blocked,
    Deferred,
    Closed,
}

impl Status {
    pub const ALL: [Self; 5] = [
        Self::Open,
        Self::InProgress,
        Self::Blocked,
        Self::Deferred,
        Self::Closed,
    ];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Open => "open",
            Self::InProgress => "in_progress",
            Self::Blocked => "blocked",
            Self::Deferred => "deferred",
            Self::Closed => "closed",
        }
    }
}

impl fmt::Display for Status {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for Status {
    type Err = Error;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "open" => Ok(Self::Open),
            "in_progress" => Ok(Self::InProgress),
            "blocked" => Ok(Self::Blocked),
            "deferred" => Ok(Self::Deferred),
            "closed" => Ok(Self::Closed),
            _ => Err(Error::InvalidStatus(value.to_string())),
        }
    }
}

#[derive(Clone, Debug)]
pub struct IssueUpdate {
    pub id: String,
    pub title: String,
    pub description: String,
    pub acceptance_criteria: String,
    pub design: String,
    pub notes: String,
    pub status: Status,
    pub priority: u8,
    pub issue_type: String,
    pub assignee: String,
    pub labels: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct Client {
    workspace: PathBuf,
    binary: OsString,
}

impl Client {
    pub fn new(workspace: impl AsRef<Path>) -> Result<Self, Error> {
        Self::with_binary(workspace, "bd")
    }

    pub fn with_binary(
        workspace: impl AsRef<Path>,
        binary: impl AsRef<OsStr>,
    ) -> Result<Self, Error> {
        let workspace =
            workspace
                .as_ref()
                .canonicalize()
                .map_err(|source| Error::InvalidWorkspace {
                    path: workspace.as_ref().to_path_buf(),
                    source,
                })?;
        if !workspace.is_dir() {
            return Err(Error::WorkspaceIsNotDirectory(workspace));
        }
        Ok(Self {
            workspace,
            binary: binary.as_ref().to_os_string(),
        })
    }

    pub fn workspace(&self) -> &Path {
        &self.workspace
    }

    pub fn list(&self) -> Result<Vec<Issue>, Error> {
        let payload = self.run(true, &["list", "--json", "--all", "--limit", "0"])?;
        serde_json::from_str(&payload).map_err(|source| Error::InvalidJson {
            operation: "list",
            source,
        })
    }

    pub fn show(&self, id: &str) -> Result<Issue, Error> {
        let payload = self.run(true, &["show", id, "--json"])?;
        parse_single_issue("show", &payload)
    }

    pub fn set_status(&self, id: &str, status: Status) -> Result<Issue, Error> {
        let payload = self.run(
            false,
            &["update", id, "--status", status.as_str(), "--json"],
        )?;
        parse_single_issue("update", &payload)
    }

    pub fn update(&self, update: &IssueUpdate) -> Result<Issue, Error> {
        let priority = update.priority.to_string();
        let labels = update.labels.join(",");
        let args = [
            "update",
            update.id.as_str(),
            "--title",
            update.title.as_str(),
            "--description",
            update.description.as_str(),
            "--allow-empty-description",
            "--acceptance",
            update.acceptance_criteria.as_str(),
            "--design",
            update.design.as_str(),
            "--notes",
            update.notes.as_str(),
            "--status",
            update.status.as_str(),
            "--priority",
            priority.as_str(),
            "--type",
            update.issue_type.as_str(),
            "--assignee",
            update.assignee.as_str(),
            "--set-labels",
            labels.as_str(),
            "--json",
        ];
        let payload = self.run(false, &args)?;
        parse_single_issue("update", &payload)
    }

    fn run(&self, readonly: bool, args: &[&str]) -> Result<String, Error> {
        let mut command = Command::new(&self.binary);
        if readonly {
            command.arg("--readonly");
        }
        let output = command
            .args(args)
            .current_dir(&self.workspace)
            .output()
            .map_err(|source| Error::Start {
                binary: self.binary.clone(),
                source,
            })?;

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if output.status.success() {
            return Ok(stdout);
        }

        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let message = if stderr.is_empty() { stdout } else { stderr };
        Err(Error::Command {
            operation: args.first().copied().unwrap_or("command").to_string(),
            status: output.status.code(),
            message,
        })
    }
}

fn parse_single_issue(operation: &'static str, payload: &str) -> Result<Issue, Error> {
    let mut issues: Vec<Issue> =
        serde_json::from_str(payload).map_err(|source| Error::InvalidJson { operation, source })?;
    if issues.len() != 1 {
        return Err(Error::UnexpectedIssueCount {
            operation,
            count: issues.len(),
        });
    }
    Ok(issues.remove(0))
}

#[derive(Debug)]
pub enum Error {
    InvalidWorkspace {
        path: PathBuf,
        source: std::io::Error,
    },
    WorkspaceIsNotDirectory(PathBuf),
    InvalidStatus(String),
    Start {
        binary: OsString,
        source: std::io::Error,
    },
    Command {
        operation: String,
        status: Option<i32>,
        message: String,
    },
    InvalidJson {
        operation: &'static str,
        source: serde_json::Error,
    },
    UnexpectedIssueCount {
        operation: &'static str,
        count: usize,
    },
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidWorkspace { path, source } => {
                write!(formatter, "cannot open {}: {source}", path.display())
            }
            Self::WorkspaceIsNotDirectory(path) => {
                write!(formatter, "{} is not a directory", path.display())
            }
            Self::InvalidStatus(status) => write!(formatter, "unknown bead status: {status}"),
            Self::Start { binary, source } => {
                write!(
                    formatter,
                    "could not start {}: {source}",
                    binary.to_string_lossy()
                )
            }
            Self::Command {
                operation,
                status,
                message,
            } => {
                let status = status
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "signal".to_string());
                if message.is_empty() {
                    write!(formatter, "bd {operation} failed with status {status}")
                } else {
                    write!(formatter, "bd {operation} failed: {message}")
                }
            }
            Self::InvalidJson { operation, source } => {
                write!(formatter, "bd {operation} returned invalid JSON: {source}")
            }
            Self::UnexpectedIssueCount { operation, count } => {
                write!(
                    formatter,
                    "bd {operation} returned {count} issues instead of one"
                )
            }
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidWorkspace { source, .. } | Self::Start { source, .. } => Some(source),
            Self::InvalidJson { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ISSUE: &str = r#"{
        "id": "bd-1",
        "title": "First",
        "status": "in_progress",
        "priority": 1,
        "issue_type": "feature",
        "labels": ["kde", "rust"]
    }"#;

    #[test]
    fn parses_issue_list() {
        let issues: Vec<Issue> = serde_json::from_str(&format!("[{ISSUE}]")).unwrap();
        assert_eq!(issues.len(), 1);
        assert_eq!(issues[0].status, Status::InProgress);
        assert_eq!(issues[0].description, "");
    }

    #[test]
    fn parses_single_issue() {
        let issue = parse_single_issue("show", &format!("[{ISSUE}]")).unwrap();
        assert_eq!(issue.id, "bd-1");
        assert_eq!(issue.labels, ["kde", "rust"]);
    }

    #[test]
    fn rejects_unexpected_single_issue_shape() {
        let error = parse_single_issue("show", "[]").unwrap_err();
        assert!(matches!(
            error,
            Error::UnexpectedIssueCount {
                operation: "show",
                count: 0
            }
        ));
    }

    #[test]
    fn validates_status_names() {
        assert_eq!(Status::from_str("closed").unwrap(), Status::Closed);
        assert!(Status::from_str("unknown").is_err());
    }
}
