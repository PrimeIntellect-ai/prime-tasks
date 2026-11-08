#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import time
import pytest

RAW_DATA_PATH = "/home/user/raw_data.txt"
CLEAN_DATA_PATH = "/home/user/clean_data.jsonl"
BENCHMARK_PATH = "/home/user/benchmark.txt"
BENCHMARK_RE = re.compile(r"^Throughput: (\d+\.\d{2}) lines/sec$")


def derive_expected(path):
    expected_data = []
    with open(path, "r") as f:
        for line in f:
            original_line = line.strip()
            if not original_line:
                continue
            if "AI" in original_line and len(original_line.split()) > 5:
                transformed = original_line.lower()
                for p in [".", ",", "!", "?"]:
                    transformed = transformed.replace(p, "")
                expected_data.append({"tokens": transformed.split()})
    return expected_data


def read_jsonl(path):
    actual_data = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual_data.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON in {path}: {line}")
    return actual_data


def read_benchmark():
    assert os.path.isfile(BENCHMARK_PATH), f"Missing {BENCHMARK_PATH}"
    with open(BENCHMARK_PATH, "r") as f:
        content = f.read().strip()
    match = BENCHMARK_RE.fullmatch(content)
    assert match, (f"Benchmark format incorrect in {BENCHMARK_PATH}. Expected format "
                   f"'Throughput: X.XX lines/sec', got: '{content}'")
    value = float(match.group(1))
    assert math.isfinite(value) and value > 0
    return value


def test_clean_data_jsonl():
    assert os.path.isfile(RAW_DATA_PATH), f"Missing {RAW_DATA_PATH}"
    assert os.path.isfile(CLEAN_DATA_PATH), f"Missing {CLEAN_DATA_PATH}"

    expected_data = derive_expected(RAW_DATA_PATH)
    actual_data = read_jsonl(CLEAN_DATA_PATH)

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} lines in {CLEAN_DATA_PATH}, found {len(actual_data)}"
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert "tokens" in actual, f"Line {i+1} missing 'tokens' key"
        assert actual["tokens"] == expected["tokens"], f"Mismatch at line {i+1}. Expected {expected['tokens']}, got {actual['tokens']}"


def test_benchmark_txt():
    read_benchmark()


def candidate_scripts():
    found = []
    this_file = os.path.realpath(__file__)
    for root in ("/home/user", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".local", "__pycache__"}]
            for name in files:
                if not name.endswith(".py"):
                    continue
                path = os.path.join(directory, name)
                if os.path.realpath(path) != this_file and os.path.isfile(path):
                    found.append(path)
    return sorted(set(found))


def test_script_recomputes_and_measures_benchmark():
    paths = [RAW_DATA_PATH, CLEAN_DATA_PATH, BENCHMARK_PATH]
    backups = {}
    for path in paths:
        with open(path, "rb") as f:
            backups[path] = f.read() if os.path.exists(path) else None

    try:
        probe = (
            "AI alpha beta gamma delta epsilon!\n"
            "ordinary words without the required target keyword\n"
            "AI tiny line.\n"
        )
        expected_probe = [{"tokens": ["ai", "alpha", "beta", "gamma", "delta", "epsilon"]}]
        selected = None

        for script in candidate_scripts():
            with open(RAW_DATA_PATH, "w") as f:
                f.write(probe)
            for output in (CLEAN_DATA_PATH, BENCHMARK_PATH):
                if os.path.exists(output):
                    os.remove(output)
            try:
                result = subprocess.run(
                    ["python3", script], cwd=os.path.dirname(script) or "/",
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=15
                )
                if result.returncode != 0:
                    continue
                if not os.path.isfile(CLEAN_DATA_PATH) or not os.path.isfile(BENCHMARK_PATH):
                    continue
                if read_jsonl(CLEAN_DATA_PATH) != expected_probe:
                    continue
                read_benchmark()
                selected = script
                break
            except (subprocess.SubprocessError, OSError, AssertionError):
                continue

        assert selected is not None, "No executable Python ETL script was found that regenerates both requested outputs"

        total_lines = 250000
        raw_line = "ordinary words without the target keyword here\n"
        with open(RAW_DATA_PATH, "w") as f:
            for _ in range(total_lines):
                f.write(raw_line)
        for output in (CLEAN_DATA_PATH, BENCHMARK_PATH):
            if os.path.exists(output):
                os.remove(output)

        wall_start = time.perf_counter()
        result = subprocess.run(
            ["python3", selected], cwd=os.path.dirname(selected) or "/",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        wall_elapsed = time.perf_counter() - wall_start
        assert result.returncode == 0, f"ETL script failed when rerun: {result.stderr}"
        assert os.path.isfile(CLEAN_DATA_PATH), f"Script did not regenerate {CLEAN_DATA_PATH}"
        assert read_jsonl(CLEAN_DATA_PATH) == [], "Script did not process the replacement raw input correctly"
        reported = read_benchmark()

        with open(RAW_DATA_PATH, "r") as f:
            raw_lines = f.readlines()
        reference_start = time.perf_counter()
        for line in raw_lines:
            original_line = line.strip()
            if not original_line:
                continue
            if "AI" in original_line and len(original_line.split()) > 5:
                transformed = original_line.lower()
                for p in [".", ",", "!", "?"]:
                    transformed = transformed.replace(p, "")
                transformed.split()
        reference_elapsed = time.perf_counter() - reference_start

        reference_throughput = total_lines / reference_elapsed
        whole_process_throughput = total_lines / wall_elapsed
        assert reference_throughput / 20 <= reported <= reference_throughput * 20, (
            f"Reported throughput {reported:.2f} is not plausible for the measured processing loop "
            f"(reference {reference_throughput:.2f} lines/sec)"
        )
        assert whole_process_throughput / 20 <= reported <= whole_process_throughput * 100, (
            f"Reported throughput {reported:.2f} is inconsistent with the independently timed script run "
            f"({whole_process_throughput:.2f} lines/sec end-to-end)"
        )
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
