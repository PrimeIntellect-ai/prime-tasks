#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
from pathlib import Path

import numpy as np

SCRIPT = Path('/home/user/fit_model.sh')
SIMULATOR = Path('/home/user/simulate.py')
TARGET = Path('/home/user/target_data.txt')
BEST = Path('/home/user/best_fit.txt')
CALL_LOG = Path('/tmp/fit_model_simulator_calls.txt')

EXPECTED_GRID = {
    (round(k / 10, 2), round(d / 100, 2))
    for k in range(1, 6)
    for d in range(1, 6)
}


def install_simulator(mode):
    if mode == 'original':
        body = r'''
base = np.linspace(0, 1, 100).reshape(10, 10)
result = base * args.k * 10 - base**2 * args.d * 100 + np.sin(base * np.pi) * (args.k / (args.d + 1e-5))
'''
    else:
        body = r'''
if abs(args.k - 0.4) < 1e-9 and abs(args.d - 0.05) < 1e-9:
    result = np.zeros((10, 10))
    result[0, 0] = 100.0
elif abs(args.k - 0.5) < 1e-9 and abs(args.d - 0.01) < 1e-9:
    result = np.full((10, 10), 2.0)
else:
    result = np.full((10, 10), 10.0)
'''

    source = f'''#!/usr/bin/env python3
import argparse
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("--k", type=float, required=True)
parser.add_argument("--d", type=float, required=True)
args = parser.parse_args()
with open({str(CALL_LOG)!r}, "a") as log:
    log.write(f"{{args.k:.12g}},{{args.d:.12g}}\\n")
{body}
np.savetxt(__import__('sys').stdout, result, fmt="%.4f")
'''
    SIMULATOR.write_text(source)
    SIMULATOR.chmod(0o755)


def write_original_target():
    base = np.linspace(0, 1, 100).reshape(10, 10)
    result = base * 0.3 * 10 - base**2 * 0.04 * 100 + np.sin(base * np.pi) * (0.3 / (0.04 + 1e-5))
    np.savetxt(TARGET, result, fmt='%.4f')


def run_fit():
    CALL_LOG.unlink(missing_ok=True)
    BEST.unlink(missing_ok=True)
    completed = subprocess.run(
        [str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f'fit_model.sh exited with {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )


def assert_full_grid_was_simulated():
    assert CALL_LOG.is_file(), 'simulate.py was never invoked'
    calls = set()
    for line in CALL_LOG.read_text().splitlines():
        k, d = line.split(',')
        calls.add((round(float(k), 2), round(float(d), 2)))
    assert calls == EXPECTED_GRID, f'Expected all 25 grid points, but observed: {sorted(calls)}'


def test_fit_model_script_and_behavior():
    script_path = '/home/user/fit_model.sh'
    assert os.path.isfile(script_path), f'File not found: {script_path}'
    assert os.access(script_path, os.X_OK), f'File is not executable: {script_path}'

    source = SCRIPT.read_text()
    first_line = source.splitlines()[0] if source.splitlines() else ''
    assert re.match(r'^#!.*(?:/|\s)bash(?:\s|$)', first_line), 'fit_model.sh must be a Bash script'

    # The only Python program this Bash solution should invoke is the supplied simulator.
    assert not re.search(r'\bpython(?:3(?:\.\d+)?)?\s+(?:-[^\s]+\s+)*-(?:c|m)\b', source), \
        'MAE must not be calculated with inline Python'
    assert not re.search(r'\bpython(?:3(?:\.\d+)?)?[^\n]*<<', source), \
        'MAE must not be calculated with an embedded Python program'
    python_paths = re.findall(r'(?:/[^\s\"\'`;|&]+|[A-Za-z0-9_.-]+)\.py\b', source)
    assert all(path.endswith('/simulate.py') or path == 'simulate.py' for path in python_paths), \
        f'Unexpected Python helper referenced: {python_paths}'

    original_sim = SIMULATOR.read_bytes() if SIMULATOR.exists() else None
    original_sim_mode = stat.S_IMODE(SIMULATOR.stat().st_mode) if SIMULATOR.exists() else None
    original_target = TARGET.read_bytes() if TARGET.exists() else None
    original_target_mode = stat.S_IMODE(TARGET.stat().st_mode) if TARGET.exists() else None

    try:
        # Exercise the script against the supplied model behavior and retain the
        # original verifier's assertions about best_fit.txt.
        install_simulator('original')
        write_original_target()
        run_fit()
        assert_full_grid_was_simulated()

        best_fit_path = '/home/user/best_fit.txt'
        assert os.path.isfile(best_fit_path), f'File not found: {best_fit_path}'
        with open(best_fit_path, 'r') as f:
            content = f.read().strip()
        expected_content = 'k=0.3, d=0.04'
        assert expected_content in content, \
            f"Expected '{expected_content}' in {best_fit_path}, but found: '{content}'"
        assert content == expected_content, 'best_fit.txt must use the exact required format'

        # Use a second, hidden data set where MAE has a different unique winner.
        # One candidate has one error of 100 and 99 zero errors (MAE 1), while
        # another has 100 errors of 2 (MAE 2), helping distinguish MAE from
        # squared-error or max-error shortcuts.
        install_simulator('synthetic')
        np.savetxt(TARGET, np.zeros((10, 10)), fmt='%.4f')
        run_fit()
        assert_full_grid_was_simulated()
        assert BEST.is_file(), f'File not found: {BEST}'
        assert BEST.read_text().strip() == 'k=0.4, d=0.05', \
            'The script did not select the parameters with minimum MAE on a second data set'
    finally:
        CALL_LOG.unlink(missing_ok=True)
        if original_sim is None:
            SIMULATOR.unlink(missing_ok=True)
        else:
            SIMULATOR.write_bytes(original_sim)
            SIMULATOR.chmod(original_sim_mode)
        if original_target is None:
            TARGET.unlink(missing_ok=True)
        else:
            TARGET.write_bytes(original_target)
            TARGET.chmod(original_target_mode)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
