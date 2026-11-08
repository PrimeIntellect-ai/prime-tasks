#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import subprocess
import csv
import random
import shutil
import tempfile
import uuid
import pytest

FILTER_BIN = "/home/user/filter"

def test_filter_binary_exists():
    assert os.path.isfile(FILTER_BIN), f"Executable not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"File at {FILTER_BIN} is not executable"

def test_evil_corpus():
    evil_files = glob.glob("/corpus/evil/*.csv")
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed = []
    for evil_file in evil_files:
        out_file = f"/tmp/out_evil_{os.path.basename(evil_file)}"
        if os.path.exists(out_file):
            os.remove(out_file)

        result = subprocess.run([FILTER_BIN, evil_file, out_file], capture_output=True)
        if result.returncode != 1:
            bypassed.append((os.path.basename(evil_file), f"exit code {result.returncode}"))
        elif os.path.exists(out_file):
            bypassed.append((os.path.basename(evil_file), "output file was created"))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed}")

def test_clean_corpus():
    clean_files = glob.glob("/corpus/clean/*.csv")
    assert len(clean_files) > 0, "No clean corpus files found."

    modified = []
    for clean_file in clean_files:
        out_file = f"/tmp/out_clean_{os.path.basename(clean_file)}"
        if os.path.exists(out_file):
            os.remove(out_file)

        result = subprocess.run([FILTER_BIN, clean_file, out_file], capture_output=True)
        if result.returncode != 0:
            modified.append((os.path.basename(clean_file), f"exit code {result.returncode}"))
            continue

        if not os.path.isfile(out_file):
            modified.append((os.path.basename(clean_file), "output file not created"))
            continue

        with open(clean_file, 'r', encoding='utf-8') as f:
            in_rows = list(csv.reader(f))

        with open(out_file, 'r', encoding='utf-8') as f:
            out_rows = list(csv.reader(f))

        if len(in_rows) != len(out_rows):
            modified.append((os.path.basename(clean_file), f"row count mismatch: expected {len(in_rows)}, got {len(out_rows)}"))
            continue

        def sort_key(r):
            try:
                ts = int(r[2])
            except ValueError:
                ts = 0
            return (r[1], -ts)

        try:
            sorted_in_rows = sorted(in_rows, key=sort_key)
            if out_rows != sorted_in_rows:
                modified.append((os.path.basename(clean_file), "sorting incorrect or data modified"))
        except Exception as e:
            modified.append((os.path.basename(clean_file), f"error parsing rows: {e}"))

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/failed: {modified}")

def test_opaque_relabeled_inputs():
    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="csv_batch_")
    clean_payloads = [
        '{"msg":"plain text"}',
        '{"msg":"BMP \\u263A escape"}',
        '{"msg":"valid pair \\uD83D\\uDE00"}',
        '{"msg":"two pairs \\uD834\\uDD1E and \\uD83D\\uDE03"}',
    ]
    bad_payloads = [
        '{"msg":"isolated high \\uD83D"}',
        '{"msg":"isolated low \\uDC00"}',
        '{"msg":"high then BMP \\uD800\\u0041"}',
        '{"msg":"reversed \\uDE00\\uD83D"}',
        '{"msg":"text after high \\uDBFFxyz"}',
        '{"msg":"lowercase digits \\ud83d"}',
    ]

    cases = []
    try:
        # Every path is opaque and all clean and tainted cases share one directory.
        # Thus behavior cannot be selected from corpus labels or file names.
        for tainted, payloads in ((False, clean_payloads), (True, bad_payloads)):
            for payload in payloads:
                rows = []
                groups = ["zeta", "alpha", "middle", "alpha", "zeta", "beta", "middle"]
                timestamps = [17, 900, 42, 1200, 300, 42, 700]
                for i, (group, timestamp) in enumerate(zip(groups, timestamps)):
                    rows.append([
                        "req_" + uuid.uuid4().hex,
                        group,
                        str(timestamp),
                        rng.choice(clean_payloads),
                    ])
                if tainted:
                    rows[rng.randrange(len(rows))][3] = payload
                rng.shuffle(rows)

                input_path = os.path.join(workdir, uuid.uuid4().hex + ".csv")
                output_path = os.path.join(workdir, uuid.uuid4().hex + ".csv")
                with open(input_path, "w", newline="", encoding="utf-8") as f:
                    csv.writer(f).writerows(rows)
                cases.append((tainted, input_path, output_path, rows))

        rng.shuffle(cases)
        failures = []
        for tainted, input_path, output_path, rows in cases:
            assert not os.path.exists(output_path)
            result = subprocess.run(
                [FILTER_BIN, input_path, output_path],
                capture_output=True,
                timeout=15,
            )

            if tainted:
                if result.returncode != 1:
                    failures.append((os.path.basename(input_path), f"tainted input returned {result.returncode}"))
                if os.path.exists(output_path):
                    failures.append((os.path.basename(input_path), "tainted input created an output file"))
                continue

            if result.returncode != 0:
                failures.append((os.path.basename(input_path), f"clean input returned {result.returncode}"))
                continue
            if not os.path.isfile(output_path):
                failures.append((os.path.basename(input_path), "clean input did not create output"))
                continue

            with open(output_path, "r", newline="", encoding="utf-8") as f:
                actual = list(csv.reader(f))
            expected = sorted(rows, key=lambda row: (row[1], -int(row[2])))
            if actual != expected:
                failures.append((os.path.basename(input_path), "clean output was modified or incorrectly sorted"))

        if failures:
            pytest.fail(f"Opaque generated cases failed: {failures}")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
