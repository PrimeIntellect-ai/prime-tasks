#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import tempfile
import uuid

import pytest

ROOT = '/home/user/forensics'
SOURCE = os.path.join(ROOT, 'analyzer.cpp')
ANALYZER = os.path.join(ROOT, 'analyzer')
BATCH = os.path.join(ROOT, 'data', 'batch_42.csv')
RESULTS = os.path.join(ROOT, 'results.csv')


def run_checked(command, timeout, cwd=None):
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out after {timeout}s: {' '.join(command)}")
    assert result.returncode == 0, (
        f"Command failed with exit code {result.returncode}: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Expected executable {path} was not created"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{path} is not a compiled ELF executable"


def verify_output(output_file, rows):
    with open(output_file, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None
        assert 'ID' in reader.fieldnames and 'RiskScore' in reader.fieldnames
        actual_rows = list(reader)

    assert len(actual_rows) == len(rows), (
        f"Expected {len(rows)} output rows, found {len(actual_rows)}"
    )
    actual = {}
    for row in actual_rows:
        assert row['ID'] not in actual, f"Duplicate output ID {row['ID']}"
        actual[row['ID']] = float(row['RiskScore'])

    for event_id, base, events, window, _payload in rows:
        assert event_id in actual, f"Missing event {event_id}"
        expected = round((base * 0.6) + ((float(events) / float(window)) * 0.4), 2)
        assert abs(actual[event_id] - expected) <= 0.015, (
            f"Score for {event_id} is incorrect: expected {expected:.2f}, "
            f"got {actual[event_id]:.2f}"
        )


def test_analyzer_cpp_builds_and_both_binaries_process_unseen_input():
    assert os.path.isfile(SOURCE), 'analyzer.cpp is missing'
    assert os.path.isfile(os.path.join(ROOT, 'Makefile')), 'Makefile is missing'

    rng = random.SystemRandom()
    rows = []
    for i in range(7):
        window = rng.randint(4, 18)
        events = window * rng.randint(3, 35) + max(1, window // 2)
        base = rng.randint(11, 97)
        payload = 'Contains_0x00_Byte' if i == 3 else f'MAL_payload_{i}'
        rows.append((f'CHECK-{uuid.uuid4().hex}', base, events, window, payload))

    with tempfile.TemporaryDirectory(prefix='analyzer-verifier-') as td:
        input_file = os.path.join(td, 'unseen.csv')
        source_output = os.path.join(td, 'source-results.csv')
        make_output = os.path.join(td, 'make-results.csv')
        source_binary = os.path.join(td, 'source-analyzer')

        with open(input_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['ID', 'BaseScore', 'EventCount', 'TimeWindow', 'Payload'])
            writer.writerows(rows)

        # Compile analyzer.cpp directly so a fabricated results.csv or unrelated
        # Makefile-produced program cannot hide unfixed source code.
        run_checked(
            ['g++', '-O2', '-Wall', SOURCE, '-o', source_binary],
            timeout=20,
            cwd=ROOT,
        )
        assert_elf_executable(source_binary)
        run_checked([source_binary, input_file, source_output], timeout=5, cwd=ROOT)
        verify_output(source_output, rows)

        # Require the requested make build to succeed from a missing artifact.
        if os.path.lexists(ANALYZER):
            os.remove(ANALYZER)
        run_checked(['make'], timeout=20, cwd=ROOT)
        assert_elf_executable(ANALYZER)
        run_checked([ANALYZER, input_file, make_output], timeout=5, cwd=ROOT)
        verify_output(make_output, rows)

    # Generate the required final artifact with the make-built service.
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)
    run_checked([ANALYZER, BATCH, RESULTS], timeout=5, cwd=ROOT)


def test_results_file_exists():
    assert os.path.isfile('/home/user/forensics/results.csv'), "The output file /home/user/forensics/results.csv is missing. Did you run the compiled analyzer?"


def test_results_content_and_accuracy():
    input_file = '/home/user/forensics/data/batch_42.csv'
    output_file = '/home/user/forensics/results.csv'

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_scores = {}
    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            id_val = row['ID']
            base = int(row['BaseScore'])
            events = int(row['EventCount'])
            time_w = int(row['TimeWindow'])

            # Compute expected score using floating point division
            score = (base * 0.6) + ((float(events) / float(time_w)) * 0.4)
            expected_scores[id_val] = score

    actual_scores = {}
    with open(output_file, 'r') as f:
        reader = csv.DictReader(f)
        assert 'ID' in reader.fieldnames and 'RiskScore' in reader.fieldnames, "results.csv must have headers 'ID' and 'RiskScore'"
        for row in reader:
            actual_scores[row['ID']] = float(row['RiskScore'])

    assert len(actual_scores) == len(expected_scores), f"Expected {len(expected_scores)} rows in results.csv, but found {len(actual_scores)}. The service might have crashed or hung."

    for id_val, expected_score in expected_scores.items():
        assert id_val in actual_scores, f"Event {id_val} is missing from results.csv. The parser might have stopped prematurely."
        actual_score = actual_scores[id_val]

        # Format expected score to 2 decimal places as C++ would with std::fixed and std::setprecision(2)
        expected_rounded = round(expected_score, 2)

        assert abs(actual_score - expected_rounded) <= 0.015, (
            f"Score for {id_val} is incorrect. "
            f"Expected ~{expected_rounded:.2f}, got {actual_score:.2f}. "
            "Check if the integer division bug was properly fixed."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
