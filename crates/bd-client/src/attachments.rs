// SPDX-License-Identifier: MIT

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Component, Path, PathBuf};
use std::thread;
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use super::{Client, Error, Issue, parse_single_issue};

const METADATA_PREFIX: &str = "knecklace.attachment_";
const RECORD_VERSION: u8 = 1;
const HASH_ALGORITHM: &str = "sha256";

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AttachmentProvider {
    Native,
    Polyfill,
}

fn default_provider() -> AttachmentProvider {
    AttachmentProvider::Native
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Attachment {
    pub id: String,
    #[serde(default)]
    pub issue_id: String,
    #[serde(default)]
    pub hash_algorithm: String,
    #[serde(default)]
    pub content_hash: String,
    #[serde(default)]
    pub original_filename: String,
    #[serde(default)]
    pub mime_type: String,
    #[serde(default)]
    pub byte_size: u64,
    #[serde(default)]
    pub storage_relpath: String,
    #[serde(default)]
    pub missing: bool,
    #[serde(default = "default_provider")]
    pub provider: AttachmentProvider,
}

#[derive(Clone, Debug)]
pub struct MaterializedAttachment {
    pub path: PathBuf,
    pub temporary: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
struct PolyfillAttachment {
    version: u8,
    id: String,
    hash_algorithm: String,
    content_hash: String,
    original_filename: String,
    mime_type: String,
    byte_size: u64,
    storage_relpath: String,
}

impl Client {
    pub fn supports_native_attachments(&self) -> Result<bool, Error> {
        match self.run(false, &["attachment", "--help"]) {
            Ok(_) => Ok(true),
            Err(Error::Command { message, .. })
                if message.contains("unknown command") || message.contains("no help topic") =>
            {
                Ok(false)
            }
            Err(error) => Err(error),
        }
    }

    pub fn add_attachment(&self, issue_id: &str, source: impl AsRef<Path>) -> Result<Issue, Error> {
        if self.supports_native_attachments()? {
            let source = utf8_path(source.as_ref())?;
            self.run(false, &["attachment", "add", issue_id, source, "--json"])?;
        } else {
            self.add_polyfill_attachment(issue_id, source.as_ref())?;
        }
        self.show(issue_id)
    }

    pub fn remove_attachment(&self, issue_id: &str, attachment_id: &str) -> Result<Issue, Error> {
        let issue = self.show_raw(issue_id)?;
        let native_supported = self.supports_native_attachments()?;
        let attachments = self.attachments_for_issue(&issue, native_supported)?;
        let attachment = attachments
            .iter()
            .find(|attachment| attachment.id == attachment_id)
            .ok_or_else(|| {
                Error::Attachment(format!(
                    "attachment {attachment_id} was not found on {issue_id}"
                ))
            })?;

        match attachment.provider {
            AttachmentProvider::Native => {
                self.run(
                    false,
                    &["attachment", "remove", issue_id, attachment_id, "--json"],
                )?;
            }
            AttachmentProvider::Polyfill => {
                self.remove_polyfill_attachment(&issue.id, attachment_id)?;
            }
        }
        self.show(issue_id)
    }

    pub fn materialize_attachment(
        &self,
        issue_id: &str,
        attachment_id: &str,
    ) -> Result<MaterializedAttachment, Error> {
        let issue = self.show(issue_id)?;
        let attachment = issue
            .attachments
            .iter()
            .find(|attachment| attachment.id == attachment_id)
            .ok_or_else(|| {
                Error::Attachment(format!(
                    "attachment {attachment_id} was not found on {issue_id}"
                ))
            })?;
        if attachment.missing {
            return Err(Error::Attachment(format!(
                "{} is not available on this machine",
                attachment.original_filename
            )));
        }

        match attachment.provider {
            AttachmentProvider::Polyfill => {
                let path = self.polyfill_blob_path(issue_id, &attachment.content_hash)?;
                verify_polyfill_blob(&path, &attachment.content_hash)?;
                Ok(MaterializedAttachment {
                    path,
                    temporary: false,
                })
            }
            AttachmentProvider::Native => Ok(MaterializedAttachment {
                path: self.copy_native_attachment(issue_id, attachment_id)?,
                temporary: true,
            }),
        }
    }

    pub fn migrate_polyfill_attachments(&self, issue_id: &str) -> Result<Issue, Error> {
        if !self.supports_native_attachments()? {
            return Err(Error::Attachment(
                "the installed bd does not support native attachments yet".to_string(),
            ));
        }

        let _lock = self.acquire_polyfill_lock()?;
        let issue = self.show_raw(issue_id)?;
        let attachments = polyfill_attachments(&issue)?;
        if attachments.is_empty() {
            return self.show(issue_id);
        }

        for attachment in attachments {
            let blob_path = self.polyfill_blob_path(issue_id, &attachment.content_hash)?;
            verify_polyfill_blob(&blob_path, &attachment.content_hash)?;
            let native_available = self
                .list_native_attachments(issue_id)?
                .iter()
                .any(|item| item.content_hash == attachment.content_hash && !item.missing);
            if !native_available {
                let source = self.migration_source_path(&attachment)?;
                copy_to_new_file(&blob_path, &source)?;
                let source_arg = utf8_path(&source)?;
                let result = self.run(
                    false,
                    &["attachment", "add", issue_id, source_arg, "--json"],
                );
                let _ = fs::remove_file(&source);
                if let Err(error) = result {
                    let repaired = self
                        .list_native_attachments(issue_id)?
                        .into_iter()
                        .any(|item| item.content_hash == attachment.content_hash && !item.missing);
                    if !repaired {
                        return Err(error);
                    }
                }
            }

            let native = self.list_native_attachments(issue_id)?;
            let Some(native_attachment) = native
                .iter()
                .find(|item| item.content_hash == attachment.content_hash && !item.missing)
            else {
                return Err(Error::Attachment(format!(
                    "native attachment bytes were not available after migrating {}",
                    attachment.original_filename
                )));
            };
            self.verify_native_attachment_bytes(issue_id, native_attachment)?;
            self.unset_polyfill_attachment(issue_id, &attachment.content_hash)?;
            let _ = fs::remove_file(blob_path);
        }
        self.show(issue_id)
    }

    pub(super) fn cleanup_deleted_polyfill_storage(&self, issue_id: &str) -> Result<(), Error> {
        validate_component(issue_id, "bead ID")?;
        let _lock = self.acquire_polyfill_lock()?;
        let issue_dir = self.polyfill_issue_dir(issue_id, false)?;
        let entries = match fs::read_dir(&issue_dir) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => {
                return Err(attachment_io_error(
                    "read deleted bead attachment directory",
                    &issue_dir,
                    error,
                ));
            }
        };
        for entry in entries {
            let entry = entry.map_err(|error| {
                attachment_io_error("read deleted bead attachment directory", &issue_dir, error)
            })?;
            let path = entry.path();
            let metadata = fs::symlink_metadata(&path)
                .map_err(|error| attachment_io_error("inspect attachment", &path, error))?;
            if metadata.file_type().is_symlink() || !metadata.is_file() {
                return Err(Error::Attachment(format!(
                    "deleted bead attachment storage contains an unsafe entry: {}",
                    path.display()
                )));
            }
            fs::remove_file(&path)
                .map_err(|error| attachment_io_error("remove attachment", &path, error))?;
        }
        fs::remove_dir(&issue_dir).map_err(|error| {
            attachment_io_error(
                "remove deleted bead attachment directory",
                &issue_dir,
                error,
            )
        })?;
        Ok(())
    }

    pub(crate) fn hydrate_attachments(&self, issue: &mut Issue) -> Result<(), Error> {
        let native_supported = self.supports_native_attachments()?;
        let attachments = self.attachments_for_issue(issue, native_supported)?;
        issue.polyfill_attachment_count = attachments
            .iter()
            .filter(|attachment| attachment.provider == AttachmentProvider::Polyfill)
            .count();
        issue.native_attachments_supported = native_supported;
        issue.attachments = attachments;
        Ok(())
    }

    fn attachments_for_issue(
        &self,
        issue: &Issue,
        native_supported: bool,
    ) -> Result<Vec<Attachment>, Error> {
        let mut attachments = if native_supported {
            self.list_native_attachments(&issue.id)?
        } else {
            Vec::new()
        };
        attachments.extend(self.list_polyfill_attachments(issue)?);
        Ok(attachments)
    }

    fn list_native_attachments(&self, issue_id: &str) -> Result<Vec<Attachment>, Error> {
        let payload = self.run(true, &["attachment", "list", issue_id, "--json"])?;
        let mut attachments: Vec<Attachment> =
            serde_json::from_str(&payload).map_err(|source| Error::InvalidJson {
                operation: "attachment list",
                source,
            })?;
        for attachment in &mut attachments {
            attachment.provider = AttachmentProvider::Native;
        }
        Ok(attachments)
    }

    fn copy_native_attachment(
        &self,
        issue_id: &str,
        attachment_id: &str,
    ) -> Result<PathBuf, Error> {
        let target = tempfile::NamedTempFile::new()
            .map_err(|error| {
                Error::Attachment(format!(
                    "could not create secure attachment preview: {error}"
                ))
            })?
            .into_temp_path()
            .keep()
            .map_err(|error| {
                Error::Attachment(format!(
                    "could not retain secure attachment preview: {error}"
                ))
            })?;
        let target_arg = utf8_path(&target)?;
        if let Err(error) = self.run(
            false,
            &[
                "attachment",
                "copy",
                issue_id,
                attachment_id,
                target_arg,
                "--force",
                "--json",
            ],
        ) {
            let _ = fs::remove_file(&target);
            return Err(error);
        }
        Ok(target)
    }

    fn verify_native_attachment_bytes(
        &self,
        issue_id: &str,
        attachment: &Attachment,
    ) -> Result<(), Error> {
        let path = self.copy_native_attachment(issue_id, &attachment.id)?;
        let result = verify_polyfill_blob(&path, &attachment.content_hash);
        let _ = fs::remove_file(path);
        result
    }

    fn list_polyfill_attachments(&self, issue: &Issue) -> Result<Vec<Attachment>, Error> {
        polyfill_attachments(issue)?
            .into_iter()
            .map(|attachment| {
                let path = self.polyfill_blob_path(&issue.id, &attachment.content_hash)?;
                Ok(Attachment {
                    id: attachment.id,
                    issue_id: issue.id.clone(),
                    hash_algorithm: attachment.hash_algorithm,
                    content_hash: attachment.content_hash,
                    original_filename: attachment.original_filename,
                    mime_type: attachment.mime_type,
                    byte_size: attachment.byte_size,
                    storage_relpath: attachment.storage_relpath,
                    missing: !path.is_file(),
                    provider: AttachmentProvider::Polyfill,
                })
            })
            .collect()
    }

    fn add_polyfill_attachment(&self, issue_id: &str, source: &Path) -> Result<(), Error> {
        let _lock = self.acquire_polyfill_lock()?;
        let issue = self.show_raw(issue_id)?;
        let attachments = polyfill_attachments(&issue)?;
        let original_filename = safe_filename(source)?;
        let (content_hash, byte_size, newly_stored) = self.store_polyfill_blob(issue_id, source)?;
        if attachments
            .iter()
            .any(|attachment| attachment.content_hash == content_hash)
        {
            return Ok(());
        }

        let attachment = PolyfillAttachment {
            version: RECORD_VERSION,
            id: format!("polyfill:{content_hash}"),
            hash_algorithm: HASH_ALGORITHM.to_string(),
            content_hash: content_hash.clone(),
            original_filename,
            mime_type: mime_type(source),
            byte_size,
            storage_relpath: polyfill_relpath(issue_id, &content_hash)?,
        };
        if let Err(error) = self.set_polyfill_attachment(issue_id, &attachment) {
            if newly_stored {
                if let Ok(path) = self.polyfill_blob_path(issue_id, &content_hash) {
                    let _ = fs::remove_file(path);
                }
            }
            return Err(error);
        }
        Ok(())
    }

    fn remove_polyfill_attachment(&self, issue_id: &str, attachment_id: &str) -> Result<(), Error> {
        let _lock = self.acquire_polyfill_lock()?;
        let issue = self.show_raw(issue_id)?;
        let attachment = polyfill_attachments(&issue)?
            .into_iter()
            .find(|attachment| attachment.id == attachment_id)
            .ok_or_else(|| {
                Error::Attachment(format!(
                    "attachment {attachment_id} was not found on {}",
                    issue.id
                ))
            })?;
        self.unset_polyfill_attachment(&issue.id, &attachment.content_hash)?;
        let path = self.polyfill_blob_path(&issue.id, &attachment.content_hash)?;
        if let Err(error) = fs::remove_file(&path) {
            if error.kind() != std::io::ErrorKind::NotFound {
                return Err(attachment_io_error(
                    "remove polyfill attachment",
                    &path,
                    error,
                ));
            }
        }
        Ok(())
    }

    fn set_polyfill_attachment(
        &self,
        issue_id: &str,
        attachment: &PolyfillAttachment,
    ) -> Result<(), Error> {
        let value = serde_json::to_string(attachment).map_err(|error| {
            Error::Attachment(format!("could not encode attachment metadata: {error}"))
        })?;
        let assignment = format!("{}{}={value}", METADATA_PREFIX, attachment.content_hash);
        let payload = self.run(
            false,
            &["update", issue_id, "--set-metadata", &assignment, "--json"],
        )?;
        let _ = parse_single_issue("update attachment metadata", &payload)?;
        Ok(())
    }

    fn unset_polyfill_attachment(&self, issue_id: &str, content_hash: &str) -> Result<(), Error> {
        validate_hash(content_hash)?;
        let key = format!("{METADATA_PREFIX}{content_hash}");
        let payload = self.run(
            false,
            &["update", issue_id, "--unset-metadata", &key, "--json"],
        )?;
        let _ = parse_single_issue("update attachment metadata", &payload)?;
        Ok(())
    }

    fn store_polyfill_blob(
        &self,
        issue_id: &str,
        source: &Path,
    ) -> Result<(String, u64, bool), Error> {
        let issue_dir = self.polyfill_issue_dir(issue_id, true)?;
        let source_file = File::open(source)
            .map_err(|error| attachment_io_error("open attachment source", source, error))?;
        if !source_file
            .metadata()
            .map_err(|error| attachment_io_error("inspect attachment source", source, error))?
            .is_file()
        {
            return Err(Error::Attachment(format!(
                "attachment source is not a regular file: {}",
                source.display()
            )));
        }

        let temp_path = unique_temp_path(&issue_dir);
        let mut temp = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp_path)
            .map_err(|error| {
                attachment_io_error("create temporary attachment", &temp_path, error)
            })?;
        let mut source_file = source_file;
        let mut hasher = Sha256::new();
        let mut buffer = [0_u8; 64 * 1024];
        let mut byte_size = 0_u64;
        loop {
            let read = source_file
                .read(&mut buffer)
                .map_err(|error| attachment_io_error("read attachment source", source, error))?;
            if read == 0 {
                break;
            }
            hasher.update(&buffer[..read]);
            temp.write_all(&buffer[..read]).map_err(|error| {
                attachment_io_error("write temporary attachment", &temp_path, error)
            })?;
            byte_size += read as u64;
        }
        temp.sync_all()
            .map_err(|error| attachment_io_error("sync temporary attachment", &temp_path, error))?;
        drop(temp);

        let content_hash = hex_digest(hasher.finalize().as_slice());
        let final_path = issue_dir.join(&content_hash);
        if final_path.exists() {
            let _ = fs::remove_file(&temp_path);
            verify_polyfill_blob(&final_path, &content_hash)?;
            return Ok((content_hash, byte_size, false));
        }
        fs::rename(&temp_path, &final_path).map_err(|error| {
            let _ = fs::remove_file(&temp_path);
            attachment_io_error("store attachment", &final_path, error)
        })?;
        Ok((content_hash, byte_size, true))
    }

    fn polyfill_issue_dir(&self, issue_id: &str, create: bool) -> Result<PathBuf, Error> {
        validate_component(issue_id, "bead ID")?;
        let beads_dir = checked_directory(&self.workspace.join(".beads"), false)?;
        let namespace = checked_directory(&beads_dir.join("knecklace"), create)?;
        let attachments = checked_directory(&namespace.join("attachments"), create)?;
        checked_directory(&attachments.join(issue_id), create)
    }

    fn polyfill_blob_path(&self, issue_id: &str, content_hash: &str) -> Result<PathBuf, Error> {
        validate_hash(content_hash)?;
        Ok(self.polyfill_issue_dir(issue_id, false)?.join(content_hash))
    }

    fn acquire_polyfill_lock(&self) -> Result<PolyfillLock, Error> {
        let beads_dir = checked_directory(&self.workspace.join(".beads"), false)?;
        let namespace = checked_directory(&beads_dir.join("knecklace"), true)?;
        let path = namespace.join("attachments.lock");
        match fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
                return Err(Error::Attachment(format!(
                    "attachment lock path is unsafe: {}",
                    path.display()
                )));
            }
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(attachment_io_error("inspect attachment lock", &path, error));
            }
        }
        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&path)
            .map_err(|error| attachment_io_error("open attachment lock", &path, error))?;
        for _ in 0..100 {
            match file.try_lock_exclusive() {
                Ok(()) => return Ok(PolyfillLock { file }),
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(50));
                }
                Err(error) => {
                    return Err(attachment_io_error("acquire attachment lock", &path, error));
                }
            }
        }
        Err(Error::Attachment(format!(
            "timed out waiting for attachment lock {}",
            path.display()
        )))
    }

    fn migration_source_path(&self, attachment: &PolyfillAttachment) -> Result<PathBuf, Error> {
        validate_hash(&attachment.content_hash)?;
        validate_component(&attachment.original_filename, "attachment filename")?;
        let beads_dir = checked_directory(&self.workspace.join(".beads"), false)?;
        let namespace = checked_directory(&beads_dir.join("knecklace"), true)?;
        let migration = checked_directory(&namespace.join("migration"), true)?;
        let hash_dir = checked_directory(&migration.join(&attachment.content_hash), true)?;
        let path = hash_dir.join(&attachment.original_filename);
        match fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
                return Err(Error::Attachment(format!(
                    "attachment migration path is unsafe: {}",
                    path.display()
                )));
            }
            Ok(_) => fs::remove_file(&path).map_err(|error| {
                attachment_io_error("clear attachment migration file", &path, error)
            })?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(attachment_io_error(
                    "inspect attachment migration path",
                    &path,
                    error,
                ));
            }
        }
        Ok(path)
    }
}

