#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import http.server
import json
import os
import secrets
import stat
import subprocess
import threading
import urllib.request

import pytest

AUDIT_GO = "/home/user/audit.go"
REPORT_JSON = "/home/user/report.json"
APP_DIR = "/home/user/app"


def get_expected_files(base_dir):
    suid_files = []
    world_writable_files = []

    if os.path.isdir(base_dir):
        for root, _, files in os.walk(base_dir):
            for file in files:
                filepath = os.path.join(root, file)
                try:
                    st = os.stat(filepath)
                    mode = st.st_mode
                    if mode & stat.S_ISUID:
                        suid_files.append(filepath)
                    if mode & stat.S_IWOTH:
                        world_writable_files.append(filepath)
                except OSError:
                    pass

    return sorted(suid_files), sorted(world_writable_files)


def check_csp(url):
    try:
        response = urllib.request.urlopen(url, timeout=5)
        csp = response.headers.get("Content-Security-Policy")
        return bool(csp and csp.strip())
    except Exception:
        return False


class ReusableHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True


@contextlib.contextmanager
def local_server(csp_value):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            if csp_value is not None:
                self.send_header("Content-Security-Policy", csp_value)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, format, *args):
            pass

    server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()


def load_and_check_report():
    assert os.path.isfile(REPORT_JSON), (
        f"{REPORT_JSON} does not exist. Did the Go program generate it?"
    )

    with open(REPORT_JSON, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_JSON} is not a valid JSON file.")

    expected_suid, expected_ww = get_expected_files(APP_DIR)
    expected_csp = check_csp("http://localhost:8080/")

    assert "suid_files" in report, "Missing 'suid_files' key in report.json"
    assert "world_writable_files" in report, "Missing 'world_writable_files' key in report.json"
    assert "csp_enforced" in report, "Missing 'csp_enforced' key in report.json"

    assert isinstance(report["suid_files"], list), "'suid_files' must be a list"
    assert isinstance(report["world_writable_files"], list), "'world_writable_files' must be a list"
    assert isinstance(report["csp_enforced"], bool), "'csp_enforced' must be a boolean"

    assert sorted(report["suid_files"]) == expected_suid, (
        f"Expected suid_files to be {expected_suid}, got {sorted(report['suid_files'])}"
    )
    assert sorted(report["world_writable_files"]) == expected_ww, (
        f"Expected world_writable_files to be {expected_ww}, got {sorted(report['world_writable_files'])}"
    )
    assert report["csp_enforced"] == expected_csp, (
        f"Expected csp_enforced to be {expected_csp}, got {report['csp_enforced']}"
    )


def run_auditor(binary):
    if os.path.lexists(REPORT_JSON):
        if os.path.isdir(REPORT_JSON) and not os.path.islink(REPORT_JSON):
            pytest.fail(f"{REPORT_JSON} is a directory")
        os.unlink(REPORT_JSON)

    result = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Compiled audit program exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    load_and_check_report()


def test_audit_go_exists():
    assert os.path.isfile(AUDIT_GO), f"{AUDIT_GO} does not exist."
    source_stat = os.lstat(AUDIT_GO)
    assert stat.S_ISREG(source_stat.st_mode), f"{AUDIT_GO} must be a regular Go source file."


def test_audit_program_compiles_runs_and_recomputes_findings(tmp_path):
    binary = str(tmp_path / "audit")
    build = subprocess.run(
        ["go", "build", "-o", binary, AUDIT_GO],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, (
        f"{AUDIT_GO} did not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    token = secrets.token_hex(12)
    test_dir = os.path.join(APP_DIR, ".verifier_" + token)
    suid_path = os.path.join(test_dir, "suid_" + token)
    writable_path = os.path.join(test_dir, "writable_" + token)
    changed_path = os.path.join(test_dir, "changed_" + token)

    os.mkdir(test_dir, 0o755)
    try:
        for path in (suid_path, writable_path, changed_path):
            with open(path, "wb") as f:
                f.write(token.encode("ascii"))

        os.chmod(suid_path, 0o4755)
        os.chmod(writable_path, 0o666)
        os.chmod(changed_path, 0o644)

        with local_server("default-src 'self'"):
            run_auditor(binary)

        os.chmod(suid_path, 0o755)
        os.chmod(writable_path, 0o644)
        os.chmod(changed_path, 0o4777)

        with local_server(None):
            run_auditor(binary)
    finally:
        for path in (suid_path, writable_path, changed_path):
            try:
                os.chmod(path, 0o644)
                os.unlink(path)
            except FileNotFoundError:
                pass
        try:
            os.rmdir(test_dir)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
