# Changelog

All notable updates to the **Cognitally / TokDash** standalone binary distribution (`tokdash-releases`) are documented in this file.

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
