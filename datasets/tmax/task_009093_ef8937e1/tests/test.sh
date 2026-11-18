#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess

import pytest

HOME = "/home/user"
DATA = os.path.join(HOME, "data.csv")
OUTPUT = os.path.join(HOME, "output.txt")
EXECUTABLE = os.path.join(HOME, "recommender")
SOURCE = os.path.join(HOME, "recommender.cpp")
REBUILT = "/tmp/recommender_verified"


def run_recommender(program, target):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [program, str(target)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{program} failed for target {target} with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{program} did not create {OUTPUT}."
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def find_eigen_include():
    for root, dirs, files in os.walk(os.path.join(HOME, "eigen")):
        dense = os.path.join(root, "Eigen", "Dense")
        core = os.path.join(root, "Eigen", "Core")
        macros = os.path.join(root, "Eigen", "src", "Core", "util", "Macros.h")
        if os.path.isfile(dense) and os.path.isfile(core) and os.path.isfile(macros):
            with open(macros, "r", errors="ignore") as f:
                text = f.read()
            if re.search(r"#\s*define\s+EIGEN_WORLD_VERSION\s+\d+", text):
                return root
    return None


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    return 0.0 if na == 0 or nb == 0 else dot / (na * nb)


def expected_line(rows, target):
    vectors = dict(rows)
    ranked = sorted(
        ((item_id, cosine(vectors[target], vector))
         for item_id, vector in rows if item_id != target),
        key=lambda pair: pair[1],
        reverse=True,
    )
    return f"{target}: {ranked[0][0]}, {ranked[1][0]}, {ranked[2][0]}"


def make_random_dataset():
    rng = random.SystemRandom()
    while True:
        ids = rng.sample(range(1000, 100000), 9)
        rows = []
        for item_id in ids:
            # Values are rounded before both writing and calculating the oracle.
            vector = [round(rng.uniform(-1.0, 1.0), 10) for _ in range(5)]
            rows.append((item_id, vector))

        # Avoid numerically ambiguous rankings around third place.
        good = True
        vectors = dict(rows)
        for target in ids[:3]:
            scores = sorted(
                (cosine(vectors[target], vector)
                 for item_id, vector in rows if item_id != target),
                reverse=True,
            )
            if min(abs(scores[i] - scores[i + 1]) for i in range(len(scores) - 1)) < 1e-6:
                good = False
                break
        if good:
            return rows, ids[:3]


def test_eigen_directory_exists():
    """Test that the eigen directory was created and contains Eigen headers."""
    assert os.path.isdir("/home/user/eigen"), "/home/user/eigen directory is missing. You must download and extract the Eigen library here."
    assert find_eigen_include() is not None, (
        "/home/user/eigen does not contain a usable Eigen header installation."
    )


def test_executable_exists():
    """Test that the recommender script was compiled into an executable."""
    assert os.path.isfile(EXECUTABLE), "The compiled executable /home/user/recommender is missing."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/recommender is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/recommender is not a compiled ELF executable."


def test_output_file_exists_and_correct_and_is_reproducible():
    """Retain the required final-state check, then verify the executable produces it."""
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} is missing. Did the script run successfully?"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    expected = "10: 11, 13, 14"
    assert content == expected, f"Expected output '{expected}', but got '{content}'."

    reproduced = run_recommender(EXECUTABLE, 10)
    assert reproduced == expected, (
        f"Running the executable should produce '{expected}', but got '{reproduced}'."
    )


def test_fixed_source_compiles_against_local_eigen():
    assert os.path.isfile(SOURCE), f"The source file {SOURCE} is missing."
    include_dir = find_eigen_include()
    assert include_dir is not None
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-I" + include_dir, "-o", REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"The fixed source does not compile against local Eigen:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_executable_and_fixed_source_on_unseen_data():
    original_data = open(DATA, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
    rows, targets = make_random_dataset()
    try:
        with open(DATA, "w") as f:
            for item_id, vector in rows:
                f.write(str(item_id) + "," + ",".join(format(x, ".10f") for x in vector) + "\n")

        for program in (EXECUTABLE, REBUILT):
            for target in targets:
                expected = expected_line(rows, target)
                actual = run_recommender(program, target)
                assert actual == expected, (
                    f"{program} returned '{actual}' for target {target}; expected '{expected}'."
                )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
