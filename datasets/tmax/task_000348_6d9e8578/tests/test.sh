#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import random
import string
import subprocess
import tempfile
import time
import pytest

AGENT_SCRIPT = "/home/user/sanitize.py"
ORACLE_SCRIPT = "/tests/oracle_sanitize.py"
LOG_FILE = "/tmp/artifact_db.log"


def generate_random_path(length, absolute=False):
    chars = string.ascii_letters + string.digits + "_-"
    parts = []
    current_len = 0
    while current_len < length:
        part_len = random.randint(1, 10)
        part = ''.join(random.choices(chars, k=part_len))
        parts.append(part)
        current_len += part_len + 1
    path = "/".join(parts)[:length]
    if absolute and not path.startswith("/"):
        path = "/" + path.lstrip("/")
    return path


def generate_manifest_line():
    length = random.randint(5, 50)
    chars = string.ascii_letters + string.digits + "_-."

    if random.random() < 0.5:
        malicious_parts = ["../", "..", "/../", "/"]
        part = random.choice(malicious_parts)
        rest_len = max(1, length - len(part))
        rest = ''.join(random.choices(chars + "/", k=rest_len))
        if part == "/":
            return part + rest
        mid = len(rest) // 2
        return rest[:mid] + part + rest[mid:]
    return ''.join(random.choices(chars + "/", k=length))


def output_lines(text):
    stripped = text.strip()
    return stripped.split('\n') if stripped else []


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    expected_log_lines = []

    for i in range(100):
        target_dir = generate_random_path(random.randint(10, 30), absolute=True)
        manifest_lines = [generate_manifest_line() for _ in range(random.randint(10, 50))]

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            for line in manifest_lines:
                f.write(line + "\n")
            manifest_path = f.name

        try:
            oracle_cmd = ["python3", ORACLE_SCRIPT, target_dir, manifest_path]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)

            agent_cmd = ["python3", AGENT_SCRIPT, target_dir, manifest_path]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            if oracle_out != agent_out:
                pytest.fail(
                    f"Mismatch on iteration {i}.\n"
                    f"Target dir: {target_dir}\n"
                    f"Manifest:\n{chr(10).join(manifest_lines)}\n"
                    f"Oracle output:\n{oracle_out}\n"
                    f"Agent output:\n{agent_out}"
                )

            expected_log_lines.extend(output_lines(oracle_res.stdout))
        finally:
            os.remove(manifest_path)

    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} was not created by the agent script"
    with open(LOG_FILE, 'r') as f:
        log_content = f.read().strip()

    if expected_log_lines:
        assert len(log_content) > 0, "Log file is empty but there should be logged paths"
        assert "[SECURE-BIN-84]" in log_content, "Log file does not contain the expected repo ID"

    log_lines = output_lines(log_content)
    assert len(log_lines) == len(expected_log_lines), (
        f"Log file has {len(log_lines)} lines, expected {len(expected_log_lines)}"
    )
    assert log_lines == expected_log_lines, "Log file lines do not exactly match stdout output"


def test_agent_uses_file_locking():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    with open(AGENT_SCRIPT, 'r') as f:
        content = f.read()
    assert "fcntl" in content, "The script does not import or use fcntl"
    assert "flock" in content, "The script does not use flock for file locking as required"

    with open(LOG_FILE, 'r') as f:
        prior_lines = output_lines(f.read())

    with tempfile.NamedTemporaryFile(mode='w', delete=False) as manifest:
        manifest.write("locked/item.bin\n")
        manifest_path = manifest.name

    target_dir = "/tmp/locking-target"
    oracle_res = subprocess.run(
        ["python3", ORACLE_SCRIPT, target_dir, manifest_path],
        capture_output=True,
        text=True,
        check=True,
    )
    expected_new_lines = output_lines(oracle_res.stdout)
    assert expected_new_lines, "Locking test must produce a safe output line"

    proc = None
    try:
        with open(LOG_FILE, 'a+') as held_log:
            fcntl.flock(held_log.fileno(), fcntl.LOCK_EX)
            env = os.environ.copy()
            env["PYTHONUNBUFFERED"] = "1"
            proc = subprocess.Popen(
                ["python3", AGENT_SCRIPT, target_dir, manifest_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )
            time.sleep(3)
            assert proc.poll() is None, (
                "Agent completed while another process held an exclusive lock on the log file"
            )
            fcntl.flock(held_log.fileno(), fcntl.LOCK_UN)

        stdout, stderr = proc.communicate(timeout=20)
        assert proc.returncode == 0, f"Agent failed during locking test: {stderr}"
        assert stdout.strip() == oracle_res.stdout.strip(), "Locking test stdout mismatch"
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.communicate()
        os.remove(manifest_path)

    with open(LOG_FILE, 'r') as f:
        final_lines = output_lines(f.read())
    assert final_lines == prior_lines + expected_new_lines, (
        "The locked invocation did not append the exact stdout lines to the log"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
