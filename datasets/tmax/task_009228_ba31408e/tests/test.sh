#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

rm -rf /tmp/bootstrap_oracle
mkdir -p /tmp/bootstrap_oracle/src
cat > /tmp/bootstrap_oracle/Cargo.toml <<'EOF'
[package]
name = "bootstrap_oracle"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
rand_chacha = "0.3"
EOF

cat > /tmp/bootstrap_oracle/src/main.rs <<'EOF'
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let values: Vec<f64> = input.lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| line.trim().parse::<f64>().unwrap())
        .collect();
    assert!(!values.is_empty());

    let mut rng = ChaCha8Rng::seed_from_u64(42);
    let mut means = Vec::with_capacity(10_000);
    for _ in 0..10_000 {
        let mut sum = 0.0;
        for _ in 0..values.len() {
            sum += values[rng.gen_range(0..values.len())];
        }
        means.push(sum / values.len() as f64);
    }
    means.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!("{:.17} {:.17}", means[250], means[9749]);
}
EOF

cargo build --release --quiet --manifest-path /tmp/bootstrap_oracle/Cargo.toml
if [ $? -ne 0 ]; then
    exit 0
fi

cat > /tmp/test_final_state.py <<'PYEOF'
import csv
import json
import math
import os
import pathlib
import random
import re
import subprocess
import time

PROJECT = pathlib.Path('/home/user/etl_pipeline')
CSV_PATH = pathlib.Path('/home/user/data/sensor_log.csv')
RESULTS_PATH = pathlib.Path('/home/user/output/results.json')
ORACLE = '/tmp/bootstrap_oracle/target/release/bootstrap_oracle'


def clean_csv():
    cleaned_x = []
    cleaned_y = []
    with CSV_PATH.open('r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sx = row['sensor_x']
            sy = row['sensor_y']
            if not sx or not sy or sx.lower() == 'nan' or sy.lower() == 'nan':
                continue
            try:
                x_val = float(sx)
                y_val = float(sy)
            except ValueError:
                continue
            if x_val > 1000.0:
                continue
            cleaned_x.append(x_val)
            cleaned_y.append(y_val)
    return cleaned_x, cleaned_y


def exact_bootstrap_ci(values):
    proc = subprocess.run(
        [ORACLE],
        input=''.join(f'{x:.17g}\n' for x in values),
        text=True,
        capture_output=True,
        timeout=30,
        check=True,
    )
    lower, upper = map(float, proc.stdout.split())
    return lower, upper


def validate_results(wall_ms):
    # Original existence assertions.
    assert RESULTS_PATH.exists(), 'results.json does not exist in /home/user/output/'
    assert RESULTS_PATH.is_file(), '/home/user/output/results.json is not a file'
    try:
        with RESULTS_PATH.open('r') as f:
            results = json.load(f)
    except json.JSONDecodeError:
        assert False, 'results.json is not valid JSON'

    expected_keys = {
        'cleaned_row_count', 'slope', 'mean_x', 'bootstrap_ci_lower',
        'bootstrap_ci_upper', 'compute_time_ms'
    }
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f'results.json is missing keys: {missing_keys}'

    assert CSV_PATH.exists(), 'Original CSV file is missing'
    cleaned_x, cleaned_y = clean_csv()
    n = len(cleaned_x)
    assert n > 1
    assert results['cleaned_row_count'] == n, (
        f"Expected cleaned_row_count to be {n}, got {results['cleaned_row_count']}"
    )

    mean_x = sum(cleaned_x) / n
    mean_y = sum(cleaned_y) / n
    assert math.isclose(results['mean_x'], mean_x, rel_tol=1e-2), (
        f"Expected mean_x ~ {mean_x:.4f}, got {results['mean_x']}"
    )

    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(cleaned_x, cleaned_y))
    denominator = sum((x - mean_x) ** 2 for x in cleaned_x)
    expected_slope = numerator / denominator
    assert math.isclose(results['slope'], expected_slope, rel_tol=1e-2), (
        f"Expected slope ~ {expected_slope:.4f}, got {results['slope']}"
    )

    # Preserve the original analytical sanity checks.
    variance_x = sum((x - mean_x) ** 2 for x in cleaned_x) / (n - 1)
    std_x = math.sqrt(variance_x)
    margin_of_error = 1.96 * (std_x / math.sqrt(n))
    expected_ci_lower = mean_x - margin_of_error
    expected_ci_upper = mean_x + margin_of_error
    assert abs(results['bootstrap_ci_lower'] - expected_ci_lower) <= 1.0, (
        f"bootstrap_ci_lower {results['bootstrap_ci_lower']} is not within 1.0 "
        f"of analytical bound {expected_ci_lower:.4f}"
    )
    assert abs(results['bootstrap_ci_upper'] - expected_ci_upper) <= 1.0, (
        f"bootstrap_ci_upper {results['bootstrap_ci_upper']} is not within 1.0 "
        f"of analytical bound {expected_ci_upper:.4f}"
    )

    # Require the exact seeded ChaCha8 percentile-bootstrap result.
    exact_lower, exact_upper = exact_bootstrap_ci(cleaned_x)
    assert math.isclose(results['bootstrap_ci_lower'], exact_lower, rel_tol=1e-7, abs_tol=1e-7), (
        f"Expected seeded bootstrap lower bound {exact_lower}, got {results['bootstrap_ci_lower']}"
    )
    assert math.isclose(results['bootstrap_ci_upper'], exact_upper, rel_tol=1e-7, abs_tol=1e-7), (
        f"Expected seeded bootstrap upper bound {exact_upper}, got {results['bootstrap_ci_upper']}"
    )

    compute = results['compute_time_ms']
    assert isinstance(compute, (int, float)) and not isinstance(compute, bool) and compute > 0, (
        'compute_time_ms must be a positive number'
    )
    assert math.isfinite(float(compute))
    assert compute <= wall_ms + 1000, 'compute_time_ms exceeds the application wall-clock time'
    return RESULTS_PATH.read_bytes()


