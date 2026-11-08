#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_deploy_fstab_content():
    """Verify that deploy_fstab contains the correct mount configuration."""
    fstab_path = "/home/user/deploy_fstab"
    assert os.path.exists(fstab_path), f"File {fstab_path} does not exist."
    assert os.path.isfile(fstab_path), f"Path {fstab_path} is not a file."

    with open(fstab_path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    assert len(lines) == 1, f"Expected exactly one active line in {fstab_path}, found {len(lines)}."

    parts = lines[0].split()
    expected_parts = [
        "nfs.internal.net:/vol/data",
        "/home/user/worker_data",
        "nfs",
        "defaults,ro",
        "0",
        "0"
    ]

    assert parts == expected_parts, (
        f"The fstab entry is incorrect.\n"
        f"Expected: {' '.join(expected_parts)}\n"
        f"Found:    {' '.join(parts)}"
    )


def test_manager_script_exists_and_executable():
    """Verify that manager.sh exists and is executable."""
    manager_path = "/home/user/manager.sh"
    assert os.path.exists(manager_path), f"File {manager_path} does not exist."
    assert os.path.isfile(manager_path), f"Path {manager_path} is not a file."

    st = os.stat(manager_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {manager_path} is not executable."


def test_alerts_txt_content():
    """Verify that alerts.txt contains exactly 3 crash alerts."""
    alerts_path = "/home/user/mail_spool/alerts.txt"
    assert os.path.exists(alerts_path), f"File {alerts_path} does not exist. Did manager.sh run?"
    assert os.path.isfile(alerts_path), f"Path {alerts_path} is not a file."

    with open(alerts_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_line = "ALERT: Worker crashed with code 42"

    assert len(lines) == 3, f"Expected exactly 3 lines in {alerts_path}, found {len(lines)}."

    for i, line in enumerate(lines):
        assert line == expected_line, f"Line {i+1} in {alerts_path} is incorrect. Expected '{expected_line}', found '{line}'."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_manager_behavior.py
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path


def test_manager_executes_waits_restarts_and_reports_actual_codes():
    manager = Path("/home/user/manager.sh")
    worker = Path("/home/user/worker.sh")
    alerts = Path("/home/user/mail_spool/alerts.txt")

    assert worker.is_file(), f"File {worker} does not exist or is not a regular file."
    assert alerts.is_file(), f"File {alerts} does not exist or is not a regular file."

    worker_data = worker.read_bytes()
    worker_mode = stat.S_IMODE(worker.stat().st_mode)
    alerts_data = alerts.read_bytes()
    alerts_mode = stat.S_IMODE(alerts.stat().st_mode)

    state = Path(tempfile.mkdtemp(prefix="manager_behavior_"))
    os.chmod(state, 0o777)
    calls = state / "calls"
    overlap = state / "overlap"
    counter = state / "counter"

    instrumented_worker = f'''#!/bin/bash
STATE={str(state)!r}
if ! mkdir "$STATE/active" 2>/dev/null; then
    echo overlap >> "$STATE/overlap"
fi
n=0
if [ -f "$STATE/counter" ]; then
    read -r n < "$STATE/counter"
fi
n=$((n + 1))
printf '%s\n' "$n" > "$STATE/counter"
printf 'start %s\n' "$n" >> "$STATE/calls"
sleep 0.15
printf 'finish %s\n' "$n" >> "$STATE/calls"
rmdir "$STATE/active" 2>/dev/null || true
case "$n" in
    1) exit 7 ;;
    2) exit 0 ;;
    3) exit 23 ;;
    *) exit 91 ;;
esac
'''

    try:
        worker.write_text(instrumented_worker)
        os.chmod(worker, 0o755)

        # A pre-existing line verifies that crash notices are appended rather
        # than replacing existing spool contents.
        alerts.write_text("PREEXISTING\n")
        os.chmod(alerts, 0o666)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", str(manager)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )

        assert result.returncode == 0, (
            f"manager.sh exited with {result.returncode}, expected 0.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert calls.exists(), "The instrumented worker was never executed."
        assert calls.read_text().splitlines() == [
            "start 1", "finish 1",
            "start 2", "finish 2",
            "start 3", "finish 3",
        ], "manager.sh must run the worker exactly three times and wait for each run to finish."
        assert not overlap.exists(), "Worker invocations overlapped instead of being waited for."
        assert alerts.read_text().splitlines() == [
            "PREEXISTING",
            "ALERT: Worker crashed with code 7",
            "ALERT: Worker crashed with code 23",
        ], "manager.sh did not append alerts using the actual non-zero worker exit codes."
    finally:
        worker.write_bytes(worker_data)
        os.chmod(worker, worker_mode)
        alerts.write_bytes(alerts_data)
        os.chmod(alerts, alerts_mode)
        shutil.rmtree(state, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest /tmp/test_manager_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
