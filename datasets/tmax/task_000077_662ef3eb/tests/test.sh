#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/filter"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
HEADER = "TransactionID,CustomerName,Department,Amount"


def run_filter(input_path, output_path, log_path):
    return subprocess.run(
        [EXECUTABLE, input_path, output_path, log_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_output_empty(path):
    assert not os.path.exists(path) or os.path.getsize(path) == 0, \
        f"Rejected input wrote data to output file {path}"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    assert evil_files, f"No CSV files found in {EVIL_DIR}"

    failures = []
    for f in evil_files:
        input_path = os.path.join(EVIL_DIR, f)
        with tempfile.NamedTemporaryFile(delete=False) as out_csv, \
             tempfile.NamedTemporaryFile(delete=False) as log_txt:
            out_path = out_csv.name
            log_path = log_txt.name

        try:
            result = run_filter(input_path, out_path, log_path)
            if result.returncode != 1:
                failures.append(f"{f} (exit code {result.returncode})")
            elif os.path.getsize(out_path) != 0:
                failures.append(f"{f} (wrote output while rejecting)")
        finally:
            if os.path.exists(out_path):
                os.remove(out_path)
            if os.path.exists(log_path):
                os.remove(log_path)

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files failed checks: {failures}")


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    assert clean_files, f"No CSV files found in {CLEAN_DIR}"

    failed_files = []
    for f in clean_files:
        input_path = os.path.join(CLEAN_DIR, f)
        with tempfile.NamedTemporaryFile(delete=False) as out_csv, \
             tempfile.NamedTemporaryFile(delete=False) as log_txt:
            out_path = out_csv.name
            log_path = log_txt.name

        try:
            result = run_filter(input_path, out_path, log_path)
            if result.returncode != 0:
                failed_files.append(f"{f} (exit code {result.returncode})")
                continue

            with open(input_path, 'r') as infile:
                in_lines = infile.read().splitlines()
            with open(out_path, 'r') as outfile:
                out_lines = outfile.read().splitlines()

            seen = set()
            expected_out = []
            expected_logs = []
            if in_lines:
                expected_out.append(in_lines[0])
                for line in in_lines[1:]:
                    if not line.strip():
                        continue
                    parts = line.split(',')
                    tid = parts[0]
                    if tid not in seen:
                        seen.add(tid)
                        expected_out.append(line)
                    else:
                        expected_logs.append(f"Duplicate Dropped: {tid}")

            if out_lines != expected_out:
                failed_files.append(f"{f} (output mismatch)")
                continue

            with open(log_path, 'r') as logfile:
                log_lines = logfile.read().splitlines()
            if log_lines != expected_logs:
                failed_files.append(f"{f} (log mismatch)")
        finally:
            if os.path.exists(out_path):
                os.remove(out_path)
            if os.path.exists(log_path):
                os.remove(log_path)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/failed: {failed_files}")


def test_generated_clean_input_deduplicates_and_normalizes():
    token = secrets.token_hex(8)
    tid1 = str(secrets.randbelow(800000000) + 100000000)
    tid2 = str(secrets.randbelow(800000000) + 100000000)
    while tid2 == tid1:
        tid2 = str(secrets.randbelow(800000000) + 100000000)
    tid3 = str(secrets.randbelow(800000000) + 100000000)
    while tid3 in {tid1, tid2}:
        tid3 = str(secrets.randbelow(800000000) + 100000000)

    first = f"{tid1},Customer{token},SALES,17.25"
    quoted = f'{tid2},"Doe, {token}",IT,0'
    third = f"{tid3},Person{token},HR,999.01"
    duplicate1 = f"{tid1},Changed{token},HR,1.00"
    duplicate2 = f"{tid2},Other{token},SALES,2.00"
    input_lines = [HEADER, first, quoted, third, duplicate1, duplicate2]
    expected_output = [HEADER, first, quoted, third]
    expected_log = [
        f"Duplicate Dropped: {tid1}",
        f"Duplicate Dropped: {tid2}",
    ]

    with tempfile.TemporaryDirectory(prefix=f"etl_{token}_") as work:
        input_path = os.path.join(work, f"input_{secrets.token_hex(6)}.csv")
        output_path = os.path.join(work, f"output_{secrets.token_hex(6)}.csv")
        log_path = os.path.join(work, f"log_{secrets.token_hex(6)}.txt")
        with open(input_path, "w", newline="") as f:
            f.write("\n".join(input_lines) + "\n")

        result = run_filter(input_path, output_path, log_path)
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(output_path), "Successful run did not create output"
        assert os.path.isfile(log_path), "Successful run did not create log"

        with open(output_path, "r") as f:
            assert f.read().splitlines() == expected_output
        with open(log_path, "r") as f:
            assert f.read().splitlines() == expected_log


def test_generated_invalid_inputs_are_rejected_without_output():
    token = secrets.token_hex(8)
    base_tid = secrets.randbelow(700000000) + 200000000
    valid_prefix = [
        f"{base_tid},Valid{token},SALES,12.50",
        f"{base_tid},Duplicate{token},IT,99.00",
    ]
    invalid_rows = [
        f"{base_tid + 1},Negative{token},HR,-{secrets.randbelow(9000) + 1}.25",
        f"{base_tid + 2},Dept{token},BAD{token},10.00",
        f"{base_tid + 3},Name<{token},IT,10.00",
        f"{base_tid + 4},Name>{token},SALES,10.00",
        f"{base_tid + 5},Number{token},HR,not_a_number_{token}",
        f'{base_tid + 6},"Quoted, <{token}",SALES,4.00',
    ]

    with tempfile.TemporaryDirectory(prefix=f"etl_invalid_{token}_") as work:
        for index, invalid_row in enumerate(invalid_rows):
            input_path = os.path.join(work, f"case_{index}_{secrets.token_hex(5)}.csv")
            output_path = os.path.join(work, f"out_{index}_{secrets.token_hex(5)}.csv")
            log_path = os.path.join(work, f"log_{index}_{secrets.token_hex(5)}.txt")
            with open(input_path, "w", newline="") as f:
                f.write("\n".join([HEADER] + valid_prefix + [invalid_row]) + "\n")

            result = run_filter(input_path, output_path, log_path)
            assert result.returncode == 1, \
                f"Invalid generated case {index} exited {result.returncode}: {result.stderr}"
            assert_output_empty(output_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
