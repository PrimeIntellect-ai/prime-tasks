#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/pcr_sim")
OUTPUT = Path("/home/user/simulation_results.json")
TEMPLATE = Path("/home/user/template.txt")
PRIMERS = Path("/home/user/primers.txt")
EXPERIMENTAL = Path("/home/user/experimental_dist.json")
_ran_original = False


def euler_sim(dt, count=3):
    A = [1.0] * count
    k = 0.8
    C_max = 100000.0
    steps = int(round(30.0 / dt))
    for _ in range(steps):
        sum_A = sum(A)
        rate = k * (1.0 - sum_A / C_max)
        A = [a + dt * a * rate for a in A]
    return sum(A)


def expected_optimal(count):
    baseline_total = euler_sim(0.001, count)
    for dt in [1.0, 0.5, 0.1, 0.05, 0.01]:
        total = euler_sim(dt, count)
        if abs(total - baseline_total) / baseline_total <= 0.005:
            return dt
    raise AssertionError("Could not find a valid optimal dt in the test logic.")


def run_submission():
    if OUTPUT.exists():
        OUTPUT.unlink()
    try:
        proc = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
            cwd=str(PROJECT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Rust application did not finish within 120 seconds.")
    assert proc.returncode == 0, (
        "The Rust application failed.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )
    assert OUTPUT.is_file(), "Running the Rust application did not create simulation_results.json."


def run_original_once():
    global _ran_original
    if not _ran_original:
        run_submission()
        _ran_original = True


def load_output():
    with OUTPUT.open("r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT} is not valid JSON.")


def test_rust_project_exists():
    assert PROJECT.is_dir(), f"Rust project directory {PROJECT} is missing."
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing from the Rust project."
    rust_sources = list(PROJECT.rglob("*.rs"))
    assert rust_sources, "The project contains no Rust source files."


def test_simulation_results_file_exists():
    run_original_once()
    path = "/home/user/simulation_results.json"
    assert os.path.exists(path), f"Output file {path} is missing."


def test_simulation_results_content():
    run_original_once()
    path = "/home/user/simulation_results.json"
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    # Check required keys
    required_keys = {"optimal_dt", "amplicon_lengths", "final_total_concentration", "tv_distance"}
    missing = required_keys - set(data.keys())
    assert not missing, f"JSON is missing keys: {missing}"

    # Verify amplicon lengths
    lengths = sorted(data["amplicon_lengths"])
    assert lengths == [998, 999, 1000], f"Expected amplicon lengths [998, 999, 1000], got {lengths}"

    # Compute baseline and find expected optimal dt
    baseline_total = euler_sim(0.001)
    dts = [1.0, 0.5, 0.1, 0.05, 0.01]
    expected_optimal_dt = None
    for dt in dts:
        total = euler_sim(dt)
        if abs(total - baseline_total) / baseline_total <= 0.005:
            expected_optimal_dt = dt
            break

    assert expected_optimal_dt is not None, "Could not find a valid optimal dt in the test logic."

    # Verify optimal dt
    assert math.isclose(data["optimal_dt"], expected_optimal_dt, rel_tol=1e-5), \
        f"Expected optimal_dt {expected_optimal_dt}, got {data['optimal_dt']}"

    # Verify final total concentration
    expected_total = euler_sim(expected_optimal_dt)
    assert math.isclose(data["final_total_concentration"], expected_total, rel_tol=1e-2), \
        f"Expected final_total_concentration around {expected_total}, got {data['final_total_concentration']}"

    # Verify TV distance
    # P = 1/3 for each
    # Q = 1000: 0.35, 999: 0.35, 998: 0.30
    tv_expected = 0.5 * (abs(1/3 - 0.35) + abs(1/3 - 0.35) + abs(1/3 - 0.30))
    tv_rounded = round(tv_expected, 4)

    assert math.isclose(data["tv_distance"], tv_rounded, abs_tol=0.0005), \
        f"Expected tv_distance around {tv_rounded}, got {data['tv_distance']}"


def make_random_fixture():
    rng = secrets.SystemRandom()
    primer_count = rng.choice([2, 4, 5])
    primer_len = 18

    while True:
        template = "".join(rng.choice("ACGT") for _ in range(257))
        candidates = []
        for pos in range(0, len(template) - primer_len + 1):
            primer = template[pos:pos + primer_len]
            if template.count(primer) == 1:
                candidates.append(pos)
        if len(candidates) >= primer_count:
            positions = rng.sample(candidates, primer_count)
            primers = [template[p:p + primer_len] for p in positions]
            if len(set(primers)) == primer_count:
                break

    lengths = [len(template) - p for p in positions]
    support = lengths + [len(template) + 17]
    weights = [rng.uniform(0.2, 2.0) for _ in support]
    weight_total = sum(weights)
    q = {str(length): weight / weight_total for length, weight in zip(support, weights)}
    return template, primers, lengths, q


def test_application_recomputes_randomized_fixture():
    original_files = {
        TEMPLATE: TEMPLATE.read_bytes(),
        PRIMERS: PRIMERS.read_bytes(),
        EXPERIMENTAL: EXPERIMENTAL.read_bytes(),
    }

    template, primers, expected_lengths, q_json = make_random_fixture()
    try:
        TEMPLATE.write_text(template + "\n")
        PRIMERS.write_text("\n".join(primers) + "\n")
        EXPERIMENTAL.write_text(json.dumps(q_json))
        run_submission()
        data = load_output()

        required_keys = {"optimal_dt", "amplicon_lengths", "final_total_concentration", "tv_distance"}
        missing = required_keys - set(data.keys())
        assert not missing, f"JSON is missing keys on randomized input: {missing}"
        assert sorted(data["amplicon_lengths"]) == sorted(expected_lengths), (
            f"Expected randomized amplicon lengths {sorted(expected_lengths)}, "
            f"got {sorted(data['amplicon_lengths'])}"
        )

        count = len(primers)
        dt = expected_optimal(count)
        assert math.isclose(data["optimal_dt"], dt, rel_tol=1e-9, abs_tol=1e-9), (
            f"Expected optimal_dt {dt} on randomized input, got {data['optimal_dt']}"
        )

        expected_total = round(euler_sim(dt, count), 4)
        assert math.isclose(data["final_total_concentration"], expected_total, abs_tol=0.00011), (
            f"Expected rounded final total {expected_total}, got {data['final_total_concentration']}"
        )

        p = {length: 1.0 / count for length in expected_lengths}
        q = {int(length): probability for length, probability in q_json.items()}
        union = set(p) | set(q)
        expected_tv = round(0.5 * sum(abs(p.get(x, 0.0) - q.get(x, 0.0)) for x in union), 4)
        assert math.isclose(data["tv_distance"], expected_tv, abs_tol=0.00011), (
            f"Expected randomized TV distance {expected_tv}, got {data['tv_distance']}"
        )
    finally:
        for path, contents in original_files.items():
            path.write_bytes(contents)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
