#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/run_pipeline.sh"
DATASET_PATH = "/home/user/dataset.csv"
MODEL_PATH = "/home/user/model.py"
BOOTSTRAP_PATH = "/home/user/bootstrap_sample.csv"
METRIC_PATH = "/home/user/final_metric.txt"
CALL_LOG = "/tmp/model_calls.log"
HEADER = "col1,col2,col3,label"


def run_pipeline():
    return subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=60)


def read_lines(path):
    with open(path, "r") as f:
        return f.read().splitlines()


def assert_bootstrap_matches_dataset():
    assert os.path.isfile(BOOTSTRAP_PATH), f"Bootstrap sample {BOOTSTRAP_PATH} was not created."
    lines = read_lines(BOOTSTRAP_PATH)
    assert len(lines) == 50, f"Expected exactly 50 lines in bootstrap_sample.csv, found {len(lines)}."

    if lines:
        assert HEADER not in lines[0], "Bootstrap sample should not include the header."

    dataset_rows = read_lines(DATASET_PATH)[1:]
    allowed = set(dataset_rows)
    assert all(line in allowed for line in lines), \
        "Every bootstrap row must come from the data rows of dataset.csv."
    assert HEADER not in lines, "Bootstrap sample should not include the header."
    return lines


def test_run_pipeline_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_pipeline_execution_and_artifacts():
    result = run_pipeline()
    assert result.returncode == 0, f"Script failed to execute. Stderr: {result.stderr}"

    assert_bootstrap_matches_dataset()

    assert os.path.isfile(METRIC_PATH), f"Final metric file {METRIC_PATH} was not created."
    with open(METRIC_PATH, "r") as f:
        metric_content = f.read().strip()
    assert metric_content == "0.85", \
        f"Expected final metric to be '0.85', but got '{metric_content}'."


def test_cross_validation_routing_dynamic_metric_and_replacement_sampling():
    original_dataset = open(DATASET_PATH, "rb").read()
    original_model = open(MODEL_PATH, "rb").read()
    dataset_mode = stat.S_IMODE(os.stat(DATASET_PATH).st_mode)
    model_mode = stat.S_IMODE(os.stat(MODEL_PATH).st_mode)

    controlled_rows = [f"{i},{1000+i},{2000+i},{i % 2}" for i in range(1, 101)]
    controlled_dataset = HEADER + "\n" + "\n".join(controlled_rows) + "\n"

    validating_model = r'''import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--train", required=True)
parser.add_argument("--test", required=True)
parser.add_argument("--pca", action="store_true")
args = parser.parse_args()

with open("/home/user/dataset.csv", "r") as f:
    all_rows = f.read().splitlines()[1:]
with open(args.train, "r") as f:
    train_rows = f.read().splitlines()
with open(args.test, "r") as f:
    test_rows = f.read().splitlines()

accuracies = ["0.61", "0.72", "0.83", "0.94", "0.55"]
matched_fold = None
for fold in range(5):
    start = fold * 20
    expected_test = all_rows[start:start + 20]
    expected_train = all_rows[:start] + all_rows[start + 20:]
    if test_rows == expected_test and train_rows == expected_train:
        matched_fold = fold
        break

if not args.pca or matched_fold is None:
    print("Invalid cross-validation routing", file=sys.stderr)
    sys.exit(3)

with open("/tmp/model_calls.log", "a") as log:
    log.write(str(matched_fold + 1) + "\n")
print("Accuracy: " + accuracies[matched_fold])
'''

    saw_duplicate = False
    try:
        with open(DATASET_PATH, "w") as f:
            f.write(controlled_dataset)
        with open(MODEL_PATH, "w") as f:
            f.write(validating_model)

        # Two independent executions make a no-duplicate result from genuine
        # sampling with replacement vanishingly unlikely, while reliably
        # rejecting sampling without replacement.
        for _ in range(2):
            if os.path.exists(CALL_LOG):
                os.remove(CALL_LOG)

            result = run_pipeline()
            assert result.returncode == 0, \
                f"Script failed under validation inputs. Stderr: {result.stderr}"

            sample = assert_bootstrap_matches_dataset()
            if any(count > 1 for count in Counter(sample).values()):
                saw_duplicate = True

            assert os.path.isfile(CALL_LOG), "The model was not executed."
            calls = read_lines(CALL_LOG)
            assert len(calls) == 5, \
                f"Expected exactly 5 model executions, found {len(calls)}."
            assert sorted(calls) == ["1", "2", "3", "4", "5"], \
                f"Expected one correctly routed execution for each fold, got {calls}."

            assert os.path.isfile(METRIC_PATH), \
                f"Final metric file {METRIC_PATH} was not created."
            with open(METRIC_PATH, "r") as f:
                metric_content = f.read().strip()
            assert metric_content == "0.73", \
                f"Expected average of dynamic fold accuracies to be '0.73', got '{metric_content}'."

        assert saw_duplicate, \
            "Bootstrap samples showed no repeated row; sampling appears to be without replacement."
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original_dataset)
        with open(MODEL_PATH, "wb") as f:
            f.write(original_model)
        os.chmod(DATASET_PATH, dataset_mode)
        os.chmod(MODEL_PATH, model_mode)
        if os.path.exists(CALL_LOG):
            os.remove(CALL_LOG)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
