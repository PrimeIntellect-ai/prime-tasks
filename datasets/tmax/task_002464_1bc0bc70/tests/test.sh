#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

PIPELINE = "/home/user/pipeline.sh"


def test_pipeline_exists_and_executable():
    assert os.path.isfile(PIPELINE), f"Script not found at {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Script {PIPELINE} is not executable"


def expected_output(dataset, rand_src):
    with open(dataset, "r") as f:
        lines = f.read().strip().split("\n")

    data = lines[1:]
    n_rows = len(data)
    train_n = n_rows * 70 // 100
    test_n = n_rows - train_n
    train_init = data[:train_n]
    test_set = data[train_n:]

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("\n".join(train_init) + "\n")
        temp_train_path = f.name

    try:
        cmd_shuf = [
            "shuf",
            f"--random-source={rand_src}",
            "-r",
            "-n",
            str(train_n),
            temp_train_path,
        ]
        res_shuf = subprocess.run(
            cmd_shuf, capture_output=True, text=True, check=True, timeout=15
        )
        train_boot = [row for row in res_shuf.stdout.strip().split("\n") if row]
    finally:
        os.remove(temp_train_path)

    sum_x = 0.0
    sum_y = 0.0
    for row in train_boot:
        parts = row.split(",")
        sum_x += float(parts[1])
        sum_y += float(parts[2])

    mean_x = sum_x / train_n
    mean_y = sum_y / train_n

    sum_prod = 0.0
    for row in test_set:
        if not row:
            continue
        parts = row.split(",")
        centered_x = float(parts[1]) - mean_x
        centered_y = float(parts[2]) - mean_y
        sum_prod += centered_x * centered_y

    return f"{sum_prod / (test_n - 1):.4f}"


def assert_pipeline_output(dataset, rand_src):
    expected = expected_output(dataset, rand_src)
    result = subprocess.run(
        [PIPELINE, dataset, rand_src],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )
    output = result.stdout.strip()
    assert output == expected, f"Expected covariance '{expected}', but got '{output}'"


def test_pipeline_output():
    dataset = "/home/user/dataset.csv"
    rand_src = "/home/user/fixed_rand"
    assert os.path.isfile(dataset), f"Dataset is missing: {dataset}"
    assert os.path.isfile(rand_src), f"Random source is missing: {rand_src}"
    assert_pipeline_output(dataset, rand_src)


def test_pipeline_on_varied_hidden_inputs():
    secure_random = random.SystemRandom()

    for case_number, n_rows in enumerate((13, 29, 83), start=1):
        with tempfile.TemporaryDirectory(prefix="pipeline_case_") as temp_dir:
            dataset = os.path.join(temp_dir, "input.csv")
            rand_src = os.path.join(temp_dir, "random.bin")

            with open(dataset, "w") as f:
                f.write("ID,Feature_X,Feature_Y\n")
                for row_number in range(1, n_rows + 1):
                    x = secure_random.uniform(-250.0, 400.0)
                    noise = secure_random.uniform(-90.0, 90.0)
                    slope = (-1.75, 0.65, 3.20)[case_number - 1]
                    offset = (120.0, -45.0, 8.0)[case_number - 1]
                    y = slope * x + offset + noise
                    f.write(f"{1000 * case_number + row_number},{x:.4f},{y:.4f}\n")

            with open(rand_src, "wb") as f:
                f.write(os.urandom(262144))

            assert_pipeline_output(dataset, rand_src)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
