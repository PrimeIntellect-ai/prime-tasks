#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess

import pytest

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "data.csv")
POSTERIOR_PATH = os.path.join(HOME, "posterior.txt")
PROCESSOR_PATH = os.path.join(HOME, "processor")
SOURCE_PATH = os.path.join(HOME, "processor.c")
VERIFIER_PROCESSOR = "/tmp/verifier_processor"


def compute_expected_posterior(csv_path):
    if not os.path.exists(csv_path):
        return None

    sum_prec = 1.0
    sum_prec_x = 0.0
    sum_prec_y = 0.0

    with open(csv_path, "r") as f:
        lines = f.readlines()

    if not lines:
        return None

    # Skip header
    for line in lines[1:]:
        parts = line.strip().split(",")
        if len(parts) != 4:
            continue
        try:
            sensor_id = int(parts[0])
            x = float(parts[1])
            y = float(parts[2])
            variance = float(parts[3])
        except ValueError:
            continue

        if variance <= 0:
            continue

        prec = 1.0 / variance
        sum_prec += prec
        sum_prec_x += prec * x
        sum_prec_y += prec * y

    post_x = sum_prec_x / sum_prec
    post_y = sum_prec_y / sum_prec
    return f"{post_x:.4f},{post_y:.4f}"


def expected_from_rows(rows):
    total_precision = 1.0
    weighted_x = 0.0
    weighted_y = 0.0
    for _, x, y, variance in rows:
        precision = 1.0 / variance
        total_precision += precision
        weighted_x += precision * x
        weighted_y += precision * y
    return f"{weighted_x / total_precision:.4f},{weighted_y / total_precision:.4f}"


def run(command):
    return subprocess.run(
        command,
        cwd=HOME,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def assert_output(expected):
    assert os.path.isfile(POSTERIOR_PATH), "processor did not create posterior.txt"
    with open(POSTERIOR_PATH, "r", newline="") as f:
        actual = f.read()
    assert actual in (expected, expected + "\n"), (
        f"Output in posterior.txt is incorrect. Expected exactly '{expected}', got {actual!r}."
    )


@pytest.fixture(scope="session", autouse=True)
def build_and_restore_pipeline():
    assert os.path.isfile(CSV_PATH), "/home/user/data.csv is missing."
    original_data = open(CSV_PATH, "rb").read()

    try:
        if os.path.lexists(PROCESSOR_PATH):
            os.remove(PROCESSOR_PATH)
        if os.path.lexists(POSTERIOR_PATH):
            os.remove(POSTERIOR_PATH)

        # Exercise the required Makefile targets from a state with no executable.
        run(["make", "all"])
        assert os.path.isfile(PROCESSOR_PATH), "make all did not create processor"
        assert os.access(PROCESSOR_PATH, os.X_OK), "processor is not executable"
        with open(PROCESSOR_PATH, "rb") as f:
            assert f.read(4) == b"\x7fELF", "make all did not produce a compiled executable"
        run(["make", "run"])

        # Independently compile processor.c so behavior of the submitted C source is tested too.
        if os.path.lexists(VERIFIER_PROCESSOR):
            os.remove(VERIFIER_PROCESSOR)
        run(["gcc", SOURCE_PATH, "-o", VERIFIER_PROCESSOR, "-lm"])
        assert os.path.isfile(VERIFIER_PROCESSOR)
        assert os.access(VERIFIER_PROCESSOR, os.X_OK)
        yield
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_data)
        try:
            run(["make", "run"])
        except Exception:
            pass
        if os.path.lexists(VERIFIER_PROCESSOR):
            os.remove(VERIFIER_PROCESSOR)


def test_files_exist():
    assert os.path.isfile("/home/user/processor.c"), "/home/user/processor.c is missing."
    assert os.path.isfile("/home/user/Makefile"), "/home/user/Makefile is missing."
    assert os.path.isfile("/home/user/processor"), "The executable /home/user/processor is missing. Did 'make all' run successfully?"
    assert os.path.isfile("/home/user/posterior.txt"), "/home/user/posterior.txt is missing. Did 'make run' execute successfully?"


def test_posterior_output():
    expected_output = compute_expected_posterior(CSV_PATH)
    assert expected_output is not None, "Could not compute expected posterior from data.csv."

    with open(POSTERIOR_PATH, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, f"Output in posterior.txt is incorrect. Expected '{expected_output}', got '{actual_output}'."


def test_c_source_and_make_pipeline_on_unpredictable_inputs():
    rng = secrets.SystemRandom()

    for trial in range(3):
        rows = []
        csv_lines = ["sensor_id,x,y,variance"]
        for index in range(rng.randint(3, 7)):
            sensor_id = trial * 100 + index + 1
            x = rng.randint(-300, 300) / 10.0
            y = rng.randint(-300, 300) / 10.0
            variance = rng.choice([0.25, 0.5, 1.0, 2.0, 4.0])
            rows.append((sensor_id, x, y, variance))
            csv_lines.append(f"{sensor_id},{x},{y},{variance}")

        # These malformed rows must be ignored completely.
        csv_lines.extend([
            "bad,900,900,1",
            "901,900,900,0",
            "902,900,900,-2",
            "903,900,900,1junk",
            "904,900,900",
            "905,900,900,1,extra",
            "906,,900,1",
            "907,not-a-number,900,1",
        ])
        expected = expected_from_rows(rows)
        with open(CSV_PATH, "w", newline="") as f:
            f.write("\n".join(csv_lines) + "\n")

        # Run the independently compiled submitted C source.
        if os.path.lexists(POSTERIOR_PATH):
            os.remove(POSTERIOR_PATH)
        run([VERIFIER_PROCESSOR])
        assert_output(expected)

        # Also exercise the submitted Makefile's run target on the same unknown input.
        if os.path.lexists(POSTERIOR_PATH):
            os.remove(POSTERIOR_PATH)
        run(["make", "run"])
        assert_output(expected)


def test_all_invalid_rows_fall_back_to_prior():
    contents = """sensor_id,x,y,variance
bad,1,2,1
1,1,2,0
2,1,2,-1
3,1,2,broken
4,1,2
5,1,2,1,extra
"""
    with open(CSV_PATH, "w", newline="") as f:
        f.write(contents)

    if os.path.lexists(POSTERIOR_PATH):
        os.remove(POSTERIOR_PATH)
    run([VERIFIER_PROCESSOR])
    assert_output("0.0000,0.0000")

    if os.path.lexists(POSTERIOR_PATH):
        os.remove(POSTERIOR_PATH)
    run(["make", "run"])
    assert_output("0.0000,0.0000")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
