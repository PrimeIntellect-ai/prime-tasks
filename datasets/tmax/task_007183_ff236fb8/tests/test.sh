#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import stat
import subprocess
import tempfile

HOME = "/home/user"
RAW = f"{HOME}/raw_data.csv"
CLEAN = f"{HOME}/clean_data.csv"
SOURCE = f"{HOME}/detector.cpp"
DETECTOR = f"{HOME}/detector"
CLEAN_SH = f"{HOME}/clean.sh"
TUNE_SH = f"{HOME}/tune.sh"
GRID = f"{HOME}/grid_results.csv"

EXPECTED_CLEAN = """id,value,label
1,10.0,0
2,10.2,0
3,10.1,0
4,10.1,0
5,10.3,0
6,15.5,1
7,10.1,0
8,10.2,0
9,10.2,0
10,10.4,0
11,20.0,1
12,10.1,0
13,10.0,0
14,9.9,0
15,14.0,1"""


def run_checked(command, timeout=30):
    result = subprocess.run(
        command,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def assert_clean_data_content():
    assert os.path.exists(CLEAN), f"{CLEAN} is missing."
    with open(CLEAN, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_CLEAN, (
        f"The content of {CLEAN} does not match the expected forward-filled data."
    )


def get_expected_f1(W, T, values, labels):
    tp = 0
    fp = 0
    fn = 0
    for i in range(W, len(values)):
        mean = sum(values[i-W:i]) / W
        pred = 1 if abs(values[i] - mean) > T else 0
        actual = labels[i]
        if pred == 1 and actual == 1:
            tp += 1
        elif pred == 1 and actual == 0:
            fp += 1
        elif pred == 0 and actual == 1:
            fn += 1
    if tp == 0:
        return 0.0
    return 2 * tp / (2 * tp + fp + fn)


def assert_grid_results():
    assert os.path.exists(GRID), f"{GRID} is missing."

    values = [10.0, 10.2, 10.1, 10.1, 10.3, 15.5, 10.1, 10.2, 10.2, 10.4, 20.0, 10.1, 10.0, 9.9, 14.0]
    labels = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1]

    expected_results = {}
    for W in [2, 3, 4]:
        for T in [1.5, 2.0, 2.5]:
            f1 = get_expected_f1(W, T, values, labels)
            expected_results[(W, T)] = f"{f1:.4f}"

    with open(GRID, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["W", "T", "F1"], f"Header in {GRID} must be exactly W,T,F1."

        actual_results = {}
        for row in reader:
            assert len(row) == 3, f"Invalid row format in {GRID}: {row}"
            w, t, f1 = row
            actual_results[(int(w), float(t))] = f1

    assert len(actual_results) == 9, f"Expected 9 result rows, found {len(actual_results)}."
    for w_t, expected_f1 in expected_results.items():
        assert w_t in actual_results, f"Missing result for W={w_t[0]}, T={w_t[1]}."
        actual_f1 = actual_results[w_t]
        assert actual_f1 == expected_f1, (
            f"F1 mismatch for W={w_t[0]}, T={w_t[1]}: "
            f"expected {expected_f1}, got {actual_f1}."
        )


def write_detector_dataset(values, labels):
    with open(CLEAN, "w") as f:
        f.write("id,value,label\n")
        for i, (value, label) in enumerate(zip(values, labels), 1):
            f.write(f"{i},{value:.8f},{label}\n")


def assert_detector(binary, values, labels, cases):
    for W, T in cases:
        result = run_checked([binary, str(W), str(T)])
        expected = f"{get_expected_f1(W, T, values, labels):.4f}"
        assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n?", result.stdout), (
            f"Detector output must contain only one F1 score with exactly four decimal places; "
            f"got {result.stdout!r}."
        )
        assert result.stdout.strip() == expected, (
            f"Detector returned {result.stdout.strip()!r} for W={W}, T={T}; expected {expected!r}."
        )


def test_complete_pipeline_and_artifacts():
    for path in [CLEAN_SH, SOURCE, TUNE_SH]:
        assert os.path.isfile(path), f"Required artifact {path} is missing or is not a regular file."

    with open(RAW, "rb") as f:
        original_raw = f.read()

    # Exercise clean.sh on unpredictable input rather than trusting the fixed output file.
    rng = random.SystemRandom()
    numeric = [f"{rng.uniform(-80, 80):.6f}" for _ in range(7)]
    dynamic_rows = [
        (1, numeric[0], 0),
        (2, "NaN", 1),
        (3, numeric[1], 0),
        (4, "ERROR", 0),
        (5, "NaN", 1),
        (6, numeric[2], 0),
        (7, numeric[3], 1),
        (8, "ERROR", 0),
        (9, numeric[4], 0),
        (10, "NaN", 1),
        (11, numeric[5], 0),
        (12, numeric[6], 1),
    ]
    expected_rows = []
    last = None
    for row_id, value, label in dynamic_rows:
        if value not in ("NaN", "ERROR"):
            last = value
        expected_rows.append(f"{row_id},{last},{label}")

    try:
        with open(RAW, "w") as f:
            f.write("id,value,label\n")
            for row_id, value, label in dynamic_rows:
                f.write(f"{row_id},{value},{label}\n")
        if os.path.lexists(CLEAN):
            os.remove(CLEAN)
        run_checked(["bash", CLEAN_SH])
        assert os.path.isfile(CLEAN), "clean.sh did not generate clean_data.csv."
        with open(CLEAN, "r") as f:
            actual = f.read().strip()
        expected = "id,value,label\n" + "\n".join(expected_rows)
        assert actual == expected, "clean.sh failed forward-fill testing on dynamic input."
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)

    # Regenerate and retain the originally required cleaned data.
    run_checked(["bash", CLEAN_SH])
    assert_clean_data_content()

    # tune.sh must recreate both the compiled executable and the full grid.
    for path in [DETECTOR, GRID]:
        if os.path.lexists(path):
            os.remove(path)
    run_checked(["bash", TUNE_SH], timeout=60)
    assert os.path.isfile(DETECTOR), "tune.sh did not create /home/user/detector."
    assert os.access(DETECTOR, os.X_OK), "/home/user/detector is not executable."
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/detector is not a compiled ELF executable."
    assert_clean_data_content()
    assert_grid_results()

    # Compile detector.cpp independently so both the requested source and the
    # executable produced by tune.sh are exercised against runtime-generated data.
    fd, compiled_copy = tempfile.mkstemp(prefix="verifier_detector_", dir="/tmp")
    os.close(fd)
    os.unlink(compiled_copy)
    try:
        run_checked(["g++", "-O3", SOURCE, "-o", compiled_copy], timeout=60)
        detector_data = []
        base = rng.uniform(-25, 25)
        for i in range(21):
            value = base + rng.uniform(-1.2, 1.2)
            if i in (5, 11, 17):
                value += rng.choice([-1, 1]) * rng.uniform(5.5, 9.0)
            detector_data.append(value)
        labels = [rng.randint(0, 1) for _ in detector_data]
        cases = [(1, 0.73), (3, 1.61), (5, 2.47), (7, 4.13)]

        original_clean = open(CLEAN, "rb").read()
        try:
            write_detector_dataset(detector_data, labels)
            assert_detector(DETECTOR, detector_data, labels, cases)
            assert_detector(compiled_copy, detector_data, labels, cases)
        finally:
            with open(CLEAN, "wb") as f:
                f.write(original_clean)
    finally:
        if os.path.exists(compiled_copy):
            os.remove(compiled_copy)

    # Preserve the original final-state assertions after behavioral testing.
    assert_clean_data_content()
    assert_grid_results()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
