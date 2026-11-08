#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import pytest

CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
SANITIZER_BIN = "/home/user/sanitizer"
SANITIZER_SOURCE = "/home/user/sanitizer.cpp"
LIB_DIR = "/app/vendored/libcsv_etl"
LIB_PATH = os.path.join(LIB_DIR, "libcsv_etl.a")
HEADER_PATH = os.path.join(LIB_DIR, "csv_etl.h")
MAKEFILE_PATH = os.path.join(LIB_DIR, "Makefile")
HEADER = "timestamp,tx_id,card_number,amount,status"


def process_csv(input_lines):
    if not input_lines:
        return ""
    header = input_lines[0].strip()
    output = [header]
    seen_tx_ids = set()
    rolling_window = []

    for line in input_lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) != 5:
            continue
        timestamp, tx_id, card_number, amount_str, status = parts

        if status not in ("SUCCESS", "PENDING"):
            continue
        if tx_id in seen_tx_ids:
            continue

        try:
            amount = float(amount_str)
        except ValueError:
            continue

        test_window = rolling_window + [amount]
        if len(test_window) > 3:
            test_window = test_window[-3:]
        if sum(test_window) / len(test_window) > 5000.0:
            continue

        seen_tx_ids.add(tx_id)
        rolling_window = test_window
        if len(card_number) == 16:
            masked_card = "*" * 12 + card_number[-4:]
        else:
            masked_card = card_number
        output.append(f"{timestamp},{tx_id},{masked_card},{amount_str},{status}")

    return "\n".join(output) + "\n"


def run_sanitizer(input_data):
    return subprocess.run(
        [SANITIZER_BIN], input=input_data, text=True, capture_output=True, timeout=5
    )


def assert_sanitized(input_data):
    expected = process_csv(input_data.strip().split("\n"))
    proc = run_sanitizer(input_data)
    assert proc.returncode == 0, f"sanitizer exited with {proc.returncode}: {proc.stderr}"
    assert proc.stdout.strip() == expected.strip(), (
        f"unexpected sanitizer output\nEXPECTED:\n{expected}\nACTUAL:\n{proc.stdout}"
    )


def test_makefile_fixed_and_library_builds():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile missing at {MAKEFILE_PATH}"
    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()
    assert "-DSIMULATE_RETRY_DUPLICATION=1" not in content, \
        "The perturbation in the Makefile was not removed."

    build = subprocess.run(
        ["make", "clean", "all"], cwd=LIB_DIR, text=True,
        capture_output=True, timeout=30
    )
    assert build.returncode == 0, f"vendored library failed to build: {build.stdout}\n{build.stderr}"
    assert os.path.isfile(LIB_PATH), f"library missing at {LIB_PATH}"
    assert os.path.getsize(LIB_PATH) > 0, "libcsv_etl.a is empty"
    assert os.path.isfile(HEADER_PATH), f"header missing at {HEADER_PATH}"

    archive = subprocess.run(["ar", "t", LIB_PATH], text=True, capture_output=True)
    assert archive.returncode == 0 and "csv_etl.o" in archive.stdout, \
        "libcsv_etl.a is not a valid archive containing csv_etl.o"

    probe_source = "/tmp/csv_etl_probe.cpp"
    probe_binary = "/tmp/csv_etl_probe"
    with open(probe_source, "w") as f:
        f.write(r'''#include "csv_etl.h"
#include <iostream>
int main() {
    auto fields = csv_etl::split("alpha,beta,gamma");
    if (fields.size() != 3) return 2;
    std::cout << fields[0] << "|" << fields[1] << "|" << fields[2];
    return 0;
}
''')
    compile_probe = subprocess.run(
        ["g++", "-std=c++17", "-I", LIB_DIR, probe_source, LIB_PATH, "-o", probe_binary],
        text=True, capture_output=True, timeout=30
    )
    assert compile_probe.returncode == 0, \
        f"could not link against libcsv_etl.a: {compile_probe.stderr}"
    probe = subprocess.run([probe_binary], text=True, capture_output=True, timeout=5)
    assert probe.returncode == 0 and probe.stdout == "alpha|beta|gamma", \
        "the built csv_etl library does not provide a working split implementation"


