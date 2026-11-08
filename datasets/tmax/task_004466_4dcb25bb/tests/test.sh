#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import subprocess
import tempfile
import uuid

LIB_DIR = "/app/libinfer_ops-1.2.0"
SOURCE_PATH = "/home/user/sanitizer.cpp"
BINARY_PATH = "/home/user/sanitizer"


def is_elf(path):
    with open(path, "rb") as f:
        return f.read(4) == b"\x7fELF"


def test_libinfer_ops_compiled_and_benchmarked():
    baseline_file = os.path.join(LIB_DIR, "baseline_perf.txt")
    assert os.path.isfile(baseline_file), f"Expected benchmark output file {baseline_file} does not exist. Did you run ./benchmark_infer?"
    with open(baseline_file, "r") as f:
        content = f.read()
    assert "TRACKER_OVERHEAD_MS" in content, f"File {baseline_file} does not contain the expected benchmark output."

    subprocess.run(["make", "clean"], cwd=LIB_DIR, check=True, timeout=30, capture_output=True)
    build = subprocess.run(["make"], cwd=LIB_DIR, timeout=60, capture_output=True, text=True)
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"

    benchmark = os.path.join(LIB_DIR, "benchmark_infer")
    assert os.path.isfile(benchmark) and os.access(benchmark, os.X_OK), "make did not produce an executable benchmark_infer"
    assert is_elf(benchmark), "benchmark_infer is not a compiled executable"

    if os.path.exists(baseline_file):
        os.unlink(baseline_file)
    run = subprocess.run([benchmark], cwd=LIB_DIR, timeout=30, capture_output=True, text=True)
    assert run.returncode == 0, f"benchmark_infer failed: {run.stderr}"
    assert os.path.isfile(baseline_file), "Running benchmark_infer did not generate baseline_perf.txt"
    with open(baseline_file, "r") as f:
        regenerated = f.read()
    match = re.search(r"TRACKER_OVERHEAD_MS\s*:\s*([-+0-9.eE]+)", regenerated)
    assert match, "Regenerated baseline_perf.txt lacks a numeric TRACKER_OVERHEAD_MS result"
    value = float(match.group(1))
    assert math.isfinite(value) and value >= 0, "Benchmark overhead must be a finite non-negative number"


def test_sanitizer_binary_and_source_exist():
    assert os.path.isfile(SOURCE_PATH), f"Sanitizer source not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, "Sanitizer source is empty"
    assert os.path.isfile(BINARY_PATH), f"Sanitizer binary not found at {BINARY_PATH}. Did you compile it?"
    assert os.access(BINARY_PATH, os.X_OK), f"Sanitizer binary at {BINARY_PATH} is not executable."
    assert is_elf(BINARY_PATH), "Sanitizer must be a compiled executable, not a script"


def test_sanitizer_adversarial_corpus():
    evil_files = glob.glob("/app/corpora/evil/*.csv")
    clean_files = glob.glob("/app/corpora/clean/*.csv")
    assert len(evil_files) > 0, "Evil corpus is empty or missing."
    assert len(clean_files) > 0, "Clean corpus is empty or missing."

    evil_bypassed = []
    for path in evil_files:
        result = subprocess.run([BINARY_PATH, path], capture_output=True, timeout=10)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(path))

    clean_modified = []
    for path in clean_files:
        result = subprocess.run([BINARY_PATH, path], capture_output=True, timeout=10)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_bypassed[:10]))
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: " + ", ".join(clean_modified[:10]))
    assert not errors, " | ".join(errors)


def write_case(directory, rows):
    path = os.path.join(directory, uuid.uuid4().hex + ".csv")
    shuffled = list(rows)
    random.SystemRandom().shuffle(shuffled)
    with open(path, "w") as f:
        f.write("latency_ms\n")
        for value in shuffled:
            f.write(str(value) + "\n")
    return path


def exercise(binary, directory):
    cases = [
        (["NaN"] * 11 + ["-1.0"] * 10 + ["30.0"] * 79, 1, "more than 20 percent invalid"),
        (["NaN"] * 10 + ["-1.0"] * 10 + ["30.0"] * 80, 0, "exactly 20 percent invalid"),
        (["30.0"] * 100, 0, "ordinary clean data"),
        (["100.0"] * 100, 0, "upper bound equal to 100"),
        (["100.1"] * 100, 1, "upper bound above 100"),
        (["150.0"] * 100, 1, "constant high latency"),
        # Raw mean is 97 ms, but the bootstrap upper confidence bound is above 100.
        (["80.0"] * 90 + ["250.0"] * 10, 1, "bootstrap upper bound above 100 despite mean below 100"),
        # A single large observation does not by itself put the bootstrap upper bound near 100.
        (["30.0"] * 199 + ["500.0"], 0, "isolated high observation with low bootstrap upper bound"),
    ]
    random.SystemRandom().shuffle(cases)
    for rows, expected, description in cases:
        path = write_case(directory, rows)
        result = subprocess.run([binary, path], capture_output=True, timeout=15)
        assert result.returncode == expected, (
            f"Wrong status for {description}: expected {expected}, got {result.returncode}"
        )

    no_arg = subprocess.run([binary], capture_output=True, timeout=10)
    assert no_arg.returncode != 0, "Sanitizer must reject invocation without a CSV path"
    missing = os.path.join(directory, uuid.uuid4().hex + ".csv")
    missing_result = subprocess.run([binary, missing], capture_output=True, timeout=10)
    assert missing_result.returncode != 0, "Sanitizer must reject a nonexistent input file"


def test_sanitizer_on_generated_unpredictable_inputs_and_rebuild_source():
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "rebuilt_sanitizer")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert compile_result.returncode == 0, (
            f"sanitizer.cpp does not compile as C++:\n{compile_result.stdout}\n{compile_result.stderr}"
        )
        assert is_elf(rebuilt), "Rebuilding sanitizer.cpp did not produce a compiled executable"

        # Test both the submitted artifact and a fresh build of the submitted C++ source.
        exercise(rebuilt, directory)
        exercise(BINARY_PATH, directory)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
