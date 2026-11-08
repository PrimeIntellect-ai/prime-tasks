#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

APP_DIR = "/home/user/app"
DAEMON_PATH = "/home/user/app/daemon"
MAIN_GO_PATH = "/home/user/app/main.go"
LOG_FILE_PATH = "/home/user/app/logs/app.log"
SUCCESS_FILE_PATH = "/home/user/success.txt"
EXPECTED_MESSAGE = "Daemon initialized: Log rotation configured for /home/user/app/logs/app.log"


def test_app_logs_directory_exists():
    """Verify that the required log directory was created."""
    dir_path = "/home/user/app/logs"
    assert os.path.isdir(dir_path), f"Expected directory {dir_path} does not exist."


def test_daemon_executable_exists():
    """Verify that the Go application was compiled to the expected binary."""
    assert os.path.isfile(DAEMON_PATH), f"Expected executable {DAEMON_PATH} does not exist."
    assert os.access(DAEMON_PATH, os.X_OK), f"The file {DAEMON_PATH} is not executable."


def test_daemon_is_go_binary_and_matches_source_behavior():
    """Build the current source and compare its behavior with the submitted Go binary."""
    with open(DAEMON_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The daemon is not a compiled Linux binary."

    metadata = subprocess.run(
        ["go", "version", "-m", DAEMON_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert metadata.returncode == 0, f"The daemon is not recognized as a Go binary: {metadata.stderr}"

    with tempfile.TemporaryDirectory() as tmpdir:
        reference_daemon = os.path.join(tmpdir, "daemon")
        build = subprocess.run(
            ["go", "build", "-o", reference_daemon, MAIN_GO_PATH],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"main.go does not compile successfully: {build.stderr}"

        if os.path.exists(LOG_FILE_PATH):
            os.remove(LOG_FILE_PATH)
        reference_run = subprocess.run(
            [reference_daemon], capture_output=True, text=True, timeout=10
        )
        assert reference_run.returncode == 0, f"Binary built from main.go failed: {reference_run.stderr}"

        if os.path.exists(LOG_FILE_PATH):
            os.remove(LOG_FILE_PATH)
        submitted_run = subprocess.run(
            [DAEMON_PATH], capture_output=True, text=True, timeout=10
        )
        assert submitted_run.returncode == 0, f"Submitted daemon failed: {submitted_run.stderr}"
        assert submitted_run.stdout == reference_run.stdout, (
            "Submitted daemon output does not match the output of the current main.go source."
        )
        assert EXPECTED_MESSAGE in submitted_run.stdout, (
            f"Submitted daemon did not print the expected startup message: {submitted_run.stdout}"
        )
        assert os.path.isfile(LOG_FILE_PATH), "Running the submitted daemon did not create its log file."

        assert os.path.isfile(SUCCESS_FILE_PATH), f"Expected output file {SUCCESS_FILE_PATH} does not exist."
        with open(SUCCESS_FILE_PATH, "r") as f:
            saved_output = f.read()
        assert saved_output == submitted_run.stdout, (
            "success.txt does not contain the standard output produced by the submitted daemon."
        )


def test_app_log_file_exists():
    """Verify that the daemon successfully ran and created its log file."""
    assert os.path.isfile(LOG_FILE_PATH), f"Expected log file {LOG_FILE_PATH} does not exist. Did the daemon run successfully?"


def test_success_txt_contents():
    """Verify that the success.txt file contains the correct daemon startup message."""
    assert os.path.isfile(SUCCESS_FILE_PATH), f"Expected output file {SUCCESS_FILE_PATH} does not exist."

    with open(SUCCESS_FILE_PATH, "r") as f:
        content = f.read().strip()

    assert EXPECTED_MESSAGE in content, f"The file {SUCCESS_FILE_PATH} does not contain the expected success message. Found: {content}"


def test_main_go_modified():
    """Verify that main.go was correctly modified in-place."""
    assert os.path.isfile(MAIN_GO_PATH), f"Expected source file {MAIN_GO_PATH} does not exist."

    with open(MAIN_GO_PATH, "r") as f:
        content = f.read()

    assert "/var/log/customdaemon/app.log" not in content, "The old restricted path was not removed from main.go."
    assert "/home/user/app/logs/app.log" in content, "The new local path was not found in main.go."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
