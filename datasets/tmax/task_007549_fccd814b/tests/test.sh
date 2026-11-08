#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
OBS = HOME / 'observations.csv'
REF = HOME / 'reference.csv'
OUT = HOME / 'model_inputs.log'
EXPECTED_ORIGINAL = [
    'Q1: Singular',
    'Q2: Valid',
    'Q3: Anomalous',
    'Q4: Valid',
]


def read_output():
    assert OUT.is_file(), 'The file /home/user/model_inputs.log does not exist.'
    with OUT.open('r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_model_inputs_log_exists():
    assert OUT.is_file(), 'The file /home/user/model_inputs.log does not exist.'


def test_model_inputs_log_content():
    actual_lines = read_output()
    assert actual_lines == EXPECTED_ORIGINAL, (
        'The contents of /home/user/model_inputs.log are incorrect.\n'
        f'Expected: {EXPECTED_ORIGINAL}\nActual: {actual_lines}'
    )


def quadrant(x, y):
    if x <= 4 and y <= 4:
        return 'Q1'
    if x >= 5 and y <= 4:
        return 'Q2'
    if x <= 4 and y >= 5:
        return 'Q3'
    return 'Q4'


def derive_expected(observations, references):
    result = []
    for q in ('Q1', 'Q2', 'Q3', 'Q4'):
        cells = [(xy, value) for xy, value in observations.items()
                 if quadrant(*xy) == q]
        values = [value for _, value in cells]
        n = len(values)
        variance = sum(v * v for v in values) / n - (sum(values) / n) ** 2
        if variance < 0.1:
            status = 'Singular'
        else:
            mae = sum(abs(value - references[xy]) for xy, value in cells) / n
            status = 'Anomalous' if mae > 5.0 else 'Valid'
        result.append(f'{q}: {status}')
    return result


def make_dataset(statuses):
    rng = secrets.SystemRandom()
    observations = {}
    references = {}
    base = rng.uniform(20.0, 80.0)

    for x in range(10):
        for y in range(10):
            q = quadrant(x, y)
            ref_value = base + 3.25 * x + 4.5 * y + rng.uniform(-0.1, 0.1)
            references[(x, y)] = ref_value
            if statuses[q] == 'Singular':
                obs_value = base + 100.0 + 7.0 * int(q[1])
            elif statuses[q] == 'Anomalous':
                obs_value = ref_value + rng.choice((-9.0, 9.0))
            else:
                obs_value = ref_value + rng.uniform(-1.5, 1.5)
            observations[(x, y)] = obs_value

    return observations, references


def write_csv(path, values):
    with path.open('w') as f:
        f.write('x,y,value\n')
        for x in range(10):
            for y in range(10):
                f.write(f'{x},{y},{values[(x, y)]:.8f}\n')


def candidate_scripts():
    excluded = {OBS.resolve(), REF.resolve(), OUT.resolve()}
    candidates = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path.resolve() in excluded:
            continue
        try:
            if path.stat().st_size > 262144:
                continue
            data = path.read_bytes()
            if b'\x00' in data:
                continue
            data.decode('utf-8')
        except (OSError, UnicodeDecodeError):
            continue
        candidates.append(path)
    return candidates


def test_bash_pipeline_recomputes_classifications():
    candidates = candidate_scripts()
    assert candidates, (
        'No Bash pipeline artifact was found under /home/user. '
        'A prewritten model_inputs.log alone is insufficient.'
    )

    original_obs = OBS.read_bytes()
    original_ref = REF.read_bytes()
    original_out = OUT.read_bytes() if OUT.exists() else None
    rng = secrets.SystemRandom()
    original_pattern = ('Singular', 'Valid', 'Anomalous', 'Valid')
    patterns = set()
    while len(patterns) < 3:
        values = ['Singular', 'Anomalous', 'Valid', 'Valid']
        rng.shuffle(values)
        pattern = tuple(values)
        if pattern != original_pattern:
            patterns.add(pattern)

    failures = []
    try:
        for script in candidates:
            passed = True
            reason = ''
            for pattern in patterns:
                statuses = dict(zip(('Q1', 'Q2', 'Q3', 'Q4'), pattern))
                observations, references = make_dataset(statuses)
                expected = derive_expected(observations, references)
                write_csv(OBS, observations)
                write_csv(REF, references)
                if OUT.exists():
                    OUT.unlink()
                try:
                    completed = subprocess.run(
                        ['/bin/bash', str(script)],
                        cwd=str(HOME),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=15,
                    )
                except (subprocess.TimeoutExpired, OSError) as exc:
                    passed = False
                    reason = str(exc)
                    break
                if completed.returncode != 0:
                    passed = False
                    reason = f'exited with status {completed.returncode}'
                    break
                if not OUT.is_file():
                    passed = False
                    reason = 'did not create model_inputs.log'
                    break
                actual = read_output()
                if actual != expected:
                    passed = False
                    reason = f'expected {expected}, got {actual}'
                    break
            if passed:
                return
            failures.append(f'{script}: {reason}')

        raise AssertionError(
            'No submitted Bash pipeline correctly recomputed the classifications '
            'for independently generated CSV inputs.\n' + '\n'.join(failures)
        )
    finally:
        OBS.write_bytes(original_obs)
        REF.write_bytes(original_ref)
        if original_out is None:
            if OUT.exists():
                OUT.unlink()
        else:
            OUT.write_bytes(original_out)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