struct PolyfillLock {
    file: File,
}

impl Drop for PolyfillLock {
    fn drop(&mut self) {
        let _ = FileExt::unlock(&self.file);
    }
}

fn polyfill_attachments(issue: &Issue) -> Result<Vec<PolyfillAttachment>, Error> {
    let mut attachments = Vec::new();
    for (key, value) in &issue.metadata {
        let Some(key_hash) = key.strip_prefix(METADATA_PREFIX) else {
            continue;
        };
        validate_hash(key_hash)?;
        let attachment: PolyfillAttachment = match value {
            Value::String(value) => serde_json::from_str(value),
            value => serde_json::from_value(value.clone()),
        }
        .map_err(|error| {
            Error::Attachment(format!("{} has invalid {key} metadata: {error}", issue.id))
        })?;
        if attachment.version != RECORD_VERSION {
            return Err(Error::Attachment(format!(
                "{} uses unsupported attachment record version {}",
                issue.id, attachment.version
            )));
        }
        let expected_id = format!("polyfill:{key_hash}");
        let expected_path = polyfill_relpath(&issue.id, key_hash)?;
        if attachment.hash_algorithm != HASH_ALGORITHM
            || attachment.content_hash != key_hash
            || attachment.id != expected_id
            || attachment.storage_relpath != expected_path
        {
            return Err(Error::Attachment(format!(
                "{} has inconsistent attachment metadata in {key}",
                issue.id
            )));
        }
        attachments.push(attachment);
    }
    Ok(attachments)
}