def test_sanitizer_binary_exists():
    assert os.path.isfile(SANITIZER_SOURCE), f"C++ source not found at {SANITIZER_SOURCE}"
    assert os.path.getsize(SANITIZER_SOURCE) > 0, "sanitizer.cpp is empty"
    assert os.path.isfile(SANITIZER_BIN), f"Sanitizer binary not found at {SANITIZER_BIN}"
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary at {SANITIZER_BIN} is not executable"
    with open(SANITIZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer is not a compiled executable"


def test_clean_corpus():
    failed_files = []
    total = 0
    for fname in sorted(os.listdir(CLEAN_DIR)):
        if not fname.endswith(".csv"):
            continue
        total += 1
        fpath = os.path.join(CLEAN_DIR, fname)
        with open(fpath, "r") as f:
            input_data = f.read()
        expected_output = process_csv(input_data.strip().split("\n"))
        proc = run_sanitizer(input_data)
        if proc.returncode != 0 or proc.stdout.strip() != expected_output.strip():
            failed_files.append(fname)
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total} clean modified: {', '.join(failed_files)}")


def test_evil_corpus():
    failed_files = []
    total = 0
    for fname in sorted(os.listdir(EVIL_DIR)):
        if not fname.endswith(".csv"):
            continue
        total += 1
        fpath = os.path.join(EVIL_DIR, fname)
        with open(fpath, "r") as f:
            input_data = f.read()
        expected_output = process_csv(input_data.strip().split("\n"))
        proc = run_sanitizer(input_data)
        if proc.returncode != 0 or proc.stdout.strip() != expected_output.strip():
            failed_files.append(fname)
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total} evil bypassed: {', '.join(failed_files)}")


def test_all_sanitization_rules_with_nonempty_input():
    suffix = secrets.token_hex(4)
    rows = [
        HEADER,
        f"2026-01-01T00:00:00Z,first-{suffix},1234567890123456,100.00,SUCCESS",
        f"2026-01-01T00:00:01Z,first-{suffix},9999888877776666,1.00,PENDING",
        f"2026-01-01T00:00:02Z,bad-{suffix},1111222233334444,50.00,FAILED",
        f"2026-01-01T00:00:03Z,high-{suffix},2222333344445555,12000.00,SUCCESS",
        f"2026-01-01T00:00:04Z,second-{suffix},3333444455556666,200.00,PENDING",
        f"2026-01-01T00:00:05Z,invalid-{suffix},4444555566667777,not-a-number,SUCCESS",
        f"2026-01-01T00:00:06Z,invalid-{suffix},4444555566667777,300.00,SUCCESS",
        f"2026-01-01T00:00:07Z,edge-drop-{suffix},5555666677778888,14501.00,SUCCESS",
        f"2026-01-01T00:00:08Z,edge-keep-{suffix},6666777788889999,14500.00,PENDING",
    ]
    assert_sanitized("\n".join(rows) + "\n")


def test_randomized_nonempty_stream():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    rows = [HEADER]
    prior_ids = []
    statuses = ["SUCCESS", "PENDING", "FAILED", "success", "RETRY"]

    for i in range(120):
        if prior_ids and rng.random() < 0.22:
            tx_id = rng.choice(prior_ids)
        else:
            tx_id = f"tx-{secrets.token_hex(6)}-{i}"
            prior_ids.append(tx_id)
        card = "".join(str(rng.randrange(10)) for _ in range(16))
        status = rng.choice(statuses)
        if rng.random() < 0.08:
            amount = "invalid"
        else:
            amount = f"{rng.randrange(0, 1800000) / 100:.2f}"
        rows.append(f"2026-02-01T12:{i % 60:02d}:00Z,{tx_id},{card},{amount},{status}")

    assert_sanitized("\n".join(rows) + "\n")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
