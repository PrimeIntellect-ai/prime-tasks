#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess


def run_pipeline():
    subprocess.run(
        ["/home/user/pipeline.sh"],
        cwd="/home/user",
        check=True,
        timeout=15,
    )


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    # Require the submitted script itself to reproduce the checked outputs.
    for output_path in ("/home/user/train_processed.csv", "/home/user/test_processed.csv"):
        if os.path.lexists(output_path):
            os.remove(output_path)
    run_pipeline()


def test_train_processed_output():
    train_path = "/home/user/train_processed.csv"
    assert os.path.exists(train_path), f"Output file {train_path} does not exist."
    assert os.path.isfile(train_path), f"Path {train_path} is not a file."

    expected_train = [
        "1|hello world|0|22",
        "2|bash is great for text processing|1|22",
        "3|data science in the shell|1|22",
        "5|another valid row|0|22",
        "6|short text|1|22",
        "7|a very very long text string for testing|0|22"
    ]

    with open(train_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_train, f"Content of {train_path} does not match expected output. Got: {lines}"


def test_test_processed_output():
    test_path = "/home/user/test_processed.csv"
    assert os.path.exists(test_path), f"Output file {test_path} does not exist."
    assert os.path.isfile(test_path), f"Path {test_path} is not a file."

    expected_test = [
        "8|testing dataset|1|22",
        "9|more data|0|22",
        "10|final row|1|22"
    ]

    with open(test_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_test, f"Content of {test_path} does not match expected output. Got: {lines}"


def test_pipeline_on_altered_input():
    rng = random.SystemRandom()
    lengths = [5, 8, 11, 14, 17, 20, 41, 44, 47]

    def make_text(length, offset):
        letters = [rng.choice(string.ascii_lowercase) for _ in range(length)]
        return "".join(
            ch.upper() if (index + offset) % 3 == 0 else ch
            for index, ch in enumerate(letters)
        )

    valid_lines = [
        f"dyn{i + 1}|{make_text(length, i)}|{i % 2}"
        for i, length in enumerate(lengths)
    ]
    input_lines = [
        valid_lines[0],
        "malformed row without delimiters",
        valid_lines[1],
        "too|many|columns|in|this|row",
        valid_lines[2],
        valid_lines[3],
        "only|two",
        valid_lines[4],
        valid_lines[5],
        valid_lines[6],
        valid_lines[7],
        valid_lines[8],
    ]

    dataset_content = "\n".join(input_lines) + "\n"
    with open("/home/user/dataset.csv", "w") as f:
        f.write(dataset_content)

    # Independently derive the required result from the altered input.
    parsed = []
    for line in dataset_content.splitlines():
        fields = line.split("|")
        if len(fields) == 3:
            parsed.append((fields[0], fields[1].lower(), fields[2]))

    train = parsed[:6]
    test = parsed[6:]
    training_average = sum(len(row[1]) for row in train) // len(train)
    whole_dataset_average = sum(len(row[1]) for row in parsed) // len(parsed)
    assert training_average != whole_dataset_average

    expected_train = ["|".join((*row, str(training_average))) for row in train]
    expected_test = ["|".join((*row, str(training_average))) for row in test]

    for output_path in ("/home/user/train_processed.csv", "/home/user/test_processed.csv"):
        if os.path.lexists(output_path):
            os.remove(output_path)

    run_pipeline()

    train_path = "/home/user/train_processed.csv"
    test_path = "/home/user/test_processed.csv"
    assert os.path.exists(train_path), f"Output file {train_path} does not exist after rerun."
    assert os.path.isfile(train_path), f"Path {train_path} is not a file."
    assert os.path.exists(test_path), f"Output file {test_path} does not exist after rerun."
    assert os.path.isfile(test_path), f"Path {test_path} is not a file."

    with open(train_path, "r") as f:
        actual_train = f.read().splitlines()
    with open(test_path, "r") as f:
        actual_test = f.read().splitlines()

    assert actual_train == expected_train, (
        f"Pipeline failed on altered training input. Got: {actual_train}"
    )
    assert actual_test == expected_test, (
        f"Pipeline failed on altered testing input. Got: {actual_test}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
