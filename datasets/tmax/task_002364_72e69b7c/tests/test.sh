#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_pipeline.py
import json
import math
import os
import re
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

SIM_DIR = Path('/home/user/sim')
RESULTS = Path('/home/user/simulation_results.json')
GO_LOG = Path('/tmp/verifier_go_calls.log')


def numeric_literals(source):
    values = []
    for token in re.findall(r'(?<![A-Za-z0-9_])(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', source):
        try:
            values.append(float(token))
        except ValueError:
            pass
    return values


def has_number(values, expected, tolerance=1e-12):
    return any(math.isclose(value, expected, rel_tol=0.0, abs_tol=tolerance) for value in values)


def test_go_implementation_and_launcher_exist():
    assert SIM_DIR.is_dir(), 'Expected /home/user/sim to exist.'
    go_files = sorted(SIM_DIR.rglob('*.go'))
    assert go_files, 'No Go source files were found in /home/user/sim.'
    assert (SIM_DIR / 'Makefile').is_file() or (SIM_DIR / 'run.sh').is_file(), \
        'Expected /home/user/sim/Makefile or /home/user/sim/run.sh.'

    source = '\n'.join(path.read_text(errors='replace') for path in go_files)
    # Remove comments before checking that the requested algorithms are represented
    # by executable source rather than by explanatory text alone.
    code = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    code = re.sub(r'//[^\n]*', '', code)
    compact = re.sub(r'\s+', '', code).lower()
    values = numeric_literals(code)

    assert re.search(r'\bpackage\s+main\b', code), 'Go program must use package main.'
    assert re.search(r'\bfunc\s+main\s*\(', code), 'Go program must define func main.'
    assert len(re.findall(r'\bfor\b', code)) >= 2, \
        'Expected iterative Newton-Raphson and RK4 integration loops in the Go source.'

    for expected in (4.0, 0.5, 10.0, 3.0, 0.01, 0.1, 0.2, 0.6):
        assert has_number(values, expected), f'Missing required problem constant {expected} in Go source.'
    assert has_number(values, 1e-6, 1e-12), 'Missing Newton-Raphson tolerance 1e-6.'
    assert has_number(values, 50.0) or has_number(values, 5000.0), \
        'Missing the t=50 integration limit or its 5000 fixed steps.'

    assert ('math.sqrt' in compact or 'math.hypot' in compact), \
        'Expected a magnitude/square-root calculation for Newton convergence or steady state.'
    assert '/' in code and ('/6' in compact or '/6.0' in compact or '1.0/6' in compact), \
        'Expected the RK4 weighted 1/6 update in Go source.'
    assert not re.search(r'gonum|scipy|numpy', code, flags=re.I), \
        'External mathematics/scientific libraries are not permitted.'


def run_pipeline():
    real_go = shutil.which('go')
    assert real_go, 'Go toolchain is unavailable.'

    wrapper_dir = Path('/tmp/verifier-bin')
    wrapper_dir.mkdir(exist_ok=True)
    wrapper = wrapper_dir / 'go'
    wrapper.write_text(
        '#!/bin/bash\n'
        'printf "%s\\n" "$*" >> /tmp/verifier_go_calls.log\n'
        f'exec {real_go} "$@"\n'
    )
    wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    env = os.environ.copy()
    env['PATH'] = str(wrapper_dir) + os.pathsep + env.get('PATH', '')

    launchers = []
    if (SIM_DIR / 'run.sh').is_file():
        launchers.append(['bash', str(SIM_DIR / 'run.sh')])
    if (SIM_DIR / 'Makefile').is_file():
        launchers.append(['make', '-B', '-C', str(SIM_DIR)])
    assert launchers

    errors = []
    for command in launchers:
        RESULTS.write_text('{"verifier_sentinel": true}\n')
        GO_LOG.unlink(missing_ok=True)
        try:
            completed = subprocess.run(
                command, cwd=SIM_DIR, env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                timeout=120, check=False,
            )
        except Exception as exc:
            errors.append(f'{command!r}: {exc}')
            continue

        calls = GO_LOG.read_text(errors='replace') if GO_LOG.exists() else ''
        used_build_tool = any(
            re.search(r'(^|\s)' + verb + r'(\s|$)', line)
            for line in calls.splitlines() for verb in ('run', 'build')
        )
        if completed.returncode == 0 and used_build_tool and RESULTS.exists():
            try:
                produced = json.loads(RESULTS.read_text())
            except Exception:
                produced = None
            if isinstance(produced, dict) and 'verifier_sentinel' not in produced:
                return
        errors.append(
            f'{command!r} returned {completed.returncode}; Go calls={calls!r}; '
            f'output={completed.stdout[-2000:]!r}'
        )

    pytest.fail('No supplied build/run launcher rebuilt and ran the Go program to replace the report. ' + ' | '.join(errors))


