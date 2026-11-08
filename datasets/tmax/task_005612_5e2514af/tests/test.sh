#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import subprocess
from pathlib import Path

INPUT = Path('/home/user/input.csv')
WEIGHTS = Path('/home/user/weights.csv')
SOURCE = Path('/home/user/evaluate.go')
VALIDATION = Path('/home/user/validation.txt')
BINARY = Path('/tmp/evaluate_submission')

ORIGINAL_INPUT = b'''id,v1,v2,v3,target
1,0.5,1.2,0.1,2.5
2,1.0,0.0,1.0,3.5
3,2.0,-1.0,0.5,4.0
4,0.0,2.0,1.0,-0.5
5,-1.0,-1.0,-1.0,-2.0
'''
ORIGINAL_WEIGHTS = b'1.5,-0.5,2.0\n'


def expected_output(input_bytes, weights_bytes):
    weights_str = weights_bytes.decode().strip()
    weights = [float(w) for w in weights_str.split(',')]
    assert len(weights) == 3, 'Weights file should contain exactly 3 weights.'

    sq_errors = []
    anomalies = []
    reader = csv.DictReader(io.StringIO(input_bytes.decode()))
    for row in reader:
        row_id = int(row['id'])
        v1, v2, v3 = float(row['v1']), float(row['v2']), float(row['v3'])
        target = float(row['target'])
        y_pred = v1 * weights[0] + v2 * weights[1] + v3 * weights[2]
        error = y_pred - target
        sq_errors.append(error ** 2)
        if abs(error) > 2.0:
            anomalies.append(row_id)

    assert sq_errors, 'Input must contain at least one data row.'
    mse = sum(sq_errors) / len(sq_errors)
    return '\n'.join([f'MSE: {mse:.4f}', 'Anomalies:'] + [str(a) for a in anomalies])


def run_case(input_bytes, weights_bytes):
    INPUT.write_bytes(input_bytes)
    WEIGHTS.write_bytes(weights_bytes)
    if VALIDATION.exists():
        VALIDATION.unlink()

    result = subprocess.run(
        [str(BINARY)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f'evaluate.go exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    assert os.path.isfile(VALIDATION), f'{VALIDATION} is missing. Did you run your Go program?'
    assert os.path.isfile(INPUT), f'{INPUT} is missing.'
    assert os.path.isfile(WEIGHTS), f'{WEIGHTS} is missing.'
    assert INPUT.read_bytes() == input_bytes, 'The program must not modify input.csv.'
    assert WEIGHTS.read_bytes() == weights_bytes, 'The program must not modify weights.csv.'

    expected_content = expected_output(input_bytes, weights_bytes)
    actual_content = VALIDATION.read_text().strip()
    assert actual_content == expected_content, (
        f'Content of {VALIDATION} is incorrect.\n'
        f'Expected:\n{expected_content}\n\nActual:\n{actual_content}'
    )
    return VALIDATION.read_bytes()


def test_evaluate_go_exists():
    assert os.path.isfile(SOURCE), '/home/user/evaluate.go is missing. You must save your Go program at this path.'


def test_validation_txt_correctness():
    assert os.path.isfile(INPUT), f'{INPUT} is missing.'
    assert os.path.isfile(WEIGHTS), f'{WEIGHTS} is missing.'
    assert INPUT.read_bytes() == ORIGINAL_INPUT, 'input.csv was modified from the provided fixture.'
    assert WEIGHTS.read_bytes() == ORIGINAL_WEIGHTS, 'weights.csv was modified from the provided fixture.'

    build = subprocess.run(
        ['go', 'build', '-o', str(BINARY), str(SOURCE)],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=60
    )
    assert build.returncode == 0, (
        f'/home/user/evaluate.go does not compile.\n'
        f'stdout:\n{build.stdout}\nstderr:\n{build.stderr}'
    )
    assert INPUT.read_bytes() == ORIGINAL_INPUT, 'input.csv changed during compilation.'
    assert WEIGHTS.read_bytes() == ORIGINAL_WEIGHTS, 'weights.csv changed during compilation.'

    original_validation = None
    try:
        # First verify the supplied fixtures and require the executable to create the log.
        original_validation = run_case(ORIGINAL_INPUT, ORIGINAL_WEIGHTS)

        # Then exercise the same executable on an unpredictable dataset so a hard-coded
        # validation.txt or implementation cannot pass.
        rng = secrets.SystemRandom()
        weights = [rng.choice([-4, -3, -2, -1, 1, 2, 3, 4]) for _ in range(3)]
        weights_bytes = (','.join(map(str, weights)) + '\n').encode()
        errors = [0, 2, -2, 3, -3, 5, -5]
        rows = ['id,v1,v2,v3,target']
        used_ids = set()
        for error in errors:
            row_id = rng.randrange(1000, 1000000)
            while row_id in used_ids:
                row_id = rng.randrange(1000, 1000000)
            used_ids.add(row_id)
            features = [rng.randrange(-9, 10) for _ in range(3)]
            prediction = sum(v * w for v, w in zip(features, weights))
            target = prediction - error
            rows.append(','.join(map(str, [row_id] + features + [target])))
        challenge_input = ('\n'.join(rows) + '\n').encode()
        run_case(challenge_input, weights_bytes)
    finally:
        INPUT.write_bytes(ORIGINAL_INPUT)
        WEIGHTS.write_bytes(ORIGINAL_WEIGHTS)
        if original_validation is not None:
            VALIDATION.write_bytes(original_validation)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
