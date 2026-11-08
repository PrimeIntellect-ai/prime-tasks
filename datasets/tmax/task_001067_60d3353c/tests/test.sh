#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
from collections import Counter

import pytest

HOME = "/home/user"
SCRIPT = f"{HOME}/process.sh"
OUTPUTS = [
    f"{HOME}/tokenized.txt",
    f"{HOME}/fold_1.txt",
    f"{HOME}/fold_2.txt",
    f"{HOME}/fold_3.txt",
    f"{HOME}/best_param.txt",
]

CANONICAL_RAW = """Data science is an interdisciplinary academic field.
Data science uses statistics, scientific computing, and algorithms.
Algorithms are used in data science to extract insights from noisy data.
Machine learning is a part of data science.
Statistics and machine learning are related to data science.
"""


def expected_for(raw_text):
    words = re.sub(r"[^a-z]", " ", raw_text.lower()).split()
    folds = [words[i::3] for i in range(3)]
    counts = Counter(folds[0] + folds[1])
    valid_thresholds = [
        threshold
        for threshold in range(1, 6)
        if sum(count >= threshold for count in counts.values()) == 4
    ]
    assert len(valid_thresholds) == 1, "Verifier test input must have one exact threshold"
    return words, folds, valid_thresholds[0]


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def read_lines(path):
    assert os.path.isfile(path), f"Failed: {path} does not exist or is not a file."
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().splitlines()


def assert_outputs(raw_text):
    expected_words, expected_folds, expected_threshold = expected_for(raw_text)

    actual_words = read_lines(f"{HOME}/tokenized.txt")
    assert actual_words == expected_words, "Failed: tokenized.txt does not match raw_data.txt tokenization."

    for number, expected_fold in enumerate(expected_folds, start=1):
        actual_fold = read_lines(f"{HOME}/fold_{number}.txt")
        assert actual_fold == expected_fold, (
            f"Failed: fold_{number}.txt is not the strict round-robin assignment."
        )

    param_path = f"{HOME}/best_param.txt"
    assert os.path.isfile(param_path), f"Failed: {param_path} does not exist or is not a file."
    with open(param_path, "r", encoding="utf-8") as handle:
        actual_param = handle.read().strip()
    assert actual_param == str(expected_threshold), (
        f"Failed: expected threshold {expected_threshold}, got {actual_param!r}."
    )


def run_script(raw_text):
    with open(f"{HOME}/raw_data.txt", "w", encoding="utf-8") as handle:
        handle.write(raw_text)
    for path in OUTPUTS:
        remove_path(path)

    result = subprocess.run(
        [SCRIPT],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"Failed: process.sh exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_outputs(raw_text)


@pytest.fixture(scope="session")
def generated_outputs():
    # Exercise the script on a second input with a different uniquely correct T.
    training = (
        ["alpha"] * 3
        + ["beta"] * 3
        + ["gamma"] * 3
        + ["delta"] * 3
        + ["epsilon"] * 2
        + ["zeta"]
    )
    validation = ["noise", "spare", "unused", "sample", "holdout", "verify", "check"]
    tokens = []
    validation_index = 0
    for index, word in enumerate(training):
        tokens.append(word.upper() if index % 2 == 0 else word)
        if index % 2 == 1:
            tokens.append(validation[validation_index])
            validation_index += 1
    alternate_raw = " ,!\n".join(tokens) + ".\n"

    run_script(alternate_raw)
    run_script(CANONICAL_RAW)
    return True


def test_process_script_exists_and_configured():
    script_path = "/home/user/process.sh"
    assert os.path.exists(script_path), f"Failed: {script_path} does not exist."
    assert os.path.isfile(script_path), f"Failed: {script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Failed: {script_path} is not executable."

    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read()
    assert "export OMP_NUM_THREADS=1" in content, f"Failed: 'export OMP_NUM_THREADS=1' not found in {script_path}."


def test_process_script_generates_correct_outputs(generated_outputs):
    assert generated_outputs


def test_tokenized_txt(generated_outputs):
    tokenized_path = "/home/user/tokenized.txt"
    assert os.path.exists(tokenized_path), f"Failed: {tokenized_path} does not exist."

    with open(tokenized_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 44, f"Failed: {tokenized_path} should contain exactly 44 words, but has {len(lines)}."
    for word in lines:
        assert word.isalpha() and word.islower(), f"Failed: Word '{word}' in {tokenized_path} is not strictly lowercase alphabetic."


def test_fold_sizes(generated_outputs):
    f1_path = "/home/user/fold_1.txt"
    f2_path = "/home/user/fold_2.txt"
    f3_path = "/home/user/fold_3.txt"

    assert os.path.exists(f1_path), f"Failed: {f1_path} does not exist."
    assert os.path.exists(f2_path), f"Failed: {f2_path} does not exist."
    assert os.path.exists(f3_path), f"Failed: {f3_path} does not exist."

    with open(f1_path, 'r', encoding='utf-8') as f:
        f1_lines = len([line for line in f if line.strip()])
    with open(f2_path, 'r', encoding='utf-8') as f:
        f2_lines = len([line for line in f if line.strip()])
    with open(f3_path, 'r', encoding='utf-8') as f:
        f3_lines = len([line for line in f if line.strip()])

    assert f1_lines == 15, f"Failed: {f1_path} should have 15 lines, got {f1_lines}."
    assert f2_lines == 15, f"Failed: {f2_path} should have 15 lines, got {f2_lines}."
    assert f3_lines == 14, f"Failed: {f3_path} should have 14 lines, got {f3_lines}."


def test_best_param(generated_outputs):
    param_path = "/home/user/best_param.txt"
    assert os.path.exists(param_path), f"Failed: {param_path} does not exist."

    with open(param_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content == "2", f"Failed: {param_path} should contain exactly '2', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
