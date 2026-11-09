#!/bin/bash
mkdir -p /logs/verifier
reward=0

if /usr/bin/awk 'BEGIN {
  srand(42);
  for(i=1; i<=1000; i++) {
    col1 = i;
    col2 = int(rand() * 100);
    col3 = int(rand() * 1000);
    col4 = int(rand() * 2);
    col5 = "CORRUPT";
    if (i == 950) { col3 = 9999; }
    if (i == 150) { col3 = -500; }
    print col1 "," col2 "," col3 "," col4 "," col5;
  }
}' > /tmp/reference_dataset.raw && \
/usr/bin/awk 'BEGIN { FS=OFS="," } {
  if (NR == 900) $3 = 5000;
  if (NR == 901) $3 = -1000;
  if (NR == 100) $3 = 4000;
  if (NR == 101) $3 = -500;
  print $0
}' /tmp/reference_dataset.raw > /tmp/reference_dataset.csv; then

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

with open("/tmp/reference_dataset.csv", "rb") as f:
    EXPECTED_DATASET_BYTES = f.read()

@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    dataset_path = "/home/user/dataset.csv"
    pipeline_path = "/home/user/pipeline.sh"

    assert os.path.isfile(dataset_path), f"Original dataset {dataset_path} is missing."
    with open(dataset_path, "rb") as f:
        assert f.read() == EXPECTED_DATASET_BYTES, "The supplied dataset was modified or replaced."

    assert os.path.isfile(pipeline_path), f"Required pipeline {pipeline_path} is missing or is not a regular file."

    for output_path in ("/home/user/train_processed.csv", "/home/user/test_processed.csv"):
        try:
            os.remove(output_path)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            ["/bin/bash", pipeline_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("pipeline.sh did not finish within 30 seconds.")

    assert result.returncode == 0, (
        f"pipeline.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )

    assert os.path.isfile(dataset_path), "pipeline.sh removed the supplied dataset."
    with open(dataset_path, "rb") as f:
        assert f.read() == EXPECTED_DATASET_BYTES, "pipeline.sh modified or replaced the supplied dataset."

def test_processed_files_exist():
    assert os.path.isfile("/home/user/train_processed.csv"), "/home/user/train_processed.csv is missing. Did the script run and save the output?"
    assert os.path.isfile("/home/user/test_processed.csv"), "/home/user/test_processed.csv is missing. Did the script run and save the output?"

def test_row_counts():
    with open("/home/user/train_processed.csv", "r") as f:
        train_lines = f.readlines()
    with open("/home/user/test_processed.csv", "r") as f:
        test_lines = f.readlines()

    assert len(train_lines) == 800, f"Expected exactly 800 rows in train_processed.csv, but found {len(train_lines)}."
    assert len(test_lines) == 200, f"Expected exactly 200 rows in test_processed.csv, but found {len(test_lines)}."

def test_data_processing_correctness():
    dataset_path = "/home/user/dataset.csv"
    assert os.path.isfile(dataset_path), f"Original dataset {dataset_path} is missing."

    with open(dataset_path, "r") as f:
        dataset_lines = [line.strip().split(',') for line in f.readlines() if line.strip()]

    assert len(dataset_lines) == 1000, "Original dataset does not have 1000 rows. It might have been modified incorrectly."

    train_data = dataset_lines[:800]
    test_data = dataset_lines[800:]

    # Calculate min and max strictly from the training set
    train_c3 = [float(row[2]) for row in train_data]
    train_min = min(train_c3)
    train_max = max(train_c3)

    def process_row(row):
        # Scale using train min/max and drop 5th column
        scaled_val = (float(row[2]) - train_min) / (train_max - train_min)
        # Format to 4 decimal places
        scaled_str = f"{scaled_val:.4f}"
        return f"{row[0]},{row[1]},{scaled_str},{row[3]}\n"

    expected_train = [process_row(row) for row in train_data]
    expected_test = [process_row(row) for row in test_data]

    with open("/home/user/train_processed.csv", "r") as f:
        actual_train = f.readlines()

    with open("/home/user/test_processed.csv", "r") as f:
        actual_test = f.readlines()

    # Verify Train Set
    for i, (exp, act) in enumerate(zip(expected_train, actual_train)):
        act_cols = act.strip().split(',')
        assert len(act_cols) == 4, f"Train row {i+1} has {len(act_cols)} columns instead of 4. Column 5 was likely not dropped."
        assert act == exp, f"Train row {i+1} mismatch.\nExpected: {exp.strip()}\nGot:      {act.strip()}"

    # Verify Test Set
    for i, (exp, act) in enumerate(zip(expected_test, actual_test)):
        act_cols = act.strip().split(',')
        assert len(act_cols) == 4, f"Test row {i+1} has {len(act_cols)} columns instead of 4. Column 5 was likely not dropped."
        assert act == exp, f"Test row {i+1} mismatch.\nExpected: {exp.strip()}\nGot:      {act.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
fi

echo "$reward" > /logs/verifier/reward.txt
