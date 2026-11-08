#!/bin/bash
set -e
export PATH=/opt/rust/bin:$PATH
mkdir -p /logs/verifier

repo_dir=/home/user/math_toolkit
mkdir -p "$repo_dir/tests"
hidden_test=$(mktemp "$repo_dir/tests/verifier_hidden_XXXXXX.rs")
cleanup() {
    rm -f "$hidden_test"
}
trap cleanup EXIT

cat > "$hidden_test" <<'RUST_EOF'
use math_toolkit::{calculate_stats, collatz_length};

fn reference_collatz_length(mut n: u64) -> u64 {
    let mut length = 0;
    while n != 1 {
        if n % 2 == 0 {
            n /= 2;
        } else {
            n = 3 * n + 1;
        }
        length += 1;
    }
    length
}

#[test]
fn verifier_checks_general_collatz_behavior() {
    let mut values: Vec<u64> = (1..=256).collect();
    values.extend([511, 999, 1000, 6171]);

    for &n in &values {
        assert_eq!(collatz_length(n), reference_collatz_length(n), "wrong Collatz length for {n}");
    }

    let expected: Vec<u64> = values.iter().copied().map(reference_collatz_length).collect();
    assert_eq!(calculate_stats(&values), expected);
}
RUST_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import pytest

REPO_DIR = "/home/user/math_toolkit"
EXPECTED_NUMBERS = [15, 27, 42, 99, 1000]


def reference_collatz_length(n):
    length = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        length += 1
    return length


def test_inputs_json_recovered_and_fixed():
    path = "/home/user/math_toolkit/inputs.json"
    assert os.path.isfile(path), f"File {path} does not exist. Did you recover it?"

    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} contains invalid JSON. Did you fix the syntax errors?")

    assert "numbers" in data, "JSON must contain a 'numbers' key."
    numbers = data["numbers"]
    assert isinstance(numbers, list), "'numbers' must be a list."

    expected_numbers = {15, 27, 42, 99, 1000}
    assert expected_numbers.issubset(set(numbers)), f"Expected numbers {expected_numbers} to be in the input JSON, got {numbers}."

    assert data == {"numbers": EXPECTED_NUMBERS}, (
        "inputs.json must be the recovered dangling input with only its corrupt JSON elements repaired; "
        f"got {data!r}"
    )


def test_cargo_test_passes():
    result = subprocess.run(
        ["cargo", "test"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"`cargo test` failed with output:\n{result.stdout}\n{result.stderr}"


def test_result_txt_exists_and_contains_output():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the program and redirect output?"

    with open(path, "r") as f:
        content = f.read()

    expected_substrings = ["15", "27", "42", "99", "1000", "17", "111", "8", "25"]
    for sub in expected_substrings:
        assert sub in content, f"Expected to find '{sub}' in {path}, but it was missing. Content:\n{content}"

    run = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert run.returncode == 0, f"`cargo run` failed with output:\n{run.stdout}\n{run.stderr}"

    expected_output = "".join(
        f"Number: {n}, Collatz Length: {reference_collatz_length(n)}\n"
        for n in EXPECTED_NUMBERS
    )
    assert run.stdout == expected_output, (
        "Program stdout does not precisely match the output required for the recovered input.\n"
        f"Expected:\n{expected_output}\nActual:\n{run.stdout}"
    )
    assert content == run.stdout, (
        "/home/user/result.txt must precisely match the current standard output of `cargo run`.\n"
        f"File content:\n{content}\nProgram output:\n{run.stdout}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
