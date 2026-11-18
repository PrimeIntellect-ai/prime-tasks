#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

SECURE_AUDIT_DIR = Path("/home/user/secure_audit")
APP_LOGS_DIR = Path("/home/user/app_logs")
AUDIT_REPORT = Path("/home/user/audit_report.txt")
SCRIPT = Path("/home/user/redact_logs.py")
TOKEN_PATTERN = re.compile(r"Token:\s+[a-zA-Z0-9]+")

ORIGINAL_LOGS = {
    "web_access.log": (
        "[INFO] 10.0.0.1 - GET /login HTTP/1.1\n"
        "[DEBUG] User authenticated successfully. Token: xJ92mA01\n"
        "[INFO] 10.0.0.1 - GET /dashboard HTTP/1.1\n"
        "[DEBUG] Checking session. Token: xJ92mA01\n"
    ),
    "api_error.log": (
        "[ERROR] Failed to fetch data. Token: Invalid883\n"
        "[WARN] Rate limit exceeded for Token: RateLim55\n"
        "[ERROR] Missing parameters.\n"
    ),
    "system.log": (
        "[INFO] System startup at 00:00:00.\n"
        "[INFO] Loading modules...\n"
        "[INFO] Ready.\n"
    ),
}


def get_permissions(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def run_script():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f"redact_logs.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_original_inputs_unchanged():
    actual_names = {p.name for p in APP_LOGS_DIR.glob("*.log") if p.is_file()}
    assert actual_names == set(ORIGINAL_LOGS), "The supplied raw .log files were removed, renamed, or augmented."
    for name, expected in ORIGINAL_LOGS.items():
        assert (APP_LOGS_DIR / name).read_text() == expected, f"Raw log {name} was modified."


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert SCRIPT.exists(), f"Required script {SCRIPT} does not exist."
    assert SCRIPT.is_file() and not SCRIPT.is_symlink(), f"{SCRIPT} must be a regular file."
    assert_original_inputs_unchanged()

    if SECURE_AUDIT_DIR.exists() or SECURE_AUDIT_DIR.is_symlink():
        if SECURE_AUDIT_DIR.is_dir() and not SECURE_AUDIT_DIR.is_symlink():
            shutil.rmtree(SECURE_AUDIT_DIR)
        else:
            SECURE_AUDIT_DIR.unlink()
    if AUDIT_REPORT.exists() or AUDIT_REPORT.is_symlink():
        AUDIT_REPORT.unlink()

    run_script()
    assert_original_inputs_unchanged()
    yield


def test_secure_audit_directory_permissions():
    assert os.path.isdir(SECURE_AUDIT_DIR), f"Directory {SECURE_AUDIT_DIR} does not exist."
    perms = get_permissions(SECURE_AUDIT_DIR)
    assert perms == 0o700, f"Directory {SECURE_AUDIT_DIR} should have 700 permissions, got {oct(perms)}."


def test_redacted_logs_content_and_permissions():
    log_files = ["web_access.log", "api_error.log", "system.log"]
    total_expected_redactions = 0
    token_pattern = re.compile(r"Token:\s+[a-zA-Z0-9]+")

    for filename in log_files:
        orig_path = os.path.join(APP_LOGS_DIR, filename)
        secure_path = os.path.join(SECURE_AUDIT_DIR, filename)

        assert os.path.isfile(secure_path), f"Redacted log file {secure_path} does not exist."

        perms = get_permissions(secure_path)
        assert perms == 0o600, f"File {secure_path} should have 600 permissions, got {oct(perms)}."

        with open(orig_path, "r") as f:
            orig_content = f.read()

        expected_content, count = token_pattern.subn("Token: [REDACTED]", orig_content)
        total_expected_redactions += count

        with open(secure_path, "r") as f:
            actual_content = f.read()

        assert actual_content == expected_content, f"Content of {secure_path} does not match expected redacted content."


def test_all_log_files_are_processed():
    for orig_path in APP_LOGS_DIR.glob("*.log"):
        secure_path = SECURE_AUDIT_DIR / orig_path.name
        assert secure_path.is_file(), f"Redacted log file {secure_path} does not exist."
        expected, _ = TOKEN_PATTERN.subn("Token: [REDACTED]", orig_path.read_text())
        assert secure_path.read_text() == expected
        assert get_permissions(secure_path) == 0o600


def test_audit_report():
    assert os.path.isfile(AUDIT_REPORT), f"Audit report {AUDIT_REPORT} does not exist."

    with open(AUDIT_REPORT, "r") as f:
        content = f.read().strip()

    expected_line = "Total Redactions: 4"
    assert content == expected_line, f"Audit report content is incorrect. Expected '{expected_line}', got '{content}'."


def test_script_handles_unseen_logs_and_values():
    marker = uuid.uuid4().hex
    token_a = ("A" + marker)[:24]
    token_b = (marker.upper() + "9")[:25]
    filename = f"unseen_{uuid.uuid4().hex}.log"
    second_name = f"other_{uuid.uuid4().hex}.log"
    fixtures = {
        filename: f"prefix Token: {token_a} suffix\nToken: {token_b}\n",
        second_name: "no secret here\nToken: Z9y8X7\n",
    }
    expected = {}
    expected_count = 0
    for name, content in fixtures.items():
        expected[name], count = TOKEN_PATTERN.subn("Token: [REDACTED]", content)
        expected_count += count

    backup = Path(tempfile.mkdtemp(prefix="redact-verifier-"))
    saved_app = backup / "app_logs"
    saved_secure = backup / "secure_audit"
    saved_report = backup / "audit_report.txt"

    try:
        APP_LOGS_DIR.rename(saved_app)
        if SECURE_AUDIT_DIR.exists() or SECURE_AUDIT_DIR.is_symlink():
            SECURE_AUDIT_DIR.rename(saved_secure)
        if AUDIT_REPORT.exists() or AUDIT_REPORT.is_symlink():
            AUDIT_REPORT.rename(saved_report)

        APP_LOGS_DIR.mkdir(mode=0o755)
        account = pwd.getpwnam("user")
        os.chown(APP_LOGS_DIR, account.pw_uid, account.pw_gid)
        for name, content in fixtures.items():
            path = APP_LOGS_DIR / name
            path.write_text(content)
            os.chown(path, account.pw_uid, account.pw_gid)
            path.chmod(0o644)
        ignored = APP_LOGS_DIR / "ignored.txt"
        ignored.write_text(f"Token: {token_a}\n")
        os.chown(ignored, account.pw_uid, account.pw_gid)

        run_script()

        assert get_permissions(SECURE_AUDIT_DIR) == 0o700
        for name, original in fixtures.items():
            assert (APP_LOGS_DIR / name).read_text() == original, "The script must not modify raw logs."
            output = SECURE_AUDIT_DIR / name
            assert output.is_file(), f"The script did not process unseen .log file {name}."
            assert output.read_text() == expected[name]
            assert get_permissions(output) == 0o600

        assert AUDIT_REPORT.is_file()
        assert AUDIT_REPORT.read_text().strip() == f"Total Redactions: {expected_count}"
    finally:
        if APP_LOGS_DIR.exists():
            shutil.rmtree(APP_LOGS_DIR)
        if SECURE_AUDIT_DIR.exists() or SECURE_AUDIT_DIR.is_symlink():
            if SECURE_AUDIT_DIR.is_dir() and not SECURE_AUDIT_DIR.is_symlink():
                shutil.rmtree(SECURE_AUDIT_DIR)
            else:
                SECURE_AUDIT_DIR.unlink()
        if AUDIT_REPORT.exists() or AUDIT_REPORT.is_symlink():
            AUDIT_REPORT.unlink()
        if saved_app.exists():
            saved_app.rename(APP_LOGS_DIR)
        if saved_secure.exists() or saved_secure.is_symlink():
            saved_secure.rename(SECURE_AUDIT_DIR)
        if saved_report.exists() or saved_report.is_symlink():
            saved_report.rename(AUDIT_REPORT)
        shutil.rmtree(backup, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
