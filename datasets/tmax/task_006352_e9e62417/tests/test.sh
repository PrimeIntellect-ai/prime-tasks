#!/bin/bash
set -e
mkdir -p /logs/verifier

DATASET=/home/user/data/logs.jsonl
BACKUP=/tmp/logs.jsonl.verifier-backup
cp "$DATASET" "$BACKUP"
restore_dataset() {
    cp "$BACKUP" "$DATASET"
}
trap restore_dataset EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess

PROJECT = "/home/user/etl_tester"
DATASET = "/home/user/data/logs.jsonl"
OUTPUT = os.path.join(PROJECT, "output.json")


def run_project():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["cargo", "run"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"cargo run failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."
    try:
        with open(OUTPUT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError("output.json is not valid JSON.") from exc

    assert "mean_frequency" in data, "Key 'mean_frequency' is missing from output.json."
    assert "standard_error" in data, "Key 'standard_error' is missing from output.json."
    mean = data["mean_frequency"]
    se = data["standard_error"]
    assert isinstance(mean, (int, float)) and not isinstance(mean, bool), "mean_frequency must be a number."
    assert isinstance(se, (int, float)) and not isinstance(se, bool), "standard_error must be a number."
    assert math.isfinite(mean), "mean_frequency must be finite."
    assert math.isfinite(se), "standard_error must be finite."
    return data


def write_records(texts):
    with open(DATASET, "w") as f:
        for i, text in enumerate(texts):
            f.write(json.dumps({"id": i, "text": text}) + "\n")


def test_complete_submission():
    # Preserve the original project, execution, format, and broad-result checks.
    assert os.path.isdir(PROJECT), "Rust project directory /home/user/etl_tester does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing in /home/user/etl_tester."

    original = run_project()
    assert 0.04 < original["mean_frequency"] < 0.08, (
        f"Mean frequency {original['mean_frequency']} is out of expected bounds (0.04 - 0.08)."
    )
    assert 0.001 < original["standard_error"] < 0.015, (
        f"Standard error {original['standard_error']} is out of expected bounds (0.001 - 0.015)."
    )

    # Check that the requested seeded bootstrap machinery is present in Rust code.
    rust_sources = []
    for root, _, files in os.walk(PROJECT):
        if os.sep + "target" + os.sep in root + os.sep:
            continue
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r", errors="replace") as f:
                    rust_sources.append(f.read())
    source = "\n".join(rust_sources)
    assert source, "No Rust source files were found."
    assert "StdRng" in source, "The implementation must use rand::rngs::StdRng."
    assert "seed_from_u64" in source and re.search(r"\b42\b", source), "StdRng must be seeded with 42."
    assert re.search(r"\b(?:1000|1_000)\b", source), "The implementation must perform B = 1000 iterations."
    assert "critical" in source.lower(), "The target token 'critical' is missing from the implementation."

    system_random = random.SystemRandom()

    # Hidden homogeneous data gives an exact answer independent of RNG draws and
    # exercises lowercase conversion, punctuation removal, and empty-token filtering.
    n = system_random.randint(13, 29)
    token_count = system_random.randint(8, 17)
    critical_count = system_random.randint(1, token_count - 1)
    tokens = []
    for i in range(critical_count):
        tokens.append("CrItIcAl!!!" if i % 2 == 0 else "critical,.")
    for i in range(token_count - critical_count):
        tokens.append(f"FiLlEr-{i}?")
    text = "  ".join(tokens[:1] + ["###"] + tokens[1:])
    write_records([text] * n)

    homogeneous = run_project()
    expected = critical_count / token_count
    assert abs(homogeneous["mean_frequency"] - expected) <= 1e-12, (
        f"Hidden tokenization case expected mean {expected}, got {homogeneous['mean_frequency']}."
    )
    assert abs(homogeneous["standard_error"]) <= 1e-12, (
        "Identical records must produce zero bootstrap standard deviation."
    )

    # Hidden variable records exercise record-level resampling. Every record has
    # the same token denominator, so the bootstrap distribution has a derived
    # population mean and standard deviation without trusting submitted output.
    n = system_random.randint(67, 97)
    token_count = system_random.randint(10, 18)
    while True:
        counts = [system_random.randint(0, token_count) for _ in range(n)]
        if len(set(counts)) >= 4:
            break

    texts = []
    for row, count in enumerate(counts):
        toks = ["CRITICAL!!!" if j % 2 == 0 else "critical," for j in range(count)]
        toks += [f"word{row}x{j}." for j in range(token_count - count)]
        toks.insert(system_random.randint(0, len(toks)), "@@@")
        texts.append(" \t ".join(toks))
    write_records(texts)

    variable = run_project()
    repeat = run_project()
    assert variable == repeat, "Repeated runs on the same data are not deterministic; verify the fixed RNG seed."

    record_frequencies = [count / token_count for count in counts]
    expected_mean = sum(record_frequencies) / n
    population_variance = sum((x - expected_mean) ** 2 for x in record_frequencies) / n
    expected_bootstrap_sd = math.sqrt(population_variance / n)

    # The submitted values are empirical moments from 1000 deterministic draws.
    mean_tolerance = max(0.003, 7.0 * expected_bootstrap_sd / math.sqrt(1000))
    assert abs(variable["mean_frequency"] - expected_mean) <= mean_tolerance, (
        f"Bootstrap mean {variable['mean_frequency']} disagrees with the derived population mean "
        f"{expected_mean} (tolerance {mean_tolerance})."
    )
    assert abs(variable["standard_error"] - expected_bootstrap_sd) <= max(0.001, 0.12 * expected_bootstrap_sd), (
        f"Bootstrap standard deviation {variable['standard_error']} disagrees with the derived expected "
        f"scale {expected_bootstrap_sd}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
