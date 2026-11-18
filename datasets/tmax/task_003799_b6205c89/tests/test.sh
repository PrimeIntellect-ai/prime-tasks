#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/mcmc_profiler.c')
DATA = Path('/home/user/latencies.txt')
RESULTS = Path('/home/user/profiler_results.txt')
BINARY = Path('/tmp/mcmc_profiler_verified')
KEYS = {'w', 'mu1', 'mu2', 'kl_divergence'}


def assert_source_exists():
    assert SOURCE.exists(), f'Source file {SOURCE} is missing.'
    assert SOURCE.is_file(), f'{SOURCE} is not a file.'


def compile_source():
    if BINARY.exists():
        BINARY.unlink()
    proc = subprocess.run(
        ['gcc', '-O3', str(SOURCE), '-lm', '-o', str(BINARY)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, f'Compilation failed:\n{proc.stdout}{proc.stderr}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Compilation did not produce an executable.'


def run_program():
    if RESULTS.exists():
        RESULTS.unlink()
    proc = subprocess.run(
        [str(BINARY)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert proc.returncode == 0, f'Program failed:\n{proc.stdout}{proc.stderr}'
    assert RESULTS.exists(), f'Results file {RESULTS} is missing.'
    assert RESULTS.is_file(), f'{RESULTS} is not a file.'


def original_format_assertions():
    expected_keys = {'w', 'mu1', 'mu2', 'kl_divergence'}
    parsed_keys = set()
    with RESULTS.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            assert ':' in line, f"Invalid format in results file. Line missing colon: '{line}'"
            key, val_str = line.split(':', 1)
            key = key.strip()
            val_str = val_str.strip()
            assert key in expected_keys, f"Unexpected key '{key}' found in results file."
            try:
                float(val_str)
            except ValueError:
                raise AssertionError(f"Value for '{key}' is not a valid float: '{val_str}'")
            parsed_keys.add(key)
    missing_keys = expected_keys - parsed_keys
    assert not missing_keys, f'Missing expected keys in results file: {missing_keys}'


def parse_strict_results():
    original_format_assertions()
    lines = [line.strip() for line in RESULTS.read_text().splitlines() if line.strip()]
    assert len(lines) == 4, 'Results must contain exactly four non-empty lines.'
    expected_order = ['w', 'mu1', 'mu2', 'kl_divergence']
    values = {}
    pattern = re.compile(r'^([A-Za-z0-9_]+): (-?\d+\.\d{3})$')
    for line, expected_key in zip(lines, expected_order):
        match = pattern.fullmatch(line)
        assert match, f"Result line is not in the required three-decimal format: '{line}'"
        key, text = match.groups()
        assert key == expected_key, f'Expected key {expected_key}, found {key}.'
        value = float(text)
        assert math.isfinite(value), f'{key} must be finite.'
        values[key] = value
    return values


def specified_kl(data, w, mu1, mu2):
    counts = [0] * 50
    for x in data:
        if 0.0 <= x <= 20.0:
            index = 49 if x == 20.0 else int(x / 0.4)
            if 0 <= index < 50:
                counts[index] += 1
    n = len(data)
    norm = 1.0 / math.sqrt(2.0 * math.pi)
    q = []
    for i in range(50):
        midpoint = (i + 0.5) * 0.4
        a = norm * math.exp(-0.5 * (midpoint - mu1) ** 2)
        b = norm * math.exp(-0.5 * (midpoint - mu2) ** 2)
        q.append((w * a + (1.0 - w) * b) * 0.4)
    total_q = sum(q)
    q = [v / total_q for v in q]
    result = 0.0
    for count, qi in zip(counts, q):
        if count:
            p = count / n
            result += p * math.log(p / qi)
    return result


def write_case(center1, center2, count1, count2):
    offsets = [-1.25, -0.75, -0.35, 0.0, 0.35, 0.75, 1.25]
    values = []
    for i in range(count1):
        values.append(center1 + offsets[i % len(offsets)])
    for i in range(count2):
        values.append(center2 + offsets[i % len(offsets)])
    random.SystemRandom().shuffle(values)
    DATA.write_text(''.join(f'{x:.6f}\n' for x in values))
    return values


def check_generated_case(center1, center2, count1, count2):
    values = write_case(center1, center2, count1, count2)
    run_program()
    result = parse_strict_results()
    expected_w = count1 / (count1 + count2)
    assert abs(result['w'] - expected_w) <= 0.12, \
        f"w={result['w']} does not fit generated data (expected near {expected_w})."
    assert abs(result['mu1'] - center1) <= 0.45, \
        f"mu1={result['mu1']} does not fit generated data (expected near {center1})."
    assert abs(result['mu2'] - center2) <= 0.45, \
        f"mu2={result['mu2']} does not fit generated data (expected near {center2})."
    assert 0.0 <= result['w'] <= 1.0
    assert 0.0 <= result['mu1'] < result['mu2'] <= 20.0
    expected_kl = specified_kl(values, result['w'], result['mu1'], result['mu2'])
    assert result['kl_divergence'] >= 0.0
    assert abs(result['kl_divergence'] - expected_kl) <= 0.006, \
        f"KL mismatch: reported {result['kl_divergence']}, recomputed {expected_kl:.6f}."


def original_bounds_assertions(result):
    assert 0.28 <= result['w'] <= 0.42, \
        f"w out of bounds: {result['w']}. Expected between 0.28 and 0.42."
    assert 3.7 <= result['mu1'] <= 4.3, \
        f"mu1 out of bounds: {result['mu1']}. Expected between 3.7 and 4.3."
    assert 10.7 <= result['mu2'] <= 11.3, \
        f"mu2 out of bounds: {result['mu2']}. Expected between 10.7 and 11.3."
    assert result['kl_divergence'] < 0.1, \
        f"KL divergence too high: {result['kl_divergence']}. Expected < 0.1."


def main():
    assert_source_exists()
    compile_source()
    original_data = DATA.read_bytes()
    try:
        rng = random.SystemRandom()
        c1a = rng.uniform(2.8, 4.2)
        c2a = rng.uniform(12.0, 14.5)
        check_generated_case(c1a, c2a, 60, 180)

        c1b = rng.uniform(5.0, 6.5)
        c2b = rng.uniform(15.0, 17.0)
        check_generated_case(c1b, c2b, 168, 72)
    finally:
        DATA.write_bytes(original_data)

    # Re-run on the required input so stale or synthetic-case output cannot pass.
    run_program()
    result = parse_strict_results()
    original_bounds_assertions(result)
    original_values = [float(line) for line in DATA.read_text().splitlines() if line.strip()]
    expected_kl = specified_kl(
        original_values, result['w'], result['mu1'], result['mu2']
    )
    assert result['kl_divergence'] >= 0.0, 'KL divergence cannot be negative.'
    assert abs(result['kl_divergence'] - expected_kl) <= 0.006, \
        f"KL mismatch: reported {result['kl_divergence']}, recomputed {expected_kl:.6f}."


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
