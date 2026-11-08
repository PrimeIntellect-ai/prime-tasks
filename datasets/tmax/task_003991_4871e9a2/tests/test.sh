#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

BINARY_PATH = "/home/user/log_filter"
SOURCE_PATH = "/home/user/log_filter.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_program(binary, *args):
    return subprocess.run(
        [binary, *map(str, args)], capture_output=True, text=True, timeout=10
    )


def get_expected_output(csv_path):
    expected_lines = []
    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row or len(row) < 5:
                continue
            event_id, timestamp, cpu, mem, retry = row
            expected_lines.append(f"{event_id},{timestamp},CPU_Usage,{cpu}")
            expected_lines.append(f"{event_id},{timestamp},Memory_Usage,{mem}")
    return expected_lines


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["EventID", "Timestamp", "CPU_Usage", "Memory_Usage", "RetryCount"])
        writer.writerows(rows)


def assert_valid(binary, path, expected):
    result = run_program(binary, path)
    assert result.returncode == 0, result.stderr
    actual = result.stdout.splitlines()
    assert all(line != "" for line in actual), "Unexpected blank output line"
    assert sorted(actual) == sorted(expected)


def assert_invalid(binary, path):
    result = run_program(binary, path)
    assert result.returncode != 0
    assert result.stdout == "", "Invalid input must produce no stdout"


@pytest.fixture(scope="session")
def rebuilt_binary(tmp_path_factory):
    assert os.path.isfile(SOURCE_PATH), f"Source not found at {SOURCE_PATH}"
    source = Path(SOURCE_PATH).read_text(errors="replace")
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(
        r"(?m)^\s*#\s*pragma\s+omp\s+(?:parallel(?:\s+for)?|for)\b",
        without_comments,
    ), "Source does not contain an active OpenMP parallel/for pragma"

    output = tmp_path_factory.mktemp("build") / "log_filter_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-O2", "-fopenmp", SOURCE_PATH, "-o", str(output)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    symbols = subprocess.run(
        ["nm", "-D", str(output)], capture_output=True, text=True, timeout=10
    )
    assert symbols.returncode == 0
    assert re.search(r"\b(?:GOMP_|omp_)", symbols.stdout), (
        "Rebuilt program contains no OpenMP runtime references"
    )
    return str(output)


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled log_filter must be an ELF binary"


def test_source_builds_with_openmp(rebuilt_binary):
    assert os.path.isfile(rebuilt_binary)
    assert os.access(rebuilt_binary, os.X_OK)


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".csv")]
    assert clean_files, "No clean CSV files found in corpus"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = run_program(BINARY_PATH, filepath)
        if result.returncode != 0:
            failed_files.append((filename, f"Exit code {result.returncode} instead of 0"))
            continue
        expected_lines = get_expected_output(filepath)
        actual_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if sorted(expected_lines) != sorted(actual_lines):
            failed_files.append((filename, "Output data does not match expected long format"))

    if failed_files:
        errors = "\n".join(f"{f}: {err}" for f, err in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files failed:\n{errors}")


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".csv")]
    assert evil_files, "No evil CSV files found in corpus"

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = run_program(BINARY_PATH, filepath)
        if result.returncode == 0:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed validation:\n"
            + "\n".join(bypassed_files)
        )


def test_exact_argument_handling(tmp_path):
    valid = tmp_path / "argument_input.csv"
    write_csv(valid, [["901", "2026-01-01T00:00:00Z", "1.0", "2.0", "0"]])
    for binary in [BINARY_PATH]:
        assert run_program(binary).returncode != 0
        assert run_program(binary, valid, valid).returncode != 0


def test_randomized_valid_records_and_boundaries(tmp_path, rebuilt_binary):
    rng = secrets.SystemRandom()
    base = rng.randrange(1000000, 9000000)
    rows = [
        [str(base), "2026-07-01T00:00:00Z", "0.0", "100.0", "2"],
        [str(base + 1), "2026-07-01T00:00:01Z", "100.0", "0.0", "0"],
    ]
    for i in range(2, 18):
        cpu = f"{rng.randrange(0, 100001) / 1000:.3f}"
        mem = f"{rng.randrange(0, 100001) / 1000:.3f}"
        rows.append([
            str(base + i),
            f"2026-07-01T00:{i:02d}:00Z",
            cpu,
            mem,
            str(rng.randrange(0, 3)),
        ])

    path = tmp_path / f"valid_{secrets.token_hex(8)}.csv"
    write_csv(path, rows)
    expected = []
    for event_id, timestamp, cpu, mem, _ in rows:
        expected.extend([
            f"{event_id},{timestamp},CPU_Usage,{cpu}",
            f"{event_id},{timestamp},Memory_Usage,{mem}",
        ])

    for binary in [BINARY_PATH, rebuilt_binary]:
        assert_valid(binary, path, expected)


def test_randomized_validation_failures(tmp_path, rebuilt_binary):
    rng = secrets.SystemRandom()
    base = rng.randrange(10000000, 90000000)
    cases = {
        "cpu_high": [[str(base), "2026-08-01T00:00:00Z", "100.0001", "50", "0"]],
        "cpu_low": [[str(base + 1), "2026-08-01T00:00:01Z", "-0.001", "50", "0"]],
        "mem_high": [[str(base + 2), "2026-08-01T00:00:02Z", "50", "100.01", "1"]],
        "mem_low": [[str(base + 3), "2026-08-01T00:00:03Z", "50", "-1", "2"]],
        "retry_high": [[str(base + 4), "2026-08-01T00:00:04Z", "50", "50", "3"]],
        "duplicate": [
            [str(base + 5), "2026-08-01T00:00:05Z", "10", "20", "0"],
            [str(base + 5), "2026-08-01T00:00:06Z", "30", "40", "1"],
        ],
        "nonnumeric_cpu": [[str(base + 6), "2026-08-01T00:00:07Z", "invalid", "50", "0"]],
        "nan_cpu": [[str(base + 7), "2026-08-01T00:00:08Z", "NaN", "50", "0"]],
        "infinite_mem": [[str(base + 8), "2026-08-01T00:00:09Z", "50", "inf", "0"]],
        "bad_retry": [[str(base + 9), "2026-08-01T00:00:10Z", "50", "50", "2junk"]],
        "missing_field": [[str(base + 10), "2026-08-01T00:00:11Z", "50", "50"]],
    }

    for name, rows in cases.items():
        path = tmp_path / f"{name}_{secrets.token_hex(6)}.csv"
        write_csv(path, rows)
        for binary in [BINARY_PATH, rebuilt_binary]:
            assert_invalid(binary, path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
