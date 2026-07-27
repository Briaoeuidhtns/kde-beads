// SPDX-License-Identifier: MIT

use std::collections::HashMap;

use serde_json::{Map, Value};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum OptimisticKind {
    Move,
    Save,
}

#[derive(Clone)]
struct OptimisticUpdate {
    generation: u64,
    kind: OptimisticKind,
    patch: Map<String, Value>,
}

#[derive(Default)]
struct WorkspaceState {
    issues: Option<Vec<Value>>,
    error: String,
    error_generation: u64,
    latest_issue_generation: u64,
    refresh: Option<RefreshRequest>,
    pending_refresh_report_errors: Option<bool>,
    foreground_generation: Option<u64>,
    optimistic_updates: HashMap<String, Vec<OptimisticUpdate>>,
}

#[derive(Clone, Copy)]
struct RefreshRequest {
    generation: u64,
    report_errors: bool,
}

#[derive(Debug, PartialEq)]
pub(crate) struct WorkspaceView {
    pub(crate) issues: Vec<Value>,
    pub(crate) cached: bool,
    pub(crate) error: String,
    pub(crate) loading: bool,
    pub(crate) refreshing: bool,
}

#[derive(Default)]
pub(crate) struct WorkspaceCache {
    states: HashMap<String, WorkspaceState>,
    next_generation: u64,
}

impl WorkspaceCache {
    pub(crate) fn allocate_generation(&mut self) -> u64 {
        self.next_generation = self.next_generation.checked_add(1).unwrap_or(1);
        self.next_generation
    }

    pub(crate) fn begin_refresh(&mut self, workspace: &str, report_errors: bool) -> Option<u64> {
        let state = self.states.entry(workspace.to_string()).or_default();
        if let Some(refresh) = state.refresh {
            if report_errors && !refresh.report_errors {
                state.pending_refresh_report_errors = Some(true);
            }
            return None;
        }
        if state.foreground_generation.is_some() {
            state.pending_refresh_report_errors =
                Some(state.pending_refresh_report_errors.unwrap_or(false) || report_errors);
            return None;
        }

        let generation = self.allocate_generation();
        let state = self.states.entry(workspace.to_string()).or_default();
        state.latest_issue_generation = generation;
        state.refresh = Some(RefreshRequest {
            generation,
            report_errors,
        });
        Some(generation)
    }

    pub(crate) fn refresh_reports_errors(&self, workspace: &str, generation: u64) -> Option<bool> {
        self.states
            .get(workspace)?
            .refresh
            .filter(|request| request.generation == generation)
            .map(|request| request.report_errors)
    }

