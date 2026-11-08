#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import re
import secrets
import subprocess

import numpy as np

SCRIPT_PATH = '/home/user/compute_energy.py'
DATA_PATH = '/home/user/data.txt'
REPORT_PATH = '/home/user/bug_report.txt'
EXPECTED_DATA_BYTES = b'463\n' * 10000


def expected_energy(values, seed):
    rng = np.random.RandomState(seed)
    noise = rng.randint(0, 10, size=values.shape, dtype=np.int32)
    widened = (values + noise).astype(np.int64)
    return int(np.sum(widened * widened, dtype=np.int64))


def overflowed_energy(values, seed):
    rng = np.random.RandomState(seed)
    noise = rng.randint(0, 10, size=values.shape, dtype=np.int32)
    v = values + noise
    return int(np.sum(v * v, dtype=np.int32))


def test_data_txt_is_unchanged():
    assert os.path.isfile(DATA_PATH), f'The data file {DATA_PATH} is missing.'
    with open(DATA_PATH, 'rb') as f:
        assert f.read() == EXPECTED_DATA_BYTES, f'{DATA_PATH} was modified.'


def test_bug_report_contents():
    report_path = REPORT_PATH
    assert os.path.isfile(report_path), f"The report file {report_path} is missing."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}."

    assert lines[0] == "Failing Seed: 4", f"Expected 'Failing Seed: 4', got '{lines[0]}'"
    assert lines[1] == "Overflowed Energy: -2146914693", f"Expected 'Overflowed Energy: -2146914693', got '{lines[1]}'"
    assert lines[2] == "Correct Energy: 2148052603", f"Expected 'Correct Energy: 2148052603', got '{lines[2]}'"

    data = np.full(10000, 463, dtype=np.int32)
    seed = 1
    while overflowed_energy(data, seed) >= 0:
        seed += 1
        assert seed < 10000, 'Could not independently reproduce the overflow.'

    assert seed == 4
    assert lines == [
        f'Failing Seed: {seed}',
        f'Overflowed Energy: {overflowed_energy(data, seed)}',
        f'Correct Energy: {expected_energy(data, seed)}',
    ]


def run_script(seed):
    return subprocess.run(
        ['python3', SCRIPT_PATH, str(seed)],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_compute_energy_fixed():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"The script {script_path} is missing."

    # Retain the original seed-4 regression check.
    result = run_script(4)

    assert result.returncode == 0, f"Script failed with seed 4. Error: {result.stderr}\nOutput: {result.stdout}"
    assert "Error: Negative energy calculated!" not in result.stdout, "Script still produces negative energy error for seed 4."
    assert "Energy: 2148052603" in result.stdout, f"Script did not output the correct energy. Output was: {result.stdout}"

    # Exercise unpredictable seeds and derive every expected answer independently.
    data = np.full(10000, 463, dtype=np.int32)
    seeds = {1, 2, 3, 4, 5}
    while len(seeds) < 15:
        seeds.add(secrets.randbelow(2**31 - 1) + 1)

    for seed in seeds:
        result = run_script(seed)
        expected = expected_energy(data, seed)
        assert result.returncode == 0, (
            f'Script failed with seed {seed}. Error: {result.stderr}\nOutput: {result.stdout}'
        )
        assert re.fullmatch(rf'Energy: {expected}\s*', result.stdout), (
            f'Wrong energy for seed {seed}: expected {expected}, output was {result.stdout!r}'
        )


def test_compute_energy_handles_wide_squares_without_overflow():
    # Import and exercise the required function on unpredictable values whose
    # individual squares exceed int32, ensuring arithmetic is widened before multiplication.
    spec = importlib.util.spec_from_file_location('submitted_compute_energy', SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'compute_energy', None)), 'compute_energy is missing or not callable.'

    chooser = secrets.SystemRandom()
    values = np.array([
        chooser.choice((-1, 1)) * chooser.randrange(50000, 100001)
        for _ in range(257)
    ], dtype=np.int32)
    seed = secrets.randbelow(2**31 - 1) + 1
    expected = expected_energy(values, seed)
    actual = module.compute_energy(values.copy(), seed)
    assert int(actual) == expected, (
        f'compute_energy overflowed or lost precision: expected {expected}, got {actual}'
    )


def test_data_txt_remains_unchanged_after_execution():
    with open(DATA_PATH, 'rb') as f:
        assert f.read() == EXPECTED_DATA_BYTES, f'{DATA_PATH} was modified during execution.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