def run_application():
    if RESULTS_PATH.exists():
        RESULTS_PATH.unlink()
    start = time.monotonic()
    proc = subprocess.run(
        ['cargo', 'run', '--release', '--quiet'],
        cwd=str(PROJECT),
        text=True,
        capture_output=True,
        timeout=180,
    )
    elapsed_ms = (time.monotonic() - start) * 1000.0
    assert proc.returncode == 0, f'cargo run --release failed:\n{proc.stdout}\n{proc.stderr}'
    return validate_results(elapsed_ms)


def write_challenge_csv(seed, n):
    rng = random.Random(seed)
    rows = []
    for i in range(n):
        x = rng.uniform(-30.0, 140.0) + i * 0.0137
        y = -1.75 * x + 8.0 + rng.uniform(-2.0, 2.0)
        rows.append([i + 1, f'{x:.12f}', f'{y:.12f}'])
    rows.extend([
        [n + 1, '', '12.0'],
        [n + 2, '4.0', 'NaN'],
        [n + 3, 'not-a-number', '7.0'],
        [n + 4, '5001.0', '9.0'],
    ])
    with CSV_PATH.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'sensor_x', 'sensor_y'])
        writer.writerows(rows)


def test_pipeline_is_rust_and_executes_exact_bootstrap():
    assert PROJECT.exists() and PROJECT.is_dir(), '/home/user/etl_pipeline is missing'
    cargo_toml = PROJECT / 'Cargo.toml'
    src_dir = PROJECT / 'src'
    assert cargo_toml.is_file(), 'Cargo.toml is missing'
    assert src_dir.is_dir(), 'Rust src directory is missing'

    manifest = cargo_toml.read_text(errors='replace')
    assert re.search(r'(?m)^\s*rand\s*=', manifest), 'Cargo.toml must depend on rand'
    assert re.search(r'(?m)^\s*rand_chacha\s*=', manifest), 'Cargo.toml must depend on rand_chacha'
    rust_files = list(src_dir.rglob('*.rs'))
    assert rust_files, 'No Rust source files found'
    source = '\n'.join(p.read_text(errors='replace') for p in rust_files)
    assert 'ChaCha8Rng' in source, 'Rust application does not use ChaCha8Rng'
    assert re.search(r'seed_from_u64\s*\(\s*42\s*\)', source), 'ChaCha8Rng is not seeded with 42'
    assert re.search(r'10_?000', source), 'Rust source does not specify 10,000 bootstrap resamples'
    assert 'Instant' in source and 'elapsed' in source, 'Rust source does not measure elapsed computation time'

    original_csv = CSV_PATH.read_bytes()
    preexisting_result = RESULTS_PATH.read_bytes() if RESULTS_PATH.is_file() else None
    restored_result = preexisting_result
    try:
        # Execute the submitted Rust artifact on the supplied data first.
        restored_result = run_application()

        # Exercise it on verifier-generated inputs so precomputed analytical bounds
        # or hard-coded results cannot pass.
        for n in (11, 23):
            seed = int.from_bytes(os.urandom(8), 'big')
            write_challenge_csv(seed, n)
            run_application()
    finally:
        CSV_PATH.write_bytes(original_csv)
        RESULTS_PATH.parent.mkdir(parents=True, exist_ok=True)
        if restored_result is None:
            if RESULTS_PATH.exists():
                RESULTS_PATH.unlink()
        else:
            RESULTS_PATH.write_bytes(restored_result)
PYEOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
if [ $? -eq 0 ]; then
    reward=1
fi
exit 0
