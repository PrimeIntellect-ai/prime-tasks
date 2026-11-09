#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess
import tempfile

import pytest

AUDIT_DIR = "/home/user/audit"
SOURCE_PATH = os.path.join(AUDIT_DIR, "parser.c")
BINARY_PATH = os.path.join(AUDIT_DIR, "parser_fixed")
REPORT_PATH = "/home/user/audit_report.txt"


def get_expected_cookie():
    dump_path = os.path.join(AUDIT_DIR, "http_traffic.dump")
    if not os.path.isfile(dump_path):
        return None
    with open(dump_path, "r") as f:
        for line in f:
            if line.lower().startswith("set-cookie:"):
                match = re.search(r"session=([^;]+)", line)
                if match:
                    return match.group(1)
    return None


def get_expected_log():
    checksum_path = os.path.join(AUDIT_DIR, "checksum.txt")
    logs_dir = os.path.join(AUDIT_DIR, "logs")
    if not os.path.isfile(checksum_path) or not os.path.isdir(logs_dir):
        return None

    with open(checksum_path, "r") as f:
        expected_hash = f.read().strip()

    for filename in os.listdir(logs_dir):
        filepath = os.path.join(logs_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as lf:
                file_hash = hashlib.sha256(lf.read()).hexdigest()
            if file_hash == expected_hash:
                return filename
    return None


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), "The report file /home/user/audit_report.txt is missing."


def test_report_content():
    expected_cookie = get_expected_cookie()
    assert expected_cookie is not None, "Could not compute expected cookie from dump."

    expected_log = get_expected_log()
    assert expected_log is not None, "Could not compute expected log file from checksum."

    with open(REPORT_PATH, "r") as f:
        lines = f.read().splitlines()

    assert lines == [
        f"Cookie: {expected_cookie}",
        f"Valid Log: {expected_log}",
        "CWE: CWE-732",
        "Fixed: Yes",
    ], "The report must contain exactly the required four lines in the required order."


def test_parser_fixed_executable():
    assert os.path.isfile(BINARY_PATH), f"The fixed binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"The fixed binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "parser_fixed must be a compiled ELF executable, not a script."


def test_parser_fixed_was_compiled_from_parser_source():
    assert os.path.isfile(SOURCE_PATH), f"The modified source {SOURCE_PATH} is missing."
    assert os.path.isfile(BINARY_PATH), f"The fixed binary {BINARY_PATH} is missing."

    with tempfile.TemporaryDirectory(prefix="parser-rebuild-") as td:
        rebuilt = os.path.join(td, "parser_fixed")
        result = subprocess.run(
            ["/usr/bin/gcc", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"parser.c does not compile with the required command: {result.stderr}"
        assert sha256_file(BINARY_PATH) == sha256_file(rebuilt), (
            "parser_fixed is not the executable produced by compiling the current parser.c "
            "with the required gcc command."
        )


def test_parser_fixed_permissions():
    test_out = os.path.join(AUDIT_DIR, next(tempfile._get_candidate_names()) + ".txt")
    assert not os.path.exists(test_out)

    old_umask = os.umask(0)
    try:
        result = subprocess.run(
            [BINARY_PATH, test_out],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    finally:
        os.umask(old_umask)

    try:
        assert result.returncode == 0, f"Execution of {BINARY_PATH} failed: {result.stderr}"
        assert os.path.isfile(test_out), f"The binary {BINARY_PATH} did not create the output file."
        perms = stat.S_IMODE(os.stat(test_out).st_mode)
        assert perms == 0o600, (
            f"The fixed binary created a file with incorrect permissions. "
            f"Expected 0600, got {oct(perms)}."
        )
    finally:
        if os.path.exists(test_out):
            os.remove(test_out)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
