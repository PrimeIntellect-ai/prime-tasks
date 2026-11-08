#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
from fractions import Fraction
from pathlib import Path

import pytest


def test_processor_c_exists():
    path = "/home/user/processor.c"
    assert os.path.isfile(path), f"Source file not found: {path}"


def test_processor_executable_exists():
    path = "/home/user/processor"
    assert os.path.isfile(path), f"Executable not found: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable is not a compiled ELF binary: {path}"


def test_output_csv():
    path = "/home/user/output.csv"
    assert os.path.isfile(path), f"Output file not found: {path}"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "user_id,score",
        "4,60.00",
        "6,60.00",
        "7,50.00",
        "8,50.00"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {path}, but found {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"


def _make_case():
    rng = random.SystemRandom()
    ids = [2, 10, 101]
    pool = [n for n in range(3, 997) if n not in ids]
    ids.extend(rng.sample(pool, 7))

    # Feature values are represented as quarter-units so expected formatting is exact.
    features = {
        ids[0]: (50, 0, 0),       # 12.50 * 4 = exactly 50.00
        ids[1]: (65, 0, 0),       # 16.25 * 3 = 48.75, filtered out
        ids[2]: (42, 10, 0),      # 10.50 * 5 = 52.50
    }
    weights = {
        ids[0]: (4, rng.randint(0, 6), rng.randint(0, 6)),
        ids[1]: (3, rng.randint(0, 6), rng.randint(0, 6)),
        ids[2]: (5, 0, rng.randint(0, 6)),
    }

    for uid in ids[3:8]:
        features[uid] = tuple(rng.randint(0, 80) for _ in range(3))
        weights[uid] = tuple(rng.randint(0, 7) for _ in range(3))

    # One ID appears only in users, and another only in weights.
    features[ids[8]] = (80, 80, 80)
    weights[ids[9]] = (7, 7, 7)

    user_rows = list(features.items())
    weight_rows = list(weights.items())
    rng.shuffle(user_rows)
    rng.shuffle(weight_rows)

    users_text = "user_id,f1,f2,f3\n" + "".join(
        f"{uid},{vals[0] / 4:.2f},{vals[1] / 4:.2f},{vals[2] / 4:.2f}\n"
        for uid, vals in user_rows
    )
    weights_text = "user_id,w1,w2,w3\n" + "".join(
        f"{uid},{vals[0]},{vals[1]},{vals[2]}\n"
        for uid, vals in weight_rows
    )

    results = []
    for uid in features.keys() & weights.keys():
        score = sum(
            Fraction(features[uid][i], 4) * weights[uid][i]
            for i in range(3)
        )
        if score >= 50:
            cents = score * 100
            assert cents.denominator == 1
            cents = cents.numerator
            results.append((uid, f"{cents // 100}.{cents % 100:02d}"))

    results.sort(key=lambda item: item[0])
    expected = ["user_id,score"] + [f"{uid},{score}" for uid, score in results]
    return users_text, weights_text, expected


def _run_and_check(executable, users_text, weights_text, expected):
    users_path = Path("/home/user/users.csv")
    weights_path = Path("/home/user/weights.csv")
    output_path = Path("/home/user/output.csv")

    users_path.write_text(users_text)
    weights_path.write_text(weights_text)
    if output_path.exists():
        output_path.unlink()

    completed = subprocess.run(
        [str(executable)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}. stderr: {completed.stderr}"
    )
    assert output_path.is_file(), f"{executable} did not generate {output_path}"

    with output_path.open("r") as f:
        actual = [line.strip() for line in f.readlines() if line.strip()]
    assert actual == expected, (
        f"Incorrect output from {executable}. Expected {expected}, got {actual}"
    )


def test_processor_behavior_and_source():
    users_path = Path("/home/user/users.csv")
    weights_path = Path("/home/user/weights.csv")
    output_path = Path("/home/user/output.csv")
    original_users = users_path.read_bytes()
    original_weights = weights_path.read_bytes()
    original_output = output_path.read_bytes()

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            rebuilt = Path(temp_dir) / "processor_from_source"
            compiled = subprocess.run(
                ["gcc", "-std=c11", "-O2", "/home/user/processor.c", "-o", str(rebuilt)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert compiled.returncode == 0, f"processor.c does not compile: {compiled.stderr}"
            assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)

            cases = [_make_case(), _make_case()]
            for executable in (Path("/home/user/processor"), rebuilt):
                for users_text, weights_text, expected in cases:
                    _run_and_check(executable, users_text, weights_text, expected)
    finally:
        users_path.write_bytes(original_users)
        weights_path.write_bytes(original_weights)
        output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