fn polyfill_relpath(issue_id: &str, content_hash: &str) -> Result<String, Error> {
    validate_component(issue_id, "bead ID")?;
    validate_hash(content_hash)?;
    Ok(format!("knecklace/attachments/{issue_id}/{content_hash}"))
}

fn checked_directory(path: &Path, create: bool) -> Result<PathBuf, Error> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() || !metadata.is_dir() {
                return Err(Error::Attachment(format!(
                    "attachment storage is not a regular directory: {}",
                    path.display()
                )));
            }
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound && create => {
            fs::create_dir(path)
                .map_err(|error| attachment_io_error("create attachment directory", path, error))?;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(path.to_path_buf()),
        Err(error) => {
            return Err(attachment_io_error(
                "inspect attachment directory",
                path,
                error,
            ));
        }
    }
    Ok(path.to_path_buf())
}

fn validate_component(value: &str, label: &str) -> Result<(), Error> {
    let mut components = Path::new(value).components();
    if value.is_empty()
        || !matches!(components.next(), Some(Component::Normal(_)))
        || components.next().is_some()
        || value.contains(['/', '\\'])
    {
        return Err(Error::Attachment(format!("invalid {label}: {value:?}")));
    }
    Ok(())
}

fn validate_hash(content_hash: &str) -> Result<(), Error> {
    if content_hash.len() != 64
        || !content_hash
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
    {
        return Err(Error::Attachment(format!(
            "invalid attachment SHA-256: {content_hash:?}"
        )));
    }
    Ok(())
}

