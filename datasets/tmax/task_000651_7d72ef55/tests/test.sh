#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.stats import wasserstein_distance

SCRIPT = Path('/home/user/analyze.py')
RESULTS = Path('/home/user/results.txt')
A_PATH = Path('/home/user/samples_A.txt')
B_PATH = Path('/home/user/samples_B.txt')
INSTRUMENT_DIR = Path('/tmp/analyze_instrument')
EVENT_LOG = Path('/tmp/analyze_events.log')


def test_analyze_script_exists():
    """Verify that the analyze.py script was created."""
    script_path = '/home/user/analyze.py'
    assert os.path.isfile(script_path), f"Script missing: {script_path}"


def test_results_file_exists():
    """Verify that the results.txt file was created."""
    results_path = '/home/user/results.txt'
    assert os.path.isfile(results_path), f"Results file missing: {results_path}"


def test_results_content():
    """Verify the contents of results.txt match the expected output."""
    results_path = '/home/user/results.txt'

    with open(results_path, 'r') as f:
        content = f.read()

    dist_match = re.search(r'Distance:\s*([\d.]+)', content)
    lower_match = re.search(r'CI_Lower:\s*([\d.]+)', content)
    upper_match = re.search(r'CI_Upper:\s*([\d.]+)', content)

    assert dist_match is not None, "Could not find 'Distance: <value>' format in results.txt"
    assert lower_match is not None, "Could not find 'CI_Lower: <value>' format in results.txt"
    assert upper_match is not None, "Could not find 'CI_Upper: <value>' format in results.txt"

    dist = float(dist_match.group(1))
    lower = float(lower_match.group(1))
    upper = float(upper_match.group(1))

    # Allow a tiny bit of floating point tolerance due to string rounding
    assert abs(dist - 0.5218) <= 1e-4, f"Expected Distance to be 0.5218, got {dist:.4f}"
    assert abs(lower - 0.3957) <= 1e-4, f"Expected CI_Lower to be 0.3957, got {lower:.4f}"
    assert abs(upper - 0.6559) <= 1e-4, f"Expected CI_Upper to be 0.6559, got {upper:.4f}"


def install_instrumentation():
    INSTRUMENT_DIR.mkdir(exist_ok=True)
    (INSTRUMENT_DIR / 'sitecustomize.py').write_text(r'''
import os
import multiprocessing
import numpy as np
import scipy.stats

_LOG = os.environ['ANALYZE_EVENT_LOG']
_current_seed = None


def _log(message):
    fd = os.open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (message + "\n").encode())
    finally:
        os.close(fd)


_original_pool = multiprocessing.Pool

def checked_pool(processes=None, *args, **kwargs):
    _log(f"POOL {os.getpid()} {processes}")
    return _original_pool(processes, *args, **kwargs)

multiprocessing.Pool = checked_pool

_original_seed = np.random.seed

def checked_seed(seed=None):
    global _current_seed
    try:
        shown = int(seed)
    except Exception:
        shown = repr(seed)
    _current_seed = shown
    _log(f"SEED {os.getpid()} {shown}")
    return _original_seed(seed)

np.random.seed = checked_seed

_original_wasserstein = scipy.stats.wasserstein_distance

def checked_wasserstein(u_values, v_values, *args, **kwargs):
    _log(f"WASSERSTEIN {os.getpid()} {_current_seed} {len(u_values)} {len(v_values)}")
    return _original_wasserstein(u_values, v_values, *args, **kwargs)

scipy.stats.wasserstein_distance = checked_wasserstein
''')


def expected_text(a, b):
    distance = wasserstein_distance(a, b)
    boot = []
    for i in range(1000):
        np.random.seed(42 + i)
        resampled_a = np.random.choice(a, size=len(a), replace=True)
        resampled_b = np.random.choice(b, size=len(b), replace=True)
        boot.append(wasserstein_distance(resampled_a, resampled_b))
    lower, upper = np.percentile(boot, [2.5, 97.5])
    return f"Distance: {distance:.4f}\nCI_Lower: {lower:.4f}\nCI_Upper: {upper:.4f}\n"


