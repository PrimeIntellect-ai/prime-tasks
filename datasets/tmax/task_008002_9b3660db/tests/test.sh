#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess
from collections import Counter

import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold

SCRIPT_PATH = "/home/user/analyze.sh"
OUTPUT_PATHS = [
    "/home/user/joined.csv",
    "/home/user/sample_1.csv",
    "/home/user/sample_2.csv",
    "/home/user/sample_3.csv",
    "/home/user/best_alphas.txt",
]


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."

    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_join_rows():
    with open("/home/user/data/users.csv", newline="") as f:
        users = list(csv.DictReader(f))
    with open("/home/user/data/transactions.csv", newline="") as f:
        transactions = list(csv.DictReader(f))

    tx_by_user = {}
    for row in transactions:
        tx_by_user.setdefault(row["user_id"], []).append(row)

    rows = []
    for user in users:
        for tx in tx_by_user.get(user["user_id"], []):
            rows.append(
                f'{user["user_id"]},{user["age"]},{user["income"]},{tx["spend"]}'
            )
    return rows


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return f.read().strip().split("\n")


def test_analyze_script_exists_and_executable():
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_joined_csv():
    file_path = "/home/user/joined.csv"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    lines = read_nonempty_lines(file_path)

    assert len(lines) == 16, f"Expected 16 lines in {file_path} (1 header + 15 data rows), found {len(lines)}."
    assert lines[0] == "user_id,age,income,spend", f"Incorrect header in {file_path}."

    # Preserve the original specific-row assertion.
    has_row_1 = any(line == "1,25,50000,1000" for line in lines)
    assert has_row_1, f"Expected joined data '1,25,50000,1000' not found in {file_path}."

    # Validate the complete inner join, including multiplicities.
    expected = expected_join_rows()
    assert Counter(lines[1:]) == Counter(expected), (
        f"{file_path} is not the complete inner join of users.csv and transactions.csv."
    )


@pytest.mark.parametrize("sample_num", [1, 2, 3])
def test_sample_csvs(sample_num):
    file_path = f"/home/user/sample_{sample_num}.csv"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    lines = read_nonempty_lines(file_path)

    assert len(lines) == 16, f"Expected 16 lines in {file_path} (1 header + 15 data rows), found {len(lines)}."
    assert lines[0] == "user_id,age,income,spend", f"Incorrect header in {file_path}."

    # Preserve the original four-column assertion.
    for i, line in enumerate(lines[1:], start=2):
        cols = line.split(",")
        assert len(cols) == 4, f"Row {i} in {file_path} does not have exactly 4 columns."

    # Every bootstrap draw must come from the joined data.
    allowed_rows = set(expected_join_rows())
    for i, line in enumerate(lines[1:], start=2):
        assert line in allowed_rows, (
            f"Row {i} in {file_path} was not drawn from joined.csv: {line!r}"
        )


def test_bootstrap_replacement_and_independence():
    samples = [read_nonempty_lines(f"/home/user/sample_{i}.csv")[1:] for i in (1, 2, 3)]
    counters = [Counter(sample) for sample in samples]

    # Independently generated samples must not simply be copies of one another.
    assert len({tuple(sorted(counter.items())) for counter in counters}) == 3, (
        "The three bootstrap samples are not independent; two or more have identical draws."
    )

    # Across three size-15 bootstrap samples, require observable replacement.
    # A genuine bootstrap fails this only if all three happen to be permutations,
    # whose probability is negligible; this catches shuffling without replacement.
    assert any(len(set(sample)) < len(sample) for sample in samples), (
        "No sample contains a repeated draw; the data appears to have been sampled without replacement."
    )


def test_best_alphas_txt():
    file_path = "/home/user/best_alphas.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    lines = read_nonempty_lines(file_path)

    assert len(lines) == 3, f"Expected exactly 3 lines in {file_path}, found {len(lines)}."

    expected_pattern = r"^Sample [1-3]: (0\.1|1\.0|10\.0)$"
    samples_found = set()
    reported = {}

    for i, line in enumerate(lines):
        match = re.match(expected_pattern, line)
        assert match, f"Line {i+1} in {file_path} does not match expected format: '{line}'"
        sample_name, value = line.split(": ")
        samples_found.add(sample_name)
        reported[int(sample_name.split()[1])] = float(value)

    assert samples_found == {"Sample 1", "Sample 2", "Sample 3"}, f"Missing or duplicate samples in {file_path}."

    # Recompute GridSearchCV from each actual bootstrap sample rather than
    # trusting that any allowed alpha is correct.
    for sample_num in (1, 2, 3):
        frame = pd.read_csv(f"/home/user/sample_{sample_num}.csv")
        X = frame[["age", "income"]]
        y = frame["spend"]
        cv = KFold(n_splits=3, shuffle=True, random_state=42)
        search = GridSearchCV(
            Ridge(),
            {"alpha": [0.1, 1.0, 10.0]},
            cv=cv,
        )
        search.fit(X, y)
        expected_alpha = float(search.best_params_["alpha"])
        assert reported[sample_num] == expected_alpha, (
            f"Sample {sample_num} reports alpha {reported[sample_num]}, "
            f"but GridSearchCV gives {expected_alpha}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
