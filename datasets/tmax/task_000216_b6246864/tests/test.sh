#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import random
import re
import secrets
import statistics
import subprocess
import time

import pytest

BASE_DIR = "/home/user/build_metrics"
SOURCE = os.path.join(BASE_DIR, "fast_parser.c")
EXECUTABLE = os.path.join(BASE_DIR, "fast_parser")
VERIFIED_EXECUTABLE = "/tmp/fast_parser_from_source"
LOG_PATH = os.path.join(BASE_DIR, "build_trace.log")


def get_expected_stats():
    starts = {}
    durations = []

    if not os.path.exists(LOG_PATH):
        return 0, 0

    with open(LOG_PATH, "r") as f:
        for line in f:
            if line.startswith("START_TRACE::"):
                parts = line.strip().split("::")
                if len(parts) == 3:
                    starts[parts[1]] = int(parts[2])
            elif line.startswith("END_TRACE::"):
                parts = line.strip().split("::")
                if len(parts) == 3:
                    name = parts[1]
                    end_ts = int(parts[2])
                    if name in starts and name.startswith("mobile_module_"):
                        durations.append(end_ts - starts[name])

    if durations:
        mean = sum(durations) / len(durations)
        variance = sum((x - mean) ** 2 for x in durations) / len(durations)
        return mean, variance
    return 0, 0


def strip_c_comments(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


@pytest.fixture(scope="session", autouse=True)
def build_and_validate_artifacts():
    assert os.path.isfile(SOURCE), "fast_parser.c is missing."
    makefile_path = os.path.join(BASE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), "Makefile is missing."

    with open(makefile_path, "r") as f:
        makefile = f.read()
    assert "-O3" in makefile, "Makefile does not use -O3 optimization."
    assert "stats" in makefile, "Makefile does not link against stats library."

    with open(SOURCE, "r") as f:
        source = strip_c_comments(f.read())

    for function in ("stats_init", "stats_add", "stats_get_mean", "stats_get_variance"):
        assert re.search(r"\b" + function + r"\s*\(", source), \
            f"fast_parser.c does not call {function}()."
        assert not re.search(
            r"\b(?:void|double|float|int)\s+" + function + r"\s*\([^;]*\)\s*\{",
            source,
        ), f"fast_parser.c must use the provided implementation of {function}()."

    assert re.search(r"\b(fgetc|getc|fread|read|mmap)\s*\(", source), \
        "fast_parser.c does not read and scan the input as characters or buffers."
    has_state_identifier = re.search(r"\b\w*state\w*\b", source, re.I)
    has_state_control = re.search(r"\bswitch\s*\([^)]*state[^)]*\)", source, re.I)
    state_assignments = re.findall(r"\b\w*state\w*\s*=", source, re.I)
    assert has_state_identifier and (has_state_control or len(state_assignments) >= 2), \
        "fast_parser.c does not contain an identifiable parsing state machine."

    if os.path.exists(EXECUTABLE):
        os.remove(EXECUTABLE)
    subprocess.run(["make", "-B"], cwd=BASE_DIR, check=True, timeout=30)
    assert os.path.isfile(EXECUTABLE), "fast_parser executable is missing after running make."
    assert os.access(EXECUTABLE, os.X_OK), "fast_parser is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_parser is not a compiled native executable."

    subprocess.run([
        "gcc", "-O3", "-I" + os.path.join(BASE_DIR, "include"),
        SOURCE, os.path.join(BASE_DIR, "lib", "libstats.a"),
        "-o", VERIFIED_EXECUTABLE,
    ], cwd=BASE_DIR, check=True, timeout=30)

    symbols = subprocess.run(
        ["nm", VERIFIED_EXECUTABLE], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
    ).stdout
    for function in ("stats_init", "stats_add", "stats_get_mean", "stats_get_variance"):
        assert re.search(r"\b[Tt]\s+" + function + r"$", symbols, re.M), \
            f"Compiled fast_parser is not linked with {function} from libstats.a."


@contextlib.contextmanager
def temporary_log(contents):
    with open(LOG_PATH, "rb") as f:
        original = f.read()
    try:
        with open(LOG_PATH, "w") as f:
            f.write(contents)
        yield
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original)