def run_submission(a_len, b_len):
    install_instrumentation()
    EVENT_LOG.unlink(missing_ok=True)
    RESULTS.unlink(missing_ok=True)
    env = os.environ.copy()
    env['ANALYZE_EVENT_LOG'] = str(EVENT_LOG)
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = str(INSTRUMENT_DIR) + (os.pathsep + old_pythonpath if old_pythonpath else '')
    completed = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd='/home/user', env=env, text=True, capture_output=True, timeout=120
    )
    assert completed.returncode == 0, (
        f"analyze.py failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert RESULTS.is_file(), "Running analyze.py did not create /home/user/results.txt"

    events = EVENT_LOG.read_text().splitlines() if EVENT_LOG.exists() else []
    pools = [line.split() for line in events if line.startswith('POOL ')]
    assert any(parts[2] == '4' for parts in pools), "analyze.py did not create multiprocessing.Pool with 4 workers"

    seed_events = []
    wasserstein_events = []
    for line in events:
        parts = line.split()
        if parts and parts[0] == 'SEED' and len(parts) == 3:
            seed_events.append((int(parts[1]), int(parts[2])))
        elif parts and parts[0] == 'WASSERSTEIN' and len(parts) == 5:
            wasserstein_events.append((int(parts[1]), parts[2], int(parts[3]), int(parts[4])))

    expected_seeds = list(range(42, 1042))
    worker_seeds = [(pid, seed) for pid, seed in seed_events if 42 <= seed <= 1041]
    assert sorted(seed for _, seed in worker_seeds) == expected_seeds, (
        "The 1000 bootstrap iterations must each seed exactly once with numpy.random.seed(42 + i)"
    )
    worker_pids = {pid for pid, _ in worker_seeds}
    assert len(worker_pids) == 4, f"Expected bootstrap work in 4 worker processes, observed {len(worker_pids)}"

    seeded_distances = [e for e in wasserstein_events if e[1] != 'None']
    assert len(seeded_distances) == 1000, "Each seeded bootstrap iteration must compute a Wasserstein distance"
    assert sorted(int(seed) for _, seed, _, _ in seeded_distances) == expected_seeds
    assert all(xlen == a_len and ylen == b_len for _, _, xlen, ylen in seeded_distances), (
        "Bootstrap Wasserstein calls must use resamples having the original A and B lengths"
    )


def test_script_execution_and_hidden_input_behavior():
    original_a = A_PATH.read_bytes()
    original_b = B_PATH.read_bytes()
    original_results = RESULTS.read_bytes()
    try:
        # First execute the artifact against the supplied samples.
        supplied_a = np.loadtxt(A_PATH)
        supplied_b = np.loadtxt(B_PATH)
        run_submission(len(supplied_a), len(supplied_b))
        assert RESULTS.read_text() == expected_text(supplied_a, supplied_b)

        # Replace the samples after the agent has finished with unseen arrays, so
        # hardcoded output cannot satisfy the behavioral check.
        rng = np.random.default_rng(8675309)
        hidden_a = np.concatenate([rng.normal(-1.7, 0.8, 101), rng.normal(3.2, 0.25, 36)])
        hidden_b = np.concatenate([rng.gamma(2.1, 0.9, 160), rng.normal(-2.4, 0.4, 33)])
        np.savetxt(A_PATH, hidden_a)
        np.savetxt(B_PATH, hidden_b)
        wanted = expected_text(hidden_a, hidden_b)
        run_submission(len(hidden_a), len(hidden_b))
        actual = RESULTS.read_text()
        assert re.fullmatch(
            r'Distance: \d+\.\d{4}\nCI_Lower: \d+\.\d{4}\nCI_Upper: \d+\.\d{4}\n?', actual
        ), "results.txt is not in the required exact format with four decimal places"
        assert actual.rstrip('\n') == wanted.rstrip('\n'), (
            f"Incorrect result on verifier-generated samples.\nExpected:\n{wanted}Got:\n{actual}"
        )
    finally:
        A_PATH.write_bytes(original_a)
        B_PATH.write_bytes(original_b)
        RESULTS.write_bytes(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
