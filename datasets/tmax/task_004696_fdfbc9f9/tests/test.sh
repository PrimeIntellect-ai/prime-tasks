#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -rf /tmp/bootstrap_oracle
mkdir -p /tmp/bootstrap_oracle/src

cat << 'CARGO_EOF' > /tmp/bootstrap_oracle/Cargo.toml
[package]
name = "bootstrap_oracle"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "=0.8.5"
CARGO_EOF

cat << 'RUST_EOF' > /tmp/bootstrap_oracle/src/main.rs
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use std::collections::BTreeMap;
use std::env;
use std::fs;

fn main() {
    let path = env::args().nth(1).expect("signals CSV path");
    let text = fs::read_to_string(path).expect("read signals CSV");
    let mut signals: BTreeMap<u64, Vec<f64>> = BTreeMap::new();

    for line in text.lines().skip(1) {
        if line.trim().is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split(',').collect();
        assert_eq!(fields.len(), 3);
        let node_id: u64 = fields[0].parse().unwrap();
        let value: f64 = fields[2].parse().unwrap();
        signals.entry(node_id).or_default().push(value);
    }

    for (node_id, values) in signals {
        let n = values.len();
        let mut rng = StdRng::seed_from_u64(node_id);
        let mut means = Vec::with_capacity(1000);
        for _ in 0..1000 {
            let mut sum = 0.0f64;
            for _ in 0..n {
                let index = rng.gen_range(0..n);
                sum += values[index];
            }
            means.push(sum / n as f64);
        }
        means.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!("{},{:.17},{:.17}", node_id, means[24], means[974]);
    }
}
RUST_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/feature_extractor')
SIGNALS = Path('/home/user/data/signals.csv')
NETWORK = Path('/home/user/data/network.json')
OUTPUT = Path('/home/user/features.csv')
ORACLE = Path('/tmp/bootstrap_oracle/target/release/bootstrap_oracle')
HEADER = ['node_id', 'degree', 'dominant_freq_index', 'ci_lower', 'ci_upper']


def run_checked(command, cwd=None, timeout=240):
    result = subprocess.run(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Command {' '.join(map(str, command))} failed with exit code "
        f"{result.returncode}:\n{result.stdout}"
    )
    return result.stdout


def build_and_run_submission():
    main_rs = PROJECT / 'src/main.rs'
    cargo_toml = PROJECT / 'Cargo.toml'
    assert main_rs.is_file(), f'{main_rs} does not exist'
    assert cargo_toml.is_file(), f'{cargo_toml} does not exist'

    run_checked(['cargo', 'build', '--release'], cwd=PROJECT)
    if OUTPUT.exists():
        OUTPUT.unlink()
    run_checked(['cargo', 'run', '--release', '--quiet'], cwd=PROJECT)
    assert OUTPUT.is_file(), f'{OUTPUT} does not exist. Did the Rust program generate it?'


def read_signals():
    grouped = {}
    with SIGNALS.open(newline='') as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ['node_id', 'time', 'signal']
        for row in reader:
            node = int(row['node_id'])
            grouped.setdefault(node, []).append(float(row['signal']))
    return grouped


def bootstrap_bounds():
    output = run_checked([str(ORACLE), str(SIGNALS)])
    bounds = {}
    for line in output.splitlines():
        if line.strip():
            node, lower, upper = line.split(',')
            bounds[int(node)] = (float(lower), float(upper))
    return bounds