def parse_program_output(executable):
    result = subprocess.run(
        [executable], cwd=BASE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=True,
    )
    match = re.fullmatch(
        r"\s*Mean:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?),\s*"
        r"Variance:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*",
        result.stdout,
    )
    assert match, f"Unexpected parser output: {result.stdout!r}; stderr: {result.stderr!r}"
    return float(match.group(1)), float(match.group(2))


def assert_close(actual, expected, label):
    tolerance = max(0.011, abs(expected) * 1e-9)
    assert abs(actual - expected) <= tolerance, \
        f"Incorrect {label}: expected {expected}, got {actual}"


def make_hidden_trace():
    rng = random.Random(secrets.randbits(64))
    records = []
    durations = []
    endings = []

    for i in range(137):
        mobile = (i % 3) != 1
        name = ("mobile_module_" if mobile else "other_module_") + f"hidden_{i}"
        start = rng.randint(1_000, 5_000_000)
        duration = rng.randint(1, 25_000)
        records.append(f"START_TRACE::{name}::{start}\n")
        records.append(f"noise record {rng.randrange(1000000)}\n")
        endings.append(f"END_TRACE::{name}::{start + duration}\n")
        if mobile:
            durations.append(duration)

    rng.shuffle(endings)
    records.extend([
        "START_TRACE::mobile_module_malformed\n",
        " END_TRACE::mobile_module_ignored::999\n",
        "END_TRACE::mobile_module_without_start::12345\n",
        "warning::START_TRACE::mobile_module_fake::1\n",
    ])
    records.extend(endings)
    rng.shuffle(records)

    # Ensure every valid start precedes its corresponding end while retaining
    # broad interleaving: starts/noise first, then independently shuffled ends.
    starts_and_noise = [r for r in records if not r.startswith("END_TRACE::")]
    valid_ends = [r for r in records if r.startswith("END_TRACE::")]
    text = "".join(starts_and_noise + valid_ends)
    mean = sum(durations) / len(durations)
    variance = sum((x - mean) ** 2 for x in durations) / len(durations)
    return text, mean, variance


def test_parser_behavior_on_derived_input():
    trace, expected_mean, expected_variance = make_hidden_trace()
    with temporary_log(trace):
        for executable in (EXECUTABLE, VERIFIED_EXECUTABLE):
            mean, variance = parse_program_output(executable)
            assert_close(mean, expected_mean, "mean")
            assert_close(variance, expected_variance, "variance")


def test_parser_zero_matching_targets():
    trace = (
        "START_TRACE::other_module_a::10\n"
        "END_TRACE::other_module_a::45\n"
        "random warning\n"
        "END_TRACE::mobile_module_missing::100\n"
    )
    with temporary_log(trace):
        for executable in (EXECUTABLE, VERIFIED_EXECUTABLE):
            mean, variance = parse_program_output(executable)
            assert_close(mean, 0.0, "empty-input mean")
            assert_close(variance, 0.0, "empty-input variance")


def test_report_txt_content_and_benchmark_result():
    report_path = os.path.join(BASE_DIR, "report.txt")
    assert os.path.isfile(report_path), "report.txt is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"report.txt should have exactly 3 lines, found {len(lines)}."

    expected_mean, expected_variance = get_expected_stats()
    expected_mean_str = f"Mean: {expected_mean:.2f}"
    expected_variance_str = f"Variance: {expected_variance:.2f}"
    assert lines[0] == expected_mean_str, f"Expected '{expected_mean_str}', got '{lines[0]}'"
    assert lines[1] == expected_variance_str, f"Expected '{expected_variance_str}', got '{lines[1]}'"
    assert lines[2] == "Fast Parser was Faster: True", \
        f"Expected 'Fast Parser was Faster: True', got '{lines[2]}'"

    start = time.perf_counter()
    subprocess.run(
        ["python3", "slow_parser.py"], cwd=BASE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=True, timeout=30,
    )
    slow_time = time.perf_counter() - start

    fast_times = []
    for _ in range(3):
        start = time.perf_counter()
        mean, variance = parse_program_output(EXECUTABLE)
        fast_times.append(time.perf_counter() - start)
        assert_close(mean, expected_mean, "original-log mean")
        assert_close(variance, expected_variance, "original-log variance")

    assert min(fast_times) < slow_time, \
        f"Measured fast parser time {min(fast_times):.6f}s was not below slow parser time {slow_time:.6f}s."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
