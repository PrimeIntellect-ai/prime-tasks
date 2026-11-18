#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
X_PATH = HOME / 'sensor_x.csv'
Y_PATH = HOME / 'sensor_y.csv'
OUT_PATH = HOME / 'bootstrap_results.txt'
BIN_PATH = Path('/tmp/submission_analyzer')


class MT19937:
    def __init__(self, seed):
        self.mt = [0] * 624
        self.mt[0] = seed & 0xffffffff
        for i in range(1, 624):
            prev = self.mt[i - 1]
            self.mt[i] = (1812433253 * (prev ^ (prev >> 30)) + i) & 0xffffffff
        self.index = 624

    def twist(self):
        for i in range(624):
            x = (self.mt[i] & 0x80000000) | (self.mt[(i + 1) % 624] & 0x7fffffff)
            xa = x >> 1
            if x & 1:
                xa ^= 0x9908b0df
            self.mt[i] = self.mt[(i + 397) % 624] ^ xa
        self.index = 0

    def next(self):
        if self.index >= 624:
            self.twist()
        y = self.mt[self.index]
        self.index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9d2c5680
        y ^= (y << 15) & 0xefc60000
        y ^= y >> 18
        return y & 0xffffffff


def expected_lines(data_x, data_y):
    projections = [
        (data_x[i] + data_y[i]) / math.sqrt(2.0)
        for i in sorted(set(data_x) & set(data_y))
    ]
    assert projections
    n = len(projections)
    original_mean = sum(projections) / n

    gen = MT19937(42)
    bootstrap_means = []
    for _ in range(10000):
        total = 0.0
        for _ in range(n):
            total += projections[gen.next() % n]
        bootstrap_means.append(total / n)

    bootstrap_mean = sum(bootstrap_means) / 10000
    variance = sum((v - bootstrap_mean) ** 2 for v in bootstrap_means) / 9999
    se = math.sqrt(variance)
    return [f'Original Mean: {original_mean:.6f}', f'Bootstrap SE: {se:.6f}']


def write_csv(path, value_name, rows):
    with path.open('w', newline='') as f:
        f.write(f'id,{value_name}\n')
        for row_id, value in rows:
            f.write(f'{row_id},{value:.8f}\n')


def run_submission():
    if OUT_PATH.exists():
        OUT_PATH.unlink()
    result = subprocess.run(
        [str(BIN_PATH)], cwd=str(HOME), capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'Compiled C++ program exited with {result.returncode}. '
        f'stdout={result.stdout!r} stderr={result.stderr!r}'
    )
    assert OUT_PATH.exists(), f'Output file {OUT_PATH} is missing after executing the C++ program.'
    return OUT_PATH.read_text().splitlines()


def make_case(common_count):
    rng = secrets.SystemRandom()
    common = rng.sample(range(100, 10000), common_count)
    remaining = [i for i in rng.sample(range(10001, 30000), 6)]
    x_ids = common + remaining[:3]
    y_ids = common + remaining[3:]
    rng.shuffle(x_ids)
    rng.shuffle(y_ids)

    data_x = {i: float(f'{rng.uniform(-50.0, 50.0):.8f}') for i in x_ids}
    data_y = {i: float(f'{rng.uniform(-50.0, 50.0):.8f}') for i in y_ids}
    return data_x, data_y, x_ids, y_ids


def compute_expected_mean():
    data_x = {1: 1.5, 2: 2.3, 3: 3.1, 4: 4.0, 5: 5.2, 6: 6.1, 7: 7.0, 8: 8.5, 9: 9.2, 10: 10.1}
    data_y = {3: 2.9, 1: 1.4, 10: 9.9, 5: 5.1, 4: 4.1, 8: 8.3, 2: 2.0, 9: 8.9, 7: 7.2, 6: 5.8}
    p = []
    for i in sorted(data_x.keys()):
        if i in data_y:
            p.append((data_x[i] + data_y[i]) / math.sqrt(2))
    return sum(p) / len(p)


def test_cpp_pipeline_and_bootstrap_results():
    sources = sorted(str(p) for p in HOME.rglob('*.cpp') if p.is_file())
    assert sources, 'No C++ source file was found under /home/user.'

    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', *sources, '-o', str(BIN_PATH)],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f'C++ source did not compile. stdout={compile_result.stdout!r} '
        f'stderr={compile_result.stderr!r}'
    )

    original_x = X_PATH.read_bytes()
    original_y = Y_PATH.read_bytes()
    try:
        for common_count in (7, 13):
            data_x, data_y, x_ids, y_ids = make_case(common_count)
            write_csv(X_PATH, 'val_x', [(i, data_x[i]) for i in x_ids])
            write_csv(Y_PATH, 'val_y', [(i, data_y[i]) for i in y_ids])
            actual = run_submission()
            expected = expected_lines(data_x, data_y)
            assert actual == expected, f'Expected {expected!r}, got {actual!r}'
    finally:
        X_PATH.write_bytes(original_x)
        Y_PATH.write_bytes(original_y)
        run_submission()

    file_path = '/home/user/bootstrap_results.txt'
    assert os.path.exists(file_path), f'Output file {file_path} is missing.'

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f'Expected exactly 2 lines in {file_path}, found {len(lines)}.'
    assert lines[0].startswith('Original Mean:'), "First line must start with 'Original Mean:'"
    assert lines[1].startswith('Bootstrap SE:'), "Second line must start with 'Bootstrap SE:'"

    try:
        actual_mean_str = lines[0].split(':')[1].strip()
        actual_se_str = lines[1].split(':')[1].strip()
        float(actual_mean_str)
        float(actual_se_str)
    except ValueError:
        pytest.fail('Could not parse numeric values from the output file.')

    expected_mean = compute_expected_mean()
    expected_mean_str = f'{expected_mean:.6f}'
    expected_se_str = '1.258525'

    assert actual_mean_str == expected_mean_str, f'Expected Original Mean to be {expected_mean_str}, got {actual_mean_str}'
    assert actual_se_str == expected_se_str, f'Expected Bootstrap SE to be {expected_se_str}, got {actual_se_str}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
