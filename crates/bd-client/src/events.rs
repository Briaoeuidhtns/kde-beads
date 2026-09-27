// SPDX-License-Identifier: MIT

use std::io::{BufRead, BufReader, Read};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{Client, Error, Issue};

/// A committed mutation in the workspace-local Beads journal.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct EventRecord {
    pub seq: u64,
    pub op: String,
    pub issue_id: String,
    #[serde(default)]
    pub issue: Option<Issue>,
    #[serde(default)]
    pub dep: Option<DependencyChange>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct DependencyChange {
    pub kind: String,
    pub target: String,
    #[serde(default)]
    pub metadata: Option<Value>,
}

/// A streaming `bd events tail` process. Dropping it terminates its child.
///
/// `next_event` blocks while `--follow` waits for another committed mutation.
/// A `None` result means the child exited successfully (normally only for a
/// non-following tail). A new tail can replace this transport without changing
/// the event records consumed by callers.
pub struct EventTail {
    child: Arc<Mutex<Child>>,
    stdout: BufReader<ChildStdout>,
}

/// A cloneable handle for interrupting a blocked journal read from another thread.
#[derive(Clone)]
pub struct EventStopHandle(Arc<Mutex<Child>>);

impl EventStopHandle {
    pub fn stop(&self) -> std::io::Result<()> {
        let mut child = self.0.lock().expect("events child mutex poisoned");
        match child.try_wait()? {
            Some(_) => Ok(()),
            None => child.kill(),
        }
    }
}

impl Client {
    /// Start following mutations after `since`, including those committed while
    /// the initial snapshot is being read. Errors emitted by bd are returned by
    /// `next_event` when the process exits.
    pub fn events_tail(&self, since: u64) -> Result<EventTail, Error> {
        self.spawn_events(since, true)
    }

    /// Acquire a journal checkpoint before reading an initial snapshot. Start
    /// `events_tail(head)` after the snapshot to replay intervening mutations.
    /// A pruned journal reports its current head in the truncation error, so no
    /// old rows need to be read in that case.
    pub fn events_head(&self) -> Result<u64, Error> {
        let mut tail = self.spawn_events(0, false)?;
        let mut head = 0;
        loop {
            match tail.next_event() {
                Ok(Some(record)) => head = record.seq,
                Ok(None) => return Ok(head),
                Err(Error::EventsTruncated { head, .. }) => return Ok(head),
                Err(error) => return Err(error),
            }
        }
    }

    fn spawn_events(&self, since: u64, follow: bool) -> Result<EventTail, Error> {
        let mut command = Command::new(&self.binary);
        command.args(["--readonly", "--json", "events", "tail", "--since"]);
        command.arg(since.to_string());
        if follow {
            command.arg("--follow");
        }
        let mut child = command
            .current_dir(&self.workspace)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|source| Error::Start {
                binary: self.binary.clone(),
                source,
            })?;
        let stdout = BufReader::new(child.stdout.take().expect("piped events stdout"));
        Ok(EventTail {
            child: Arc::new(Mutex::new(child)),
            stdout,
        })
    }
}

impl EventTail {
    pub fn stop_handle(&self) -> EventStopHandle {
        EventStopHandle(Arc::clone(&self.child))
    }

    pub fn next_event(&mut self) -> Result<Option<EventRecord>, Error> {
        let mut line = String::new();
        let count = self.stdout.read_line(&mut line).map_err(Error::EventIo)?;
        if count != 0 {
            return match serde_json::from_str(&line) {
                Ok(record) => Ok(Some(record)),
                Err(source) => match event_failure(None, &line) {
                    error @ (Error::EventsDisabled | Error::EventsTruncated { .. }) => Err(error),
                    _ => Err(Error::InvalidJson {
                        operation: "events tail",
                        source,
                    }),
                },
            };
        }
        let mut child = self.child.lock().expect("events child mutex poisoned");
        let status = child.wait().map_err(Error::EventIo)?;
        let mut stderr = String::new();
        if let Some(mut stream) = child.stderr.take() {
            stream.read_to_string(&mut stderr).map_err(Error::EventIo)?;
        }
        if stderr.contains("events journal is disabled") {
            return Err(Error::EventsDisabled);
        }
        if status.success() {
            return Ok(None);
        }
        Err(event_failure(status.code(), &stderr))
    }
}

impl Drop for EventTail {
    fn drop(&mut self) {
        let _ = self.stop_handle().stop();
        let _ = self
            .child
            .lock()
            .expect("events child mutex poisoned")
            .wait();
    }
}

fn event_failure(status: Option<i32>, stderr: &str) -> Error {
    // Cobra may prefix a structured JSON error with "Error: ".
    for line in stderr.lines().rev() {
        let json = line
            .get(line.find('{').unwrap_or(line.len())..)
            .unwrap_or("");
        if let Ok(value) = serde_json::from_str::<Value>(json) {
            match value.get("code").and_then(Value::as_str) {
                Some("events_journal_disabled") => return Error::EventsDisabled,
                Some("events_journal_truncated") => {
                    if let (Some(since), Some(floor), Some(head)) = (
                        value.get("since").and_then(Value::as_u64),
                        value.get("floor").and_then(Value::as_u64),
                        value.get("head").and_then(Value::as_u64),
                    ) {
                        return Error::EventsTruncated { since, floor, head };
                    }
                }
                _ => {}
            }
        }
    }
    Error::Command {
        operation: "events tail".to_string(),
        status,
        message: stderr.trim().to_string(),
    }
}
