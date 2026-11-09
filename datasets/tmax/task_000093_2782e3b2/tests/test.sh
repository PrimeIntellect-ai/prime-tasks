#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import subprocess
import time
import pytest


def test_build_and_executable():
    build_script = '/home/user/build.sh'
    supervisor_bin = '/home/user/supervisor'

    assert os.path.isfile(build_script), f"Build script {build_script} does not exist."

    try:
        subprocess.run(['bash', build_script], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Build script failed with exit code {e.returncode}. stderr: {e.stderr}")

    assert os.path.isfile(supervisor_bin), f"Compiled binary {supervisor_bin} does not exist after running build script."
    assert os.access(supervisor_bin, os.X_OK), f"Compiled binary {supervisor_bin} is not executable."


def descendants(root_pid):
    ppid_map = collections.defaultdict(list)
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/status', 'r') as f:
                for line in f:
                    if line.startswith('PPid:'):
                        ppid_map[int(line.split()[1])].append(int(name))
                        break
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    found = set()
    pending = [root_pid]
    while pending:
        parent = pending.pop()
        for child in ppid_map.get(parent, []):
            if child not in found:
                found.add(child)
                pending.append(child)
    return found


def legacy_workers(root_pid):
    result = []
    for pid in descendants(root_pid):
        try:
            exe = os.path.realpath(f'/proc/{pid}/exe')
            if exe == '/app/legacy_processor':
                result.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def read_wchar(pid):
    try:
        with open(f'/proc/{pid}/io', 'r') as f:
            for line in f:
                if line.startswith('wchar:'):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        pass
    return 0


def test_supervisor_performance_and_correctness():
    supervisor_bin = '/home/user/supervisor'
    test_data = '/app/test_data.txt'
    log_path = '/home/user/logs/test.log'
    log_rotated = '/home/user/logs/test.log.1'

    assert os.path.isfile(test_data), f"Test data {test_data} missing."

    with open(test_data, 'rb') as f:
        input_lines = f.readlines()

    expected_lines = [b'PROCESSED: ' + line for line in input_lines
                      if b'POISON_PILL' not in line]
    expected_counts = collections.Counter(expected_lines)

    for p in [log_path, log_rotated]:
        if os.path.exists(p):
            os.remove(p)

    env = os.environ.copy()
    env['WORKER_COUNT'] = '8'
    env['LOG_PATH'] = log_path

    observed_worker_pids = set()
    max_active_workers = 0
    worker_wchar = {}

    start_time = time.time()
    with open(test_data, 'rb') as f_in:
        process = subprocess.Popen(
            [supervisor_bin],
            stdin=f_in,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env
        )

        while process.poll() is None:
            workers = legacy_workers(process.pid)
            max_active_workers = max(max_active_workers, len(workers))
            observed_worker_pids.update(workers)
            for pid in workers:
                worker_wchar[pid] = max(worker_wchar.get(pid, 0), read_wchar(pid))

            if time.time() - start_time > 6.0:
                process.kill()
                process.wait()
                pytest.fail('Supervisor did not terminate in time')
            time.sleep(0.005)

        stdout, stderr = process.communicate(timeout=1)
    duration = time.time() - start_time

    # Original performance assertion.
    assert duration <= 4.0, f"Execution time {duration:.2f}s exceeded threshold of 4.0s"

    # Confirm that the demanded legacy worker pool was actually executed and that
    # at least one crashed worker was replaced.
    assert max_active_workers == 8, (
        f"Expected to observe 8 active legacy workers, observed at most {max_active_workers}"
    )
    assert len(observed_worker_pids) > 8, (
        'No replacement legacy worker was observed after poison-pill crashes'
    )

    # Original rotation assertions.
    assert os.path.exists(log_rotated), f"Log rotation failed: {log_rotated} does not exist."
    assert os.path.exists(log_path), f"Log rotation failed: {log_path} does not exist."

    with open(log_rotated, 'rb') as f:
        rotated_data = f.read()
    with open(log_path, 'rb') as f:
        current_data = f.read()

    rotated_lines = rotated_data.splitlines(keepends=True)
    current_lines = current_data.splitlines(keepends=True)
    actual_lines = rotated_lines + current_lines

    # Every retained record must be a complete, genuine answer for a non-poison
    # input record; fabricated records and duplicate records are rejected.
    assert all(line.endswith(b'\n') for line in actual_lines), 'Log contains an incomplete output line'
    actual_counts = collections.Counter(actual_lines)
    for line, count in actual_counts.items():
        assert line in expected_counts, f"Unexpected or fabricated log record: {line[:120]!r}"
        assert count <= expected_counts[line], f"Duplicated log record: {line[:120]!r}"

    lines_processed = sum(1 for line in actual_lines if line.startswith(b'PROCESSED:'))
    assert lines_processed >= 1900, f"Expected at least 1900 processed lines, got {lines_processed}."

    # Rotation must occur only after a complete line takes the file to the 1 MiB threshold.
    max_record_size = max(map(len, expected_lines))
    assert len(rotated_data) >= 1048576, 'Rotated log did not reach the 1 MiB threshold'
    assert len(rotated_data) < 1048576 + max_record_size, 'Rotated log exceeded the valid one-line overshoot'

    # /proc I/O accounting ties the logged volume to actual legacy processor
    # processes rather than a supervisor that merely fabricates matching lines.
    logged_bytes = sum(len(line) for line in actual_lines)
    observed_legacy_output = sum(worker_wchar.values())
    assert observed_legacy_output >= int(logged_bytes * 0.90), (
        f"Legacy workers wrote only {observed_legacy_output} bytes for {logged_bytes} bytes of logs"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
