#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import shutil
import statistics
import subprocess
import tempfile

FLOAT_RE = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')


def read_times(path='/home/user/times.txt'):
    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    values = []
    for i, line in enumerate(lines):
        assert FLOAT_RE.fullmatch(line), f"Line {i+1} is not exactly one float: '{line}'"
        value = float(line)
        assert math.isfinite(value), f"Line {i+1} is not finite: '{line}'"
        values.append(value)
    return lines, values


def test_mc_sim_executable_exists():
    """Check if /home/user/mc_sim exists and is executable."""
    exe_path = '/home/user/mc_sim'
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    with open(exe_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{exe_path} is not an ELF executable."


def test_mc_sim_was_built_from_source_with_o3():
    """Compare the submitted program's machine code with an -O3 build of the supplied source."""
    source = '/home/user/mc_sim.c'
    assert os.path.isfile(source), f"Source file {source} is missing."

    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, 'mc_sim_reference')
        submitted_text = os.path.join(td, 'submitted.text')
        reference_text = os.path.join(td, 'reference.text')

        subprocess.run(
            ['gcc', '-O3', source, '-o', reference],
            check=True, capture_output=True, text=True
        )
        subprocess.run(
            ['objcopy', '--only-section=.text', '-O', 'binary', '/home/user/mc_sim', submitted_text],
            check=True, capture_output=True, text=True
        )
        subprocess.run(
            ['objcopy', '--only-section=.text', '-O', 'binary', reference, reference_text],
            check=True, capture_output=True, text=True
        )

        with open(submitted_text, 'rb') as f:
            submitted_code = f.read()
        with open(reference_text, 'rb') as f:
            reference_code = f.read()

        assert submitted_code, 'Submitted executable has no .text section.'
        assert submitted_code == reference_code, \
            'Submitted executable machine code does not match gcc -O3 compilation of mc_sim.c.'


def test_mc_sim_executes_with_required_iteration_count():
    """Actually execute the artifact with N=50000000 and validate its output."""
    result = subprocess.run(
        ['/home/user/mc_sim', '50000000'],
        check=True, capture_output=True, text=True, timeout=180
    )
    output = result.stdout.strip()
    assert '\n' not in output, f"mc_sim produced more than one output line: {output!r}"
    assert FLOAT_RE.fullmatch(output), f"mc_sim output is not exactly one float: {output!r}"
    observed = float(output)
    assert math.isfinite(observed) and observed > 0, \
        f"mc_sim returned an invalid execution time: {output!r}"

    _, recorded = read_times()
    assert all(value > 0 for value in recorded), 'All recorded execution times must be positive.'
    assert len(set(recorded)) > 1, 'The 50 recorded timings cannot all be identical.'
    recorded_median = statistics.median(recorded)
    assert observed / 4.0 <= recorded_median <= observed * 4.0, \
        f"Recorded timings are inconsistent with a fresh N=50000000 run ({observed:.6f}s)."


