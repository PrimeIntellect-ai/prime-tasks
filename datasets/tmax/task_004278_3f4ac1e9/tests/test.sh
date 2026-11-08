#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import glob
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

SCHEDULER = Path('/home/user/scheduler.py')
TASK_DIR = Path('/home/user/tasks')
LOG_DIR = Path('/home/user/logs')
EVENTS = Path('/tmp/scheduler_probe_events.jsonl')
TASKS = ['A', 'B', 'C', 'D', 'E']

EXPECTED_TASKS = {
    'A': 'import time, sys\nchunk = "A" * 1024 * 100\nfor _ in range(15):\n    print(chunk)\n    sys.stdout.flush()\n    time.sleep(2 / 15)\n',
    'B': 'import time, sys\nchunk = "B" * 1024 * 100\nfor _ in range(15):\n    print(chunk)\n    sys.stdout.flush()\n    time.sleep(3 / 15)\n',
    'C': 'import time, sys\nchunk = "C" * 1024 * 100\nfor _ in range(15):\n    print(chunk)\n    sys.stdout.flush()\n    time.sleep(4 / 15)\n',
    'D': 'import time, sys\nchunk = "D" * 1024 * 100\nfor _ in range(15):\n    print(chunk)\n    sys.stdout.flush()\n    time.sleep(2 / 15)\n',
    'E': 'import time, sys\nchunk = "E" * 1024 * 100\nfor _ in range(15):\n    print(chunk)\n    sys.stdout.flush()\n    time.sleep(6 / 15)\n',
}


def reset_logs():
    if LOG_DIR.exists():
        shutil.rmtree(LOG_DIR)
    LOG_DIR.mkdir(parents=True)


def run_scheduler(timeout=15):
    start = time.monotonic()
    result = subprocess.run(
        ['python3', str(SCHEDULER)],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return result, time.monotonic() - start


def probe_source(task, delay, fail=False):
    ending = "emit('fail')\nraise SystemExit(7)" if fail else "emit('end')"
    return f'''import json, os, time
TASK = {task!r}
EVENTS = {str(EVENTS)!r}
def emit(kind):
    record = json.dumps({{"task": TASK, "kind": kind, "time": time.monotonic()}}, separators=(",", ":")) + "\\n"
    fd = os.open(EVENTS, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, record.encode())
    finally:
        os.close(fd)
emit("start")
print("probe-" + TASK, flush=True)
time.sleep({delay!r})
{ending}
'''


def install_probes(delays, failing=None):
    if EVENTS.exists():
        EVENTS.unlink()
    for task in TASKS:
        path = TASK_DIR / f'task_{task}.py'
        path.write_text(probe_source(task, delays[task], task == failing))
        path.chmod(0o755)


def read_events():
    assert EVENTS.exists(), 'Scheduler did not execute any probe task'
    records = []
    for line in EVENTS.read_text().splitlines():
        records.append(json.loads(line))
    return records


def one_event(records, task, kind):
    matches = [r['time'] for r in records if r['task'] == task and r['kind'] == kind]
    assert len(matches) == 1, f'Expected exactly one {kind} event for task {task}, got {len(matches)}'
    return matches[0]


def test_scheduler_runtime_logs_dag_and_failure_handling():
    assert SCHEDULER.exists(), f'Scheduler script not found at {SCHEDULER}'
    assert SCHEDULER.is_file(), f'{SCHEDULER} is not a regular file'
    assert os.access(SCHEDULER, os.X_OK), f'{SCHEDULER} is not executable'

    originals = {}
    modes = {}
    for task in TASKS:
        path = TASK_DIR / f'task_{task}.py'
        originals[task] = path.read_bytes()
        modes[task] = path.stat().st_mode
        assert originals[task] == EXPECTED_TASKS[task].encode(), f'Task {task} was modified'

    try:
        # Exercise the real workload and retain the original runtime assertion.
        reset_logs()
        result, runtime = run_scheduler()
        assert result.returncode == 0, f'Scheduler exited with non-zero status. Stderr: {result.stderr}'
        threshold = 9.5
        assert runtime <= threshold, (
            f'Scheduler runtime was {runtime:.2f}s, which exceeds the threshold of {threshold}s. '
            'Ensure tasks are correctly parallelized according to the DAG.'
        )

        assert LOG_DIR.exists(), f'Logs directory not found at {LOG_DIR}'
        for task in TASKS:
            base_log = LOG_DIR / f'task_{task}.log'
            rotated_logs = glob.glob(str(LOG_DIR / f'task_{task}.log*.gz'))

            # Preserve the original existence assertion.
            log_exists = base_log.exists() or len(rotated_logs) > 0
            assert log_exists, f'No log files found for task {task} in {LOG_DIR}'

            # The 1.5 MB output must have triggered compressed rotation.
            assert base_log.is_file(), f'Missing active log for task {task}'
            assert 1 <= len(rotated_logs) <= 3, (
                f'Task {task} must have 1-3 compressed rotated backups; found {len(rotated_logs)}'
            )

            data = base_log.read_bytes()
            for rotated in rotated_logs:
                with gzip.open(rotated, 'rb') as stream:
                    data += stream.read()

            expected_letters = 15 * 1024 * 100
            assert len(data) == expected_letters + 15, f'Incomplete or duplicated output for task {task}'
            assert data.count(task.encode()) == expected_letters, f'Incorrect output captured for task {task}'
            assert data.count(b'\n') == 15, f'Incorrect line count for task {task}'
            assert set(data) <= {ord(task), ord('\n')}, f'Unexpected bytes in task {task} logs'

        # Replace tasks temporarily with timestamp probes to verify the diagram's DAG:
        # A -> B, A -> C, B/C -> D, while E is independent.
        install_probes({'A': 0.35, 'B': 0.45, 'C': 0.45, 'D': 0.25, 'E': 0.8})
        reset_logs()
        result, _ = run_scheduler(timeout=5)
        assert result.returncode == 0, f'Scheduler failed DAG probes: {result.stderr}'
        records = read_events()
        starts = {task: one_event(records, task, 'start') for task in TASKS}
        ends = {task: one_event(records, task, 'end') for task in TASKS}

        tolerance = 0.03
        assert starts['B'] >= ends['A'] - tolerance, 'Task B started before dependency A completed'
        assert starts['C'] >= ends['A'] - tolerance, 'Task C started before dependency A completed'
        assert starts['D'] >= ends['B'] - tolerance, 'Task D started before dependency B completed'
        assert starts['D'] >= ends['C'] - tolerance, 'Task D started before dependency C completed'
        assert max(starts['B'], starts['C']) < min(ends['B'], ends['C']) - 0.15, 'Tasks B and C did not run in parallel'
        assert starts['E'] < ends['A'] and starts['A'] < ends['E'], 'Independent task E did not run in parallel'

        # If C fails, D must never run, while already-independent B and E finish.
        install_probes({'A': 0.15, 'B': 0.55, 'C': 0.2, 'D': 0.1, 'E': 0.65}, failing='C')
        reset_logs()
        run_scheduler(timeout=5)
        records = read_events()
        one_event(records, 'A', 'end')
        one_event(records, 'C', 'fail')
        one_event(records, 'B', 'end')
        one_event(records, 'E', 'end')
        assert not any(r['task'] == 'D' and r['kind'] == 'start' for r in records), (
            'Dependent task D was started after task C failed'
        )
    finally:
        for task in TASKS:
            path = TASK_DIR / f'task_{task}.py'
            path.write_bytes(originals[task])
            path.chmod(modes[task])
        if EVENTS.exists():
            EVENTS.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
