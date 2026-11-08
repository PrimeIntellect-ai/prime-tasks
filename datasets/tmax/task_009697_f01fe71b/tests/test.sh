#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import hashlib
import io
import ipaddress
import json
import os
import re
from pathlib import Path

import pytest

APP_DIR = Path("/home/user/app_legacy")
WORKER_PATH = APP_DIR / "worker_bin"
CHECKSUM_PATH = APP_DIR / "checksums.txt"
SERVICE_PATH = APP_DIR / "service.py"
SECRET_PATH = Path("/home/user/secrets/db_pass.txt")
REPORT_PATH = Path("/home/user/rotation_report.json")
POLICY_PATH = APP_DIR / "net_policy.json"


def worker_findings():
    assert WORKER_PATH.is_file(), f"Binary {WORKER_PATH} does not exist."
    raw = WORKER_PATH.read_bytes()
    assert raw.startswith(b"\x7fELF"), f"{WORKER_PATH} is not an ELF binary."

    password_matches = re.findall(rb"DB_PASS=([ -~]+)\x00", raw)
    ip_matches = re.findall(rb"DB_IP=((?:[0-9]{1,3}\.){3}[0-9]{1,3})\x00", raw)
    assert len(password_matches) == 1, "Expected exactly one DB_PASS string in worker_bin."
    assert len(ip_matches) == 1, "Expected exactly one DB_IP string in worker_bin."

    password = password_matches[0].decode("ascii")
    db_ip = ip_matches[0].decode("ascii")
    ipaddress.ip_address(db_ip)

    assert CHECKSUM_PATH.is_file(), f"Checksum file {CHECKSUM_PATH} does not exist."
    expected_hashes = []
    for line in CHECKSUM_PATH.read_text().splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2 or not re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]):
            continue
        listed_name = parts[1].strip().lstrip("*")
        if os.path.basename(listed_name) == WORKER_PATH.name:
            expected_hashes.append(parts[0].lower())

    assert len(expected_hashes) == 1, "checksums.txt must contain one valid SHA256 entry for worker_bin."
    actual_hash = hashlib.sha256(raw).hexdigest()
    return password, db_ip, actual_hash == expected_hashes[0]


def test_rotation_report_json():
    assert REPORT_PATH.is_file(), f"Report file {REPORT_PATH} does not exist."
    try:
        data = json.loads(REPORT_PATH.read_text())
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    old_password, db_ip, worker_bin_valid = worker_findings()
    expected_data = {
        "old_password": old_password,
        "worker_bin_valid": worker_bin_valid,
        "python_cwe": "CWE-798",
        "db_ip": db_ip,
    }

    for key, expected_val in expected_data.items():
        assert key in data, f"Key '{key}' missing from {REPORT_PATH}."
        assert data[key] == expected_val, f"Expected '{key}' to be {expected_val}, but got {data[key]}."


def test_net_policy_json():
    assert POLICY_PATH.is_file(), f"Network policy file {POLICY_PATH} does not exist."
    try:
        data = json.loads(POLICY_PATH.read_text())
    except json.JSONDecodeError:
        pytest.fail(f"File {POLICY_PATH} is not valid JSON.")

    _, db_ip, _ = worker_findings()
    assert "allowed_ips" in data, f"'allowed_ips' missing from {POLICY_PATH}."
    assert isinstance(data["allowed_ips"], list), "'allowed_ips' must be a JSON list."
    assert db_ip in data["allowed_ips"], f"IP '{db_ip}' missing from 'allowed_ips' in {POLICY_PATH}."
    assert "action" in data, f"'action' missing from {POLICY_PATH}."
    assert data["action"] == "allow", f"Expected 'action' to be 'allow', but got {data['action']}."


def test_db_pass_txt():
    assert SECRET_PATH.is_file(), f"Password file {SECRET_PATH} does not exist."
    content = SECRET_PATH.read_text().strip()
    assert content == "SecureRotatedPass2024!", f"Expected password to be 'SecureRotatedPass2024!', but got '{content}'."


def test_service_py_modifications(monkeypatch):
    assert SERVICE_PATH.is_file(), f"Service script {SERVICE_PATH} does not exist."
    content = SERVICE_PATH.read_text()
    assert "LegacyPass9988!" not in content, f"Hardcoded password is still present in {SERVICE_PATH}."
    assert str(SECRET_PATH) in content, f"Script {SERVICE_PATH} does not seem to read from '{SECRET_PATH}'."

    state = {"opened": False, "read": False}
    tracked_fds = set()
    target = os.path.realpath(SECRET_PATH)

    def is_target(path):
        try:
            return os.path.realpath(os.fspath(path)) == target
        except TypeError:
            return False

    class TrackingFile:
        def __init__(self, wrapped):
            self._wrapped = wrapped

        def __getattr__(self, name):
            return getattr(self._wrapped, name)

        def __enter__(self):
            self._wrapped.__enter__()
            return self

        def __exit__(self, *args):
            return self._wrapped.__exit__(*args)

        def __iter__(self):
            return self

        def __next__(self):
            state["read"] = True
            return next(self._wrapped)

        def read(self, *args, **kwargs):
            state["read"] = True
            return self._wrapped.read(*args, **kwargs)

        def readline(self, *args, **kwargs):
            state["read"] = True
            return self._wrapped.readline(*args, **kwargs)

        def readlines(self, *args, **kwargs):
            state["read"] = True
            return self._wrapped.readlines(*args, **kwargs)

        def readinto(self, *args, **kwargs):
            state["read"] = True
            return self._wrapped.readinto(*args, **kwargs)

    original_builtin_open = builtins.open
    original_io_open = io.open
    original_os_open = os.open
    original_os_read = os.read
    original_os_fdopen = os.fdopen

    def wrap_open(original):
        def tracked_open(file, *args, **kwargs):
            wrapped = original(file, *args, **kwargs)
            if is_target(file):
                state["opened"] = True
                return TrackingFile(wrapped)
            if isinstance(file, int) and file in tracked_fds:
                return TrackingFile(wrapped)
            return wrapped
        return tracked_open

    def tracked_os_open(path, *args, **kwargs):
        fd = original_os_open(path, *args, **kwargs)
        if is_target(path):
            state["opened"] = True
            tracked_fds.add(fd)
        return fd

    def tracked_os_read(fd, *args, **kwargs):
        if fd in tracked_fds:
            state["read"] = True
        return original_os_read(fd, *args, **kwargs)

    def tracked_os_fdopen(fd, *args, **kwargs):
        wrapped = original_os_fdopen(fd, *args, **kwargs)
        if fd in tracked_fds:
            return TrackingFile(wrapped)
        return wrapped

    code = compile(content, str(SERVICE_PATH), "exec")
    monkeypatch.setattr(builtins, "open", wrap_open(original_builtin_open))
    monkeypatch.setattr(io, "open", wrap_open(original_io_open))
    monkeypatch.setattr(os, "open", tracked_os_open)
    monkeypatch.setattr(os, "read", tracked_os_read)
    monkeypatch.setattr(os, "fdopen", tracked_os_fdopen)

    namespace = {
        "__name__": "__main__",
        "__file__": str(SERVICE_PATH),
        "__builtins__": builtins.__dict__,
    }
    exec(code, namespace, namespace)

    assert state["opened"], f"Executing {SERVICE_PATH} did not open {SECRET_PATH}."
    assert state["read"], f"Executing {SERVICE_PATH} opened but did not read {SECRET_PATH}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
