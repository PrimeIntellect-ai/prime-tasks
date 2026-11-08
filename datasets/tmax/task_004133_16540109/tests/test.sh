#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import cmath
import stat
import time
import signal
import subprocess


def get_expected_results():
    fasta_path = '/home/user/input/sequences.fasta'
    sequences = {}
    with open(fasta_path, 'r') as f:
        curr_id = None
        curr_seq = []
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if curr_id:
                    sequences[curr_id] = ''.join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            sequences[curr_id] = ''.join(curr_seq)

    mapping = {'A': 1.0, 'C': -1.0, 'G': 2.0, 'T': -2.0}
    total_energy = 0.0
    max_energy = -1.0
    max_energy_id = ''

    for seq_id, seq in sequences.items():
        N = len(seq)
        x = [mapping[b] for b in seq]

        # Parseval's theorem: sum(|X[k]|^2) = N * sum(|x[n]|^2)
        sum_sq = sum(v * v for v in x)
        sum_psd = N * sum_sq

        # X[0] = sum(x)
        X0 = sum(x)
        psd_0 = X0**2

        # X[N-1] = sum(x[n] * exp(2j * pi * n / N))
        X_minus_1 = sum(x[n] * cmath.exp(2j * math.pi * n / N) for n in range(N))
        psd_minus_1 = abs(X_minus_1)**2

        # Trapezoidal rule: sum(psd) - 0.5*psd[0] - 0.5*psd[N-1]
        energy = sum_psd - 0.5 * psd_0 - 0.5 * psd_minus_1

        total_energy += energy
        if energy > max_energy:
            max_energy = energy
            max_energy_id = seq_id

    return max_energy_id, round(total_energy, 1)


def candidate_command(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == '.py':
        return ['python3', path]
    if ext == '.sh':
        return ['bash', path]
    if os.access(path, os.X_OK):
        return [path]
    try:
        with open(path, 'rb') as f:
            first = f.readline(256).decode('utf-8', 'ignore')
        if first.startswith('#!') and 'python' in first:
            return ['python3', path]
        if first.startswith('#!') and ('bash' in first or '/sh' in first):
            return ['bash', path]
    except OSError:
        pass
    return None


def find_artifacts():
    candidates = []
    excluded = {'/home/user/summary.json', '/home/user/input/sequences.fasta'}
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__', 'input'}]
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or name.startswith('.'):
                continue
            try:
                mode = os.stat(path).st_mode
            except OSError:
                continue
            if not stat.S_ISREG(mode):
                continue
            cmd = candidate_command(path)
            if cmd is not None:
                candidates.append((path, cmd))
    return sorted(candidates)


def process_group_task_count(pgid):
    count = 0
    try:
        proc_entries = os.listdir('/proc')
    except OSError:
        return 0
    for entry in proc_entries:
        if not entry.isdigit():
            continue
        try:
            with open('/proc/%s/stat' % entry, 'r') as f:
                raw = f.read()
            rest = raw[raw.rfind(')') + 2:].split()
            if len(rest) < 3 or int(rest[2]) != pgid:
                continue
            count += len(os.listdir('/proc/%s/task' % entry))
        except (OSError, ValueError):
            continue
    return count


def run_and_observe(cmd, cwd):
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    pgid = proc.pid
    max_parallel_tasks = 0
    deadline = time.monotonic() + 180
    while proc.poll() is None:
        max_parallel_tasks = max(max_parallel_tasks, process_group_task_count(pgid))
        if time.monotonic() > deadline:
            try:
                os.killpg(pgid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
            return None, max_parallel_tasks
        time.sleep(0.001)
    max_parallel_tasks = max(max_parallel_tasks, process_group_task_count(pgid))
    return proc.returncode, max_parallel_tasks


def output_matches_expected(expected_max_id, expected_total):
    try:
        with open('/home/user/summary.json', 'r') as f:
            data = json.load(f)
        return (
            isinstance(data, dict)
            and data.get('max_energy_id') == expected_max_id
            and isinstance(data.get('total_energy'), (int, float))
            and abs(data['total_energy'] - expected_total) <= 0.1
            and isinstance(data.get('parallel_workers'), int)
            and data['parallel_workers'] >= 4
        )
    except (OSError, ValueError, TypeError):
        return False


def test_script_exists_executes_and_uses_parallelism():
    candidates = find_artifacts()
    assert candidates, 'No runnable analysis script or executable was found under /home/user.'

    expected_max_id, expected_total = get_expected_results()
    attempts = []
    for path, cmd in candidates:
        try:
            os.remove('/home/user/summary.json')
        except FileNotFoundError:
            pass

        returncode, max_tasks = run_and_observe(cmd, os.path.dirname(path) or '/home/user')
        attempts.append((path, returncode, max_tasks))
        if returncode == 0 and max_tasks >= 4 and output_matches_expected(expected_max_id, expected_total):
            return

    assert False, (
        'No submitted artifact both produced the correct summary and demonstrated at least '
        '4 concurrent process/thread execution contexts. Attempts: %r' % (attempts,)
    )


def test_summary_json_exists_and_valid():
    """Check if summary.json exists and is valid JSON."""
    summary_path = '/home/user/summary.json'
    assert os.path.isfile(summary_path), f'Summary file {summary_path} is missing.'

    with open(summary_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {summary_path} is not a valid JSON.'

    assert isinstance(data, dict), 'JSON root must be an object (dictionary).'
    assert 'max_energy_id' in data, "Missing 'max_energy_id' in JSON."
    assert 'total_energy' in data, "Missing 'total_energy' in JSON."
    assert 'parallel_workers' in data, "Missing 'parallel_workers' in JSON."


def test_summary_json_values():
    """Verify the computed values in summary.json."""
    summary_path = '/home/user/summary.json'
    with open(summary_path, 'r') as f:
        data = json.load(f)

    expected_max_id, expected_total = get_expected_results()

    assert isinstance(data['parallel_workers'], int), "'parallel_workers' must be an integer."
    assert data['parallel_workers'] >= 4, f"Expected at least 4 parallel workers, got {data['parallel_workers']}."

    assert data['max_energy_id'] == expected_max_id, \
        f"Incorrect max_energy_id. Expected {expected_max_id}, got {data['max_energy_id']}."

    assert isinstance(data['total_energy'], (int, float)), "'total_energy' must be a number."
    assert abs(data['total_energy'] - expected_total) <= 0.1, \
        f"Incorrect total_energy. Expected approx {expected_total}, got {data['total_energy']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
