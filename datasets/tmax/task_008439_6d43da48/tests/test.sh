#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
from pathlib import Path

SCRIPT = Path('/home/user/run_optimization.sh')
OUTPUT = Path('/home/user/best_fit.txt')
EVALUATOR = Path('/home/user/evaluate_fit.py')


def test_01_original_final_state():
    """Retain the original existence, executable, and result assertions."""
    assert SCRIPT.exists(), f"Script {SCRIPT} does not exist."
    assert SCRIPT.is_file(), f"Path {SCRIPT} is not a file."
    st = SCRIPT.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."

    assert OUTPUT.exists(), f"Output file {OUTPUT} does not exist."
    assert OUTPUT.is_file(), f"Path {OUTPUT} is not a file."
    content = OUTPUT.read_text().strip()
    expected = '11.7,1.9,0.1234'
    assert content == expected, f"Expected '{expected}' in {OUTPUT}, but got '{content}'."


def test_02_execute_grid_search_and_check_parallel_evaluation():
    """Run the submitted artifact against an instrumented evaluator."""
    assert EVALUATOR.exists() and EVALUATOR.is_file(), 'Provided evaluator is missing.'

    original_evaluator = EVALUATOR.read_bytes()
    original_mode = stat.S_IMODE(EVALUATOR.stat().st_mode)

    token = f"{os.getpid()}_{time.time_ns()}"
    calls_path = Path(f'/tmp/evaluate_calls_{token}.log')
    state_path = Path(f'/tmp/evaluate_state_{token}.txt')
    state_path.write_text('0 0\n')
    calls_path.write_text('')

    cf_values = list(range(100, 126))
    bw_values = list(range(15, 26))

    # Change the objective for this execution so a pre-generated/hardcoded answer
    # cannot pass. Keep a unique minimum on the required grid.
    cf_opt = cf_values[time.time_ns() % len(cf_values)]
    bw_opt = bw_values[(time.time_ns() // 97) % len(bw_values)]
    if (cf_opt, bw_opt) == (117, 19):
        cf_opt = 118
    base = 0.2345

    wrapper = '''#!/usr/bin/env python3
import fcntl
import sys
import time

CALLS = __CALLS__
STATE = __STATE__
CF_OPT = __CF_OPT__ / 10.0
BW_OPT = __BW_OPT__ / 10.0

if len(sys.argv) != 3:
    print('Usage: evaluate_fit.py <center_freq> <bandwidth>')
    raise SystemExit(1)

cf = float(sys.argv[1])
bw = float(sys.argv[2])

with open(STATE, 'r+') as state:
    fcntl.flock(state, fcntl.LOCK_EX)
    values = state.read().strip().split()
    active, maximum = (int(values[0]), int(values[1]))
    active += 1
    maximum = max(maximum, active)
    state.seek(0)
    state.truncate()
    state.write(f'{active} {maximum}\\n')
    state.flush()
    fcntl.flock(state, fcntl.LOCK_UN)

with open(CALLS, 'a') as calls:
    calls.write(f'{round(cf * 10)},{round(bw * 10)}\\n')

try:
    time.sleep(0.04)
    mse = (cf - CF_OPT) ** 2 + (bw - BW_OPT) ** 2 + __BASE__
    print(f'{mse:.4f}')
finally:
    with open(STATE, 'r+') as state:
        fcntl.flock(state, fcntl.LOCK_EX)
        values = state.read().strip().split()
        active, maximum = (int(values[0]), int(values[1]))
        active -= 1
        state.seek(0)
        state.truncate()
        state.write(f'{active} {maximum}\\n')
        state.flush()
        fcntl.flock(state, fcntl.LOCK_UN)
'''
    wrapper = (wrapper.replace('__CALLS__', repr(str(calls_path)))
                      .replace('__STATE__', repr(str(state_path)))
                      .replace('__CF_OPT__', str(cf_opt))
                      .replace('__BW_OPT__', str(bw_opt))
                      .replace('__BASE__', repr(base)))

    try:
        EVALUATOR.unlink()
        EVALUATOR.write_text(wrapper)
        EVALUATOR.chmod(0o755)
        OUTPUT.unlink(missing_ok=True)

        result = subprocess.run(
            [str(SCRIPT)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'run_optimization.sh exited with {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )

        assert OUTPUT.exists() and OUTPUT.is_file(), 'Script did not generate best_fit.txt.'
        raw = OUTPUT.read_text()
        assert len(raw.strip().splitlines()) == 1, 'best_fit.txt must contain exactly one line.'
        expected_output = f'{cf_opt / 10:.1f},{bw_opt / 10:.1f},{base:.4f}'
        assert raw.strip() == expected_output, (
            f'Expected the executed search to produce {expected_output!r}, got {raw.strip()!r}.'
        )

        observed = set()
        for line in calls_path.read_text().splitlines():
            a, b = line.split(',')
            observed.add((int(a), int(b)))
        required = {(cf, bw) for cf in cf_values for bw in bw_values}
        missing = required - observed
        assert not missing, f'The evaluator was not called for {len(missing)} required grid points.'

        active, maximum = map(int, state_path.read_text().split())
        assert maximum >= 2, 'Evaluator calls did not overlap; the grid was not evaluated in parallel.'
    finally:
        EVALUATOR.unlink(missing_ok=True)
        EVALUATOR.write_bytes(original_evaluator)
        EVALUATOR.chmod(original_mode)
        calls_path.unlink(missing_ok=True)
        state_path.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
