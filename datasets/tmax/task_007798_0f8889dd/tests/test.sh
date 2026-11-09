#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import shutil
import stat
import subprocess
import tempfile
import time

WORKER_PATH = "/tmp/worker.sock"
SCRIPT_PATH = "/home/user/process_data.sh"


def remove_worker_path():
    if os.path.islink(WORKER_PATH) or os.path.isfile(WORKER_PATH):
        os.unlink(WORKER_PATH)
    elif os.path.isdir(WORKER_PATH):
        shutil.rmtree(WORKER_PATH)


def run_with_lines(lines, worker_exists=False):
    remove_worker_path()
    if worker_exists:
        with open(WORKER_PATH, "w"):
            pass

    fd, input_path = tempfile.mkstemp(prefix="process-data-input-", text=True)
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")

        try:
            return subprocess.run(
                [SCRIPT_PATH, input_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=2.0,
            )
        except subprocess.TimeoutExpired:
            assert False, "The script timed out, indicating it is still hanging."
    finally:
        os.unlink(input_path)
        remove_worker_path()


def test_failing_input_file():
    path = "/home/user/failing_input.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "HALT", f"Expected failing input to be 'HALT', but got '{content}'."


def test_missing_file_txt():
    path = "/home/user/missing_file.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "/tmp/worker.sock", f"Expected missing file path to be '/tmp/worker.sock', but got '{content}'."


def test_process_data_sh_fixed_code():
    path = "/home/user/process_data.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"File {path} must be a regular file, not a symlink."
    with open(path, "r") as f:
        content = f.read()

    assert "sleep 0.1" not in content, "The script still contains 'sleep 0.1'."
    assert "while [" not in content or "worker.sock" not in content[content.find("while ["):content.find("do", content.find("while ["))], \
        "The script appears to still have a while loop waiting for the socket."


def test_process_data_sh_execution():
    script_path = "/home/user/process_data.sh"
    input_path = "/home/user/words.txt"

    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    remove_worker_path()

    start_time = time.time()
    try:
        result = subprocess.run(
            [script_path, input_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2.0
        )
    except subprocess.TimeoutExpired:
        assert False, "The script timed out, indicating it is still hanging."

    duration = time.time() - start_time
    assert duration < 1.0, f"Script took too long to execute ({duration:.2f}s), might still be hanging."

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert "Error: worker missing" in result.stdout, "The script output did not contain the expected error message 'Error: worker missing'."


def test_generated_inputs_without_worker():
    token = secrets.token_hex(12)

    no_halt = [f"BEFORE-{token}", "XHALT", f"AFTER-{token}"]
    result = run_with_lines(no_halt)
    assert result.returncode == 0, result.stderr
    assert result.stdout == "", "The missing-worker error must only be printed for the triggering line."

    mixed = [
        f"FIRST-{token}",
        "HALT",
        f"MIDDLE-{token}",
        "HALT",
        f"LAST-{token}",
        "HALT",
    ]
    expected = "Error: worker missing\n" * sum(line == "HALT" for line in mixed)
    result = run_with_lines(mixed)
    assert result.returncode == 0, result.stderr
    assert result.stdout == expected, (
        "The script must process every line and print exactly one missing-worker error "
        "for each HALT line while continuing to later lines."
    )


def test_generated_input_when_worker_exists():
    token = secrets.token_hex(12)
    lines = [f"START-{token}", "HALT", f"END-{token}", "HALT"]
    result = run_with_lines(lines, worker_exists=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout == "", "The error must not be printed when /tmp/worker.sock exists."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