fn safe_filename(path: &Path) -> Result<String, Error> {
    let filename = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| {
            Error::Attachment(format!(
                "attachment filename is not valid UTF-8: {}",
                path.display()
            ))
        })?;
    validate_component(filename, "attachment filename")?;
    Ok(filename.to_string())
}

fn verify_polyfill_blob(path: &Path, expected_hash: &str) -> Result<(), Error> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| attachment_io_error("inspect attachment", path, error))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(Error::Attachment(format!(
            "attachment is not a regular file: {}",
            path.display()
        )));
    }
    let actual_hash = hash_file(path)?;
    if actual_hash != expected_hash {
        return Err(Error::Attachment(format!(
            "attachment content does not match its SHA-256: {}",
            path.display()
        )));
    }
    Ok(())
}

fn copy_to_new_file(source: &Path, target: &Path) -> Result<(), Error> {
    let mut source_file = File::open(source)
        .map_err(|error| attachment_io_error("open migration source", source, error))?;
    let mut target_file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(target)
        .map_err(|error| attachment_io_error("create migration file", target, error))?;
    std::io::copy(&mut source_file, &mut target_file)
        .map_err(|error| attachment_io_error("copy migration file", target, error))?;
    target_file
        .sync_all()
        .map_err(|error| attachment_io_error("sync migration file", target, error))?;
    Ok(())
}

