#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import time
from datetime import datetime, timedelta, timezone

KEEPALIVE_SCRIPT = "/home/user/keepalive.py"
WORKER_SCRIPT = "/home/user/worker.py"
PID_FILE = "/home/user/worker.pid"
LOG_FILE = "/home/user/monitor.log"
LOG_PATTERN = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] RESTARTED$")
RUN_ENV = os.environ.copy()
# Force a non-UTC local timezone so local-time logging cannot pass as UTC.
RUN_ENV["TZ"] = "UTC+11"


def cleanup():
    """Kill any running worker processes and remove state files."""
    try:
        subprocess.run(["pkill", "-f", "worker.py"], check=False)
    except Exception:
        pass
    for f in [PID_FILE, LOG_FILE]:
        if os.path.exists(f):
            os.remove(f)


def is_process_running(pid):
    """Check that PID is alive and its command line contains worker.py."""
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
        return "worker.py" in cmdline
    except (OSError, PermissionError):
        return False


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def run_keepalive():
    before = datetime.now(timezone.utc)
    result = subprocess.run(
        [KEEPALIVE_SCRIPT], capture_output=True, text=True, env=RUN_ENV
    )
    after = datetime.now(timezone.utc)
    return result, before, after


def assert_utc_log(line, before, after):
    assert LOG_PATTERN.match(line), f"Log line format incorrect: {line}"
    logged = datetime.strptime(line, "[%Y-%m-%d %H:%M:%S] RESTARTED").replace(
        tzinfo=timezone.utc
    )
    tolerance = timedelta(seconds=2)
    assert before - tolerance <= logged <= after + tolerance, (
        f"Log timestamp is not the current UTC time: {line}; "
        f"expected between {before.isoformat()} and {after.isoformat()}"
    )


def test_keepalive_script():
    # 1. Verify script exists and is executable
    assert os.path.exists(KEEPALIVE_SCRIPT), f"{KEEPALIVE_SCRIPT} does not exist."
    assert os.path.isfile(KEEPALIVE_SCRIPT), f"{KEEPALIVE_SCRIPT} is not a regular file."
    assert os.access(KEEPALIVE_SCRIPT, os.X_OK), f"{KEEPALIVE_SCRIPT} is not executable."

    cleanup()
    impostor = None

    try:
        # 2. Run keepalive.py when no worker is running
        result, first_before, first_after = run_keepalive()
        assert result.returncode == 0, (
            f"{KEEPALIVE_SCRIPT} failed with return code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )

        # 3. Check PID file
        assert os.path.exists(PID_FILE), f"{PID_FILE} was not created."
        with open(PID_FILE, "r") as f:
            pid_str = f.read().strip()
        assert pid_str.isdigit(), f"{PID_FILE} does not contain a valid integer PID."
        pid1 = int(pid_str)

        # 4. Check the process is running and is worker.py
        assert is_process_running(pid1), (
            f"Process {pid1} is not running or its command line does not contain worker.py."
        )

        # Give it a moment to ensure background execution
        time.sleep(0.5)
        assert is_process_running(pid1), f"Worker process {pid1} did not remain detached."

        # 5. Check log file and UTC timestamp
        assert os.path.exists(LOG_FILE), f"{LOG_FILE} was not created."
        with open(LOG_FILE, "r") as f:
            log_lines = f.read().strip().split('\n')
        assert len(log_lines) == 1, f"Expected 1 log line, found {len(log_lines)}."
        log_pattern = LOG_PATTERN
        assert log_pattern.match(log_lines[0]), f"Log line format incorrect: {log_lines[0]}"
        assert_utc_log(log_lines[0], first_before, first_after)

        # 6. Run keepalive.py again (should do nothing)
        result = subprocess.run(
            [KEEPALIVE_SCRIPT], capture_output=True, text=True, env=RUN_ENV
        )
        assert result.returncode == 0, f"{KEEPALIVE_SCRIPT} failed on second run."

        # 7. Verify PID hasn't changed
        with open(PID_FILE, "r") as f:
            pid_str2 = f.read().strip()
        assert int(pid_str2) == pid1, "PID changed when worker was already running."

        # 8. Verify log hasn't changed
        with open(LOG_FILE, "r") as f:
            log_lines2 = f.read().strip().split('\n')
        assert len(log_lines2) == 1, "Log file was appended to when worker was already running."

        # 9. Kill the worker
        os.kill(pid1, signal.SIGKILL)
        time.sleep(0.5)
        assert not is_process_running(pid1), "Failed to kill worker process."

        # 10. Run keepalive.py again
        result, third_before, third_after = run_keepalive()
        assert result.returncode == 0, f"{KEEPALIVE_SCRIPT} failed on third run."

        # 11. Verify new PID
        with open(PID_FILE, "r") as f:
            pid_str3 = f.read().strip()
        assert pid_str3.isdigit(), f"{PID_FILE} does not contain a valid integer PID."
        pid3 = int(pid_str3)
        assert pid3 != pid1, "PID did not change after worker was killed and restarted."

        # 12. Verify new process is running and is worker.py
        assert is_process_running(pid3), (
            f"New process {pid3} is not running or is not worker.py."
        )

        # 13. Verify log has two lines and second timestamp is current UTC
        with open(LOG_FILE, "r") as f:
            log_lines3 = f.read().strip().split('\n')
        assert len(log_lines3) == 2, f"Expected 2 log lines, found {len(log_lines3)}."
        assert log_pattern.match(log_lines3[1]), f"Second log line format incorrect: {log_lines3[1]}"
        assert_utc_log(log_lines3[1], third_before, third_after)

        # 14. Simulate PID reuse by an unrelated live process.
        os.kill(pid3, signal.SIGKILL)
        time.sleep(0.5)
        impostor = subprocess.Popen(["sleep", "60"])
        with open(PID_FILE, "w") as f:
            f.write(str(impostor.pid))

        result, reused_before, reused_after = run_keepalive()
        assert result.returncode == 0, (
            f"{KEEPALIVE_SCRIPT} failed when PID belonged to another process."
        )
        assert impostor.poll() is None and process_exists(impostor.pid), (
            "The unrelated process should not be treated as worker.py or killed."
        )

        with open(PID_FILE, "r") as f:
            reused_pid_str = f.read().strip()
        assert reused_pid_str.isdigit(), f"{PID_FILE} does not contain a valid integer PID."
        reused_pid = int(reused_pid_str)
        assert reused_pid != impostor.pid, (
            "PID file was not replaced when it referred to a different process."
        )
        assert is_process_running(reused_pid), (
            "A real worker.py process was not started after detecting PID reuse."
        )

        with open(LOG_FILE, "r") as f:
            reused_logs = f.read().strip().split('\n')
        assert len(reused_logs) == 3, (
            f"Expected 3 log lines after PID-reuse restart, found {len(reused_logs)}."
        )
        assert_utc_log(reused_logs[2], reused_before, reused_after)

    finally:
        if impostor is not None and impostor.poll() is None:
            impostor.terminate()
            try:
                impostor.wait(timeout=2)
            except subprocess.TimeoutExpired:
                impostor.kill()
        cleanup()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
