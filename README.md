# KDE Beads

KDE Beads is a native KDE board and editor for [Beads](https://github.com/steveyegge/beads) repositories. The interface is built with Qt Quick and Kirigami, while the backend uses Qt's official [Qt Bridge for Rust](https://github.com/qt/qtbridge-rust).

The application never opens Beads storage directly. The `bd-client` workspace crate owns all access through the `bd` process, including:

```text
bd --readonly list --json --all --limit 0
bd --readonly show <id> --json
bd create <title> ... --json
bd update <id> ... --json
```

## Run

All build and runtime dependencies are provided by the Nix flake.

```bash
nix run . -- /path/to/a/beads/repository
```

Without a path, KDE Beads opens the current directory. Use **Open Workspace** for KDE's native folder picker. Create tickets from the toolbar, drag cards between statuses, or click one to open its editor.

## Develop

```bash
nix develop
./scripts/test
cargo run -- /path/to/a/beads/repository
```

`./scripts/test` runs the Rust suite with process-per-test isolation through `cargo-nextest`, then runs the QML interaction suite through Qt Quick Test. JUnit reports are written to `target/test-results/rust.xml` and `target/test-results/qml.xml`. `nix flake check` runs the same maintained suites in the Nix sandbox.

The flake supplies Rust, Qt 6.10 or newer, Kirigami, the KDE Qt Quick Controls style, `kdialog`, `cargo-nextest`, and `bd`.
