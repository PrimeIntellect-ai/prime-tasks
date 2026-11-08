#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

C_PATH = "/home/user/bootstrap.c"
CSV_PATH = "/home/user/sensor_data.csv"
OUT_PATH = "/home/user/ci_output.txt"
BIN_PATH = "/tmp/bootstrap_submission"


def expected_output(csv_text):
    lines = [line for line in csv_text.splitlines()[1:] if line.strip()]
    x_vals = []
    y_vals = []
    for line in lines:
        x, y = line.strip().split(",")
        x_vals.append(float(x))
        y_vals.append(float(y))

    assert len(x_vals) == 100, f"Expected exactly 100 data points in {CSV_PATH}, found {len(x_vals)}."

    state = 42

    def get_random_index(num_points=100):
        nonlocal state
        state = (1103515245 * state + 12345) % 2147483648
        return state % num_points

    slopes = []
    for _ in range(10000):
        samp_x = []
        samp_y = []
        for _ in range(100):
            idx = get_random_index(100)
            samp_x.append(x_vals[idx])
            samp_y.append(y_vals[idx])

        n = 100
        sum_x = sum(samp_x)
        sum_y = sum(samp_y)
        sum_xy = sum(x * y for x, y in zip(samp_x, samp_y))
        sum_xx = sum(x * x for x in samp_x)
        denominator = n * sum_xx - sum_x**2
        if denominator == 0:
            slope = 0.0
        else:
            slope = (n * sum_xy - sum_x * sum_y) / denominator
        slopes.append(slope)

    slopes.sort()
    return f"Slope CI: [{slopes[249]:.4f}, {slopes[9749]:.4f}]"


def run_program():
    if os.path.exists(OUT_PATH):
        os.remove(OUT_PATH)
    result = subprocess.run([BIN_PATH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.exists(OUT_PATH), f"The program did not create {OUT_PATH}."
    assert os.path.isfile(OUT_PATH), f"{OUT_PATH} is not a file."
    with open(OUT_PATH, "r") as f:
        return f.read().strip()


def test_00_compile_and_execute_program():
    assert os.path.exists(C_PATH), f"The C source file {C_PATH} does not exist."
    assert os.path.isfile(C_PATH), f"{C_PATH} is not a file."

    compile_result = subprocess.run(
        ["gcc", C_PATH, "-o", BIN_PATH, "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {C_PATH}. stdout: {compile_result.stdout!r}; "
        f"stderr: {compile_result.stderr!r}"
    )

    with open(CSV_PATH, "r") as f:
        original_csv = f.read()

    alternate_lines = ["x,y"]
    for x in range(100):
        noise = (((x * 73 + 19) % 41) - 20) * 0.137
        y = -0.85 * x + 12.0 + noise
        alternate_lines.append(f"{x},{y:.4f}")
    alternate_csv = "\n".join(alternate_lines) + "\n"

    try:
        with open(CSV_PATH, "w") as f:
            f.write(alternate_csv)
        actual = run_program()
        assert actual == expected_output(alternate_csv), (
            "The compiled program produced an incorrect result when run on valid "
            "alternate sensor data."
        )
    finally:
        with open(CSV_PATH, "w") as f:
            f.write(original_csv)
        restored_actual = run_program()

    assert restored_actual == expected_output(original_csv), (
        "The compiled program produced an incorrect result for the original sensor data."
    )


def test_c_file_exists():
    assert os.path.exists(C_PATH), f"The C source file {C_PATH} does not exist."
    assert os.path.isfile(C_PATH), f"{C_PATH} is not a file."


def test_output_file_exists():
    assert os.path.exists(OUT_PATH), f"The output file {OUT_PATH} does not exist."
    assert os.path.isfile(OUT_PATH), f"{OUT_PATH} is not a file."


def test_ci_output_content():
    assert os.path.exists(CSV_PATH), f"{CSV_PATH} is missing."
    with open(CSV_PATH, "r") as f:
        csv_text = f.read()
    with open(OUT_PATH, "r") as f:
        actual_output = f.read().strip()

    wanted = expected_output(csv_text)
    assert actual_output == wanted, (
        f"Content of {OUT_PATH} is incorrect. Expected '{wanted}', "
        f"but got '{actual_output}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