    pub(crate) fn finish_refresh(&mut self, workspace: &str, generation: u64) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if state.refresh.map(|request| request.generation) != Some(generation) {
            return false;
        }
        state.refresh = None;
        true
    }

    pub(crate) fn take_pending_refresh(&mut self, workspace: &str) -> Option<bool> {
        let state = self.states.get_mut(workspace)?;
        if state.refresh.is_some() || state.foreground_generation.is_some() {
            return None;
        }
        state.pending_refresh_report_errors.take()
    }

    pub(crate) fn begin_foreground(
        &mut self,
        workspace: &str,
        updates_issues: bool,
    ) -> Option<u64> {
        let state = self.states.get(workspace);
        if state.is_some_and(|state| {
            state.foreground_generation.is_some()
                || (state.issues.is_none() && state.refresh.is_some())
        }) {
            return None;
        }

        let generation = self.allocate_generation();
        let state = self.states.entry(workspace.to_string()).or_default();
        state.foreground_generation = Some(generation);
        state.error_generation = generation;
        state.error.clear();
        if updates_issues {
            state.latest_issue_generation = generation;
            state.refresh = None;
        }
        Some(generation)
    }

    pub(crate) fn foreground_is_current(&self, workspace: &str, generation: u64) -> bool {
        self.states
            .get(workspace)
            .is_some_and(|state| state.foreground_generation == Some(generation))
    }

    pub(crate) fn finish_foreground(&mut self, workspace: &str, generation: u64) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if state.foreground_generation != Some(generation) {
            return false;
        }
        state.foreground_generation = None;
        true
    }

    pub(crate) fn apply_snapshot(
        &mut self,
        workspace: &str,
        generation: u64,
        issues: Vec<Value>,
    ) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if state.latest_issue_generation != generation {
            return false;
        }
        if state.optimistic_updates.is_empty() || state.issues.is_none() {
            state.issues = Some(issues);
            return true;
        }

        let mut existing_by_id: HashMap<String, Value> = state
            .issues
            .take()
            .unwrap_or_default()
            .into_iter()
            .filter_map(|issue| {
                let id = issue.get("id")?.as_str()?.to_string();
                Some((id, issue))
            })
            .collect();
        let mut merged = Vec::with_capacity(issues.len() + existing_by_id.len());
        for issue in issues {
            let id = issue.get("id").and_then(Value::as_str);
            if let Some(existing) = id
                .filter(|id| state.optimistic_updates.contains_key(*id))
                .and_then(|id| existing_by_id.remove(id))
            {
                merged.push(existing);
            } else {
                merged.push(issue);
            }
        }
        for (id, issue) in existing_by_id {
            if state.optimistic_updates.contains_key(&id) {
                merged.push(issue);
            }
        }
        state.issues = Some(merged);
        true
    }

    pub(crate) fn begin_optimistic_update(
        &mut self,
        workspace: &str,
        issue_id: &str,
        generation: u64,
        kind: OptimisticKind,
        patch: Map<String, Value>,
    ) -> bool {
        let state = self.states.entry(workspace.to_string()).or_default();
        if !state.issues.as_ref().is_some_and(|issues| {
            issues
                .iter()
                .any(|issue| issue.get("id").and_then(Value::as_str) == Some(issue_id))
        }) {
            return false;
        }
        state
            .optimistic_updates
            .entry(issue_id.to_string())
            .or_default()
            .push(OptimisticUpdate {
                generation,
                kind,
                patch,
            });
        true
    }

    pub(crate) fn commit_optimistic_update(
        &mut self,
        workspace: &str,
        issue_id: &str,
        generation: u64,
        mut updated: Value,
    ) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if !has_optimistic_generation(state, issue_id, generation) {
            return false;
        }
        let Some(issues) = state.issues.as_mut() else {
            return false;
        };
        let Some(issue) = issues
            .iter_mut()
            .find(|issue| issue.get("id").and_then(Value::as_str) == Some(issue_id))
        else {
            return false;
        };
        preserve_derived_fields(issue, &mut updated);
        *issue = updated;
        invalidate_refresh(state, generation);
        remove_optimistic_generation(state, issue_id, generation)
    }

    pub(crate) fn fail_optimistic_update(
        &mut self,
        workspace: &str,
        issue_id: &str,
        generation: u64,
    ) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if !has_optimistic_generation(state, issue_id, generation) {
            return false;
        }
        invalidate_refresh(state, generation);
        remove_optimistic_generation(state, issue_id, generation)
    }

    pub(crate) fn projected_issue(&self, workspace: &str, issue_id: &str) -> Option<Value> {
        let state = self.states.get(workspace)?;
        let issue = state
            .issues
            .as_ref()?
            .iter()
            .find(|issue| issue.get("id").and_then(Value::as_str) == Some(issue_id))?;
        Some(project_issue(
            issue.clone(),
            state.optimistic_updates.get(issue_id),
        ))
    }

    pub(crate) fn apply_issue_update(
        &mut self,
        workspace: &str,
        generation: u64,
        mut updated: Value,
    ) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if state.latest_issue_generation != generation {
            return false;
        }
        let Some(updated_id) = updated.get("id").and_then(Value::as_str) else {
            return false;
        };
        let Some(issues) = state.issues.as_mut() else {
            return false;
        };
        let Some(issue) = issues
            .iter_mut()
            .find(|issue| issue.get("id").and_then(Value::as_str) == Some(updated_id))
        else {
            return false;
        };

        if let (Some(is_blocked), Some(updated)) =
            (issue.get("is_blocked").cloned(), updated.as_object_mut())
        {
            updated.insert("is_blocked".to_string(), is_blocked);
        }
        *issue = updated;
        true
    }

    pub(crate) fn apply_created_issue(
        &mut self,
        workspace: &str,
        generation: u64,
        issue: Value,
    ) -> bool {
        let Some(state) = self.states.get_mut(workspace) else {
            return false;
        };
        if state.latest_issue_generation != generation {
            return false;
        }
        let Some(issue_id) = issue.get("id").and_then(Value::as_str) else {
            return false;
        };
        let Some(issues) = state.issues.as_mut() else {
            state.issues = Some(vec![issue]);
            return true;
        };
        if let Some(existing) = issues
            .iter_mut()
            .find(|existing| existing.get("id").and_then(Value::as_str) == Some(issue_id))
        {
            *existing = issue;
        } else {
            issues.push(issue);
        }
        true
    }

    pub(crate) fn set_error(&mut self, workspace: &str, generation: u64, error: String) -> bool {
        let state = self.states.entry(workspace.to_string()).or_default();
        if generation < state.error_generation {
            return false;
        }
        state.error_generation = generation;
        state.error = error;
        true
    }

    pub(crate) fn view(&self, workspace: &str) -> WorkspaceView {
        let Some(state) = self.states.get(workspace) else {
            return WorkspaceView {
                issues: Vec::new(),
                cached: false,
                error: String::new(),
                loading: false,
                refreshing: false,
            };
        };
        let issues = state
            .issues
            .clone()
            .unwrap_or_default()
            .into_iter()
            .map(|issue| {
                let updates = issue
                    .get("id")
                    .and_then(Value::as_str)
                    .and_then(|id| state.optimistic_updates.get(id));
                project_issue(issue, updates)
            })
            .collect();
        WorkspaceView {
            issues,
            cached: state.issues.is_some(),
            error: state.error.clone(),
            loading: state.foreground_generation.is_some()
                || (state.issues.is_none() && state.refresh.is_some()),
            refreshing: state.refresh.is_some(),
        }
    }
}

