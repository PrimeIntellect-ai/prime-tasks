#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import stat
import subprocess

SCRIPT_PATH = "/home/user/clean_and_correlate.sh"
SOURCE1_PATH = "/home/user/source1.csv"
SOURCE2_PATH = "/home/user/source2.csv"
CLEANED_CSV_PATH = "/home/user/cleaned_features.csv"
CORRELATION_TXT_PATH = "/home/user/correlation.txt"

ORIGINAL_SOURCE1 = """id,feature_x
1,10.0
2,20.0
3,
4,30.0
5,100.0
6,-10.0
7,15.0
8,-60.0
9,5.0
10,25.0
"""
ORIGINAL_SOURCE2 = """id,feature_y
4,28.0
1,12.0
2,18.0
3,25.0
5,10.0
6,-5.0
7,
8,-10.0
9,8.0
10,22.0
"""


def write_sources(source1, source2):
    with open(SOURCE1_PATH, "w") as f:
        f.write(source1)
    with open(SOURCE2_PATH, "w") as f:
        f.write(source2)


def run_script():
    for path in (CLEANED_CSV_PATH, CORRELATION_TXT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Script failed to execute. stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert os.path.isfile(CLEANED_CSV_PATH), (
        f"Output file {CLEANED_CSV_PATH} was not created"
    )
    assert os.path.isfile(CORRELATION_TXT_PATH), (
        f"Output file {CORRELATION_TXT_PATH} was not created"
    )

    with open(CLEANED_CSV_PATH, "r") as f:
        cleaned_lines = [line.strip() for line in f if line.strip()]
    with open(CORRELATION_TXT_PATH, "r") as f:
        correlation_val = f.read().strip()
    return cleaned_lines, correlation_val


def pearson_text(pairs):
    xs = [float(x) for x, _ in pairs]
    ys = [float(y) for _, y in pairs]
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(
        sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)
    )
    return f"{numerator / denominator:.3f}"


def make_dynamic_case(rng, direction):
    ids = [str(v) for v in rng.sample(range(100, 9999), 16)]
    xs = rng.sample(range(-35, 36), 6)
    included = []
    rows1 = []
    rows2 = []

    for row_id, x in zip(ids[:6], xs):
        y = direction * x + rng.randint(-9, 9)
        y = max(-45, min(45, y))
        x_text = f"{x}.0"
        y_text = f"{y}.0"
        included.append((x_text, y_text))
        rows1.append((row_id, x_text))
        rows2.append((row_id, y_text))

    boundary_pairs = [("50.0", "47.0"), ("-50.0", "-43.0")]
    for row_id, pair in zip(ids[6:8], boundary_pairs):
        included.append(pair)
        rows1.append((row_id, pair[0]))
        rows2.append((row_id, pair[1]))

    # Missing values in each source and all four strict outlier directions.
    rejected = [
        (ids[8], "", "3.0"),
        (ids[9], "4.0", ""),
        (ids[10], "50.01", "1.0"),
        (ids[11], "-50.01", "2.0"),
        (ids[12], "1.0", "50.01"),
        (ids[13], "2.0", "-50.01"),
    ]
    for row_id, x, y in rejected:
        rows1.append((row_id, x))
        rows2.append((row_id, y))

    # Unmatched records must not appear in the inner join.
    rows1.append((ids[14], "11.0"))
    rows2.append((ids[15], "12.0"))

    rng.shuffle(rows1)
    rng.shuffle(rows2)
    source1 = "id,feature_x\n" + "".join(f"{i},{x}\n" for i, x in rows1)
    source2 = "id,feature_y\n" + "".join(f"{i},{y}\n" for i, y in rows2)
    return source1, source2, included


def test_script_and_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable"

    old_source1 = open(SOURCE1_PATH, "rb").read()
    old_source2 = open(SOURCE2_PATH, "rb").read()
    try:
        # Preserve the original fixture assertions.
        write_sources(ORIGINAL_SOURCE1, ORIGINAL_SOURCE2)
        cleaned_lines, correlation_val = run_script()
        expected_lines = [
            "10.0,12.0",
            "25.0,22.0",
            "20.0,18.0",
            "30.0,28.0",
            "-10.0,-5.0",
            "5.0,8.0",
        ]
        assert sorted(cleaned_lines) == sorted(expected_lines), (
            f"Contents of {CLEANED_CSV_PATH} do not match expected pairs. "
            f"Expected: {sorted(expected_lines)}, Got: {sorted(cleaned_lines)}"
        )
        assert correlation_val == "0.992", (
            f"Correlation value incorrect. Expected '0.992', Got '{correlation_val}'"
        )

        # Exercise the submitted script on unpredictable, independently derived data.
        rng = random.SystemRandom()
        for direction in (1, -1):
            source1, source2, expected_pairs = make_dynamic_case(rng, direction)
            write_sources(source1, source2)
            cleaned_lines, correlation_val = run_script()
            expected_lines = [f"{x},{y}" for x, y in expected_pairs]
            assert sorted(cleaned_lines) == sorted(expected_lines), (
                "Dynamic join/filter result was incorrect. "
                f"Expected: {sorted(expected_lines)}, Got: {sorted(cleaned_lines)}"
            )
            expected_correlation = pearson_text(expected_pairs)
            assert correlation_val == expected_correlation, (
                "Dynamic Pearson correlation was incorrect. "
                f"Expected {expected_correlation}, Got {correlation_val}"
            )
    finally:
        with open(SOURCE1_PATH, "wb") as f:
            f.write(old_source1)
        with open(SOURCE2_PATH, "wb") as f:
            f.write(old_source2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