def get_expected_simulated():
    x, y = 3.0, 1.0
    dt = 0.01
    def f(x, y): return -0.5*x + 0.1*y**2
    def g(x, y): return 0.2*x*y - 0.6*y

    for _ in range(5000):
        k1x = f(x, y)
        k1y = g(x, y)

        k2x = f(x + 0.5*dt*k1x, y + 0.5*dt*k1y)
        k2y = g(x + 0.5*dt*k1x, y + 0.5*dt*k1y)

        k3x = f(x + 0.5*dt*k2x, y + 0.5*dt*k2y)
        k3y = g(x + 0.5*dt*k2x, y + 0.5*dt*k2y)

        k4x = f(x + dt*k3x, y + dt*k3y)
        k4y = g(x + dt*k3x, y + dt*k3y)

        x += (dt/6.0) * (k1x + 2*k2x + 2*k3x + k4x)
        y += (dt/6.0) * (k1y + 2*k2y + 2*k3y + k4y)
    return x, y


def test_simulation_results_are_generated_by_pipeline():
    run_pipeline()

    results_path = '/home/user/simulation_results.json'
    assert os.path.exists(results_path), f'Expected results file {results_path} does not exist.'

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {results_path} is not valid JSON.')

    required_keys = [
        'initial_root_x', 'initial_root_y',
        'simulated_final_x', 'simulated_final_y',
        'analytical_ss_x', 'analytical_ss_y'
    ]

    for key in required_keys:
        assert key in data, f"Missing key '{key}' in JSON output."
        assert isinstance(data[key], (int, float)), f"Value for '{key}' must be a number."

    # 1. Check Initial Root
    assert math.isclose(data['initial_root_x'], 3.0, abs_tol=1e-3), \
        f"initial_root_x is {data['initial_root_x']}, expected ~3.0"
    assert math.isclose(data['initial_root_y'], 1.0, abs_tol=1e-3), \
        f"initial_root_y is {data['initial_root_y']}, expected ~1.0"

    # 2. Check Analytical Steady State
    expected_ss_x = 3.0
    expected_ss_y = math.sqrt(15)
    assert math.isclose(data['analytical_ss_x'], expected_ss_x, abs_tol=1e-3), \
        f"analytical_ss_x is {data['analytical_ss_x']}, expected ~{expected_ss_x}"
    assert math.isclose(data['analytical_ss_y'], expected_ss_y, abs_tol=1e-3), \
        f"analytical_ss_y is {data['analytical_ss_y']}, expected ~{expected_ss_y}"

    # 3. Check Simulated Final State
    expected_sim_x, expected_sim_y = get_expected_simulated()
    assert math.isclose(data['simulated_final_x'], expected_sim_x, abs_tol=1e-3), \
        f"simulated_final_x is {data['simulated_final_x']}, expected ~{expected_sim_x}"
    assert math.isclose(data['simulated_final_y'], expected_sim_y, abs_tol=1e-3), \
        f"simulated_final_y is {data['simulated_final_y']}, expected ~{expected_sim_y}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
