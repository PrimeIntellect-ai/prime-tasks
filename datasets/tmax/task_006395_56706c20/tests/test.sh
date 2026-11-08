#!/bin/bash
mkdir -p /logs/verifier
status=0

rm -rf /tmp/bootstrap_oracle
mkdir -p /tmp/bootstrap_oracle/src
cat <<'CARGO_EOF' > /tmp/bootstrap_oracle/Cargo.toml
[package]
name = "bootstrap_oracle"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
CARGO_EOF

cat <<'RUST_EOF' > /tmp/bootstrap_oracle/src/main.rs
use rand::{Rng, SeedableRng};
use rand::rngs::StdRng;
use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let values: Vec<usize> = input
        .split_whitespace()
        .map(|x| x.parse::<usize>().unwrap())
        .collect();
    let n = values[0];
    let words = values[1];
    assert!(n > 0);
    assert_eq!(values.len(), 2 + n * words);

    let matrix = &values[2..];
    let mut totals = vec![0.0f64; words];
    let mut rng = StdRng::seed_from_u64(42);

    for _ in 0..1000 {
        let mut counts = vec![0usize; words];
        for _ in 0..n {
            let index = rng.gen_range(0..n);
            for word in 0..words {
                counts[word] += matrix[index * words + word];
            }
        }
        for word in 0..words {
            totals[word] += (2 + counts[word]) as f64 / (4 + n) as f64;
        }
    }

    for total in totals {
        println!("{:.17}", total / 1000.0);
    }
}
RUST_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
from collections import Counter
from pathlib import Path

import pytest

RESULTS_PATH = Path("/home/user/results.json")
DATA_PATH = Path("/home/user/data.txt")
MANIFEST_PATH = Path("/home/user/pipeline/Cargo.toml")
ORACLE_PATH = "/tmp/bootstrap_oracle/target/release/bootstrap_oracle"


def parse_docs(text):
    lines = text.strip().split("\n")
    docs = []
    for line in lines:
        cleaned = re.sub(r"[^a-z\s]", "", line.lower())
        docs.append([token for token in cleaned.split() if token])
    return docs


def expected_values(text):
    docs = parse_docs(text)
    all_tokens = [token for doc in docs for token in doc]
    token_counts = Counter(all_tokens)
    sorted_tokens = sorted(token_counts.items(), key=lambda x: (-x[1], x[0]))
    top_words = [x[0] for x in sorted_tokens[:10]]
    assert len(top_words) == 10

    n = len(docs)
    posterior = []
    matrix = []
    for doc in docs:
        present = set(doc)
        matrix.extend(1 if word in present else 0 for word in top_words)
    for word in top_words:
        presence_count = sum(1 for doc in docs if word in doc)
        posterior.append(round((2 + presence_count) / (4 + n), 4))

    oracle_input = "{} {} {}\n".format(
        n, len(top_words), " ".join(str(value) for value in matrix)
    )
    proc = subprocess.run(
        [ORACLE_PATH],
        input=oracle_input,
        text=True,
        capture_output=True,
        timeout=30,
        check=True,
    )
    bootstrap_raw = [float(line) for line in proc.stdout.splitlines() if line.strip()]
    assert len(bootstrap_raw) == 10
    return top_words, posterior, bootstrap_raw


def load_results():
    assert RESULTS_PATH.is_file(), "results.json is missing."
    try:
        with RESULTS_PATH.open("r") as handle:
            return json.load(handle)
    except json.JSONDecodeError:
        pytest.fail("results.json is not valid JSON.")


def assert_number(value, label):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric."
    assert math.isfinite(value), f"{label} must be finite."


def assert_exact_bootstrap(actual_values, expected_raw, words):
    assert len(actual_values) == 10, "Expected 10 bootstrap means."
    for i, (actual, expected) in enumerate(zip(actual_values, expected_raw)):
        assert_number(actual, f"Bootstrap mean for '{words[i]}'")
        assert abs(actual * 10000 - round(actual * 10000)) < 1e-7, \
            f"Bootstrap mean for '{words[i]}' was not rounded to 4 decimal places: {actual}"
        assert abs(actual - expected) <= 0.000050001, \
            f"Bootstrap mean for '{words[i]}' expected the seeded 1000-resample result near {expected:.8f}, got {actual}"


