#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import uuid
import fcntl
import subprocess
import pytest

DAEMON_SOURCE = "/home/user/doc_daemon.go"
RAW_DIR = "/home/user/raw_docs"
PROCESSED_DIR = "/home/user/processed_docs"
SUFFIX = "\n\n---\nProcessed by DocWatchdog"
ACTIVE_PROC = None


def wait_for_file(path, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            return True
        time.sleep(0.1)
    return os.path.exists(path)


@pytest.fixture(scope="session", autouse=True)
def build_and_launch_submitted_daemon():
    global ACTIVE_PROC

    # Stop previously launched copies so the verifier exercises the submitted
    # Go source it builds itself rather than trusting an arbitrary background job.
    subprocess.run(["pkill", "-f", "doc_daemon"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/doc_daemon_verifier", DAEMON_SOURCE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert build.returncode == 0, "The submitted Go daemon does not build:\n" + build.stdout

    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    ACTIVE_PROC = subprocess.Popen(
        ["/tmp/doc_daemon_verifier"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.0)
    assert ACTIVE_PROC.poll() is None, "The compiled doc daemon exited instead of watching the directory."


def test_doc_daemon_exists():
    assert os.path.exists("/home/user/doc_daemon.go"), "The file /home/user/doc_daemon.go does not exist."


def test_required_go_implementation_and_module():
    with open(DAEMON_SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    assert "github.com/fsnotify/fsnotify" in source, "The daemon must use the fsnotify package."
    assert "fsnotify.NewWatcher" in source, "The daemon must create an fsnotify watcher."
    assert "syscall.Flock" in source, "The daemon must acquire file locks with syscall.Flock."
    assert "syscall.LOCK_EX" in source, "The daemon must acquire an exclusive lock."
    assert "syscall.LOCK_UN" in source, "The daemon must explicitly release the file lock."

    go_mod = "/home/user/go.mod"
    assert os.path.exists(go_mod), "The required Go module was not initialized in /home/user."
    with open(go_mod, "r", encoding="utf-8") as f:
        module_text = f.read()
    assert re.search(r"(?m)^module\s+docbot\s*$", module_text), "The Go module must be named docbot."


def test_test_doc_processed():
    processed_path = "/home/user/processed_docs/test_doc.md"
    assert os.path.exists(processed_path), f"The processed file {processed_path} does not exist. Did the daemon process the initial test file?"

    with open(processed_path, "r") as f:
        content = f.read()

    expected_content = (
        "# Welcome to Acme Corp\n"
        "This document is CONFIDENTIAL - DO NOT DISTRIBUTE.\n"
        "Please keep it safe.\n\n"
        "---\n"
        "Processed by DocWatchdog"
    )

    assert content.strip() == expected_content.strip(), f"The content of {processed_path} does not match the expected output."


def test_daemon_live_processing_with_lock():
    raw_path = "/home/user/raw_docs/eval_doc.md"
    processed_path = "/home/user/processed_docs/eval_doc.md"

    # Ensure processed file doesn't exist yet
    if os.path.exists(processed_path):
        os.remove(processed_path)

    # Write to raw_docs while holding a lock
    with open(raw_path, "w") as f:
        # Acquire exclusive lock
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)

        f.write("{{COMPANY_NAME}} Annual Report\nStatus: {{STATUS}}\n")
        f.flush()

        # Hold the lock for 2 seconds to test daemon's wait capability
        time.sleep(2)

        # Release lock
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    # Wait for the daemon to process the file
    time.sleep(2)

    assert os.path.exists(processed_path), "The daemon failed to process a newly created file (eval_doc.md) after it was unlocked."

    with open(processed_path, "r") as f:
        content = f.read()

    expected_content = (
        "Acme Corp Annual Report\n"
        "Status: CONFIDENTIAL - DO NOT DISTRIBUTE\n\n"
        "---\n"
        "Processed by DocWatchdog"
    )

    assert content.strip() == expected_content.strip(), "The content of the dynamically processed eval_doc.md does not match the expected output."


def test_random_unpredictable_file_is_read_transformed_and_locked():
    token = uuid.uuid4().hex
    filename = f"audit_{token}.md"
    staging_path = f"/home/user/staging_{token}.tmp"
    raw_path = os.path.join(RAW_DIR, filename)
    processed_path = os.path.join(PROCESSED_DIR, filename)

    secret_a = uuid.uuid4().hex
    secret_b = uuid.uuid4().hex
    original = (
        f"# {secret_a} {{COMPANY_NAME}}\n"
        f"Unchanged value: {secret_b}\n"
        "{{STATUS}} / {{COMPANY_NAME}} / {{STATUS}}"
    )
    expected = (original
                .replace("{{COMPANY_NAME}}", "Acme Corp")
                .replace("{{STATUS}}", "CONFIDENTIAL - DO NOT DISTRIBUTE")
                + SUFFIX)

    if os.path.exists(processed_path):
        os.remove(processed_path)

    # Create and lock the inode outside the watched directory, then move it into
    # raw_docs while still locked. This avoids any race between Create and flock.
    with open(staging_path, "w", encoding="utf-8") as f:
        f.write(original)
        f.flush()
        os.fsync(f.fileno())
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        os.rename(staging_path, raw_path)

        time.sleep(1.2)
        assert not os.path.exists(processed_path), "The daemon produced output before the input file's exclusive lock was released."

        fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    assert wait_for_file(processed_path), "The daemon did not process a randomly named Markdown file after its lock was released."
    with open(processed_path, "r", encoding="utf-8") as f:
        actual = f.read()

    assert actual == expected, "The daemon did not derive the output from the randomized input using the required replacements and exact suffix."
    assert ACTIVE_PROC.poll() is None, "The submitted daemon stopped running during verification."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
