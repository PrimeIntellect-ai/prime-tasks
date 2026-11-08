#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import string
import subprocess
import tempfile

import pytest

REPORT_PATH = "/home/user/audit_report.json"
AUDITOR_PATH = "/home/user/auditor.py"
LOG_DIR = "/home/user/app/logs"
CERT_DIR = "/home/user/app/certs"


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")


def run_auditor():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", AUDITOR_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"auditor.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not created by auditor.py."
    return load_report()


def test_auditor_exists_and_is_python_source():
    assert os.path.exists(AUDITOR_PATH), f"Required script {AUDITOR_PATH} is missing."
    assert not os.path.islink(AUDITOR_PATH), f"{AUDITOR_PATH} must be a regular file, not a symlink."
    assert stat.S_ISREG(os.lstat(AUDITOR_PATH).st_mode), f"{AUDITOR_PATH} is not a regular file."
    result = subprocess.run(
        ["python3", "-m", "py_compile", AUDITOR_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"{AUDITOR_PATH} is not valid Python: {result.stderr}"


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not created."


def test_report_content():
    report = load_report()

    # 1. Certificate Validation
    assert "cert_valid" in report, "Key 'cert_valid' missing from report."
    assert report["cert_valid"] is True, "'cert_valid' should be true based on the provided certificates."

    # 2. Intrusion Detection & Redaction
    assert "intrusions" in report, "Key 'intrusions' missing from report."
    expected_intrusions = [
        "192.168.1.50 - GET /api/data?key=[REDACTED]&query=UNION SELECT * FROM users HTTP/1.1",
        "10.0.0.2 - GET /download?file=../../../../etc/passwd HTTP/1.1"
    ]
    actual_intrusions = report["intrusions"]
    assert isinstance(actual_intrusions, list), "'intrusions' should be a list."
    assert len(actual_intrusions) == len(expected_intrusions), f"Expected {len(expected_intrusions)} intrusions, found {len(actual_intrusions)}."

    for expected in expected_intrusions:
        assert expected in actual_intrusions, f"Missing expected intrusion line: {expected}"

    # 3. Fixed Files
    assert "fixed_files" in report, "Key 'fixed_files' missing from report."
    expected_fixed = {
        "/home/user/app/logs/access.log",
        "/home/user/app/logs/debug.log"
    }
    actual_fixed = report["fixed_files"]
    assert isinstance(actual_fixed, list), "'fixed_files' should be a list."
    assert set(actual_fixed) == expected_fixed, f"Expected fixed_files to be {expected_fixed}, but got {set(actual_fixed)}."


def test_file_permissions_fixed():
    # Check that no files in the log directory are accessible by 'others'
    # and that the specific files were modified to 640.
    assert os.path.isdir(LOG_DIR), f"Log directory {LOG_DIR} is missing."

    for filename in os.listdir(LOG_DIR):
        filepath = os.path.join(LOG_DIR, filename)
        if not os.path.isfile(filepath):
            continue

        st = os.stat(filepath)
        mode = stat.S_IMODE(st.st_mode)
        assert (mode & stat.S_IRWXO) == 0, f"File {filepath} still grants permissions to 'others' (mode: {oct(mode)})."

    for target_file in ["access.log", "debug.log"]:
        filepath = os.path.join(LOG_DIR, target_file)
        if os.path.isfile(filepath):
            mode = stat.S_IMODE(os.stat(filepath).st_mode)
            assert mode == 0o640, f"File {filepath} permissions were not set to exactly 640 (current: {oct(mode)})."


def test_auditor_operates_on_dynamic_inputs():
    assert os.path.isfile(AUDITOR_PATH)
    work = tempfile.mkdtemp(prefix="auditor-verifier-")
    saved_logs = os.path.join(work, "saved-logs")
    server_path = os.path.join(CERT_DIR, "server.pem")
    original_server = open(server_path, "rb").read()
    report_existed = os.path.exists(REPORT_PATH)
    original_report = open(REPORT_PATH, "rb").read() if report_existed else None

    alphabet = string.ascii_uppercase + string.digits
    aws_key1 = "AKIA" + "".join(secrets.choice(alphabet) for _ in range(16))
    aws_key2 = "AKIA" + "".join(secrets.choice(alphabet) for _ in range(16))
    marker = secrets.token_hex(10)
    offender_name = f"world-{secrets.token_hex(6)}.log"
    offender_path = os.path.join(LOG_DIR, offender_name)

    try:
        shutil.move(LOG_DIR, saved_logs)
        os.mkdir(LOG_DIR, 0o750)

        line1 = f"{marker} GET /search?credential={aws_key1}&q=uNiOn SeLeCt secret"
        line2 = f"{marker} GET /files/../private/{aws_key2}"
        line3 = f"{marker} GET /view?name=EtC/PaSsWd"
        benign = f"{marker} GET /status?credential={aws_key2}"
        expected_intrusions = [
            line1.replace(aws_key1, "[REDACTED]"),
            line2.replace(aws_key2, "[REDACTED]"),
            line3,
        ]

        access_path = os.path.join(LOG_DIR, "access.log")
        with open(access_path, "w") as f:
            f.write("\n".join([benign, line1, line2, line3]) + "\n")
        os.chmod(access_path, 0o644)

        with open(offender_path, "w") as f:
            f.write("dynamic permission target\n")
        os.chmod(offender_path, 0o777)

        secure_path = os.path.join(LOG_DIR, "secure.log")
        with open(secure_path, "w") as f:
            f.write("already secure\n")
        os.chmod(secure_path, 0o640)

        report = run_auditor()
        assert report.get("cert_valid") is True, "The supplied CA/server chain should validate."
        assert isinstance(report.get("intrusions"), list), "'intrusions' should be a list."
        assert report["intrusions"] == expected_intrusions, (
            "auditor.py did not scan the dynamic log case-insensitively and redact all AWS keys correctly."
        )
        expected_fixed = {access_path, offender_path}
        assert isinstance(report.get("fixed_files"), list), "'fixed_files' should be a list."
        assert set(report["fixed_files"]) == expected_fixed, (
            f"Expected dynamically insecure files {expected_fixed}, got {report.get('fixed_files')}."
        )
        assert stat.S_IMODE(os.stat(access_path).st_mode) == 0o640
        assert stat.S_IMODE(os.stat(offender_path).st_mode) == 0o640
        assert stat.S_IMODE(os.stat(secure_path).st_mode) == 0o640

        rogue_key = os.path.join(work, "rogue.key")
        rogue_cert = os.path.join(work, "rogue.pem")
        generated = subprocess.run(
            [
                "openssl", "req", "-new", "-x509", "-nodes", "-days", "2",
                "-subj", f"/CN=rogue-{marker}", "-keyout", rogue_key, "-out", rogue_cert,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert generated.returncode == 0, f"Could not generate verifier certificate: {generated.stderr}"
        shutil.copyfile(rogue_cert, server_path)

        second_key = "AKIA" + "".join(secrets.choice(alphabet) for _ in range(16))
        second_line = f"{marker}-second GET /query?x=UNION SELECT&key={second_key}"
        with open(access_path, "w") as f:
            f.write(second_line + "\n")
        os.chmod(access_path, 0o640)
        os.chmod(offender_path, 0o606)

        report = run_auditor()
        assert report.get("cert_valid") is False, (
            "A current but self-signed rogue server certificate must not validate against ca.pem."
        )
        assert report.get("intrusions") == [second_line.replace(second_key, "[REDACTED]")], (
            "The report was not regenerated from the changed access log."
        )
        assert set(report.get("fixed_files", [])) == {offender_path}, (
            "The report did not reflect the changed file permissions on the second execution."
        )
        assert stat.S_IMODE(os.stat(offender_path).st_mode) == 0o640
    finally:
        with open(server_path, "wb") as f:
            f.write(original_server)
        if os.path.exists(LOG_DIR):
            shutil.rmtree(LOG_DIR)
        if os.path.exists(saved_logs):
            shutil.move(saved_logs, LOG_DIR)
        if report_existed:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
