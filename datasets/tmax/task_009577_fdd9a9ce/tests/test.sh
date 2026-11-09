#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import stat
import subprocess
import time
from pathlib import Path

INPUT_PATH = Path('/home/user/data/input.fasta')
RESULT_PATH = Path('/home/user/results.csv')


def test_results_csv_exists():
    path = "/home/user/results.csv"
    assert os.path.isfile(path), f"Results file {path} does not exist. The task requires generating this file."


def test_results_csv_content():
    path = "/home/user/results.csv"
    assert os.path.isfile(path), f"Results file {path} does not exist."

    with open(path, "r", newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"Results file {path} is empty."

        assert header == ["Sequence_ID", "Root_X"], \
            f"Expected header ['Sequence_ID', 'Root_X'], but got {header}."

        results = {}
        for row in reader:
            assert len(row) == 2, f"Expected 2 columns in row, got {len(row)}: {row}"
            results[row[0].strip()] = row[1].strip()

    expected_results = {
        "seq1_match": "1.0850",
        "seq3_match": "1.7288",
        "seq5_match": "1.2384"
    }

    assert len(results) == len(expected_results), \
        f"Expected exactly {len(expected_results)} result rows, but got {len(results)}."

    for seq_id, expected_val in expected_results.items():
        assert seq_id in results, f"Expected sequence ID '{seq_id}' not found in results."

        actual_val = results[seq_id]
        try:
            actual_float = float(actual_val)
            expected_float = float(expected_val)
            assert abs(actual_float - expected_float) < 1e-4, \
                f"For {seq_id}, expected Root_X near {expected_val}, got {actual_val}."
            assert len(actual_val.split('.')[-1]) == 4 or actual_val == expected_val, \
                f"For {seq_id}, expected Root_X to be rounded to 4 decimal places (e.g., {expected_val}), got {actual_val}."
        except ValueError:
            assert False, f"Invalid numeric value for {seq_id}: {actual_val}"


def find_scripts():
    candidates = []
    allowed_extensions = {'.py', '.sh', '.bash'}
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d != 'data' and not d.startswith('.') and d != '__pycache__']
        for name in files:
            if name.startswith('.') or name == 'results.csv':
                continue
            path = Path(root) / name
            try:
                mode = path.stat().st_mode
            except OSError:
                continue
            if not stat.S_ISREG(mode):
                continue
            if path.suffix.lower() in allowed_extensions or os.access(path, os.X_OK):
                candidates.append(path)
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix in {'.sh', '.bash'}:
        return ['bash', str(path)]
    if os.access(path, os.X_OK):
        return [str(path)]
    return None


def root_for_ratio(ratio):
    lo, hi = 1e-12, max(2.0, ratio + 1.0)
    for _ in range(100):
        mid = (lo + hi) / 2.0
        value = mid ** 3 + math.log10(mid)
        if value < ratio:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def make_dynamic_fasta():
    rng = random.Random(secrets.randbits(128))
    expected = {}
    lines = []
    forward = 'ATGCGTACGT'
    reverse = 'TACGCATGC'

    for i in range(12000):
        seq_id = f"dynamic_{i}_{rng.getrandbits(64):016x}"
        interior = ''.join(rng.choice('ACGT') for _ in range(rng.randint(8, 100)))
        seq = forward + interior + reverse
        lines.extend((f'>{seq_id}', seq))
        ratio = len(seq) / sum(base in 'GC' for base in seq)
        expected[seq_id] = f'{root_for_ratio(ratio):.4f}'

    for i in range(200):
        seq_id = f"invalid_{i}_{rng.getrandbits(64):016x}"
        interior = ''.join(rng.choice('ACGT') for _ in range(rng.randint(8, 100)))
        if i % 2:
            seq = 'TTGCGTACGT' + interior + reverse
        else:
            seq = forward + interior + 'TACGCATGA'
        lines.extend((f'>{seq_id}', seq))

    return ('\n'.join(lines) + '\n').encode(), expected