def test_times_txt_validity():
    """Check if /home/user/times.txt exists, has 50 lines, and contains floats."""
    times_path = '/home/user/times.txt'
    assert os.path.isfile(times_path), f"File {times_path} does not exist."

    with open(times_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 50, f"Expected exactly 50 lines in {times_path}, found {len(lines)}."

    for i, line in enumerate(lines):
        try:
            float(line)
        except ValueError:
            assert False, f"Line {i+1} in {times_path} is not a valid float: '{line}'"

    _, values = read_times(times_path)
    assert all(value > 0 for value in values), 'Execution times must be finite and positive.'


def test_bootstrap_ci_exists():
    """Check if /home/user/bootstrap_ci.txt exists."""
    ci_path = '/home/user/bootstrap_ci.txt'
    assert os.path.isfile(ci_path), f"File {ci_path} does not exist."


def test_bootstrap_script_exists():
    script_path = '/home/user/bootstrap.py'
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist."


def test_bootstrap_ci_correctness():
    """Verify the contents of bootstrap_ci.txt match the expected numpy computation."""
    times_path = '/home/user/times.txt'
    ci_path = '/home/user/bootstrap_ci.txt'

    assert os.path.isfile(times_path), f"Cannot verify CI because {times_path} is missing."
    assert os.path.isfile(ci_path), f"Cannot verify CI because {ci_path} is missing."

    with open(ci_path, 'r') as f:
        agent_output = f.read().strip()

    numpy_script = f"""
import numpy as np
with open('{times_path}', 'r') as f:
    times = np.array([float(line.strip()) for line in f if line.strip()])
np.random.seed(42)
B = 10000
means = []
for _ in range(B):
    sample = np.random.choice(times, size=len(times), replace=True)
    means.append(np.mean(sample))
lower, upper = np.percentile(means, [2.5, 97.5])
print(f"{{lower:.6f}},{{upper:.6f}}")
"""

    try:
        result = subprocess.run(
            ['python3', '-c', numpy_script],
            check=True,
            capture_output=True,
            text=True
        )
        expected_output = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to compute expected CI using numpy: {e.stderr}"

    assert agent_output == expected_output, \
        f"Bootstrap CI mismatch. Expected '{expected_output}', but got '{agent_output}'."


def test_bootstrap_script_is_executed_and_uses_required_operations():
    """Run bootstrap.py on verifier-generated data and instrument the required numpy calls."""
    times_path = '/home/user/times.txt'
    ci_path = '/home/user/bootstrap_ci.txt'
    script_path = '/home/user/bootstrap.py'
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist."

    with open(times_path, 'rb') as f:
        original_times = f.read()
    original_ci_exists = os.path.exists(ci_path)
    original_ci = None
    if original_ci_exists:
        with open(ci_path, 'rb') as f:
            original_ci = f.read()

    with tempfile.TemporaryDirectory() as td:
        token = int.from_bytes(secrets.token_bytes(8), 'big')
        controlled = [
            ((token >> (i % 48)) & 0xffff) / 997.0 + i * 0.173 + 0.25
            for i in range(50)
        ]
        with open(times_path, 'w') as f:
            for value in controlled:
                f.write(f'{value:.12f}\n')

        event_path = os.path.join(td, 'numpy_events.json')
        sitecustomize = r'''
import atexit
import json
import os
import numpy as np

_state = {
    "seed_calls": [],
    "choice_count": 0,
    "choice_calls_valid": True,
    "percentile_calls": []
}
_original_seed = np.random.seed
_original_choice = np.random.choice
_original_percentile = np.percentile

def seed(value=None):
    try:
        _state["seed_calls"].append(int(value))
    except Exception:
        _state["seed_calls"].append(repr(value))
    return _original_seed(value)

def choice(a, size=None, replace=True, p=None):
    _state["choice_count"] += 1
    try:
        valid = len(a) == 50 and size == len(a) and replace is True and p is None
    except Exception:
        valid = False
    _state["choice_calls_valid"] = _state["choice_calls_valid"] and valid
    return _original_choice(a, size=size, replace=replace, p=p)

def percentile(a, q, *args, **kwargs):
    try:
        q_value = [float(x) for x in q]
    except Exception:
        q_value = repr(q)
    _state["percentile_calls"].append(q_value)
    return _original_percentile(a, q, *args, **kwargs)

np.random.seed = seed
np.random.choice = choice
np.percentile = percentile

@atexit.register
def save_events():
    path = os.environ.get("BOOTSTRAP_EVENT_PATH")
    if path:
        with open(path, "w") as f:
            json.dump(_state, f)
'''
        with open(os.path.join(td, 'sitecustomize.py'), 'w') as f:
            f.write(sitecustomize)

        env = os.environ.copy()
        env['PYTHONPATH'] = td + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['BOOTSTRAP_EVENT_PATH'] = event_path

        try:
            result = subprocess.run(
                ['python3', script_path], env=env,
                capture_output=True, text=True, timeout=120
            )
            assert result.returncode == 0, \
                f"bootstrap.py failed when executed: {result.stderr}"
            assert os.path.isfile(ci_path), 'bootstrap.py did not create /home/user/bootstrap_ci.txt.'

            expected_program = '''
import numpy as np
with open("/home/user/times.txt") as f:
    times = np.array([float(line.strip()) for line in f if line.strip()])
np.random.seed(42)
bootstrap_means = []
for _ in range(10000):
    sample = np.random.choice(times, size=len(times), replace=True)
    bootstrap_means.append(np.mean(sample))
lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])
print(f"{lower:.6f},{upper:.6f}")
'''
            expected = subprocess.run(
                ['python3', '-c', expected_program],
                check=True, capture_output=True, text=True
            ).stdout.strip()
            with open(ci_path) as f:
                actual = f.read().strip()
            assert actual == expected, \
                f"Executed bootstrap.py produced '{actual}', expected '{expected}' on verifier data."

            assert os.path.isfile(event_path), 'Could not verify bootstrap.py numpy operations.'
            with open(event_path) as f:
                events = json.load(f)
            assert 42 in events['seed_calls'], 'bootstrap.py did not call numpy.random.seed(42).'
            assert events['choice_count'] == 10000, \
                f"Expected exactly 10000 numpy.random.choice calls, got {events['choice_count']}."
            assert events['choice_calls_valid'], \
                'Every resample must use size=len(times), replace=True, and the 50-value times array.'
            assert [2.5, 97.5] in events['percentile_calls'], \
                'bootstrap.py did not call numpy.percentile with [2.5, 97.5].'
        finally:
            with open(times_path, 'wb') as f:
                f.write(original_times)
            if original_ci_exists:
                with open(ci_path, 'wb') as f:
                    f.write(original_ci)
            elif os.path.exists(ci_path):
                os.remove(ci_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