fn has_optimistic_generation(state: &WorkspaceState, issue_id: &str, generation: u64) -> bool {
    state
        .optimistic_updates
        .get(issue_id)
        .is_some_and(|updates| updates.iter().any(|update| update.generation == generation))
}

fn remove_optimistic_generation(
    state: &mut WorkspaceState,
    issue_id: &str,
    generation: u64,
) -> bool {
    let Some(updates) = state.optimistic_updates.get_mut(issue_id) else {
        return false;
    };
    let Some(index) = updates
        .iter()
        .position(|update| update.generation == generation)
    else {
        return false;
    };
    updates.remove(index);
    if updates.is_empty() {
        state.optimistic_updates.remove(issue_id);
    }
    true
}

fn preserve_derived_fields(current: &Value, updated: &mut Value) {
    let Some(updated) = updated.as_object_mut() else {
        return;
    };
    for field in ["is_blocked", "blocked_by_gate"] {
        if let Some(value) = current.get(field) {
            updated.insert(field.to_string(), value.clone());
        }
    }
}

fn invalidate_refresh(state: &mut WorkspaceState, generation: u64) {
    if let Some(refresh) = state.refresh.take() {
        state.pending_refresh_report_errors =
            Some(state.pending_refresh_report_errors.unwrap_or(false) || refresh.report_errors);
    }
    state.latest_issue_generation = generation;
}

