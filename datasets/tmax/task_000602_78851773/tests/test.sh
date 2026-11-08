#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

SCRIPT_PATH = "/home/user/clean_pipeline.sh"
RAW_PATH = "/home/user/raw_chats.txt"
OUTPUT_PATH = "/home/user/cleaned_chats.txt"


def pristine_raw_data():
    data = (
        "   HELLO world  user@example.com  \n"
        "123-456-7890 is my number\n"
        "Duplicate line\n"
        "Duplicate line\n"
        "   another line with 999-999-9999 and test@test.com\n"
    )
    data += "".join(
        f"Line {i} with some extra   spaces and maybe email{i}@domain.com and phone 123-456-7890\n"
        for i in range(1, 10001)
    )
    return data


def expected_output(raw_data):
    email_re = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
    phone_re = re.compile(r"\d{3}-\d{3}-\d{4}")

    seen = set()
    lengths = []
    result = []

    for line in raw_data.splitlines():
        content = line.lower()
        content = re.sub(r" +", " ", content).strip()
        content = email_re.sub("<EMAIL>", content)
        content = phone_re.sub("<PHONE>", content)

        if content in seen:
            continue
        seen.add(content)

        previous = lengths[-5:]
        average = sum(previous) / len(previous) if previous else 0.0
        result.append(f"{content},{average:.1f}")
        lengths.append(len(content))

    return result


def test_pipeline_script_exists():
    path = SCRIPT_PATH
    assert os.path.exists(path), f"Missing pipeline script: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"


def test_pipeline_execution_and_exact_processing():
    raw_data = pristine_raw_data()
    with open(RAW_PATH, "w", encoding="utf-8", newline="") as handle:
        handle.write(raw_data)

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        result = subprocess.run(
            ["/bin/bash", SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Pipeline timed out after 60 seconds: {exc}")

    assert result.returncode == 0, (
        f"Pipeline failed with return code {result.returncode}.\n"
        f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist after running the pipeline."
    assert os.path.isfile(OUTPUT_PATH), f"Path is not a file: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r", encoding="utf-8") as handle:
        actual = handle.read().splitlines()

    expected = expected_output(raw_data)
    assert actual == expected, "Pipeline output does not match the processing required for raw_chats.txt."


def test_cleaned_chats_exists():
    path = OUTPUT_PATH
    assert os.path.exists(path), f"Missing cleaned output file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"


def test_evaluator_score():
    output_file = OUTPUT_PATH
    evaluator_path = "/app/evaluator"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.exists(evaluator_path), f"Evaluator binary {evaluator_path} does not exist."
    assert os.access(evaluator_path, os.X_OK), f"Evaluator binary {evaluator_path} is not executable."

    try:
        result = subprocess.run(
            [evaluator_path, output_file],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Evaluator failed to run. Return code: {e.returncode}\nStdout: {e.stdout}\nStderr: {e.stderr}")

    output = result.stdout.strip()
    match = re.search(r"Score:\s*([0-9]*\.?[0-9]+)", output)
    assert match is not None, f"Could not find score in evaluator output. Output was:\n{output}"

    score = float(match.group(1))
    threshold = 0.95
    assert score >= threshold, f"Data Readiness Score {score} is below the required threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
