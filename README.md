# Knecklace

Knecklace is a native KDE board and editor for [Beads](https://github.com/steveyegge/beads) repositories. The interface is built with Qt Quick and Kirigami, while the backend uses Qt's official [Qt Bridge for Rust](https://github.com/qt/qtbridge-rust).

The application never opens Beads storage directly. The `bd-client` workspace crate owns all access through the `bd` process, including:

```text
bd --readonly list --json --all --limit 0
bd --readonly show <id> --json
bd create <title> ... --json
bd update <id> ... --json
```

On a Beads 1.3 workspace with the events journal enabled, Knecklace reads a
snapshot and follows `bd events tail --follow` for live board changes. It still
reads a fresh snapshot for manual reloads, gate/dependency changes, and recovery
when a feed is interrupted. When the journal is disabled, it keeps polling as
before. To opt in for all writers in a workspace, run
`bd config set events-journal true` there; Knecklace does not change that setting.
Reload after enabling it while Knecklace is already open. Timer gates are
checked separately while the event feed is active. The journal is local to a
clone and does not record Dolt pulls, so reload after syncing. The feed lives
behind `bd-client` so a future `bd serve` transport can replace the CLI reader
without changing the board.

Attachment bytes are the one deliberate exception while upstream Beads attachment support is pending. On versions of `bd` without `bd attachment`, Knecklace stores content-addressed files under:

```text
.beads/knecklace/attachments/<bead-id>/<sha256>
```

Each bead link is a versioned JSON record in a custom metadata key named `knecklace.attachment_<sha256>`. Using one namespaced key per file prevents attachment updates from replacing unrelated bead metadata or other attachment records. These local bytes are not included in Dolt sync or backup, so back up `.beads/knecklace/attachments` separately if they matter.

When `bd attachment` becomes available, Knecklace reads both native and polyfill attachments, sends new files to the native command, and offers **Move to Beads storage** for existing polyfill files. Migration removes each polyfill record and local copy only after verifying that its native bytes are available, making the operation safe to retry after a partial failure.

## Run

All build and runtime dependencies are provided by the Nix flake.

When consuming this flake from a NixOS configuration, set
`inputs.knecklace.inputs.nixpkgs.follows = "nixpkgs"` to build its bundled
`bd`/Dolt runtime from the same nixpkgs revision as the system. This does not
inherit system overlays. After changing Dolt versions, restart any existing
project database server; an already-running server keeps its old executable.

```bash
nix run . -- /path/to/a/beads/repository
```

Without a path, Knecklace opens the current directory. Use **Open Workspace** for KDE's native folder picker. Create beads from the toolbar, drag cards between statuses, or click one to open its editor.

## Develop

```bash
nix develop
./scripts/test
cargo run -- /path/to/a/beads/repository
```

`./scripts/test` runs the Rust suite with process-per-test isolation through `cargo-nextest`, then runs the QML interaction suite through Qt Quick Test. JUnit reports are written to `target/test-results/rust.xml` and `target/test-results/qml.xml`. `nix flake check` runs the same maintained suites in the Nix sandbox.

The flake supplies Rust, Qt 6.10 or newer, Kirigami, the KDE Qt Quick Controls style, `kdialog`, `cargo-nextest`, and `bd`.
