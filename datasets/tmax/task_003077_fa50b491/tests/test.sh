#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path


def run_validator(path):
    return subprocess.run(
        ["/home/user/validate.sh", str(path)],
        capture_output=True,
        timeout=10,
    )


def expected_status(path):
    sums = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            timestamp, _sensor_id, value = line.rstrip("\n").split(",")
            bucket = int(timestamp) // 300
            sums[bucket] = sums.get(bucket, Decimal("0")) + Decimal(value)
    return 1 if any(total > Decimal("350") for total in sums.values()) else 0


def partition(total, count, rng):
    cuts = sorted([0, total] + [rng.randrange(total + 1) for _ in range(count - 1)])
    return [cuts[i + 1] - cuts[i] for i in range(count)]


def make_random_csv(path, should_fail, rng):
    rows = []
    bucket_count = rng.randrange(2, 7)
    bad_bucket = rng.randrange(bucket_count) if should_fail else None
    base_bucket = rng.randrange(10000, 5000000)

    for bucket_offset in range(bucket_count):
        row_count = rng.randrange(1, 7)
        if bucket_offset == bad_bucket:
            total_tenths = rng.randrange(3501, 7001)
        else:
            total_tenths = rng.randrange(0, 3501)

        for row_number, value_tenths in enumerate(partition(total_tenths, row_count, rng)):
            timestamp = (base_bucket + bucket_offset) * 300 + rng.randrange(300)
            sensor = f"sensor_{rng.randrange(1000000)}_{row_number}"
            rows.append(f"{timestamp},{sensor},{value_tenths // 10}.{value_tenths % 10}\n")

    rng.shuffle(rows)
    path.write_text("".join(rows), encoding="utf-8")


def test_validate_script_exists_and_executable():
    script_path = Path("/home/user/validate.sh")
    assert script_path.exists(), f"Script not found at {script_path}"
    assert script_path.is_file(), f"{script_path} is not a file"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_adversarial_corpus():
    script_path = "/home/user/validate.sh"

    evil_dir = Path("/app/evil")
    clean_dir = Path("/app/clean")

    evil_files = list(evil_dir.glob("*.csv"))
    clean_files = list(clean_dir.glob("*.csv"))

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    bypassed_evil = []
    for evil_file in evil_files:
        result = subprocess.run([script_path, str(evil_file)], capture_output=True)
        if result.returncode != 1:
            bypassed_evil.append(evil_file.name)

    modified_clean = []
    for clean_file in clean_files:
        result = subprocess.run([script_path, str(clean_file)], capture_output=True)
        if result.returncode != 0:
            modified_clean.append(clean_file.name)

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")

    assert not errors, " | ".join(errors)


def test_unseen_randomized_csvs_with_independent_bucket_sums():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="csv-validation-") as temp_dir:
        root = Path(temp_dir)
        cases = []

        # Explicitly exercise equality, cross-sensor aggregation, and epoch boundaries.
        edge_contents = [
            "299,a,175\n0,b,175\n300,c,350\n",
            "0,a,175\n299,b,175.1\n300,c,1\n",
            "599,a,350\n600,b,350\n",
            "301,a,200\n599,b,151\n",
        ]
        for content in edge_contents:
            path = root / f"{secrets.token_hex(16)}.csv"
            path.write_text(content, encoding="utf-8")
            cases.append(path)

        desired_results = [0, 1] * 12
        rng.shuffle(desired_results)
        for should_fail in desired_results:
            path = root / f"{secrets.token_hex(16)}.csv"
            make_random_csv(path, bool(should_fail), rng)
            assert expected_status(path) == should_fail
            cases.append(path)

        rng.shuffle(cases)
        failures = []
        for path in cases:
            expected = expected_status(path)
            result = run_validator(path)
            if result.returncode != expected:
                failures.append(
                    f"{path.name}: expected exit {expected}, got {result.returncode}"
                )

        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
