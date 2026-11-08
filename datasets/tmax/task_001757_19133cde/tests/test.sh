#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SOURCE_PATH = "/home/user/process.c"
DATA_PATH = "/home/user/sensor_data.csv"
STATS_PATH = "/home/user/clean_stats.txt"
BINARY_PATH = "/tmp/process_submission"


def run_program():
    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"The compiled C program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_content_from_pairs(pairs):
    valid = [(x, y) for x, y in pairs if -50.0 <= x <= 50.0 and -50.0 <= y <= 50.0]
    n = len(valid)
    assert n > 1, "Not enough valid data points to compute statistics."

    valid_x = [x for x, _ in valid]
    valid_y = [y for _, y in valid]
    mean_x = sum(valid_x) / n
    mean_y = sum(valid_y) / n
    cov_xx = sum((x - mean_x) ** 2 for x in valid_x) / (n - 1)
    cov_yy = sum((y - mean_y) ** 2 for y in valid_y) / (n - 1)
    cov_xy = sum((x - mean_x) * (y - mean_y) for x, y in valid) / (n - 1)
    m = cov_xy / cov_xx
    c = mean_y - m * mean_x

    return "\n".join([
        f"Valid Count: {n}",
        f"Mean X: {mean_x:.4f}",
        f"Mean Y: {mean_y:.4f}",
        f"Cov(X,X): {cov_xx:.4f}",
        f"Cov(Y,Y): {cov_yy:.4f}",
        f"Cov(X,Y): {cov_xy:.4f}",
        f"Slope (m): {m:.4f}",
        f"Intercept (c): {c:.4f}",
    ])


def test_process_c_compiles_and_generates_output():
    assert os.path.isfile(SOURCE_PATH), f"The required C source file {SOURCE_PATH} is missing."

    if os.path.exists(BINARY_PATH):
        os.remove(BINARY_PATH)
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-lm", "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SOURCE_PATH} did not compile successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce an executable program."

    if os.path.exists(STATS_PATH):
        os.remove(STATS_PATH)
    run_program()
    assert os.path.isfile(STATS_PATH), (
        f"Running the compiled C program did not generate {STATS_PATH}."
    )


def test_clean_stats_exists():
    """
    Check if the clean_stats.txt file was generated.
    """
    file_path = "/home/user/clean_stats.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. Did the C program run and generate it?"


def test_clean_stats_content():
    """
    Verify the contents of clean_stats.txt by recomputing the expected
    values from the actual sensor_data.csv file.
    """
    data_path = "/home/user/sensor_data.csv"
    stats_path = "/home/user/clean_stats.txt"

    assert os.path.isfile(data_path), f"The file {data_path} is missing."
    assert os.path.isfile(stats_path), f"The file {stats_path} is missing."

    valid_x = []
    valid_y = []

    # Read and filter data based on requirements
    with open(data_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) == 2:
                x, y = float(parts[0]), float(parts[1])
                # Filter out corrupted rows
                if -50.0 <= x <= 50.0 and -50.0 <= y <= 50.0:
                    valid_x.append(x)
                    valid_y.append(y)

    n = len(valid_x)
    assert n > 1, "Not enough valid data points to compute statistics."

    # Compute statistics
    mean_x = sum(valid_x) / n
    mean_y = sum(valid_y) / n

    cov_xx = sum((x - mean_x)**2 for x in valid_x) / (n - 1)
    cov_yy = sum((y - mean_y)**2 for y in valid_y) / (n - 1)
    cov_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(valid_x, valid_y)) / (n - 1)

    m = cov_xy / cov_xx
    c = mean_y - m * mean_x

    # Format expected output
    expected_lines = [
        f"Valid Count: {n}",
        f"Mean X: {mean_x:.4f}",
        f"Mean Y: {mean_y:.4f}",
        f"Cov(X,X): {cov_xx:.4f}",
        f"Cov(Y,Y): {cov_yy:.4f}",
        f"Cov(X,Y): {cov_xy:.4f}",
        f"Slope (m): {m:.4f}",
        f"Intercept (c): {c:.4f}"
    ]
    expected_content = "\n".join(expected_lines)

    # Read actual output
    with open(stats_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of {stats_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )


def test_program_reads_and_processes_sensor_data():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    shift = secrets.randbelow(9) - 4
    slope = secrets.choice([-3, -2, -1, 1, 2, 3])
    intercept = secrets.randbelow(11) - 5
    xs = [shift + d for d in (-5, -2, 0, 1, 3, 5)]
    pairs = [(float(x), float(slope * x + intercept)) for x in xs]
    pairs.extend([
        (-50.0, 10.0),
        (50.0, -10.0),
        (51.0, 1.0),
        (-50.1, 2.0),
        (3.0, 50.1),
        (-999.0, 4.0),
    ])
    test_data = "".join(f"{x},{y}\n" for x, y in pairs).encode("ascii")
    expected = expected_content_from_pairs(pairs)

    try:
        with open(DATA_PATH, "wb") as f:
            f.write(test_data)
        if os.path.exists(STATS_PATH):
            os.remove(STATS_PATH)
        run_program()
        assert os.path.isfile(STATS_PATH), "The program did not generate clean_stats.txt for new input data."
        with open(DATA_PATH, "rb") as f:
            assert f.read() == test_data, "The program unexpectedly modified sensor_data.csv."
        with open(STATS_PATH, "r") as f:
            actual = f.read().strip()
        assert actual == expected, (
            "The compiled program did not correctly process a verifier-provided dataset.\n"
            f"Expected:\n{expected}\n\nActual:\n{actual}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if os.path.exists(STATS_PATH):
            os.remove(STATS_PATH)
        run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
