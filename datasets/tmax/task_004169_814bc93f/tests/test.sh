#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/audit_filter.py"
EVIL_DIR = "/home/user/corpora/evil"
CLEAN_DIR = "/home/user/corpora/clean"

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The audit filter script was not found at {SCRIPT_PATH}"

def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing at {EVIL_DIR}"

    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "No evil files found to test."

    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, filepath],
                capture_output=True,
                text=True,
                timeout=5
            )
            output = result.stdout.strip()
            if output != "VIOLATION":
                bypassed_files.append((filename, output))
        except subprocess.TimeoutExpired:
            bypassed_files.append((filename, "TIMEOUT"))
        except Exception as e:
            bypassed_files.append((filename, f"ERROR: {str(e)}"))

    if bypassed_files:
        details = ", ".join([f"{f} (got {out!r})" for f, out in bypassed_files])
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {details}")

def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing at {CLEAN_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No clean files found to test."

    modified_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, filepath],
                capture_output=True,
                text=True,
                timeout=5
            )
            output = result.stdout.strip()
            if output != "SAFE":
                modified_files.append((filename, output))
        except subprocess.TimeoutExpired:
            modified_files.append((filename, "TIMEOUT"))
        except Exception as e:
            modified_files.append((filename, f"ERROR: {str(e)}"))

    if modified_files:
        details = ", ".join([f"{f} (got {out!r})" for f, out in modified_files])
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified/flagged: {details}")

def test_generated_commands_are_classified_by_content():
    token = secrets.token_hex(8)
    cases = [
        (f"echo {token} > /tmp/{token}.txt", "SAFE"),
        ("sudo id", "VIOLATION"),
        (f"grep {token} /var/log/app.log", "SAFE"),
        ("su root -c id", "VIOLATION"),
        (f"cat /tmp/{token}.txt", "SAFE"),
        (f"chmod +s /tmp/{token}", "VIOLATION"),
        ("cat /etc/shadow", "VIOLATION"),
        ("cat /etc/passwd", "VIOLATION"),
        ("ls -la /opt/secure_vault", "VIOLATION"),
        (f"chown sysadmin:wheel /tmp/{token}", "VIOLATION"),
        ("python3 --version", "SAFE"),
        ("awk 'BEGIN {system(\"/bin/sh\")}'", "VIOLATION"),
    ]

    failures = []
    with tempfile.TemporaryDirectory(prefix="audit_inputs_") as directory:
        # Reuse one opaque path for every case so classification cannot depend on
        # whether the input pathname resembles a clean or evil corpus path.
        filepath = os.path.join(directory, secrets.token_hex(12))
        for command, expected in cases:
            with open(filepath, "w", encoding="utf-8") as command_file:
                command_file.write(command + "\n")
            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, filepath],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                output = result.stdout.strip()
                if output != expected:
                    failures.append((command, expected, output))
            except subprocess.TimeoutExpired:
                failures.append((command, expected, "TIMEOUT"))
            except Exception as e:
                failures.append((command, expected, f"ERROR: {str(e)}"))

    if failures:
        details = "; ".join(
            f"{command!r}: expected {expected}, got {actual!r}"
            for command, expected, actual in failures
        )
        pytest.fail(f"Generated command classification failures: {details}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
