#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from collections import Counter
from pathlib import Path

import pytest

BASE = Path('/home/user/log_pipeline')
SCRIPT = BASE / 'process_logs.sh'
INPUT = BASE / 'data/input.csv'
OUTPUT = BASE / 'output.txt'
SUMMARY = BASE / 'summary.txt'
AGGREGATOR = BASE / 'aggregator'
CANONICAL = b'ID,User,Bytes\r\n1,alice,1500000000\r\n2,bob,800000000\r\n3,charlie,100000\r\n'


def run_pipeline(timeout=40):
    result = subprocess.run(
        [str(SCRIPT)], cwd=str(BASE), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f'process_logs.sh failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def parse_summary(path=SUMMARY):
    content = path.read_text()
    count_match = re.search(r'^Records Processed:\s*(\d+)\s*$', content, re.MULTILINE)
    total_match = re.search(r'^Total Bytes:\s*(\d+)\s*$', content, re.MULTILINE)
    assert count_match, f'Missing valid Records Processed line in summary:\n{content}'
    assert total_match, f'Missing valid Total Bytes line in summary:\n{content}'
    return int(count_match.group(1)), int(total_match.group(1))


@pytest.fixture(scope='module', autouse=True)
def rebuild_and_run_real_pipeline():
    assert SCRIPT.is_file(), f'{SCRIPT} does not exist'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable'
    assert (BASE / 'aggregator.c').is_file(), 'aggregator.c does not exist'
    assert (BASE / 'Makefile').is_file(), 'Makefile does not exist'

    INPUT.write_bytes(CANONICAL)
    if AGGREGATOR.exists() or AGGREGATOR.is_symlink():
        AGGREGATOR.unlink()

    build = subprocess.run(
        ['make'], cwd=str(BASE), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, (
        f'make failed with exit code {build.returncode}\n'
        f'stdout:\n{build.stdout}\nstderr:\n{build.stderr}'
    )
    assert AGGREGATOR.is_file(), 'make did not rebuild aggregator'
    assert os.access(AGGREGATOR, os.X_OK), 'rebuilt aggregator is not executable'
    assert AGGREGATOR.read_bytes()[:4] == b'\x7fELF', 'aggregator is not a compiled ELF utility'

    run_pipeline()
    yield
    INPUT.write_bytes(CANONICAL)


def test_summary_txt_correctness():
    summary_file = "/home/user/log_pipeline/summary.txt"
    assert os.path.isfile(summary_file), f"{summary_file} does not exist. Did the pipeline run successfully?"

    with open(summary_file, "r") as f:
        content = f.read()

    assert "Records Processed: 3" in content, "summary.txt does not indicate that 3 records were processed. Concurrency or parsing issues may remain."
    assert "Total Bytes: 2300100000" in content, "summary.txt does not show the correct Total Bytes (2300100000). The C program may still have integer overflow, or DOS newlines were not handled properly."


def test_resolution_report_txt_correctness():
    report_file = "/home/user/log_pipeline/resolution_report.txt"
    assert os.path.isfile(report_file), f"{report_file} does not exist. You must create the resolution report."

    with open(report_file, "r") as f:
        first_line = f.readline().strip()

    assert first_line == "2300100000", f"The first line of resolution_report.txt must be strictly '2300100000', but found '{first_line}'."


def test_output_txt_no_race_conditions():
    output_file = "/home/user/log_pipeline/output.txt"
    assert os.path.isfile(output_file), f"{output_file} does not exist."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"output.txt should contain exactly 3 valid lines, found {len(lines)}. Race conditions or parsing errors might be dropping or duplicating data."

    for i, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == 3, f"Line {i+1} in output.txt is malformed due to interleaved writes (race condition not fixed): '{line}'"
        assert not parts[-1].endswith("\r"), f"Line {i+1} in output.txt still contains DOS carriage returns: '{line}'"

    raw = Path(output_file).read_bytes()
    assert b'\r' not in raw, 'output.txt still contains carriage-return characters'
    actual = Counter(tuple(row) for row in csv.reader(raw.decode().splitlines()))
    expected = Counter([
        ('1', 'alice', '1500000000'),
        ('2', 'bob', '800000000'),
        ('3', 'charlie', '100000'),
    ])
    assert actual == expected, f'output.txt records are incorrect: {actual}'


def test_script_retains_background_concurrency_and_waits():
    text = SCRIPT.read_text()
    code_lines = []
    for line in text.splitlines():
        if line.startswith('#!'):
            continue
        code_lines.append(line.split('#', 1)[0])
    code = '\n'.join(code_lines)
    assert re.search(r'(^|[^&])&([^&]|$)', code), 'process_logs.sh no longer starts background jobs with &'
    assert re.search(r'(^|[;\s])wait([;\s]|$)', code), 'process_logs.sh does not wait for its background jobs'


def test_rebuilt_aggregator_handles_totals_beyond_32_bit():
    sample = b'1,one,2147483647\n2,two,2147483647\n3,three,2147483647\n'
    result = subprocess.run(
        [str(AGGREGATOR)], input=sample, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f'aggregator failed: {result.stderr.decode(errors="replace")}'
    text = result.stdout.decode()
    assert 'Records Processed: 3' in text
    assert 'Total Bytes: 6442450941' in text, f'aggregator still overflows large totals: {text}'


def test_pipeline_on_unpredictable_crlf_stress_input():
    token = secrets.token_hex(6)
    records = []
    for i in range(1, 97):
        value = 1200000000 + secrets.randbelow(600000001)
        records.append((str(i), f'user_{token}_{i}', str(value)))

    payload = 'ID,User,Bytes\r\n' + ''.join(','.join(row) + '\r\n' for row in records)
    expected = Counter(records)
    expected_total = sum(int(row[2]) for row in records)

    try:
        for attempt in range(3):
            INPUT.write_bytes(payload.encode())
            run_pipeline(timeout=60)

            raw = OUTPUT.read_bytes()
            assert b'\r' not in raw, f'run {attempt + 1}: output contains DOS carriage returns'
            rows = list(csv.reader(raw.decode().splitlines()))
            assert all(len(row) == 3 for row in rows), f'run {attempt + 1}: interleaved or malformed rows found'
            assert Counter(tuple(row) for row in rows) == expected, (
                f'run {attempt + 1}: concurrent processing dropped, duplicated, or corrupted records'
            )

            count, total = parse_summary()
            assert count == len(records), f'run {attempt + 1}: expected {len(records)} records, got {count}'
            assert total == expected_total, f'run {attempt + 1}: expected total {expected_total}, got {total}'
    finally:
        INPUT.write_bytes(CANONICAL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