fn project_issue(mut issue: Value, updates: Option<&Vec<OptimisticUpdate>>) -> Value {
    let Some(updates) = updates.filter(|updates| !updates.is_empty()) else {
        return issue;
    };
    let Some(object) = issue.as_object_mut() else {
        return issue;
    };
    for update in updates {
        object.extend(update.patch.clone());
    }
    object.insert("_pending".to_string(), Value::Bool(true));
    object.insert(
        "_pending_move".to_string(),
        Value::Bool(
            updates
                .iter()
                .any(|update| update.kind == OptimisticKind::Move),
        ),
    );
    object.insert(
        "_pending_save".to_string(),
        Value::Bool(
            updates
                .iter()
                .any(|update| update.kind == OptimisticKind::Save),
        ),
    );
    issue
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn issue(id: &str) -> Value {
        json!({"id": id})
    }

    fn store(cache: &mut WorkspaceCache, workspace: &str, issues: Vec<Value>) {
        let generation = cache.begin_refresh(workspace, true).unwrap();
        assert!(cache.apply_snapshot(workspace, generation, issues));
        assert!(cache.finish_refresh(workspace, generation));
    }

    fn patch(fields: Value) -> Map<String, Value> {
        fields.as_object().unwrap().clone()
    }

    #[test]
    fn distinguishes_uncached_loading_from_cached_revalidation() {
        let mut cache = WorkspaceCache::default();
        let generation = cache.begin_refresh("/one", true).unwrap();

        assert_eq!(
            cache.view("/one"),
            WorkspaceView {
                issues: Vec::new(),
                cached: false,
                error: String::new(),
                loading: true,
                refreshing: true,
            }
        );

        assert!(cache.apply_snapshot("/one", generation, Vec::new()));
        assert!(cache.finish_refresh("/one", generation));
        assert!(cache.view("/one").cached);

        cache.begin_refresh("/one", true).unwrap();
        let view = cache.view("/one");
        assert!(!view.loading);
        assert!(view.refreshing);
    }

    #[test]
    fn isolates_workspace_snapshots_and_errors() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        store(&mut cache, "/two", vec![issue("two")]);
        let generation = cache.allocate_generation();
        cache.set_error("/one", generation, "one failed".to_string());

        assert_eq!(cache.view("/one").issues, vec![issue("one")]);
        assert_eq!(cache.view("/one").error, "one failed");
        assert_eq!(cache.view("/two").issues, vec![issue("two")]);
        assert_eq!(cache.view("/two").error, "");
    }

    #[test]
    fn newer_mutation_supersedes_an_older_refresh() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("original")]);
        let refresh = cache.begin_refresh("/one", true).unwrap();
        let mutation = cache.begin_foreground("/one", true).unwrap();

        assert!(!cache.apply_snapshot("/one", refresh, vec![issue("stale")]));
        assert!(!cache.finish_refresh("/one", refresh));
        assert!(cache.apply_snapshot("/one", mutation, vec![issue("after-mutation")]));
        assert!(cache.finish_foreground("/one", mutation));
        assert_eq!(cache.view("/one").issues, vec![issue("after-mutation")]);
    }

    #[test]
    fn stale_completion_cannot_clear_a_newer_request() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        let old = cache.begin_refresh("/one", true).unwrap();
        let current = cache.begin_foreground("/one", true).unwrap();

        assert!(!cache.finish_refresh("/one", old));
        assert!(cache.view("/one").loading);
        assert!(!cache.finish_foreground("/one", old));
        assert!(cache.finish_foreground("/one", current));
        assert!(!cache.view("/one").loading);
    }

    #[test]
    fn failed_revalidation_preserves_cached_issues() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        let refresh = cache.begin_refresh("/one", true).unwrap();
        cache.set_error("/one", refresh, "refresh failed".to_string());
        assert!(cache.finish_refresh("/one", refresh));

        let view = cache.view("/one");
        assert_eq!(view.issues, vec![issue("one")]);
        assert_eq!(view.error, "refresh failed");
        assert!(!view.loading);
        assert!(!view.refreshing);
    }

    #[test]
    fn refresh_completion_does_not_clear_a_foreground_error() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        let refresh = cache.begin_refresh("/one", true).unwrap();
        let foreground = cache.begin_foreground("/one", false).unwrap();
        cache.set_error("/one", foreground, "detail failed".to_string());
        assert!(cache.finish_foreground("/one", foreground));

        assert!(cache.apply_snapshot("/one", refresh, vec![issue("refreshed")]));
        assert!(cache.finish_refresh("/one", refresh));
        assert_eq!(cache.view("/one").error, "detail failed");
    }

    #[test]
    fn older_refresh_error_cannot_replace_a_newer_foreground_error() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        let refresh = cache.begin_refresh("/one", true).unwrap();
        let foreground = cache.begin_foreground("/one", false).unwrap();
        assert!(cache.set_error("/one", foreground, "detail failed".to_string()));
        assert!(cache.finish_foreground("/one", foreground));

        assert!(!cache.set_error("/one", refresh, "refresh failed".to_string()));
        assert!(cache.finish_refresh("/one", refresh));
        assert_eq!(cache.view("/one").error, "detail failed");
    }

    #[test]
    fn issue_updates_preserve_derived_blocking() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({"id": "one", "is_blocked": true, "attachments": []})],
        );
        let generation = cache.begin_foreground("/one", true).unwrap();

        assert!(cache.apply_issue_update(
            "/one",
            generation,
            json!({"id": "one", "is_blocked": false, "attachments": ["new"]})
        ));
        assert!(cache.finish_foreground("/one", generation));
        assert_eq!(
            cache.view("/one").issues,
            vec![json!({
                "id": "one",
                "is_blocked": true,
                "attachments": ["new"]
            })]
        );
    }

    #[test]
    fn partial_mutation_keeps_the_update_and_reports_its_error() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({"id": "one", "attachments": []})],
        );
        let generation = cache.begin_foreground("/one", true).unwrap();

        assert!(cache.apply_issue_update(
            "/one",
            generation,
            json!({"id": "one", "attachments": ["added"]})
        ));
        assert!(cache.set_error("/one", generation, "one file failed".to_string()));
        assert!(cache.finish_foreground("/one", generation));

        let view = cache.view("/one");
        assert_eq!(
            view.issues,
            vec![json!({"id": "one", "attachments": ["added"]})]
        );
        assert_eq!(view.error, "one file failed");
    }

    #[test]
    fn successful_create_can_be_applied_when_the_followup_list_fails() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("existing")]);
        let generation = cache.begin_foreground("/one", true).unwrap();

        assert!(cache.apply_created_issue(
            "/one",
            generation,
            json!({"id": "created", "status": "open"}),
        ));
        assert!(cache.finish_foreground("/one", generation));

        assert_eq!(
            cache.view("/one").issues,
            vec![
                issue("existing"),
                json!({"id": "created", "status": "open"})
            ]
        );
    }

    #[test]
    fn refresh_waits_for_an_active_foreground_request() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        let foreground = cache.begin_foreground("/one", false).unwrap();

        assert_eq!(cache.begin_refresh("/one", true), None);
        assert_eq!(cache.take_pending_refresh("/one"), None);
        assert!(cache.set_error("/one", foreground, "foreground failed".to_string()));
        assert!(cache.finish_foreground("/one", foreground));
        assert_eq!(cache.take_pending_refresh("/one"), Some(true));
        let refresh = cache.begin_refresh("/one", true).unwrap();
        assert_eq!(cache.view("/one").error, "foreground failed");
        assert!(cache.apply_snapshot("/one", refresh, vec![issue("refreshed")]));
        assert!(cache.set_error("/one", refresh, String::new()));
        assert!(cache.finish_refresh("/one", refresh));
        assert_eq!(cache.view("/one").error, "");
    }

    #[test]
    fn explicit_refresh_waits_for_an_active_silent_poll() {
        let mut cache = WorkspaceCache::default();
        store(&mut cache, "/one", vec![issue("one")]);
        let poll = cache.begin_refresh("/one", false).unwrap();

        assert_eq!(cache.begin_refresh("/one", true), None);
        assert!(cache.finish_refresh("/one", poll));
        assert_eq!(cache.take_pending_refresh("/one"), Some(true));
        assert!(cache.begin_refresh("/one", true).is_some());
    }

    #[test]
    fn optimistic_move_changes_projection_and_rolls_back() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({"id": "one", "status": "open"})],
        );
        let generation = cache.allocate_generation();

        assert!(cache.begin_optimistic_update(
            "/one",
            "one",
            generation,
            OptimisticKind::Move,
            patch(json!({"status": "in_progress"})),
        ));
        assert_eq!(
            cache.view("/one").issues,
            vec![json!({
                "id": "one",
                "status": "in_progress",
                "_pending": true,
                "_pending_move": true,
                "_pending_save": false
            })]
        );
        assert!(cache.fail_optimistic_update("/one", "one", generation));
        assert_eq!(
            cache.view("/one").issues,
            vec![json!({"id": "one", "status": "open"})]
        );
    }

    #[test]
    fn refresh_updates_other_issues_but_freezes_a_pending_issue() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![
                json!({"id": "one", "status": "open", "title": "original"}),
                json!({"id": "two", "status": "open", "title": "original"}),
            ],
        );
        let mutation = cache.allocate_generation();
        assert!(cache.begin_optimistic_update(
            "/one",
            "one",
            mutation,
            OptimisticKind::Move,
            patch(json!({"status": "in_progress"})),
        ));
        let refresh = cache.begin_refresh("/one", false).unwrap();
        assert!(cache.apply_snapshot(
            "/one",
            refresh,
            vec![
                json!({"id": "one", "status": "open", "title": "stale"}),
                json!({"id": "two", "status": "open", "title": "refreshed"}),
            ],
        ));
        assert!(cache.finish_refresh("/one", refresh));

        let issues = cache.view("/one").issues;
        assert_eq!(issues[0]["title"], "original");
        assert_eq!(issues[0]["status"], "in_progress");
        assert_eq!(issues[1]["title"], "refreshed");
    }

    #[test]
    fn mutation_completion_invalidates_a_stale_in_flight_refresh() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({"id": "one", "status": "open"})],
        );
        let mutation = cache.allocate_generation();
        assert!(cache.begin_optimistic_update(
            "/one",
            "one",
            mutation,
            OptimisticKind::Move,
            patch(json!({"status": "in_progress"})),
        ));
        let refresh = cache.begin_refresh("/one", false).unwrap();

        assert!(cache.commit_optimistic_update(
            "/one",
            "one",
            mutation,
            json!({"id": "one", "status": "in_progress"}),
        ));
        assert!(!cache.apply_snapshot(
            "/one",
            refresh,
            vec![json!({"id": "one", "status": "open"})],
        ));
        assert!(!cache.finish_refresh("/one", refresh));
        assert_eq!(
            cache.projected_issue("/one", "one").unwrap()["status"],
            "in_progress"
        );
    }

    #[test]
    fn older_success_and_newer_failure_reveal_the_committed_value() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({"id": "one", "status": "open"})],
        );
        let first = cache.allocate_generation();
        let second = cache.allocate_generation();
        assert!(cache.begin_optimistic_update(
            "/one",
            "one",
            first,
            OptimisticKind::Move,
            patch(json!({"status": "in_progress"})),
        ));
        assert!(cache.begin_optimistic_update(
            "/one",
            "one",
            second,
            OptimisticKind::Move,
            patch(json!({"status": "closed"})),
        ));

        assert!(cache.commit_optimistic_update(
            "/one",
            "one",
            first,
            json!({"id": "one", "status": "in_progress"}),
        ));
        let projected = cache.projected_issue("/one", "one").unwrap();
        assert_eq!(projected["status"], "closed");
        assert_eq!(projected["_pending"], true);

        assert!(cache.fail_optimistic_update("/one", "one", second));
        assert_eq!(
            cache.projected_issue("/one", "one").unwrap(),
            json!({"id": "one", "status": "in_progress"})
        );
    }

    #[test]
    fn optimistic_updates_are_isolated_by_workspace() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({"id": "same", "status": "open"})],
        );
        store(
            &mut cache,
            "/two",
            vec![json!({"id": "same", "status": "open"})],
        );
        let generation = cache.allocate_generation();
        assert!(cache.begin_optimistic_update(
            "/one",
            "same",
            generation,
            OptimisticKind::Move,
            patch(json!({"status": "closed"})),
        ));

        assert_eq!(
            cache.projected_issue("/one", "same").unwrap()["status"],
            "closed"
        );
        assert_eq!(
            cache.projected_issue("/two", "same").unwrap(),
            json!({"id": "same", "status": "open"})
        );
    }

    #[test]
    fn completion_is_generation_specific_and_preserves_derived_fields() {
        let mut cache = WorkspaceCache::default();
        store(
            &mut cache,
            "/one",
            vec![json!({
                "id": "one",
                "status": "open",
                "is_blocked": true,
                "blocked_by_gate": true
            })],
        );
        let generation = cache.allocate_generation();
        assert!(cache.begin_optimistic_update(
            "/one",
            "one",
            generation,
            OptimisticKind::Save,
            patch(json!({"title": "updated"})),
        ));

        assert!(!cache.fail_optimistic_update("/one", "one", generation + 1));
        assert!(cache.commit_optimistic_update(
            "/one",
            "one",
            generation,
            json!({"id": "one", "status": "open", "title": "updated"}),
        ));
        assert!(!cache.fail_optimistic_update("/one", "one", generation));
        assert_eq!(
            cache.projected_issue("/one", "one").unwrap(),
            json!({
                "id": "one",
                "status": "open",
                "title": "updated",
                "is_blocked": true,
                "blocked_by_gate": true
            })
        );
    }
}