def dominant_frequency(values):
    n = len(values)
    best_index = None
    best_magnitude = -1.0
    for k in range(1, n // 2 + 1):
        real = 0.0
        imag = 0.0
        for t, value in enumerate(values):
            angle = -2.0 * math.pi * k * t / n
            real += value * math.cos(angle)
            imag += value * math.sin(angle)
        magnitude = math.hypot(real, imag)
        if magnitude > best_magnitude:
            best_magnitude = magnitude
            best_index = k
    return best_index


def independently_expected():
    signals = read_signals()
    with NETWORK.open() as handle:
        graph = json.load(handle)
    bounds = bootstrap_bounds()
    expected = {}
    for node, values in signals.items():
        assert len(values) == 128, f'Node {node} does not have 128 samples'
        expected[node] = (
            len(graph[str(node)]),
            dominant_frequency(values),
            bounds[node][0],
            bounds[node][1],
        )
    return expected


def read_and_validate_output(expected, require_original_assertions=False):
    assert OUTPUT.is_file(), f'{OUTPUT} does not exist. Did you run the Rust program?'
    with OUTPUT.open(newline='') as handle:
        reader = csv.reader(handle)
        header = next(reader, None)
        assert header is not None, 'features.csv is empty'
        assert header == HEADER, f'Header mismatch. Expected {HEADER}, got {header}'
        rows = list(reader)

    assert len(rows) == len(expected), (
        f'Expected exactly {len(expected)} data rows, found {len(rows)}'
    )
    ordered_nodes = sorted(expected)

    original_degrees = {0: 2, 1: 3, 2: 2, 3: 1}
    original_freqs = {0: 2, 1: 3, 2: 4, 3: 5}

    for i, row in enumerate(rows):
        assert len(row) == 5, f'Row {i} does not have exactly 5 columns'
        node_id = int(row[0])
        assert node_id == ordered_nodes[i], (
            f'Expected node_id {ordered_nodes[i]} at row {i}, found {node_id}. '
            'Rows must be sorted by node_id ascending.'
        )
        degree = int(row[1])
        freq = int(row[2])
        ci_lower = float(row[3])
        ci_upper = float(row[4])
        assert math.isfinite(ci_lower) and math.isfinite(ci_upper)

        exp_degree, exp_freq, exp_lower, exp_upper = expected[node_id]
        assert degree == exp_degree, (
            f'Node {node_id}: expected degree {exp_degree}, got {degree}'
        )
        assert freq == exp_freq, (
            f'Node {node_id}: expected dominant_freq_index {exp_freq}, got {freq}'
        )
        assert math.isclose(ci_lower, exp_lower, rel_tol=0.0, abs_tol=1e-10), (
            f'Node {node_id}: expected ci_lower {exp_lower:.17g}, got {ci_lower:.17g}'
        )
        assert math.isclose(ci_upper, exp_upper, rel_tol=0.0, abs_tol=1e-10), (
            f'Node {node_id}: expected ci_upper {exp_upper:.17g}, got {ci_upper:.17g}'
        )

        if require_original_assertions:
            assert degree == original_degrees[node_id], (
                f'Node {node_id}: expected degree {original_degrees[node_id]}, got {degree}'
            )
            assert freq == original_freqs[node_id], (
                f'Node {node_id}: expected dominant_freq_index '
                f'{original_freqs[node_id]}, got {freq}'
            )
            assert ci_lower < ci_upper, (
                f'Node {node_id}: ci_lower ({ci_lower}) must be strictly less than '
                f'ci_upper ({ci_upper})'
            )
            assert -1.0 <= ci_lower <= 1.0, (
                f'Node {node_id}: ci_lower ({ci_lower}) is outside reasonable bounds'
            )
            assert -1.0 <= ci_upper <= 1.0, (
                f'Node {node_id}: ci_upper ({ci_upper}) is outside reasonable bounds'
            )


def write_challenge_inputs():
    graph = {
        '0': [1, 2],
        '1': [0, 2],
        '2': [0, 1, 3],
        '3': [2],
    }
    NETWORK.write_text(json.dumps(graph))
    frequencies = [7, 11, 17, 23]
    with SIGNALS.open('w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['node_id', 'time', 'signal'])
        for node, frequency in enumerate(frequencies):
            for t in range(128):
                value = (
                    math.sin(2.0 * math.pi * frequency * t / 128.0)
                    + 0.27 * math.cos(2.0 * math.pi * (frequency + 3) * t / 128.0)
                    + 0.08 * math.sin(0.37 * t + 0.61 * node)
                    + 0.015 * (node - 1.5)
                )
                writer.writerow([node, t, repr(value)])


def test_built_rust_program_and_features():
    run_checked(['cargo', 'build', '--release'], cwd='/tmp/bootstrap_oracle')

    original_signals = SIGNALS.read_bytes()
    original_network = NETWORK.read_bytes()
    try:
        build_and_run_submission()
        original_expected = independently_expected()
        assert sorted(original_expected) == [0, 1, 2, 3]
        read_and_validate_output(original_expected, require_original_assertions=True)

        write_challenge_inputs()
        build_and_run_submission()
        challenge_expected = independently_expected()
        read_and_validate_output(challenge_expected)
    finally:
        SIGNALS.write_bytes(original_signals)
        NETWORK.write_bytes(original_network)
        if (PROJECT / 'Cargo.toml').is_file() and (PROJECT / 'src/main.rs').is_file():
            build_and_run_submission()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
