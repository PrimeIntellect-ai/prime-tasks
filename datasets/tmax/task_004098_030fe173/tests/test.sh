#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import uuid

import pytest

CLEAN_DIR = "/app/corpora/clean/"
EVIL_DIR = "/app/corpora/evil/"
GO_SCRIPT = "/home/user/detect_anomaly.go"


def test_go_script_exists():
    assert os.path.isfile(GO_SCRIPT), f"Go script not found at {GO_SCRIPT}"


def test_adversarial_corpus():
    assert os.path.isfile(GO_SCRIPT), f"Go script not found at {GO_SCRIPT}"

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.tsv')]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.tsv')]

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    failed_clean = []
    for cf in clean_files:
        res = subprocess.run(["go", "run", GO_SCRIPT, cf], capture_output=True)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(cf))

    failed_evil = []
    for ef in evil_files:
        res = subprocess.run(["go", "run", GO_SCRIPT, ef], capture_output=True)
        if res.returncode != 1:
            failed_evil.append(os.path.basename(ef))

    errors = []
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def pearson(xs, ys):
    mx = math.fsum(xs) / len(xs)
    my = math.fsum(ys) / len(ys)
    covariance = math.fsum((x - mx) * (y - my) for x, y in zip(xs, ys))
    xnorm = math.fsum((x - mx) ** 2 for x in xs)
    ynorm = math.fsum((y - my) ** 2 for y in ys)
    return covariance / math.sqrt(xnorm * ynorm)


def test_generated_hidden_datasets():
    assert os.path.isfile(GO_SCRIPT), f"Go script not found at {GO_SCRIPT}"

    rng = random.SystemRandom()
    cases = []

    # Generate fresh datasets with varied row counts, values, noise, and row order.
    # Their expected results are calculated from their actual contents.
    for desired_sign in (1, -1):
        made = 0
        while made < 10:
            count = rng.randint(7, 31)
            xs = rng.sample(range(100, 50001), count)
            factor = rng.randint(2, 25)
            if desired_sign > 0:
                ys = [10000 + factor * x + rng.randint(-3000, 3000) * factor for x in xs]
            else:
                ys = [factor * 60000 - factor * x + rng.randint(-3000, 3000) * factor for x in xs]
            corr = pearson(xs, ys)
            if corr * desired_sign <= 0.15:
                continue
            rows = list(zip(xs, ys))
            rng.shuffle(rows)
            cases.append((rows, 1 if corr < 0 else 0, corr))
            made += 1

    # A non-linear dataset with exactly zero covariance must be accepted because
    # the rule is strictly less than zero.
    zero_x = [997, 999, 1001, 1003]
    zero_y = [2001, 1999, 1999, 2001]
    zero_corr = pearson(zero_x, zero_y)
    assert zero_corr == 0.0
    cases.append((list(zip(zero_x, zero_y)), 0, zero_corr))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="correlation-check-") as workdir:
        binary = os.path.join(workdir, "submitted-tool")
        build = subprocess.run(
            ["go", "build", "-o", binary, GO_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"Go source did not build: {build.stderr}"
        assert os.path.isfile(binary), "Go build did not produce an executable"

        failures = []
        for index, (rows, expected, corr) in enumerate(cases):
            path = os.path.join(workdir, f"dataset-{uuid.uuid4().hex}.tsv")
            with open(path, "w", encoding="utf-8") as stream:
                stream.write("shard_id\ttoken_count\tlatency_ms\n")
                for shard_id, (token_count, latency_ms) in enumerate(rows, 1):
                    stream.write(f"{shard_id}\t{token_count}\t{latency_ms}\n")

            result = subprocess.run([binary, path], capture_output=True, timeout=10)
            if result.returncode != expected:
                failures.append(
                    f"case {index}: correlation={corr:.12g}, expected exit {expected}, got {result.returncode}"
                )

        if failures:
            pytest.fail("Generated dataset failures: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
