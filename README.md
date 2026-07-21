# KDE Beads

KDE Beads is a read-only, native KDE viewer for [Beads](https://github.com/steveyegge/beads) repositories. The interface is built with Qt Quick and Kirigami, while the backend uses Qt's official [Qt Bridge for Rust](https://github.com/qt/qtbridge-rust).

The application never opens Beads storage directly. It discovers and reads data by running:

```text
bd --readonly list --json --all --limit 0
bd --readonly show <id> --json
```

## Run

All build and runtime dependencies are provided by the Nix flake.

```bash
nix run . -- /path/to/a/beads/repository
```

Without a path, KDE Beads opens the current directory. Use **Open Workspace** to switch repositories.

## Develop

```bash
nix develop
cargo test
cargo run -- /path/to/a/beads/repository
```

The flake supplies Rust, Qt 6.10 or newer, Kirigami, the KDE Qt Quick Controls style, and `bd`.
