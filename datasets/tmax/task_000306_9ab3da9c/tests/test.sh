#!/bin/bash

mkdir -p /logs/verifier

verify() {
    [ -f /home/user/decay_sim/Cargo.toml ] || return 1
    [ -f /home/user/decay_sim/src/main.rs ] || return 1

    # Remove any pre-existing result and execute the submitted Cargo project.
    rm -f /home/user/spectrum.csv || return 1
    timeout 180 env HOME=/home/user CARGO_HOME=/home/user/.cargo \
        cargo run --quiet --manifest-path /home/user/decay_sim/Cargo.toml || return 1
    [ -f /home/user/spectrum.csv ] || return 1

    oracle_dir=$(mktemp -d) || return 1

    cat > "$oracle_dir/Cargo.toml" <<'CARGO_EOF' || return 1
[package]
name = "decay_reference"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
rand_chacha = "0.3"
rand_distr = "0.4"
CARGO_EOF

    mkdir -p "$oracle_dir/src" || return 1
    cat > "$oracle_dir/src/main.rs" <<'RUST_EOF' || return 1
use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;
use rand_distr::{Distribution, Normal};
use std::fs::File;
use std::io::{BufWriter, Write};

fn main() {
    let mut rng = ChaCha8Rng::seed_from_u64(42);
    let normal = Normal::new(500.0_f64, 20.0_f64).unwrap();
    let mut histogram = [0_u64; 40];

    let mut a = 1_000_000.0_f64;
    let mut b = 0.0_f64;
    let lambda_a = 0.1_f64;
    let lambda_b = 0.05_f64;
    let dt = 1.0_f64;

    for _ in 0..60 {
        let decay_a = lambda_a * a * dt;
        let decay_b = lambda_b * b * dt;
        let detected = (decay_b * 0.1).floor() as usize;

        for _ in 0..detected {
            let energy: f64 = normal.sample(&mut rng);
            if energy >= 400.0 && energy < 600.0 {
                let bin = ((energy - 400.0) / 5.0).floor() as usize;
                histogram[bin] += 1;
            }
        }

        a -= decay_a;
        b += decay_a - decay_b;
    }

    let output = std::env::var("EXPECTED_OUT").unwrap();
    let file = File::create(output).unwrap();
    let mut writer = BufWriter::new(file);
    for (i, count) in histogram.iter().enumerate() {
        writeln!(writer, "{},{}", 400 + i * 5, count).unwrap();
    }
}
RUST_EOF

    EXPECTED_OUT="$oracle_dir/expected.csv" \
        timeout 180 env HOME=/home/user CARGO_HOME=/home/user/.cargo \
        cargo run --offline --quiet --manifest-path "$oracle_dir/Cargo.toml" || return 1

    cat > "$oracle_dir/test_final_state.py" <<'TEST_EOF' || return 1
import os


def test_spectrum_csv_exists_and_correct():
    csv_path = "/home/user/spectrum.csv"
    assert os.path.isfile(csv_path), (
        f"{csv_path} does not exist. Did you run the simulation and write the output?"
    )

    expected_path = os.environ["EXPECTED_PATH"]
    with open(expected_path, "r") as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    assert len(expected_lines) == 40
    expected_total = sum(int(line.split(",", 1)[1]) for line in expected_lines)
    assert 90000 < expected_total < 92000

    with open(csv_path, "r") as f:
        # Preserve the original treatment of whitespace and trailing empty lines.
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 40, (
        f"Expected exactly 40 lines in {csv_path}, found {len(lines)}"
    )

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f"Line {i + 1} mismatch: expected '{expected}', got '{actual}'"
        )
TEST_EOF

    EXPECTED_PATH="$oracle_dir/expected.csv" \
        python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$oracle_dir/test_final_state.py" -x --tb=short 2>&1 || return 1

    rm -rf "$oracle_dir"
    return 0
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
