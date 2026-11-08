#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import io
import os
import random
import secrets
import subprocess
import tempfile

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
BINARY_PATH = "/home/user/config_sanitizer/target/release/config_sanitizer"
ORACLE_PATH = "/app/telemetry_oracle"


def run_binary(path):
    return subprocess.run([BINARY_PATH, path], capture_output=True, timeout=10)


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Expected Rust binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Expected a compiled ELF binary"


def test_clean_corpus():
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    assert clean_files, "No clean corpus files found."

    failed_files = []
    for f in clean_files:
        proc = subprocess.run([BINARY_PATH, f], capture_output=True)
        if proc.returncode != 0:
            failed_files.append(os.path.basename(f))
            continue

        oracle_proc = subprocess.run([ORACLE_PATH], input=proc.stdout, capture_output=True)
        if oracle_proc.returncode != 0:
            failed_files.append(os.path.basename(f))
            continue

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/failed. Offending files: {failed_files}"


def test_evil_corpus():
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    assert evil_files, "No evil corpus files found."

    bypassed_files = []
    for f in evil_files:
        proc = subprocess.run([BINARY_PATH, f], capture_output=True)
        if proc.returncode != 1:
            bypassed_files.append(os.path.basename(f))

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {bypassed_files}"


def parse_processed_output(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError("Output is not UTF-8 CSV") from exc

    rows = list(csv.reader(io.StringIO(text)))
    if rows and rows[0] == ["epoch_bucketed", "config_key", "interpolated_value", "hash"]:
        rows = rows[1:]

    parsed = []
    for row in rows:
        assert len(row) == 4, f"Malformed output row: {row!r}"
        try:
            epoch = int(row[0])
            value = int(row[2])
        except ValueError as exc:
            raise AssertionError(f"Non-integer epoch or value in row: {row!r}") from exc
        parsed.append((epoch, row[1], value, row[3]))
    return parsed


def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def test_generated_processing_semantics():
    # Values, keys, hashes, row order, and timestamps are generated only after the
    # submission has finished, so path-based or fixed-output stubs cannot pass.
    base = random.randrange(1700000000, 1800000000)
    base -= base % 60
    suffix = secrets.token_hex(5)
    alpha = f"alpha.{suffix}"
    dedup = f"dedup.{suffix}"
    tail = f"tail.{suffix}"
    zeta = f"zeta.{suffix}"
    hashes = [secrets.token_hex(8) for _ in range(9)]

    rows = [
        [str(base + 8), dedup, "99", hashes[0]],
        [iso(base + 3), dedup, "12", hashes[0]],
        [str(base + 7), zeta, "100", hashes[1]],
        [iso(base + 17), zeta, "", hashes[2]],
        [str(base + 47), zeta, "301", hashes[3]],
        [iso(base + 16), alpha, "", hashes[4]],
        [str(base + 36), alpha, "80", hashes[5]],
        [iso(base + 11), tail, "44", hashes[6]],
        [str(base + 31), tail, "", hashes[7]],
    ]
    random.SystemRandom().shuffle(rows)

    expected = [
        (base, dedup, 12, hashes[0]),
        (base, zeta, 100, hashes[1]),
        (base + 10, alpha, 0, hashes[4]),
        (base + 10, tail, 44, hashes[6]),
        (base + 10, zeta, 150, hashes[2]),
        (base + 30, alpha, 80, hashes[5]),
        (base + 30, tail, 44, hashes[7]),
        (base + 40, zeta, 301, hashes[3]),
    ]

    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, secrets.token_hex(8) + ".csv")
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp_raw", "config_key", "value_raw", "hash"])
            writer.writerows(rows)

        proc = run_binary(path)

    assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
    actual = parse_processed_output(proc.stdout)
    assert actual == expected, f"Incorrect processed rows.\nExpected: {expected!r}\nActual:   {actual!r}"


def test_generated_adversarial_inputs_exit_one_without_output():
    base = random.randrange(1700000000, 1800000000)
    suffix = secrets.token_hex(5)
    cases = [
        (f"safe.{suffix}", str(10001 + random.randrange(1000))),
        (f"safe.{suffix}", str(-1 - random.randrange(1000))),
        (f"../secret.{suffix}", "100"),
        (f"bad${suffix}", "100"),
        (f"bad|{suffix}", "100"),
        (f"bad>{suffix}", "100"),
        (f"bad<{suffix}", "100"),
    ]

    with tempfile.TemporaryDirectory() as td:
        for index, (key, value) in enumerate(cases):
            path = os.path.join(td, f"case_{index}_{secrets.token_hex(4)}.csv")
            with open(path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["timestamp_raw", "config_key", "value_raw", "hash"])
                writer.writerow([str(base + index), key, value, secrets.token_hex(8)])
            proc = run_binary(path)
            assert proc.returncode == 1, f"Adversarial case {key!r}, {value!r} returned {proc.returncode}"
            assert proc.stdout == b"", f"Adversarial case emitted output: {proc.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
