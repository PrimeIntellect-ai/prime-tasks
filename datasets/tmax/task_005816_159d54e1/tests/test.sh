#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pytest

PROJECT = Path('/home/user/sim_search')
RESULTS = Path('/home/user/output/results.json')
QUERY = Path('/home/user/data/query.csv')
DATABASE = Path('/home/user/data/database.csv')


def check_project():
    assert PROJECT.is_dir(), '/home/user/sim_search must exist and be a Rust project.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Rust project is missing Cargo.toml.'
    sources = [p for p in PROJECT.rglob('*.rs') if 'target' not in p.parts]
    assert sources, 'Rust project contains no Rust source files.'
    source_text = '\n'.join(p.read_text(errors='ignore') for p in sources)
    assert 'as_micros' in source_text, 'Rust source must convert measured durations to microseconds.'
    assert ('Instant' in source_text or 'SystemTime' in source_text), \
        'Rust source must use a standard Rust timing primitive.'
    assert ('elapsed' in source_text or 'duration_since' in source_text), \
        'Rust source must actually obtain an elapsed duration.'


def f32(x):
    return np.float32(x)


def expected_results(query_path, database_path):
    with open(query_path, newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) == 1, 'query.csv must contain one vector.'
    q64 = [float(x) for x in rows[0][1:]]
    assert len(q64) == 10
    q32 = [f32(x) for x in rows[0][1:]]

    qnorm64_sq = 0.0
    qnorm32_sq = f32(0.0)
    for a64, a32 in zip(q64, q32):
        qnorm64_sq += a64 * a64
        qnorm32_sq = f32(qnorm32_sq + f32(a32 * a32))
    qnorm64 = math.sqrt(qnorm64_sq)
    qnorm32 = f32(np.sqrt(qnorm32_sq))

    top_id = -1
    max_sim = -2.0
    max_diff = 0.0
    count = 0

    with open(database_path, newline='') as f:
        for parts in csv.reader(f):
            if not parts or not parts[0]:
                continue
            count += 1
            ident = int(parts[0])
            d64 = [float(x) for x in parts[1:]]
            d32 = [f32(x) for x in parts[1:]]
            assert len(d64) == 10

            dot64 = 0.0
            dnorm64_sq = 0.0
            dot32 = f32(0.0)
            dnorm32_sq = f32(0.0)
            for a64, b64, a32, b32 in zip(q64, d64, q32, d32):
                dot64 += a64 * b64
                dnorm64_sq += b64 * b64
                dot32 = f32(dot32 + f32(a32 * b32))
                dnorm32_sq = f32(dnorm32_sq + f32(b32 * b32))

            sim64 = dot64 / (qnorm64 * math.sqrt(dnorm64_sq))
            dnorm32 = f32(np.sqrt(dnorm32_sq))
            sim32 = f32(dot32 / f32(qnorm32 * dnorm32))
            assert math.isfinite(sim64) and math.isfinite(float(sim32))

            diff = abs(float(sim32) - sim64)
            max_diff = max(max_diff, diff)
            if sim64 > max_sim:
                max_sim = sim64
                top_id = ident

    assert count == 1000, f'Expected 1000 database vectors, found {count}.'
    return top_id, float(f'{max_diff:.6f}')


def run_program():
    if RESULTS.exists():
        RESULTS.unlink()
    proc = subprocess.run(
        ['cargo', 'run', '--release', '--quiet'],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f'cargo run --release failed:\n{proc.stdout}\n{proc.stderr}'
    assert RESULTS.is_file(), 'The executed Rust application did not create results.json.'


def validate_results(query_path, database_path):
    with open(RESULTS) as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {RESULTS} is not valid JSON.')

    expected_keys = {'time_us_f32', 'time_us_f64', 'max_abs_diff', 'top_match_id'}
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f'Missing keys in results.json: {missing_keys}'

    assert isinstance(results['time_us_f32'], int), 'time_us_f32 must be an integer'
    assert results['time_us_f32'] > 0, 'time_us_f32 must be greater than 0'
    assert isinstance(results['time_us_f64'], int), 'time_us_f64 must be an integer'
    assert results['time_us_f64'] > 0, 'time_us_f64 must be greater than 0'
    assert isinstance(results['max_abs_diff'], (float, int)), 'max_abs_diff must be a float'
    assert isinstance(results['top_match_id'], int), 'top_match_id must be an integer'

    top_id, rounded_diff = expected_results(query_path, database_path)
    assert results['top_match_id'] == top_id, \
        f"Expected top_match_id {top_id}, got {results['top_match_id']}."

    max_diff = results['max_abs_diff']
    assert math.isfinite(float(max_diff))
    assert 0.0 <= max_diff <= 0.0001, \
        f'max_abs_diff {max_diff} is out of the expected range (0.0 to 0.0001) for typical f32 vs f64 precision differences.'
    assert abs(float(max_diff) - rounded_diff) <= 5e-13, \
        f'Expected max_abs_diff rounded to six places to be {rounded_diff:.6f}, got {max_diff}.'


def write_challenge():
    rng = random.SystemRandom()
    for _ in range(40):
        q = [(0.5 + rng.random()) * 1e-20 for _ in range(10)]
        rows = []
        ids = list(range(20000, 21000))
        rng.shuffle(ids)
        for ident in ids:
            vec = [(0.5 + rng.random()) * 1e-20 for _ in range(10)]
            rows.append((ident, vec))

        with open(QUERY, 'w', newline='') as f:
            csv.writer(f).writerow(['query'] + [format(x, '.17g') for x in q])
        with open(DATABASE, 'w', newline='') as f:
            w = csv.writer(f)
            for ident, vec in rows:
                w.writerow([ident] + [format(x, '.17g') for x in vec])

        _, rounded_diff = expected_results(QUERY, DATABASE)
        if 0.0 < rounded_diff <= 0.0001:
            return
    pytest.fail('Could not construct a finite f32/f64 verification challenge.')


def test_results_json():
    check_project()
    assert QUERY.is_file(), 'Query CSV missing, cannot verify correctness.'
    assert DATABASE.is_file(), 'Database CSV missing, cannot verify correctness.'

    original_query = QUERY.read_bytes()
    original_database = DATABASE.read_bytes()
    try:
        run_program()
        validate_results(QUERY, DATABASE)

        write_challenge()
        run_program()
        validate_results(QUERY, DATABASE)
    finally:
        QUERY.write_bytes(original_query)
        DATABASE.write_bytes(original_database)

    # Leave the required output corresponding to the original supplied data.
    run_program()
    validate_results(QUERY, DATABASE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
