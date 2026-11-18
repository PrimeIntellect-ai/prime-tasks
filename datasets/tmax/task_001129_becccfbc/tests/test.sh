#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/run_filter.sh"
SOURCE = "/home/user/detector.cpp"
BUILT = "/tmp/verifier_detector"


def expected_for_csv(path):
    xs, ys, zs = [], [], []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            xs.append(float(row["sensor_x"]))
            ys.append(float(row["sensor_y"]))
            zs.append(float(row["sensor_z"]))
    assert xs, f"CSV has no data rows: {path}"
    f1 = sum(xs) / len(xs)
    f2 = max(abs(v) for v in ys)
    f3 = math.sqrt(sum(v * v for v in zs) / len(zs))
    h1 = max(0.0, 0.5 * f1 - 0.2 * f2 + 0.1 * f3)
    h2 = max(0.0, -0.1 * f1 + 0.8 * f2 - 0.5)
    logit = 1.5 * h1 - h2 + 0.2
    return ("EVIL", 1) if logit >= 0.0 else ("CLEAN", 0)


def run_checked(command, path, check_exit):
    result = subprocess.run(command + [path], capture_output=True, text=True, timeout=10)
    expected_text, expected_exit = expected_for_csv(path)
    assert result.stdout.strip() == expected_text, (
        f"Wrong prediction for {path}: expected {expected_text!r}, "
        f"got stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    if check_exit:
        assert result.returncode == expected_exit, (
            f"Wrong exit code for {path}: expected {expected_exit}, "
            f"got {result.returncode}; stderr={result.stderr!r}"
        )


def test_cmake_fixed():
    cmake_path = "/app/csv-parser/CMakeLists.txt"
    assert os.path.isfile(cmake_path), f"File missing: {cmake_path}"
    with open(cmake_path) as f:
        content = f.read()
    assert "set(CMAKE_CXX_STANDARD 17)" in content, \
        "CMakeLists.txt was not fixed to require C++17."


def test_deliverables_and_build():
    assert os.path.isfile(SCRIPT), f"File missing: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"
    assert os.path.isfile(SOURCE), f"File missing: {SOURCE}"

    elf_files = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            try:
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF" and os.access(path, os.X_OK):
                        elf_files.append(path)
            except OSError:
                pass
    assert elf_files, "No compiled executable binary was delivered under /home/user."

    build = subprocess.run([
        "g++", "-std=c++17", "-O2", SOURCE,
        "-I/app/csv-parser/single_include",
        "-I/app/csv-parser/include",
        "-pthread", "-o", BUILT,
    ], capture_output=True, text=True, timeout=60)
    assert build.returncode == 0, \
        f"detector.cpp does not build with the vendored parser: {build.stderr}"


def test_adversarial_corpus_evaluation():
    evil_files = glob.glob("/app/data/evil/*.csv")
    clean_files = glob.glob("/app/data/clean/*.csv")
    assert evil_files, "Evil corpus is missing."
    assert clean_files, "Clean corpus is missing."

    # Labels are derived from the specified feature extraction and network, rather
    # than from the directory names (the nominal 'clean' corpus is model-positive).
    for path in evil_files + clean_files:
        run_checked([SCRIPT], path, check_exit=True)


def test_hidden_generated_inputs():
    rng = secrets.SystemRandom()
    cases = []
    labels = set()
    with tempfile.TemporaryDirectory(prefix="detector-hidden-") as directory:
        attempts = 0
        while len(cases) < 20 and attempts < 1000:
            attempts += 1
            rows = []
            for i in range(rng.randint(3, 15)):
                rows.append((
                    i + rng.random(),
                    rng.uniform(-6.0, 6.0),
                    rng.uniform(-4.0, 4.0),
                    rng.uniform(-5.0, 5.0),
                ))
            path = os.path.join(directory, secrets.token_hex(12) + ".csv")
            with open(path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["timestamp", "sensor_x", "sensor_y", "sensor_z"])
                writer.writerows(rows)

            expected, _ = expected_for_csv(path)
            # Avoid numerically marginal cases while retaining unpredictable data.
            xs = [r[1] for r in rows]
            ys = [r[2] for r in rows]
            zs = [r[3] for r in rows]
            f1 = sum(xs) / len(xs)
            f2 = max(abs(v) for v in ys)
            f3 = math.sqrt(sum(v * v for v in zs) / len(zs))
            h1 = max(0.0, 0.5*f1 - 0.2*f2 + 0.1*f3)
            h2 = max(0.0, -0.1*f1 + 0.8*f2 - 0.5)
            logit = 1.5*h1 - h2 + 0.2
            if abs(logit) < 0.25:
                os.unlink(path)
                continue
            cases.append(path)
            labels.add(expected)

        assert labels == {"CLEAN", "EVIL"}, "Failed to generate both model classes."
        for path in cases:
            # Rebuilding and directly exercising the submitted C++ source prevents
            # a directory-name wrapper from standing in for the requested model.
            run_checked([BUILT], path, check_exit=False)
            run_checked([SCRIPT], path, check_exit=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
