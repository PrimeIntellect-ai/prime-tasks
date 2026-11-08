#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile

AUDIT_DIR = "/home/user/audit_system"
LOGS_DIR = os.path.join(AUDIT_DIR, "logs")
REPORT_FILE = os.path.join(AUDIT_DIR, "report.txt")
HASHES_FILE = os.path.join(AUDIT_DIR, "hashes.txt")
C_PROGRAM_FILE = os.path.join(AUDIT_DIR, "verify_integrity.c")
LOG_FILES = ["access.log", "auth.log", "system.log"]


def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} is missing."
    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f"Report file should contain exactly 3 lines, found {len(lines)}."
    assert lines[0] == "system.log", f"Line 1 of report should be 'system.log', found '{lines[0]}'."
    assert lines[1] == "10.0.5.55", f"Line 2 of report should be '10.0.5.55', found '{lines[1]}'."
    assert lines[2] == "REMEDIATED", f"Line 3 of report should be 'REMEDIATED', found '{lines[2]}'."


def test_remediated_permissions():
    assert os.path.isdir(LOGS_DIR), f"Directory {LOGS_DIR} is missing."
    dir_stat = os.stat(LOGS_DIR)
    assert oct(dir_stat.st_mode)[-3:] == '750', f"Permissions for {LOGS_DIR} should be 750, found {oct(dir_stat.st_mode)[-3:]}."

    for log_file in LOG_FILES:
        file_path = os.path.join(LOGS_DIR, log_file)
        assert os.path.isfile(file_path), f"Log file {file_path} is missing."
        file_stat = os.stat(file_path)
        assert oct(file_stat.st_mode)[-3:] == '640', f"Permissions for {file_path} should be 640, found {oct(file_stat.st_mode)[-3:]}."


def _run_program(executable):
    try:
        result = subprocess.run(
            [executable],
            cwd=AUDIT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("The compiled integrity verifier timed out.")
    return result.returncode, result.stdout + "\n" + result.stderr


def _shows_mismatch(match_result, mismatch_result, filename):
    match_rc, match_output = match_result
    mismatch_rc, mismatch_output = mismatch_result
    negative = re.compile(
        r"mismatch|tamper(?:ed)?|modified|corrupt|invalid|fail(?:ed|ure)?|"
        r"does\s+not\s+match|not\s+(?:ok|valid|match)",
        re.IGNORECASE,
    )

    if match_rc == 0 and mismatch_rc != 0:
        return True
    if negative.search(mismatch_output) and not negative.search(match_output):
        return True
    if filename in mismatch_output and filename not in match_output:
        return True
    return False


def test_c_program_exists_and_contains_openssl():
    assert os.path.isfile(C_PROGRAM_FILE), f"C program {C_PROGRAM_FILE} is missing."
    with open(C_PROGRAM_FILE, "r") as f:
        content = f.read()

    assert "openssl" in content.lower() or "evp.h" in content.lower() or "sha.h" in content.lower(), \
        "C program does not appear to include OpenSSL headers (e.g., <openssl/sha.h> or <openssl/evp.h>)."

    with tempfile.TemporaryDirectory() as build_dir:
        executable = os.path.join(build_dir, "verify_integrity")
        compilation = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", C_PROGRAM_FILE, "-o", executable, "-lcrypto"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compilation.returncode == 0, \
            "verify_integrity.c did not compile:\n" + compilation.stdout + compilation.stderr

        with open(HASHES_FILE, "rb") as f:
            original_hashes = f.read()
        original_report = None
        if os.path.exists(REPORT_FILE):
            with open(REPORT_FILE, "rb") as f:
                original_report = f.read()

        try:
            for filename in LOG_FILES:
                log_path = os.path.join(LOGS_DIR, filename)
                with open(log_path, "rb") as f:
                    original_log = f.read()
                digest = hashlib.sha256(original_log).hexdigest()
                wrong_digest = "0" * 64 if digest != "0" * 64 else "f" * 64

                # A correct baseline must be distinguishable from a changed baseline.
                with open(HASHES_FILE, "w") as f:
                    f.write(f"{digest} {filename}\n")
                match_result = _run_program(executable)

                with open(HASHES_FILE, "w") as f:
                    f.write(f"{wrong_digest} {filename}\n")
                wrong_baseline_result = _run_program(executable)
                assert _shows_mismatch(match_result, wrong_baseline_result, filename), \
                    f"Program did not detect a changed SHA256 baseline for {filename}."

                # A correct baseline must also detect an actual change to the file.
                with open(HASHES_FILE, "w") as f:
                    f.write(f"{digest} {filename}\n")
                with open(log_path, "ab") as f:
                    f.write(b"\nverifier-induced-integrity-change\n")
                changed_file_result = _run_program(executable)
                assert _shows_mismatch(match_result, changed_file_result, filename), \
                    f"Program did not detect modified contents for {filename}."

                with open(log_path, "wb") as f:
                    f.write(original_log)
                os.chmod(log_path, 0o640)
        finally:
            with open(HASHES_FILE, "wb") as f:
                f.write(original_hashes)
            if original_report is not None:
                with open(REPORT_FILE, "wb") as f:
                    f.write(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
