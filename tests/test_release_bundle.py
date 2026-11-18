"""Release bundle contract & integrity tests for tokdash-releases.

Uses only CPython standard library modules so CI runners and developer machines
can verify standalone artifacts without third-party dependencies.
"""

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
COGNITALLY_BIN = REPO_ROOT / "cognitally"
COGNITALLY_PYZ = REPO_ROOT / "cognitally.pyz"
SHA256SUMS_FILE = REPO_ROOT / "SHA256SUMS"
WORKFLOW_FILE = REPO_ROOT / ".github" / "workflows" / "verify-release.yml"


def _isolated_env(home_dir: Path) -> dict:
    env = os.environ.copy()
    env["HOME"] = str(home_dir)
    env["USERPROFILE"] = str(home_dir)
    env["XDG_CONFIG_HOME"] = str(home_dir / ".config")
    env["COGNITALLY_DIR"] = str(home_dir / ".config" / "cognitally")
    env["APPDATA"] = str(home_dir / "AppData" / "Roaming")
    env["LOCALAPPDATA"] = str(home_dir / "AppData" / "Local")
    return env


def _cli_cmd(use_pyz: bool = False) -> list:
    if use_pyz or os.name == "nt":
        return [sys.executable, str(COGNITALLY_PYZ if use_pyz else COGNITALLY_BIN)]
    return [str(COGNITALLY_BIN)]


def _run(cmd, env=None, input_text=None, timeout=20):
    """Run a subprocess with deterministic UTF-8 stdout/stderr decoding."""
    return subprocess.run(
        cmd,
        input=input_text,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        timeout=timeout,
    )


