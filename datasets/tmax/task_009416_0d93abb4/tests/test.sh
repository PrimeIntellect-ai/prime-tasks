#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/optimize_k.sh"
DATA_PATH = "/home/user/decay_data.csv"
OUTPUT_PATH = "/home/user/model_params.txt"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."


def test_model_params_output():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    expected_result = "k=0.42"
    assert content == expected_result, (
        f"Expected {OUTPUT_PATH} to contain '{expected_result}', but found '{content}'."
    )


def expected_grid_result(rows):
    best_index = min(
        range(101),
        key=lambda i: sum(
            (y - 5.0 * math.exp(-(i / 100.0) * t)) ** 2 for t, y in rows
        ),
    )
    return f"k={best_index / 100.0:.2f}"


def test_script_performs_grid_search_on_data():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    random_index = secrets.choice([i for i in range(1, 100) if i != 42])
    test_indices = [0, 100, random_index]
    times = [0.0, 0.5, 1.25, 2.5, 4.0, 6.0]

    try:
        for source_index in test_indices:
            source_k = source_index / 100.0
            rendered_rows = []
            lines = ["t,y"]
            for t in times:
                rendered_y = float(f"{5.0 * math.exp(-source_k * t):.12f}")
                rendered_rows.append((t, rendered_y))
                lines.append(f"{t:.2f},{rendered_y:.12f}")

            with open(DATA_PATH, "w") as f:
                f.write("\n".join(lines) + "\n")

            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            result = subprocess.run(
                ["/bin/bash", SCRIPT_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"The script failed with exit code {result.returncode}. "
                f"stderr: {result.stderr}"
            )
            assert os.path.isfile(OUTPUT_PATH), (
                f"The script did not create {OUTPUT_PATH}."
            )

            with open(OUTPUT_PATH, "r") as f:
                actual = f.read().strip()
            expected = expected_grid_result(rendered_rows)
            assert actual == expected, (
                f"For the supplied decay data, expected '{expected}', but found "
                f"'{actual}'."
            )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
