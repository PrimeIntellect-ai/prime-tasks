#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

BASE = Path("/home/user/perf_profiling")
LOG_DIR = BASE / "logs"
SCRIPT = BASE / "fixed_summarize.sh"
RESULTS = BASE / "results.txt"


def test_overflow_report_exists_and_correct():
    report_path = "/home/user/perf_profiling/overflow_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "log_37.txt 2500000000"
    assert content == expected_content, f"Content of {report_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_fixed_summarize_exists_and_executable():
    script_path = "/home/user/perf_profiling/fixed_summarize.sh"
    assert os.path.isfile(script_path), f"Script file {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script file {script_path} is not executable."


def test_fixed_summarize_does_not_use_binary():
    script_path = "/home/user/perf_profiling/fixed_summarize.sh"
    with open(script_path, "r") as f:
        content = f.read()

    assert "metric_filter" not in content, "The fixed_summarize.sh script should not use the buggy metric_filter binary."


def test_fixed_summarize_execution_and_results():
    script_path = "/home/user/perf_profiling/fixed_summarize.sh"
    results_path = "/home/user/perf_profiling/results.txt"

    if os.path.exists(results_path):
        os.remove(results_path)

    result = subprocess.run([script_path], cwd="/home/user/perf_profiling", capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Script {script_path} failed to execute properly. Stderr: {result.stderr}"

    assert os.path.isfile(results_path), f"The script did not generate {results_path}."

    with open(results_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 50, f"Expected 50 lines in {results_path}, but got {len(lines)}."

    results_dict = {}
    for line in lines:
        parts = line.split(":")
        assert len(parts) == 2, f"Invalid format in results.txt line: {line}"
        filename = parts[0].strip()
        total = parts[1].strip()
        results_dict[filename] = total

    for i in range(1, 51):
        filename = f"log_{i:02d}.txt"
        assert filename in results_dict, f"Missing result for {filename} in {results_path}."

        if i == 37:
            expected_total = "2500000000"
        else:
            expected_total = "1000000000"

        actual_total = results_dict[filename]
        assert actual_total == expected_total, f"Incorrect total for {filename}. Expected {expected_total}, got {actual_total}."


def compute_expected():
    expected = {}
    for path in sorted(LOG_DIR.glob("log_*.txt")):
        total = 0
        with path.open() as f:
            for line in f:
                fields = line.split()
                assert len(fields) >= 3, f"Malformed verifier fixture line in {path}: {line!r}"
                total += int(fields[2])
        expected[path.name] = str(total)
    return expected


def parse_results_strict():
    assert RESULTS.is_file(), f"The script did not generate {RESULTS}."
    parsed = {}
    lines = RESULTS.read_text().splitlines()
    assert all(line != "" for line in lines), "results.txt contains a blank line."
    for line in lines:
        match = re.fullmatch(r"([^:\n]+): (-?[0-9]+)", line)
        assert match, f"Invalid format in results.txt line: {line!r}"
        filename, total = match.groups()
        assert filename not in parsed, f"Duplicate result for {filename}."
        parsed[filename] = total
    return parsed


def test_fixed_summarize_aggregates_changed_and_new_logs():
    changed = LOG_DIR / "log_01.txt"
    added = LOG_DIR / "log_51.txt"
    changed_original = changed.read_bytes()
    added_original = added.read_bytes() if added.exists() else None
    rng = random.SystemRandom()

    changed_values = [rng.randrange(400_000_001, 900_000_000) for _ in range(4)]
    added_values = [rng.randrange(300_000_001, 800_000_000) for _ in range(5)]

    def fixture(values):
        return "".join(
            f"[2026-01-01T00:00:{index:02d}] EVENT_DYNAMIC {value}\n"
            for index, value in enumerate(values)
        )

    try:
        changed.write_text(fixture(changed_values))
        added.write_text(fixture(added_values))
        expected = compute_expected()

        if RESULTS.exists():
            RESULTS.unlink()
        result = subprocess.run(
            [str(SCRIPT)], cwd=str(BASE), capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"Script failed on changed logs. Stderr: {result.stderr}"

        actual = parse_results_strict()
        assert actual.keys() == expected.keys(), (
            f"Results must contain exactly one entry for every log file. "
            f"Expected {sorted(expected)}, got {sorted(actual)}"
        )
        for filename, expected_total in expected.items():
            assert actual[filename] == expected_total, (
                f"Incorrect dynamically computed total for {filename}. "
                f"Expected {expected_total}, got {actual[filename]}."
            )
    finally:
        changed.write_bytes(changed_original)
        if added_original is None:
            added.unlink(missing_ok=True)
        else:
            added.write_bytes(added_original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
