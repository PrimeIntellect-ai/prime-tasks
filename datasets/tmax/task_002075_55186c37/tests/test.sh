#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess
from collections import defaultdict
from pathlib import Path

CSV_PATH = Path("/home/user/experiments.csv")
SUMMARY_PATH = Path("/home/user/summary.json")
PIPELINE_PATH = Path("/home/user/pipeline")


def expected_from_csv(path):
    data = defaultdict(list)
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "experiments.csv has no header"
        required = {"experiment_id", "temperature", "particle_count"}
        assert required.issubset(reader.fieldnames), "experiments.csv is missing required columns"

        for row in reader:
            raw_count = row["particle_count"]
            try:
                count = int(raw_count)
                if count < -(2**31) or count > 2**31 - 1:
                    continue
            except (TypeError, ValueError):
                continue
            data[row["experiment_id"]].append(float(row["temperature"]))

    m = 2**31
    a = 1103515245
    c = 12345
    seed = 42
    expected = {}

    for exp_id in sorted(data):
        temperatures = data[exp_id]
        length = len(temperatures)
        boot_means = []
        for _ in range(1000):
            sample_sum = 0.0
            for _ in range(length):
                seed = (a * seed + c) % m
                sample_sum += temperatures[seed % length]
            boot_means.append(sample_sum / length)
        boot_means.sort()
        expected[exp_id] = {
            "mean": round(sum(temperatures) / length, 2),
            "ci_lower": round(boot_means[25], 2),
            "ci_upper": round(boot_means[975], 2),
            "valid_samples": length,
        }
    return expected


def load_summary():
    assert SUMMARY_PATH.exists(), "The file /home/user/summary.json does not exist."
    assert SUMMARY_PATH.is_file(), "/home/user/summary.json is not a file."
    try:
        with SUMMARY_PATH.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        raise AssertionError("The file /home/user/summary.json does not contain valid JSON.")


def assert_results(results, expected):
    assert isinstance(results, dict), "summary.json must contain a JSON object"
    assert set(results.keys()) == set(expected.keys()), \
        f"Expected experiment IDs {list(expected.keys())}, but got {list(results.keys())}"

    for exp_id, expected_stats in expected.items():
        actual_stats = results[exp_id]
        assert isinstance(actual_stats, dict), f"Result for {exp_id} must be an object"
        for stat, expected_value in expected_stats.items():
            assert stat in actual_stats, f"Missing '{stat}' in results for {exp_id}"
            actual_value = actual_stats[stat]
            assert isinstance(actual_value, (int, float)) and not isinstance(actual_value, bool), \
                f"For {exp_id} '{stat}', expected a numeric value"
            assert math.isclose(actual_value, expected_value, rel_tol=1e-5, abs_tol=1e-2), \
                f"For {exp_id} '{stat}', expected {expected_value} but got {actual_value}"


def test_pipeline_and_summary():
    # Preserve the original output assertions, deriving their answers from the actual CSV.
    original_results = load_summary()
    assert_results(original_results, expected_from_csv(CSV_PATH))

    # Require an actual Cargo project containing Rust source that builds successfully.
    assert PIPELINE_PATH.is_dir(), "/home/user/pipeline does not exist or is not a directory"
    assert (PIPELINE_PATH / "Cargo.toml").is_file(), "Cargo.toml is missing"
    rust_sources = [p for p in PIPELINE_PATH.rglob("*.rs") if p.is_file() and p.stat().st_size > 0]
    assert rust_sources, "The pipeline contains no non-empty Rust source files"

    build = subprocess.run(
        ["cargo", "build", "--quiet"], cwd=PIPELINE_PATH,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert build.returncode == 0, f"The Rust project failed to build:\n{build.stdout}"

    # Exercise the built pipeline against a fresh runtime-generated dataset so a fixed
    # precomputed summary for the image's original CSV cannot pass.
    token = secrets.token_hex(8)
    base_a = 100 + secrets.randbelow(400)
    base_z = 600 + secrets.randbelow(400)
    alpha = f"alpha_{token}"
    zeta = f"zeta_{token}"
    challenge = (
        "experiment_id,temperature,particle_count\n"
        f"{zeta},{base_z + 2},10\n"
        f"{alpha},{base_a},5\n"
        f"{alpha},{base_a + 99},NA\n"
        f"{zeta},{base_z + 7},12\n"
        f"{alpha},{base_a + 4},6\n"
        f"{zeta},{base_z + 50},3.5\n"
        f"{alpha},{base_a + 9},7\n"
        f"{zeta},{base_z + 11},15\n"
        f"{alpha},{base_a + 77},\n"
    )

    original_csv = CSV_PATH.read_bytes()
    original_summary = SUMMARY_PATH.read_bytes()
    try:
        CSV_PATH.write_text(challenge, encoding="utf-8")
        run = subprocess.run(
            ["cargo", "run", "--quiet"], cwd=PIPELINE_PATH,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
        )
        assert run.returncode == 0, f"The Rust pipeline failed to run:\n{run.stdout}"
        assert_results(load_summary(), expected_from_csv(CSV_PATH))
    finally:
        CSV_PATH.write_bytes(original_csv)
        SUMMARY_PATH.write_bytes(original_summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
