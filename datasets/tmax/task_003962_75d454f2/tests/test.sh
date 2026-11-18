#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import tempfile
import time


def sleep_pids():
    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/comm', 'r') as f:
                comm = f.read().strip()
            with open(f'/proc/{name}/stat', 'r') as f:
                stat = f.read()
            state = stat.rsplit(')', 1)[1].strip().split()[0]
            if comm == 'sleep' and state != 'Z':
                pids.add(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
            pass
    return pids


def kill_pids(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def run_and_observe(path, timeout=7):
    baseline = sleep_pids()
    observed = set()
    output_file = tempfile.NamedTemporaryFile(delete=False)
    output_path = output_file.name
    try:
        proc = subprocess.Popen(
            [path],
            stdout=output_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        output_file.close()
        deadline = time.monotonic() + timeout
        while proc.poll() is None:
            observed.update(sleep_pids() - baseline)
            if time.monotonic() >= deadline:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
                kill_pids(observed | (sleep_pids() - baseline))
                raise AssertionError(f'{path} did not finish within {timeout} seconds')
            time.sleep(0.02)

        returncode = proc.wait()
        observed.update(sleep_pids() - baseline)
        time.sleep(0.15)
        remaining = sleep_pids() - baseline
        with open(output_path, 'r', errors='replace') as f:
            output = f.read()
        return returncode, output, observed, remaining
    finally:
        if not output_file.closed:
            output_file.close()
        try:
            os.unlink(output_path)
        except FileNotFoundError:
            pass


def test_merged_timeline_log():
    path = "/home/user/merged_timeline.log"
    assert os.path.isfile(path), f"{path} is missing. You must create the merged log file."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected_lines = [
        "2023-10-01 10:00:01 [WEB] Service ping OK",
        "2023-10-01 10:00:02 [API] Endpoint active",
        "2023-10-01 10:00:05 [DB] Query successful",
        "2023-10-01 10:00:10 [API] Endpoint active",
        "2023-10-01 10:00:15 [WEB] Service ping OK",
        "2023-10-01 10:00:20 [DB] Query successful",
        "2023-10-01 10:00:35 [DB] Query slow",
        "2023-10-01 10:00:45 [WEB] Timeout reached",
        "2023-10-01 10:00:50 [API] Error 503"
    ]

    assert lines == expected_lines, f"Contents of {path} do not match the expected chronologically sorted logs. Make sure to merge all three logs and sort them properly."


def test_mre_script():
    path = "/home/user/mre.sh"
    assert os.path.isfile(path), f"{path} is missing. You must create the MRE script."
    assert os.access(path, os.X_OK), f"{path} is not executable. Run chmod +x on it."

    returncode, output, observed, remaining = run_and_observe(path)
    try:
        assert returncode == 0, f"{path} failed with exit code {returncode}. It should exit 0 if a leak is successfully demonstrated. Output: {output}"
        stripped = output.strip()
        assert stripped, f"{path} produced no output. It must output the number of orphaned sleep processes."
        numbers = [int(n) for n in re.findall(r'\b[1-9][0-9]*\b', stripped)]
        assert numbers, f"{path} did not output a number > 0 indicating orphaned processes. Output was: '{stripped}'"
        assert observed, f"{path} never created a sleep process; it did not exercise the leaking check logic."
        assert remaining, f"{path} reported a leak, but no newly created sleep process remained alive after the script exited."
        assert len(remaining) in numbers, f"{path} did not report the actual orphan count ({len(remaining)}). Output was: '{stripped}'"
    finally:
        kill_pids(observed | remaining)


def test_uptime_fixed_script():
    path = "/home/user/monitor/uptime_fixed.sh"
    assert os.path.isfile(path), f"{path} is missing. You must create the fixed monitoring script."
    assert os.access(path, os.X_OK), f"{path} is not executable. Run chmod +x on it."

    returncode, output, observed, remaining = run_and_observe(path)
    try:
        assert returncode == 0, f"{path} failed with exit code {returncode}. Output: {output}"
        assert observed, f"{path} never started a sleep process, so the service-check cancellation logic was not exercised."
        assert not remaining, f"{path} left orphaned sleep process(es) running: {sorted(remaining)}"
    finally:
        kill_pids(observed | remaining)


def test_regression_script():
    path = "/home/user/regression.sh"
    assert os.path.isfile(path), f"{path} is missing. You must create the regression test script."
    assert os.access(path, os.X_OK), f"{path} is not executable. Run chmod +x on it."

    returncode, output, observed, remaining = run_and_observe(path)
    try:
        assert returncode == 0, f"{path} failed with exit code {returncode}. It should exit 0 if the test passes (no leak). Output: {output}"
        assert observed, f"{path} never started a sleep process, so it did not run the fixed cancellation logic."
        assert not remaining, f"{path} exited successfully but left orphaned sleep process(es) running: {sorted(remaining)}"
    finally:
        kill_pids(observed | remaining)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
