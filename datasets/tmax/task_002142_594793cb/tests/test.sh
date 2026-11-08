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
import statistics
import subprocess
import tempfile
from pathlib import Path

import pytest

BINARY_PATH = "/home/user/artifact_filter/target/release/artifact_filter"
EVIL_DIR = "/app/corpora/evil/"
CLEAN_DIR = "/app/corpora/clean/"
ORACLE_PATH = Path("/app/bin/stat_oracle")


def test_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"Path {BINARY_PATH} is not a file"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled artifact_filter is not an ELF binary"


def sanitize(losses):
    valid = [float(x) for x in losses if x != "" and str(x).lower() != "nan"]
    assert valid
    median = statistics.median(valid)
    imputed = [median if x == "" or str(x).lower() == "nan" else float(x) for x in losses]
    mean = statistics.fmean(imputed)
    std = math.sqrt(sum((x - mean) ** 2 for x in imputed) / len(imputed))
    return [x for x in imputed if abs(x - mean) <= 3.0 * std]


def write_csv(path, losses):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["run_id", "loss", "note"])
        for i, loss in enumerate(losses):
            writer.writerow([f"r{i}", loss, f"n{i}"])


def install_spy(expected, source_path, score, log_path):
    script = f'''#!/usr/bin/env python3
import csv
import math
import os
import sys

expected = {expected!r}
source = {str(source_path)!r}
log_path = {str(log_path)!r}

if len(sys.argv) != 2:
    sys.exit(41)
cleaned = sys.argv[1]
if os.path.realpath(cleaned) == os.path.realpath(source):
    sys.exit(42)
if not os.path.isfile(cleaned):
    sys.exit(43)
try:
    with open(cleaned, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows or "loss" not in rows[0]:
        sys.exit(44)
    actual = [float(row["loss"]) for row in rows]
except Exception:
    sys.exit(45)
if len(actual) != len(expected):
    sys.exit(46)
if any((not math.isfinite(a)) or not math.isclose(a, e, rel_tol=1e-8, abs_tol=1e-8)
       for a, e in zip(actual, expected)):
    sys.exit(47)
with open(log_path, "a") as f:
    f.write("valid-cleaned-input\\n")
print({score!r})
'''
    ORACLE_PATH.write_text(script)
    ORACLE_PATH.chmod(0o755)


def run_and_check(path, expected_code, expected_text, log_path):
    result = subprocess.run([BINARY_PATH, str(path)], capture_output=True, text=True)
    assert result.returncode == expected_code, (
        f"Unexpected exit code {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_text, f"Unexpected stdout: {result.stdout!r}"
    assert log_path.exists(), "The oracle was not invoked with correctly cleaned data"
    assert "valid-cleaned-input" in log_path.read_text()


def test_pipeline_on_generated_inputs_and_oracle_integration():
    assert ORACLE_PATH.exists(), f"Oracle missing at {ORACLE_PATH}"
    original_oracle = ORACLE_PATH.read_bytes()
    original_mode = ORACLE_PATH.stat().st_mode

    rng = random.SystemRandom()
    work = Path(tempfile.mkdtemp(prefix="artifact-verifier-"))
    try:
        base = rng.uniform(1.25, 3.75)
        low_losses = [base + rng.uniform(-0.08, 0.08) for _ in range(30)]
        low_losses.extend(["", "NaN", base + 100.0 + rng.uniform(0, 10)])
        rng.shuffle(low_losses)
        low_path = work / f"sample_{rng.randrange(1 << 60):x}.csv"
        write_csv(low_path, low_losses)
        low_expected = sanitize(low_losses)
        assert len(low_expected) == len(low_losses) - 1
        assert max(low_expected) - min(low_expected) < 0.2

        # The same low-width artifact must change classification solely when the
        # oracle response crosses the specified threshold.
        high_score_log = work / "oracle_high.log"
        install_spy(low_expected, low_path, 0.91, high_score_log)
        run_and_check(low_path, 0, "CLEAN", high_score_log)

        low_score_log = work / "oracle_low.log"
        install_spy(low_expected, low_path, 0.41, low_score_log)
        run_and_check(low_path, 1, "EVIL", low_score_log)

        # This bimodal sample has no 3-sigma outliers, but its 95% bootstrap
        # mean interval is safely wider than 2.5.
        offset = rng.uniform(-3.0, 3.0)
        wide_losses = [offset] * 10 + [offset + 10.0] * 10
        rng.shuffle(wide_losses)
        wide_path = work / f"sample_{rng.randrange(1 << 60):x}.csv"
        write_csv(wide_path, wide_losses)
        wide_expected = sanitize(wide_losses)
        assert len(wide_expected) == 20

        wide_log = work / "oracle_wide.log"
        install_spy(wide_expected, wide_path, 0.95, wide_log)
        run_and_check(wide_path, 1, "EVIL", wide_log)
    finally:
        ORACLE_PATH.write_bytes(original_oracle)
        ORACLE_PATH.chmod(original_mode)
        shutil.rmtree(work, ignore_errors=True)


def test_adversarial_corpus_filtering():
    assert os.path.exists(EVIL_DIR) and os.path.isdir(EVIL_DIR), f"Evil corpus directory missing at {EVIL_DIR}"
    assert os.path.exists(CLEAN_DIR) and os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing at {CLEAN_DIR}"

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, f"No files found in {EVIL_DIR}"
    assert len(clean_files) > 0, f"No files found in {CLEAN_DIR}"

    evil_bypassed = []
    for evil_file in evil_files:
        res = subprocess.run([BINARY_PATH, evil_file], capture_output=True, text=True)
        if res.returncode != 1 or res.stdout.strip() != "EVIL":
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        res = subprocess.run([BINARY_PATH, clean_file], capture_output=True, text=True)
        if res.returncode != 0 or res.stdout.strip() != "CLEAN":
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}{'...' if len(evil_bypassed) > 5 else ''}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified[:5])}{'...' if len(clean_modified) > 5 else ''}")

    if errors:
        pytest.fail(" | ".join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
