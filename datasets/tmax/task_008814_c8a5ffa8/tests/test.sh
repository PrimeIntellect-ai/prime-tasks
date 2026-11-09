#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import signal
import socket
import stat
import subprocess
import time
import uuid

import pytest

UPLOAD_SCRIPT = "/home/user/app/cgi-bin/upload.sh"
UPLOADS_DIR = "/home/user/app/uploads"
POLICY_SCRIPT = "/home/user/check_policy.sh"
JSON_PATH = "/home/user/policy_status.json"
EXPECTED_KEYS = {"cwe_identified", "port_8080_active", "uploads_dir_secure"}
USER_UID = pwd.getpwnam("user").pw_uid


def port_8080_is_listening():
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 3:
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == 8080 and fields[3] == "0A":
                            return True
        except FileNotFoundError:
            pass
    return False


def listener_inodes_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == 8080 and fields[3] == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def stop_port_8080():
    inodes = listener_inodes_8080()
    pids = set()
    for proc_name in os.listdir("/proc"):
        if not proc_name.isdigit() or int(proc_name) == os.getpid():
            continue
        fd_dir = os.path.join("/proc", proc_name, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc_name))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline and port_8080_is_listening():
        time.sleep(0.1)

    if port_8080_is_listening():
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = time.time() + 3
        while time.time() < deadline and port_8080_is_listening():
            time.sleep(0.1)

    assert not port_8080_is_listening(), "Could not stop the TCP listener on port 8080 for policy testing."


def start_port_8080():
    if not port_8080_is_listening():
        subprocess.Popen(
            ["python3", "-m", "http.server", "8080", "--directory", "/home/user/app/"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    deadline = time.time() + 5
    while time.time() < deadline and not port_8080_is_listening():
        time.sleep(0.1)
    assert port_8080_is_listening(), "Failed to restore the TCP listener on port 8080."


def run_policy(expected):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    try:
        subprocess.run(
            [POLICY_SCRIPT], check=True, capture_output=True, text=True, timeout=10
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {POLICY_SCRIPT} failed: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {POLICY_SCRIPT} timed out.")

    assert os.path.isfile(JSON_PATH), f"JSON output missing: {JSON_PATH} was not created."
    try:
        with open(JSON_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{JSON_PATH} does not contain valid JSON.")

    assert set(data.keys()) == EXPECTED_KEYS, (
        f"JSON keys must be exactly {EXPECTED_KEYS}. Found: {set(data.keys())}"
    )
    for key, value in expected.items():
        assert data[key] is value, f"JSON field {key!r} should be {value}, found {data[key]!r}."


def test_cwe_identification():
    assert os.path.isfile(UPLOAD_SCRIPT), f"File missing: {UPLOAD_SCRIPT}"
    with open(UPLOAD_SCRIPT, "r") as f:
        lines = f.readlines()
    assert len(lines) >= 2, f"{UPLOAD_SCRIPT} does not have enough lines."
    assert lines[1].strip() == "# VULNERABILITY: CWE-22", (
        f"Line 2 of {UPLOAD_SCRIPT} must be exactly '# VULNERABILITY: CWE-22'. "
        f"Found: {lines[1].strip()!r}"
    )


def test_remediation():
    assert os.path.isfile(UPLOAD_SCRIPT), f"File missing: {UPLOAD_SCRIPT}"
    with open(UPLOAD_SCRIPT, "r") as f:
        content = f.read()

    # Retain the original implementation check, then exercise the upload handler.
    has_basename = "basename" in content
    has_param_expansion = "##*/" in content
    assert has_basename or has_param_expansion, (
        f"{UPLOAD_SCRIPT} does not contain 'basename' or '##*/' for path traversal remediation."
    )

    token = "verifier_upload_" + uuid.uuid4().hex
    escaped_path = os.path.join("/home/user/app", token)
    expected_path = os.path.join(UPLOADS_DIR, token)
    for path in (escaped_path, expected_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    payload = b"VERIFIER_UPLOAD_PAYLOAD\n"
    request = b'filename="../' + token.encode() + b'"\n' + payload
    try:
        result = subprocess.run(
            [UPLOAD_SCRIPT], input=request, capture_output=True, timeout=10
        )
        assert result.returncode == 0, (
            f"Upload handler exited with {result.returncode}: {result.stderr.decode(errors='replace')}"
        )
        assert not os.path.exists(escaped_path), (
            f"Path traversal remains exploitable: upload created {escaped_path}"
        )
        assert os.path.isfile(expected_path), (
            f"Sanitized upload was not written to base filename {expected_path}"
        )
        with open(expected_path, "rb") as f:
            assert f.read() == payload, "Uploaded content was not written correctly."
    finally:
        for path in (escaped_path, expected_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_permissions_and_ownership():
    assert os.path.isdir(UPLOADS_DIR), f"Directory missing: {UPLOADS_DIR}"
    dir_stat = os.stat(UPLOADS_DIR)
    dir_mode = oct(stat.S_IMODE(dir_stat.st_mode))
    assert dir_mode == "0o700", f"Directory {UPLOADS_DIR} must have 700 permissions, found {dir_mode}"
    assert dir_stat.st_uid == USER_UID, f"Directory {UPLOADS_DIR} must be owned by user."

    for filename in os.listdir(UPLOADS_DIR):
        file_path = os.path.join(UPLOADS_DIR, filename)
        if os.path.isfile(file_path):
            file_stat = os.stat(file_path)
            file_mode = oct(stat.S_IMODE(file_stat.st_mode))
            assert file_mode == "0o600", f"File {file_path} must have 600 permissions, found {file_mode}"
            assert file_stat.st_uid == USER_UID, f"File {file_path} must be owned by user."


def test_policy_script_exists_and_executable():
    assert os.path.isfile(POLICY_SCRIPT), f"Policy script missing: {POLICY_SCRIPT}"
    assert os.access(POLICY_SCRIPT, os.X_OK), f"Policy script {POLICY_SCRIPT} is not executable."


def test_policy_script_execution_and_output():
    assert port_8080_is_listening(), "No service is currently listening on TCP port 8080."
    run_policy({
        "cwe_identified": True,
        "port_8080_active": True,
        "uploads_dir_secure": True,
    })


def test_policy_script_independently_checks_cwe():
    with open(UPLOAD_SCRIPT, "rb") as f:
        original = f.read()
    modified = original.replace(
        b"# VULNERABILITY: CWE-22", b"# VULNERABILITY: CWE-999"
    )
    assert modified != original
    try:
        with open(UPLOAD_SCRIPT, "wb") as f:
            f.write(modified)
        run_policy({
            "cwe_identified": False,
            "port_8080_active": True,
            "uploads_dir_secure": True,
        })
    finally:
        with open(UPLOAD_SCRIPT, "wb") as f:
            f.write(original)


def test_policy_script_independently_checks_permissions():
    original_mode = stat.S_IMODE(os.stat(UPLOADS_DIR).st_mode)
    try:
        os.chmod(UPLOADS_DIR, 0o755)
        run_policy({
            "cwe_identified": True,
            "port_8080_active": True,
            "uploads_dir_secure": False,
        })
    finally:
        os.chmod(UPLOADS_DIR, original_mode)


def test_policy_script_independently_checks_port():
    try:
        stop_port_8080()
        run_policy({
            "cwe_identified": True,
            "port_8080_active": False,
            "uploads_dir_secure": True,
        })
    finally:
        start_port_8080()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