fn hash_file(path: &Path) -> Result<String, Error> {
    let mut file =
        File::open(path).map_err(|error| attachment_io_error("open attachment", path, error))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|error| attachment_io_error("read attachment", path, error))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex_digest(hasher.finalize().as_slice()))
}

fn hex_digest(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut value = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        value.push(HEX[(byte >> 4) as usize] as char);
        value.push(HEX[(byte & 0x0f) as usize] as char);
    }
    value
}

fn mime_type(path: &Path) -> String {
    match path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("svg") => "image/svg+xml",
        Some("pdf") => "application/pdf",
        Some("md" | "markdown") => "text/markdown",
        Some("txt" | "log") => "text/plain",
        Some("json") => "application/json",
        Some("zip") => "application/zip",
        _ => "application/octet-stream",
    }
    .to_string()
}

fn unique_temp_path(parent: &Path) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    parent.join(format!(".knecklace-{}-{nonce}.tmp", std::process::id()))
}

fn utf8_path(path: &Path) -> Result<&str, Error> {
    path.to_str()
        .ok_or_else(|| Error::Attachment(format!("path is not valid UTF-8: {}", path.display())))
}

fn attachment_io_error(operation: &str, path: &Path, error: std::io::Error) -> Error {
    Error::Attachment(format!("could not {operation} {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn parses_namespaced_attachment_from_issue_metadata() {
        let hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let mut metadata = BTreeMap::new();
        metadata.insert(
            format!("{METADATA_PREFIX}{hash}"),
            Value::String(
                format!(r#"{{"version":1,"id":"polyfill:{hash}","hash_algorithm":"sha256","content_hash":"{hash}","original_filename":"shot.png","mime_type":"image/png","byte_size":4,"storage_relpath":"knecklace/attachments/bd-1/{hash}"}}"#),
            ),
        );
        let issue = Issue {
            id: "bd-1".to_string(),
            metadata,
            ..test_issue()
        };

        let attachments = polyfill_attachments(&issue).unwrap();

        assert_eq!(attachments[0].version, 1);
        assert_eq!(attachments[0].original_filename, "shot.png");
    }

    #[test]
    fn rejects_unsafe_storage_components() {
        assert!(validate_component("bd-123", "bead ID").is_ok());
        assert!(validate_component("../outside", "bead ID").is_err());
        assert!(validate_component("dir/file", "filename").is_err());
        assert!(validate_hash("ABC").is_err());
    }

    #[test]
    fn hashes_files_as_sha256() {
        let directory = tempfile::TempDir::new().unwrap();
        let path = directory.path().join("sample");
        fs::write(&path, b"hello").unwrap();

        assert_eq!(
            hash_file(&path).unwrap(),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
    }

    #[test]
    fn polyfill_lock_can_be_reacquired_after_release() {
        let directory = tempfile::TempDir::new().unwrap();
        fs::create_dir(directory.path().join(".beads")).unwrap();
        let client = Client::with_binary(directory.path(), "bd").unwrap();
        let lock_path = directory.path().join(".beads/knecklace/attachments.lock");

        let lock = client.acquire_polyfill_lock().unwrap();
        assert!(lock_path.is_file());
        drop(lock);

        let lock = client.acquire_polyfill_lock().unwrap();
        drop(lock);
    }

    fn test_issue() -> Issue {
        Issue {
            id: String::new(),
            title: String::new(),
            description: String::new(),
            acceptance_criteria: String::new(),
            design: String::new(),
            notes: String::new(),
            status: super::super::Status::Open,
            priority: 2,
            issue_type: "task".to_string(),
            assignee: String::new(),
            owner: String::new(),
            labels: Vec::new(),
            created_at: String::new(),
            updated_at: String::new(),
            closed_at: String::new(),
            close_reason: String::new(),
            dependency_count: 0,
            dependent_count: 0,
            comment_count: 0,
            metadata: BTreeMap::new(),
            attachments: Vec::new(),
            native_attachments_supported: false,
            polyfill_attachment_count: 0,
            is_blocked: false,
            blocked_by_gate: false,
        }
    }
}
