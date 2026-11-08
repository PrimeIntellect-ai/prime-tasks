#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import signal
import stat
import subprocess
import time

import pytest

SUPERVISE_SCRIPT = "/home/user/planner/supervise.sh"
ANALYZER_SCRIPT = "/home/user/analyzer.py"
SOCKET_LINK = "/home/user/planner/run/socket"
EXPECTED_TARGET = "/home/user/app/metrics.sock"
LOG_DIR = "/home/user/planner/logs"


def stop_supervisor(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)
    subprocess.run(
        ["pkill", "-f", "python3 /home/user/analyzer.py"],
        capture_output=True,
    )


@pytest.fixture(scope="session", autouse=True)
def run_supervisor():
    """Run the student's supervise.sh script with the supplied analyzer."""
    assert os.path.isfile(SUPERVISE_SCRIPT), f"{SUPERVISE_SCRIPT} does not exist."

    st = os.stat(SUPERVISE_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SUPERVISE_SCRIPT} is not executable."

    os.makedirs(LOG_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(LOG_DIR, "analyzer.log*")):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    proc = subprocess.Popen(
        ["/bin/bash", SUPERVISE_SCRIPT],
        start_new_session=True,
    )

    time.sleep(4)
    stop_supervisor(proc)
    yield


def test_directories_exist():
    """Check if the required directories were created."""
    dirs = [
        "/home/user/planner/run",
        "/home/user/planner/logs",
        "/home/user/app",
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Required directory {d} does not exist."


def test_symlink_correctness():
    """Check if the socket symlink is correct."""
    assert os.path.islink(SOCKET_LINK), f"{SOCKET_LINK} is not a symlink."
    target = os.readlink(SOCKET_LINK)
    assert target == EXPECTED_TARGET, f"Symlink points to {target}, expected {EXPECTED_TARGET}."


def test_log_rotation():
    """Check if log rotation created historical logs with correct analyzer output."""
    for i in range(1, 4):
        log_file = os.path.join(LOG_DIR, f"analyzer.log.{i}")
        assert os.path.isfile(log_file), f"Rotated log file {log_file} does not exist. Ensure the loop restarts and rotates logs."

        with open(log_file, "r") as f:
            content = f.read()
            assert "Analyzer started successfully" in content, f"Log {log_file} does not contain expected output."
            assert "Fatal: Simulated OOM exception." in content, f"Log {log_file} does not contain the crash message."


def test_supervisor_really_executes_restarts_and_rotates_analyzer():
    """Use a fresh probe analyzer to prove the requested command is repeatedly executed."""
    token = secrets.token_hex(16)
    completion_file = f"/tmp/analyzer-completions-{token}"
    sequence_file = f"/tmp/analyzer-sequence-{token}"

    with open(ANALYZER_SCRIPT, "rb") as f:
        original_analyzer = f.read()
    original_mode = stat.S_IMODE(os.stat(ANALYZER_SCRIPT).st_mode)

    probe = f'''import fcntl
import os
import time

TOKEN = {token!r}
COMPLETION_FILE = {completion_file!r}
SEQUENCE_FILE = {sequence_file!r}
SOCKET_PATH = "/home/user/planner/run/socket"
EXPECTED_TARGET = "/home/user/app/metrics.sock"

if not os.path.islink(SOCKET_PATH):
    raise SystemExit("socket path is not a symlink")
if os.readlink(SOCKET_PATH) != EXPECTED_TARGET:
    raise SystemExit("socket symlink has the wrong target")

with open(SEQUENCE_FILE, "a+") as seq:
    fcntl.flock(seq.fileno(), fcntl.LOCK_EX)
    seq.seek(0)
    text = seq.read().strip()
    idx = int(text) + 1 if text else 1
    seq.seek(0)
    seq.truncate()
    seq.write(str(idx))
    seq.flush()
    os.fsync(seq.fileno())
    fcntl.flock(seq.fileno(), fcntl.LOCK_UN)

print(f"VERIFIER_START {{TOKEN}} {{idx}}", flush=True)
time.sleep(0.12)
print(f"VERIFIER_END {{TOKEN}} {{idx}}", flush=True)
with open(COMPLETION_FILE, "a") as completed:
    completed.write(f"{{idx}}\\n")
    completed.flush()
    os.fsync(completed.fileno())
raise SystemExit(23)
'''

    proc = None
    try:
        subprocess.run(
            ["pkill", "-f", "python3 /home/user/analyzer.py"],
            capture_output=True,
        )
        for path in glob.glob(os.path.join(LOG_DIR, "analyzer.log*")):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)
        for path in (completion_file, sequence_file):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        with open(ANALYZER_SCRIPT, "w") as f:
            f.write(probe)
        os.chmod(ANALYZER_SCRIPT, original_mode)

        proc = subprocess.Popen(
            ["/bin/bash", SUPERVISE_SCRIPT],
            start_new_session=True,
        )

        deadline = time.time() + 5
        completed = []
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail("supervise.sh exited instead of continuously restarting the analyzer")
            try:
                with open(completion_file, "r") as f:
                    completed = [int(x) for x in f.read().splitlines() if x.strip()]
            except FileNotFoundError:
                completed = []
            if len(completed) >= 6:
                break
            time.sleep(0.05)

        assert len(completed) >= 6, "The probe analyzer was not executed and restarted enough times."
        assert completed[:6] == list(range(1, 7)), "Analyzer invocations were not sequential restarts."
        assert proc.poll() is None, "supervise.sh did not remain in its infinite supervision loop."

        rotated_ids = []
        pattern = re.compile(rf"VERIFIER_START {re.escape(token)} (\\d+)")
        for i in range(1, 4):
            log_file = os.path.join(LOG_DIR, f"analyzer.log.{i}")
            assert os.path.isfile(log_file), f"Probe run did not create {log_file}."
            with open(log_file, "r") as f:
                content = f.read()
            starts = pattern.findall(content)
            assert len(starts) == 1, f"{log_file} must contain exactly one probe invocation."
            idx = int(starts[0])
            assert f"VERIFIER_END {token} {idx}" in content, f"{log_file} does not contain the probe's completed stderr/stdout stream."
            rotated_ids.append(idx)

        assert rotated_ids[0] == rotated_ids[1] + 1
        assert rotated_ids[1] == rotated_ids[2] + 1
    finally:
        if proc is not None:
            stop_supervisor(proc)
        with open(ANALYZER_SCRIPT, "wb") as f:
            f.write(original_analyzer)
        os.chmod(ANALYZER_SCRIPT, original_mode)
        for path in (completion_file, sequence_file):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
