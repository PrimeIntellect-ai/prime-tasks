#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

SOURCE = "/home/user/etl_recommender.c"
EXECUTABLE = "/home/user/etl_recommender"
OUTPUT = "/home/user/recommendations.csv"
REBUILT = "/tmp/etl_recommender_from_source"

INITIAL_USERS = [
    (1, 0.0, 0.0),
    (2, 3.0, 4.0),
    (3, -1.0, -1.0),
]
INITIAL_ITEMS = [
    (101, 1.0, 1.0),
    (102, 0.0, 5.0),
    (103, -2.0, -2.0),
]


def write_inputs(users, items):
    with open("/home/user/users.csv", "w", newline="") as f:
        for user_id, x, y in users:
            f.write(f"{user_id},{x},{y}\n")
    with open("/home/user/items.csv", "w", newline="") as f:
        for item_id, x, y in items:
            f.write(f"{item_id},{x},{y}\n")


def expected_content(users, items):
    expected_lines = []
    for u_id, ux, uy in users:
        min_dist = float("inf")
        best_item = -1
        for i_id, ix, iy in items:
            dist = math.sqrt((ux - ix) ** 2 + (uy - iy) ** 2)
            if dist < min_dist - 1e-9:
                min_dist = dist
                best_item = i_id
            elif abs(dist - min_dist) <= 1e-9 and i_id < best_item:
                best_item = i_id
        expected_lines.append(f"{u_id},{best_item},{min_dist:.4f}")
    return "\n".join(expected_lines)


def read_normalized_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did you run the executable?"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    return "\n".join(line.strip() for line in content.splitlines() if line.strip())


def run_and_check(program, users, items):
    write_inputs(users, items)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [program],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_normalized_output()
    expected = expected_content(users, items)
    assert actual == expected, (
        f"Content of {OUTPUT} does not match expected output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )
    for line in actual.splitlines():
        assert re.fullmatch(r"-?\d+,-?\d+,-?\d+\.\d{4}", line), (
            f"Output line does not have the exact user_id,item_id,distance format: {line!r}"
        )


def test_c_source_exists():
    path = SOURCE
    assert os.path.isfile(path), f"C source file {path} is missing."
    result = subprocess.run(
        ["gcc", path, "-o", REBUILT, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"The submitted C source does not compile with gcc and -lm.\n{result.stderr}"
    )


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def test_recommendations_csv_exists_and_content():
    # Recreate the original fixture, execute the submitted artifact, and retain
    # the original verifier's exact expected-content assertion.
    write_inputs(INITIAL_USERS, INITIAL_ITEMS)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [EXECUTABLE], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{EXECUTABLE} failed on the original inputs.\n{result.stderr}"
    )

    path = OUTPUT
    assert os.path.isfile(path), f"Output file {path} is missing. Did you run the executable?"
    expected = expected_content(INITIAL_USERS, INITIAL_ITEMS)
    actual = read_normalized_output()
    assert actual == expected, (
        f"Content of {path} does not match expected output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def test_program_processes_runtime_csv_inputs():
    rng = random.SystemRandom()

    # Includes unsorted users, an exact-distance tie whose smaller item ID wins,
    # and values that require double rather than single precision.
    users_a = [
        (900, 0.0, 0.0),
        (777, 100000000.0, 100000000.0),
        (42, rng.uniform(-30, 30), rng.uniform(-30, 30)),
        (5, rng.uniform(-30, 30), rng.uniform(-30, 30)),
    ]
    items_a = [
        (88, 1.0, 0.0),
        (7, -1.0, 0.0),
        (10, 100000000.0, 100000001.1),
        (20, 100000001.0, 100000000.0),
        (301, rng.uniform(-30, 30), rng.uniform(-30, 30)),
        (119, rng.uniform(-30, 30), rng.uniform(-30, 30)),
    ]

    users_b = [
        (rng.randrange(1000, 2000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
        (rng.randrange(2000, 3000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
        (rng.randrange(3000, 4000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
    ]
    items_b = [
        (rng.randrange(5000, 6000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
        (rng.randrange(6000, 7000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
        (rng.randrange(7000, 8000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
        (rng.randrange(8000, 9000), rng.uniform(-100, 100), rng.uniform(-100, 100)),
    ]

    try:
        run_and_check(REBUILT, users_a, items_a)
        run_and_check(EXECUTABLE, users_b, items_b)
    finally:
        # Leave the requested output generated from the original input files.
        write_inputs(INITIAL_USERS, INITIAL_ITEMS)
        subprocess.run(
            [EXECUTABLE], cwd="/home/user", stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=10, check=False
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