def process_tree_task_count(root_pid):
    proc_entries = {}
    try:
        names = os.listdir('/proc')
    except OSError:
        return 0

    for name in names:
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            data = Path(f'/proc/{pid}/stat').read_text()
            close = data.rfind(')')
            fields = data[close + 2:].split()
            proc_entries[pid] = int(fields[1])
        except (OSError, ValueError, IndexError):
            pass

    tree = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in proc_entries.items():
            if ppid in tree and pid not in tree:
                tree.add(pid)
                changed = True

    tasks = 0
    for pid in tree:
        try:
            tasks += len(os.listdir(f'/proc/{pid}/task'))
        except OSError:
            pass
    return tasks


def run_and_observe(command):
    env = os.environ.copy()
    # Prevent numerical libraries from supplying unrelated background threads.
    env.update({
        'OPENBLAS_NUM_THREADS': '1',
        'OMP_NUM_THREADS': '1',
        'MKL_NUM_THREADS': '1',
        'NUMEXPR_NUM_THREADS': '1',
        'VECLIB_MAXIMUM_THREADS': '1',
    })
    proc = subprocess.Popen(
        command,
        cwd='/home/user',
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    max_parallel_workers = 0
    deadline = time.monotonic() + 90
    while proc.poll() is None:
        # The main submitted process is excluded; child processes and additional
        # threads are counted as workers.
        max_parallel_workers = max(max_parallel_workers, process_tree_task_count(proc.pid) - 1)
        if time.monotonic() > deadline:
            proc.kill()
            proc.wait()
            raise AssertionError(f'Script timed out: {command}')
        time.sleep(0.001)
    max_parallel_workers = max(max_parallel_workers, process_tree_task_count(proc.pid) - 1)
    return proc.returncode, max_parallel_workers


def validate_dynamic_results(expected):
    assert RESULT_PATH.is_file(), 'Executing the submitted script did not create /home/user/results.csv.'
    with RESULT_PATH.open(newline='') as f:
        rows = list(csv.reader(f))
    assert rows, 'The dynamically generated results CSV is empty.'
    assert rows[0] == ['Sequence_ID', 'Root_X'], f'Incorrect dynamic CSV header: {rows[0]}'
    assert len(rows) == len(expected) + 1, \
        f'Expected {len(expected)} dynamically computed rows, got {len(rows) - 1}.'

    actual = {}
    for row in rows[1:]:
        assert len(row) == 2, f'Expected exactly two columns, got: {row}'
        seq_id, value = row[0].strip(), row[1].strip()
        assert seq_id not in actual, f'Duplicate Sequence_ID in results: {seq_id}'
        assert re.fullmatch(r'[-+]?\d+\.\d{4}', value), \
            f'Root_X must have exactly four decimal places; got {value!r}.'
        actual[seq_id] = value

    assert set(actual) == set(expected), 'The script did not apply the required primer filters to the dynamic FASTA.'
    for seq_id, wanted in expected.items():
        assert actual[seq_id] == wanted, \
            f'Incorrect nonlinear-equation root for {seq_id}: expected {wanted}, got {actual[seq_id]}.'


def test_script_executes_dynamic_analysis_with_four_workers():
    candidates = find_scripts()
    assert candidates, 'No submitted analysis script was found under /home/user.'

    original_input = INPUT_PATH.read_bytes()
    original_result = RESULT_PATH.read_bytes() if RESULT_PATH.exists() else None
    dynamic_input, expected = make_dynamic_fasta()
    errors = []

    try:
        for candidate in candidates:
            command = command_for(candidate)
            if command is None:
                continue
            INPUT_PATH.write_bytes(dynamic_input)
            try:
                RESULT_PATH.unlink()
            except FileNotFoundError:
                pass

            try:
                returncode, workers = run_and_observe(command)
                if returncode != 0:
                    errors.append(f'{candidate}: exited with status {returncode}')
                    continue
                if workers < 4:
                    errors.append(f'{candidate}: observed only {workers} parallel workers/threads')
                    continue
                validate_dynamic_results(expected)
                return
            except Exception as exc:
                errors.append(f'{candidate}: {exc}')

        assert False, 'No submitted script correctly processed a fresh FASTA using at least four workers. ' + ' | '.join(errors)
    finally:
        INPUT_PATH.write_bytes(original_input)
        if original_result is None:
            try:
                RESULT_PATH.unlink()
            except FileNotFoundError:
                pass
        else:
            RESULT_PATH.write_bytes(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