def run_pipeline():
    RESULTS_PATH.unlink(missing_ok=True)
    subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(MANIFEST_PATH)],
        cwd="/home/user/pipeline",
        timeout=240,
        check=True,
    )
    assert RESULTS_PATH.is_file(), "The Rust program did not generate results.json."


def test_rust_project_exists_and_is_runnable():
    assert MANIFEST_PATH.is_file(), "Missing /home/user/pipeline/Cargo.toml."
    rust_sources = list(Path("/home/user/pipeline").rglob("*.rs"))
    assert any(path.is_file() for path in rust_sources), "The Cargo project contains no Rust source files."


def test_results_file_exists():
    assert RESULTS_PATH.is_file(), f"The output file {RESULTS_PATH} does not exist."


def test_results_format_and_content():
    data = load_results()
    assert "top_words" in data, "Missing 'top_words' in results.json"
    assert "posterior_means" in data, "Missing 'posterior_means' in results.json"
    assert "bootstrap_means" in data, "Missing 'bootstrap_means' in results.json"

    text = DATA_PATH.read_text()
    expected_top_words, expected_posterior_means, expected_bootstrap_raw = expected_values(text)

    assert data["top_words"] == expected_top_words, \
        f"Expected top_words {expected_top_words}, got {data['top_words']}"

    assert len(data["posterior_means"]) == 10, "Expected 10 posterior means."
    for i, (actual, expected) in enumerate(zip(data["posterior_means"], expected_posterior_means)):
        assert_number(actual, f"Posterior mean for '{expected_top_words[i]}'")
        assert abs(actual - expected) < 1e-3, \
            f"Posterior mean for '{expected_top_words[i]}' expected ~{expected}, got {actual}"

    assert len(data["bootstrap_means"]) == 10, "Expected 10 bootstrap means."
    for i, (actual, expected) in enumerate(zip(data["bootstrap_means"], expected_posterior_means)):
        assert_number(actual, f"Bootstrap mean for '{expected_top_words[i]}'")
        assert abs(actual - expected) < 0.05, \
            f"Bootstrap mean for '{expected_top_words[i]}' ({actual}) is too far from expected posterior mean ({expected})"

    assert_exact_bootstrap(data["bootstrap_means"], expected_bootstrap_raw, expected_top_words)


def test_pipeline_on_derived_input():
    original = DATA_PATH.read_bytes()
    alternate = """Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda.
Alpha beta gamma delta epsilon.
Alpha alpha beta gamma zeta.
Beta delta eta theta.
Gamma epsilon iota kappa.
Alpha delta zeta lambda.
Beta epsilon eta iota.
Gamma theta kappa lambda.
Alpha beta iota lambda.
Delta epsilon zeta eta.
Alpha gamma theta iota.
Beta delta kappa lambda.
Gamma epsilon zeta theta.
"""
    try:
        DATA_PATH.write_text(alternate)
        run_pipeline()
        data = load_results()
        assert "top_words" in data
        assert "posterior_means" in data
        assert "bootstrap_means" in data
        words, posterior, bootstrap_raw = expected_values(alternate)
        assert data["top_words"] == words
        assert len(data["posterior_means"]) == 10
        for i, (actual, expected) in enumerate(zip(data["posterior_means"], posterior)):
            assert_number(actual, f"Posterior mean for '{words[i]}'")
            assert abs(actual - expected) < 1e-3
        assert_exact_bootstrap(data["bootstrap_means"], bootstrap_raw, words)
    finally:
        DATA_PATH.write_bytes(original)
        run_pipeline()
TEST_EOF

if [ -f /home/user/pipeline/Cargo.toml ] \
   && rm -f /home/user/results.json \
   && timeout 240 cargo run --quiet --manifest-path /home/user/pipeline/Cargo.toml \
   && cargo build --quiet --release --manifest-path /tmp/bootstrap_oracle/Cargo.toml \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
    status=1
fi

echo "$status" > /logs/verifier/reward.txt
