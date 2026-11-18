# Changelog

All notable updates to the **Cognitally / TokDash** standalone binary distribution (`tokdash-releases`) are documented in this file.

## [v0.1.1] - 2026-11-18

### Security & Integrity (`G3`, `G4`)
- **Mandatory Online & Local SHA-256 Verification (`install.sh` / `install.ps1`)**: Both installers now download/read `SHA256SUMS` from the matching release/tag source (or local directory), validate 64-hex digests, stage all artifacts into temporary files before promotion, and fail closed without overwriting an existing working installation.
- **Immutable Release Provenance (`BUILD_MANIFEST.json`)**: `cognitally` and `cognitally.pyz` embed `BUILD_MANIFEST.json` (`version: "0.1.1"`, `source_repo: "kamanager2012/tokdash"`, `source_commit: "b32dd1e272033caaaf8133da6a79f7bdf0603b85"`), exposed directly via `cognitally --version --json`.
- **Version-Pinned Installers & Docs**: Added `--version <tag>` (`install.sh`) and `-Version <tag>` (`install.ps1`) defaulting to `v0.1.1`, and pinned documentation install URLs to immutable tag `v0.1.1`.
- **Clean Historical Attribution**: Restored `v0.1.0` release history cleanly instead of overwriting existing release tags.

### Reliability & Concurrency (`G1`, `G2`)
- **Claude Sidecar Cache Self-Healing**: Automatically detects independently deleted or corrupted `scan_cache.json.claude-events.json` sidecar files and re-parses affected Claude session JSONL logs for quota & accounting consistency.
- **Snapshot Body Integrity Check**: Verifies the full payload structure alongside the 512-byte header generation check so corrupted snapshot files self-heal instead of extending stale TTLs.
- **Bounded Non-Blocking Cross-Process Locks**: Distinguishes lock contention timeouts from unsupported filesystems rather than silently falling back to unlocked writes.
- **Expanded Automated Verification**: Added fault-injection, multi-process concurrency contention, Windows CI matrix (`windows-latest`), and installer tamper-rollback tests.

## [v0.1.0] - 2026-11-04 (Distribution Hardening Update - 2026-11-18)

### Added
- **Instant CLI `--help` / `-h` & `--version` / `-V`**: Prints usage reference or version JSON (`--version --json`) immediately without triggering a 14-agent log scan.
- **Integrity Checksums (`SHA256SUMS`)**: Published SHA-256 digests for `cognitally`, `cognitally.pyz`, `cognitally.cmd`, `cognitally.ps1`, `install.sh`, and `install.ps1`.
- **Clean Uninstallation**: Added `--uninstall` to `install.sh` and `-Uninstall` to `install.ps1`, plus `tokdash.ps1` alias generation on Windows.
- **English Documentation (`README.en.md`)** and expanded CLI/MCP setup docs (Claude Code, OpenAI Codex CLI, Cursor, Windsurf/Zed/Cline).
- **Automated Release Verification Suite (`tests/test_release_bundle.py`)** and SHA-pinned GitHub Actions CI (`.github/workflows/verify-release.yml`).
- **Cross-Platform Line Ending Rules (`.gitattributes`)**: Enforces LF for POSIX scripts/docs and CRLF for Windows `.cmd`/`.ps1` shims.

### Changed
- **Hardened `install.sh`**: Added Python `>= 3.8` runtime validation, macOS (`darwin`) support, `--no-doctor` / `--local` flags, `COGNITALLY_INSTALL_DIR` override, raw `main` fallback download, Zipapp archive validation, and optional SHA-256 verification.
- **Hardened `install.ps1`, `cognitally.cmd`, `cognitally.ps1`**: Ignored Windows Store `python.exe` stub aliases by testing Python `>= 3.8` execution, fixed local `cognitally.pyz` discovery in repo root, added `COGNITALLY_PYTHON` override, and verified Zipapp integrity prior to install.
- **Updated `cognitally --doctor` Footer**: Replaced obsolete `./start.sh` desktop hint with standalone CLI commands (`--statusline`, `--budget-check`, `--mcp`, `--help`).
- **Corrected 14-Agent Table**: Separated `Grok Build` and `Grok Bot` into distinct entries across both `README.md` and `README.en.md`.

### Initial Release (`v0.1.0` - 2026-11-04)
- Cross-version standalone zipapp executables (`cognitally` for POSIX and `cognitally.pyz` + `.cmd`/`.ps1` shims for Windows, Python 3.8–3.14).
- Passive local accounting across 14 AI coding agents, read-only Stdio MCP server (`2024-11-05`, 7 tools), millisecond statusline, and EULA license.