class TestReleaseBundle(unittest.TestCase):
    def test_zipapp_structure_and_cross_version_sources(self):
        required_entries = {
            "__main__.py",
            "BUILD_MANIFEST.json",
            "usage.30s.py",
            "mcp_server.py",
            "budget_guard.py",
            "export_engine.py",
            "statusline_engine.py",
            "pricing.json",
            "pricing_overrides.json",
            "core/config.py",
            "core/diagnostics/doctor.py",
        }

        with open(COGNITALLY_BIN, "rb") as fh:
            shebang_line = fh.readline()
        self.assertEqual(shebang_line, b"#!/usr/bin/env python3\n")

        if os.name != "nt":
            mode = os.stat(COGNITALLY_BIN).st_mode
            self.assertTrue(mode & stat.S_IXUSR, "cognitally must be executable by owner")

        manifests = {}
        for archive in (COGNITALLY_BIN, COGNITALLY_PYZ):
            self.assertTrue(zipfile.is_zipfile(archive), f"{archive.name} must be a valid zipapp")
            with zipfile.ZipFile(archive, "r") as zf:
                names = set(zf.namelist())
                missing = required_entries - names
                self.assertFalse(missing, f"{archive.name} missing required entries: {sorted(missing)}")
                pyc_entries = [n for n in names if n.endswith((".pyc", ".pyo"))]
                self.assertEqual(pyc_entries, [], f"{archive.name} must not contain bytecode files")
                core_modules = [n for n in names if n.startswith("core/") and n.endswith(".py")]
                self.assertGreaterEqual(len(core_modules), 30)
                manifest = json.loads(zf.read("BUILD_MANIFEST.json").decode("utf-8"))
                self.assertEqual(manifest.get("version"), "0.1.1")
                self.assertEqual(manifest.get("source_repo"), "kamanager2012/tokdash")
                self.assertRegex(str(manifest.get("source_commit", "")), r"^[0-9a-f]{40}$")
                manifests[archive.name] = manifest
        self.assertEqual(manifests[COGNITALLY_BIN.name], manifests[COGNITALLY_PYZ.name])

    def test_sha256sums_integrity(self):
        self.assertTrue(SHA256SUMS_FILE.is_file(), "SHA256SUMS must exist")
        lines = [ln.strip() for ln in SHA256SUMS_FILE.read_text(encoding="utf-8").splitlines() if ln.strip()]
        expected_files = {
            "cognitally",
            "cognitally.pyz",
            "cognitally.cmd",
            "cognitally.ps1",
            "install.sh",
            "install.ps1",
        }
        seen_files = set()
        for line in lines:
            parts = line.split()
            self.assertEqual(len(parts), 2, f"Malformed SHA256SUMS line: {line}")
            expected_digest, rel_name = parts
            self.assertRegex(expected_digest, r"^[0-9a-f]{64}$")
            target = REPO_ROOT / rel_name
            self.assertTrue(target.is_file(), f"Checksummed file missing: {rel_name}")
            actual_digest = hashlib.sha256(target.read_bytes()).hexdigest()
            self.assertEqual(actual_digest, expected_digest, f"SHA-256 mismatch for {rel_name}")
            seen_files.add(rel_name)
        self.assertEqual(seen_files, expected_files)

    def test_cli_fast_help_and_version(self):
        with zipfile.ZipFile(COGNITALLY_PYZ, "r") as zf:
            expected_manifest = json.loads(zf.read("BUILD_MANIFEST.json").decode("utf-8"))

        with tempfile.TemporaryDirectory() as tmp:
            env = _isolated_env(Path(tmp))
            cases = [
                (_cli_cmd(False) + ["--help"], "Usage:"),
                (_cli_cmd(False) + ["--version"], "Cognitally (TokDash) v0.1.1"),
                (_cli_cmd(True) + ["--help"], "--doctor"),
                (_cli_cmd(True) + ["--version", "--json"], '"version": "0.1.1"'),
            ]
            for cmd, expected_substr in cases:
                t0 = time.monotonic()
                proc = _run(cmd, env=env, timeout=10)
                elapsed = time.monotonic() - t0
                self.assertEqual(proc.returncode, 0, f"{cmd} failed: {proc.stderr}")
                self.assertLess(elapsed, 2.0, f"{cmd} took {elapsed:.2f}s (expected < 2.0s)")
                self.assertIn(expected_substr, proc.stdout)

            ver_json = _run(_cli_cmd(True) + ["--version", "--json"], env=env, timeout=10)
            payload = json.loads(ver_json.stdout)
            self.assertEqual(payload.get("name"), "cognitally")
            self.assertEqual(payload.get("version"), "0.1.1")
            self.assertEqual(payload.get("source_commit"), expected_manifest["source_commit"])

    def test_cli_doctor_and_statusline_and_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = _isolated_env(Path(tmp))

            doc_proc = _run(_cli_cmd(False) + ["--doctor", "--json"], env=env, timeout=20)
            self.assertEqual(doc_proc.returncode, 0, doc_proc.stderr)
            doc_data = json.loads(doc_proc.stdout)
            self.assertIn("system", doc_data)
            self.assertIn("agents", doc_data)
            self.assertEqual(len(doc_data["agents"]), 14)

            doc_ascii = _run(_cli_cmd(False) + ["--doctor"], env=env, timeout=20)
            self.assertEqual(doc_ascii.returncode, 0, doc_ascii.stderr)
            self.assertNotIn("./start.sh", doc_ascii.stdout)
            self.assertIn("--help", doc_ascii.stdout)

            sl_proc = _run(_cli_cmd(False) + ["--install-statusline"], env=env, timeout=15)
            self.assertEqual(sl_proc.returncode, 0, sl_proc.stderr)
            self.assertIn("Cognitally Statusline Terminal Integration Guide", sl_proc.stdout)

            budget_proc = _run(_cli_cmd(False) + ["--budget-check", "--budget-limit", "50", "--json"], env=env, timeout=20)
            self.assertEqual(budget_proc.returncode, 0, budget_proc.stderr)
            budget_data = json.loads(budget_proc.stdout)
            self.assertEqual(budget_data["threshold_usd"], 50.0)
            self.assertFalse(budget_data["exceeded"])

            sum_proc = _run(_cli_cmd(False) + ["--summary", "--no-color"], env=env, timeout=20)
            self.assertEqual(sum_proc.returncode, 0, sum_proc.stderr)
            self.assertIn("Agent", sum_proc.stdout)
            self.assertIn("Cache Read", sum_proc.stdout)
            self.assertIn("TOTAL", sum_proc.stdout)
            self.assertNotIn("\033[", sum_proc.stdout)

            explicit_today = _run(_cli_cmd(False) + ["--summary", "--period", "today", "--no-color"], env=env, timeout=20)
            self.assertEqual(explicit_today.returncode, 0, explicit_today.stderr)
            self.assertIn("view:today", explicit_today.stdout)
            self.assertNotIn("view:all", explicit_today.stdout)
            for ln in explicit_today.stdout.splitlines():
                self.assertLessEqual(len(ln), 80, f"Default 80-col output exceeded 80 chars: {ln!r}")

    def test_mcp_stdio_protocol_handshake(self):
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "ping"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/list"},
        ]
        stdin_payload = "\n".join(json.dumps(r) for r in requests) + "\n"

        with tempfile.TemporaryDirectory() as tmp:
            env = _isolated_env(Path(tmp))
            proc = _run(_cli_cmd(False) + ["--mcp"], env=env, input_text=stdin_payload, timeout=20)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
            self.assertEqual(len(lines), 3, f"Expected 3 JSON-RPC responses, got: {lines}")

            resp_init, resp_ping, resp_tools = (json.loads(ln) for ln in lines)
            self.assertEqual(resp_init["id"], 1)
            self.assertEqual(resp_init["result"]["protocolVersion"], "2024-11-05")
            self.assertEqual(resp_ping, {"jsonrpc": "2.0", "id": 2, "result": {}})
            tool_names = {t["name"] for t in resp_tools["result"]["tools"]}
            self.assertEqual(
                tool_names,
                {
                    "get_usage",
                    "get_cost",
                    "get_quota",
                    "get_projects",
                    "get_models",
                    "get_accounting_status",
                    "check_budget",
                },
            )

    def test_install_sh_local_install_and_uninstall(self):
        if os.name == "nt":
            # On Windows runners, exercise install.ps1 local install and uninstall end-to-end
            with tempfile.TemporaryDirectory() as tmp:
                tmp_path = Path(tmp)
                install_dir = tmp_path / "cognitally-bin"
                env = _isolated_env(tmp_path)
                env["COGNITALLY_PYTHON"] = sys.executable

                inst = _run(
                    [
                        "powershell",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        str(REPO_ROOT / "install.ps1"),
                        "-InstallDir",
                        str(install_dir),
                        "-NoPathUpdate",
                        "-SkipDoctor",
                        "-Local",
                    ],
                    env=env,
                    timeout=30,
                )
                self.assertEqual(inst.returncode, 0, inst.stdout + inst.stderr)
                self.assertTrue((install_dir / "cognitally.pyz").is_file())
                self.assertTrue((install_dir / "cognitally.cmd").is_file())
                self.assertTrue((install_dir / "tokdash.cmd").is_file())
                self.assertTrue((install_dir / "tokdash.ps1").is_file())

                ver = _run([str(install_dir / "cognitally.cmd"), "--version"], env=env, timeout=15)
                self.assertEqual(ver.returncode, 0, ver.stderr)
                self.assertIn("Cognitally (TokDash) v0.1.1", ver.stdout)

                bad_env = dict(env)
                bad_env["COGNITALLY_EXPECTED_SHA256"] = "0" * 64
                tamper_inst = _run(
                    [
                        "powershell",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        str(REPO_ROOT / "install.ps1"),
                        "-InstallDir",
                        str(install_dir),
                        "-NoPathUpdate",
                        "-SkipDoctor",
                        "-Local",
                    ],
                    env=bad_env,
                    timeout=30,
                )
                self.assertNotEqual(tamper_inst.returncode, 0, "Tampered SHA-256 must fail closed")
                ver_after = _run([str(install_dir / "cognitally.cmd"), "--version"], env=env, timeout=15)
                self.assertEqual(ver_after.returncode, 0, ver_after.stderr)
                self.assertIn("Cognitally (TokDash) v0.1.1", ver_after.stdout)

                uninst = _run(
                    [
                        "powershell",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        str(REPO_ROOT / "install.ps1"),
                        "-InstallDir",
                        str(install_dir),
                        "-Uninstall",
                    ],
                    env=env,
                    timeout=30,
                )
                self.assertEqual(uninst.returncode, 0, uninst.stdout + uninst.stderr)
                for fname in ("cognitally.pyz", "cognitally.cmd", "cognitally.ps1", "tokdash.cmd", "tokdash.ps1"):
                    self.assertFalse((install_dir / fname).exists(), f"{fname} should be removed")
            return

        bash_bin = shutil.which("bash")
        self.assertIsNotNone(bash_bin, "bash is required on POSIX systems")
        syntax_chk = _run([bash_bin, "-n", str(REPO_ROOT / "install.sh")], timeout=10)
        self.assertEqual(syntax_chk.returncode, 0, syntax_chk.stderr)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            install_dir = tmp_path / "bin"
            env = _isolated_env(tmp_path)
            env["COGNITALLY_INSTALL_DIR"] = str(install_dir)
            env["COGNITALLY_LOCAL_BINARY"] = str(COGNITALLY_BIN)

            inst = _run([bash_bin, str(REPO_ROOT / "install.sh"), "--no-doctor"], env=env, timeout=20)
            self.assertEqual(inst.returncode, 0, inst.stdout + inst.stderr)
            installed_bin = install_dir / "cognitally"
            installed_alias = install_dir / "tokdash"
            self.assertTrue(installed_bin.is_file())
            self.assertTrue(installed_alias.is_symlink())

            ver = _run([str(installed_alias), "--version"], env=env, timeout=10)
            self.assertEqual(ver.returncode, 0, ver.stderr)
            self.assertIn("Cognitally (TokDash) v0.1.1", ver.stdout)

            bad_env = dict(env)
            bad_env["COGNITALLY_EXPECTED_SHA256"] = "0" * 64
            tamper_inst = _run([bash_bin, str(REPO_ROOT / "install.sh"), "--no-doctor"], env=bad_env, timeout=20)
            self.assertNotEqual(tamper_inst.returncode, 0, "Tampered SHA-256 must fail closed")
            ver_after = _run([str(installed_alias), "--version"], env=env, timeout=10)
            self.assertEqual(ver_after.returncode, 0, ver_after.stderr)
            self.assertIn("Cognitally (TokDash) v0.1.1", ver_after.stdout)

            uninst = _run([bash_bin, str(REPO_ROOT / "install.sh"), "--uninstall"], env=env, timeout=20)
            self.assertEqual(uninst.returncode, 0, uninst.stdout + uninst.stderr)
            self.assertFalse(installed_bin.exists())
            self.assertFalse(installed_alias.exists() or installed_alias.is_symlink())

    def test_windows_artifacts_and_docs_contracts(self):
        for win_file in ("install.ps1", "cognitally.cmd", "cognitally.ps1"):
            raw = (REPO_ROOT / win_file).read_bytes()
            self.assertIn(b"\r\n", raw, f"{win_file} must use CRLF line endings")
            # Ensure no bare LF exists outside CRLF pairs
            self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), f"{win_file} has bare LF line endings")

        for doc_name in ("README.md", "README.en.md"):
            doc_txt = (REPO_ROOT / doc_name).read_text(encoding="utf-8")
            numbered_rows = re.findall(r"^\|\s*(\d+)\s*\|", doc_txt, flags=re.MULTILINE)
            self.assertEqual(
                numbered_rows,
                [str(i) for i in range(1, 15)],
                f"{doc_name} must list all 14 numbered AI coding agents",
            )
            self.assertIn("Grok Build", doc_txt)
            self.assertIn("Grok Bot", doc_txt)
            self.assertIn("SHA256SUMS", doc_txt)

        self.assertTrue(WORKFLOW_FILE.is_file(), "CI verification workflow must exist")
        wf_txt = WORKFLOW_FILE.read_text(encoding="utf-8")
        uses_refs = re.findall(r"uses:\s*([^\s#]+)", wf_txt)
        self.assertGreaterEqual(len(uses_refs), 2)
        for ref in uses_refs:
            self.assertRegex(
                ref,
                r"^[^@]+@[0-9a-f]{40}$",
                f"GitHub Action must be pinned to 40-char commit SHA (G-2): {ref}",
            )


if __name__ == "__main__":
    unittest.main()
