#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import subprocess
import tempfile


def test_env_setup():
    script_path = "/home/user/env_setup.sh"
    assert os.path.isfile(script_path), f"Missing {script_path}"

    cmd = f"source {script_path} && echo -n $QA_TEST_SEED"
    result = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True)

    assert result.returncode == 0, f"Failed to source {script_path}. Stderr: {result.stderr}"
    assert result.stdout == "8472", f"Expected QA_TEST_SEED=8472, got {result.stdout!r}"


def test_math_filter_executable():
    script_path = "/home/user/math_filter.sh"
    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"


def test_math_filter_is_bash_state_machine():
    script_path = "/home/user/math_filter.sh"
    with open(script_path, "r", encoding="utf-8", errors="replace") as handle:
        source = handle.read()

    assert re.match(r"^#![^\n]*\bbash\b", source), "math_filter.sh must be a Bash script"
    has_loop = re.search(r"\b(?:while|until|for)\b", source) is not None
    has_read_one = re.search(
        r"\bread\b[^\n;]*(?:-n\s*1|-n1|-N\s*1|-N1)\b", source
    ) is not None
    has_one_char_substring = re.search(
        r"\$\{[^}\n]+:[^}\n]+:\s*1\s*\}", source
    ) is not None
    assert has_loop and (has_read_one or has_one_char_substring), (
        "math_filter.sh must iterate through the expression character by character in Bash"
    )


def test_math_filter_adversarial():
    script_path = "/home/user/math_filter.sh"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    clean_failed = []
    for path in clean_files:
        res = subprocess.run([script_path, path], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        res = subprocess.run([script_path, path], capture_output=True)
        if res.returncode == 0:
            evil_failed.append(os.path.basename(path))

    error_msgs = []
    if clean_failed:
        error_msgs.append(
            f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failed)
        )
    if evil_failed:
        error_msgs.append(
            f"{len(evil_failed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failed)
        )

    assert not error_msgs, " | ".join(error_msgs)


def _generated_expression(rng, depth):
    if depth == 0:
        value = rng.randint(0, 20)
        return str(value), value

    left, left_value = _generated_expression(rng, depth - 1)
    right, right_value = _generated_expression(rng, depth - 1)
    operator = rng.choice(["+", "-", "*"])
    spaces_left = " " * rng.randint(0, 3)
    spaces_right = " " * rng.randint(0, 3)
    expression = f"({left}{spaces_left}{operator}{spaces_right}{right})"

    if operator == "+":
        value = left_value + right_value
    elif operator == "-":
        value = left_value - right_value
    else:
        value = left_value * right_value
    return expression, value


def test_math_filter_generated_behavior_and_output():
    script_path = "/home/user/math_filter.sh"
    rng = random.SystemRandom()

    valid_cases = [
        ("42", 42),
        ("( 84 / 7 )", 12),
        ("100-(55+5)", 40),
        ("8 * (3 + 2)", 40),
    ]
    for _ in range(20):
        valid_cases.append(_generated_expression(rng, rng.randint(1, 3)))

    invalid_cases = [
        "5 + + 2",
        "8 +    * 2",
        "1 - - 2",
        "9 / / 3",
        "(5 + 2",
        "5 + 2)",
        ")1 + 2(",
        "((3 + 4)",
        "3 + 4; id",
        "$(whoami)",
        "`id`",
        "4 | 2",
        "4 & 2",
        "1 + abc",
        "2.5 + 1",
        "[1 + 2]",
        "3 \\ 2",
        "{1+2}",
        "1,2",
        "1 +\t2",
    ]

    rng.shuffle(valid_cases)
    rng.shuffle(invalid_cases)

    with tempfile.TemporaryDirectory(prefix="mfcase_") as directory:
        case_path = os.path.join(directory, "input_" + os.urandom(8).hex())

        for expression, expected in valid_cases:
            with open(case_path, "w", encoding="utf-8") as handle:
                handle.write(expression + "\n")
            result = subprocess.run(
                [script_path, case_path], capture_output=True, text=True, timeout=5
            )
            assert result.returncode == 0, (
                f"Valid generated expression was rejected: {expression!r}; "
                f"stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == str(expected), (
                f"Wrong result for {expression!r}: expected {expected}, "
                f"got {result.stdout!r}"
            )

        for expression in invalid_cases:
            with open(case_path, "w", encoding="utf-8") as handle:
                handle.write(expression + "\n")
            result = subprocess.run(
                [script_path, case_path], capture_output=True, timeout=5
            )
            assert result.returncode == 1, (
                f"Invalid generated expression must exit 1: {expression!r}; "
                f"got {result.returncode}"
            )
            assert result.stdout == b"", (
                f"Invalid generated expression must print nothing: {expression!r}; "
                f"got {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
