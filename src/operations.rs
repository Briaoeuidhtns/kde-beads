// SPDX-License-Identifier: MIT

use std::fmt::Display;
use std::path::PathBuf;

use bd_client::{Client, Comment, Issue, IssueUpdate, LinkedIssue, NewIssue, Status};
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize)]
pub(crate) struct MutationResult {
    pub(crate) issue: Issue,
    pub(crate) issues: Vec<Issue>,
}

#[derive(Deserialize, Serialize)]
pub(crate) struct DeleteMutationResult {
    pub(crate) issues: Option<Vec<Issue>>,
    pub(crate) warning: String,
}

#[derive(Deserialize, Serialize)]
pub(crate) struct IssueDetail {
    #[serde(flatten)]
    pub(crate) issue: Issue,
    pub(crate) dependencies: Vec<LinkedIssue>,
    pub(crate) dependents: Vec<LinkedIssue>,
    pub(crate) comments: Vec<Comment>,
}

#[derive(Deserialize, Serialize)]
pub(crate) struct DetailMutationResult {
    pub(crate) detail: IssueDetail,
    pub(crate) issues: Vec<Issue>,
}

pub(crate) fn list_issues(workspace: String) -> Result<Vec<Issue>, bd_client::Error> {
    Client::new(workspace)?.list()
}

pub(crate) fn canonical_workspace(workspace: &str) -> Result<String, bd_client::Error> {
    Ok(Client::new(workspace)?
        .workspace()
        .to_string_lossy()
        .into_owned())
}

pub(crate) fn load_issue_detail(
    workspace: String,
    id: &str,
) -> Result<IssueDetail, bd_client::Error> {
    let client = Client::new(workspace)?;
    load_issue_detail_with_client(&client, id)
}

pub(crate) fn move_issue(
    workspace: String,
    id: &str,
    status: Status,
) -> Result<Issue, bd_client::Error> {
    Client::new(workspace)?.set_status(id, status)
}

pub(crate) fn update_issue(
    workspace: String,
    update: &IssueUpdate,
) -> Result<Issue, bd_client::Error> {
    Client::new(workspace)?.update(update)
}

pub(crate) fn create_issue_and_list(
    workspace: String,
    issue: &NewIssue,
) -> Result<MutationResult, bd_client::Error> {
    mutate_and_list(workspace, |client| client.create(issue))
}

pub(crate) fn add_todo_and_list(
    workspace: String,
    title: &str,
) -> Result<MutationResult, bd_client::Error> {
    mutate_and_list(workspace, |client| client.add_todo(title))
}

pub(crate) fn delete_issue_and_list(
    workspace: String,
    id: &str,
) -> Result<DeleteMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    let outcome = client.delete(id)?;
    let mut warnings = outcome.cleanup_warning.into_iter().collect::<Vec<_>>();
    let issues = match client.list() {
        Ok(issues) => Some(issues),
        Err(error) => {
            warnings.push(format!(
                "Bead {id} was deleted, but the board could not be refreshed: {error}"
            ));
            None
        }
    };
    Ok(DeleteMutationResult {
        issues,
        warning: warnings.join("\n"),
    })
}

pub(crate) fn add_attachment_to_issue(
    workspace: String,
    issue_id: &str,
    path: String,
) -> Result<Issue, bd_client::Error> {
    Client::new(workspace)?.add_attachment(issue_id, path)
}

pub(crate) fn remove_attachment_from_issue(
    workspace: String,
    issue_id: &str,
    attachment_id: &str,
) -> Result<Issue, bd_client::Error> {
    Client::new(workspace)?.remove_attachment(issue_id, attachment_id)
}

pub(crate) fn migrate_attachments(
    workspace: String,
    issue_id: &str,
) -> Result<Issue, bd_client::Error> {
    Client::new(workspace)?.migrate_polyfill_attachments(issue_id)
}

pub(crate) fn add_dependency_and_list(
    workspace: String,
    issue_id: &str,
    depends_on_id: &str,
    dependency_type: &str,
    detail_issue_id: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.add_dependency(issue_id, depends_on_id, dependency_type)?;
    let detail = load_issue_detail_with_client(&client, detail_issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

pub(crate) fn remove_dependency_and_list(
    workspace: String,
    issue_id: &str,
    depends_on_id: &str,
    detail_issue_id: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.remove_dependency(issue_id, depends_on_id)?;
    let detail = load_issue_detail_with_client(&client, detail_issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

pub(crate) fn create_gate_and_list(
    workspace: String,
    issue_id: &str,
    gate_type: &str,
    reason: &str,
    timeout: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.create_gate(issue_id, gate_type, reason, timeout)?;
    let detail = load_issue_detail_with_client(&client, issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

pub(crate) fn resolve_gate_and_list(
    workspace: String,
    issue_id: &str,
    gate_id: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.resolve_gate(gate_id, "Approved in Knecklace")?;
    let detail = load_issue_detail_with_client(&client, issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

pub(crate) fn remove_gate_and_list(
    workspace: String,
    issue_id: &str,
    gate_id: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.delete(gate_id)?;
    let detail = load_issue_detail_with_client(&client, issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

pub(crate) fn add_comment_and_list(
    workspace: String,
    issue_id: &str,
    text: &str,
) -> Result<DetailMutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    client.add_comment(issue_id, text)?;
    let detail = load_issue_detail_with_client(&client, issue_id)?;
    let issues = client.list()?;
    Ok(DetailMutationResult { detail, issues })
}

pub(crate) fn materialize_attachment(
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

pub(crate) fn add_attachments_to_issue(
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

fn mutate_and_list(
    workspace: String,
    mutate: impl FnOnce(&Client) -> Result<Issue, bd_client::Error>,
) -> Result<MutationResult, bd_client::Error> {
    let client = Client::new(workspace)?;
    let issue = mutate(&client)?;
    let issues = client.list()?;
    Ok(MutationResult { issue, issues })
}

fn load_issue_detail_with_client(
    client: &Client,
    id: &str,
) -> Result<IssueDetail, bd_client::Error> {
    Ok(IssueDetail {
        issue: client.show(id)?,
        dependencies: client.dependencies(id)?,
        dependents: client.dependents(id)?,
        comments: client.comments(id)?,
    })
}

pub(crate) fn encode_result<T: Serialize, E: Display>(result: Result<T, E>) -> (String, String) {
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
