#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_output_file_exists():
    assert os.path.isfile("/home/user/collatz/output.txt"), "The file /home/user/collatz/output.txt does not exist. Did you run the Go program?"

def test_output_file_content():
    expected_lines = [
        "Input: 12, Steps: 9",
        "Input: 15, Steps: 17",
        "Input: -5, Steps: Invalid",
        "Input: 27, Steps: 111",
        "Input: 0, Steps: Invalid",
        "Input: 9, Steps: 19"
    ]

    output_path = "/home/user/collatz/output.txt"
    assert os.path.isfile(output_path), "Missing output.txt"

    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of /home/user/collatz/output.txt are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

def test_main_go_modified():
    main_go_path = "/home/user/collatz/main.go"
    assert os.path.isfile(main_go_path), "The file /home/user/collatz/main.go does not exist."

    with open(main_go_path, "r") as f:
        content = f.read()

    assert "-1" in content, "The collatzSteps function does not seem to return -1 for non-positive inputs."
    assert "Invalid" in content, "The main function does not seem to print 'Invalid' for non-positive inputs."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import os
import secrets
import shutil
import subprocess
import tempfile

ROOT = "/home/user/collatz"
SOURCE = os.path.join(ROOT, "main.go")
INPUTS = os.path.join(ROOT, "inputs.txt")
OUTPUT = os.path.join(ROOT, "output.txt")


def reference(n):
    if n <= 0:
        return -1
    steps = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps


rng = secrets.SystemRandom()
positive = [1, 2]
while len(positive) < 10:
    n = rng.randrange(3, 10000)
    if n not in positive:
        positive.append(n)
negative = []
while len(negative) < 6:
    n = -rng.randrange(1, 10000)
    if n not in negative:
        negative.append(n)
values = [0] + negative + positive
rng.shuffle(values)
expected = {n: reference(n) for n in values}

# Test collatzSteps directly so handling in main cannot conceal a broken function.
with tempfile.TemporaryDirectory(prefix="collatz-test-") as td:
    shutil.copy2(SOURCE, os.path.join(td, "main.go"))
    cases = ",\n".join(f"        {n}: {expected[n]}" for n in values)
    test_source = f'''package main

import "testing"

func TestCollatzStepsAdditionalValues(t *testing.T) {{
    cases := map[int]int{{
{cases}
    }}
    for input, want := range cases {{
        if got := collatzSteps(input); got != want {{
            t.Fatalf("collatzSteps(%d) = %d, want %d", input, got, want)
        }}
    }}
}}
'''
    with open(os.path.join(td, "main_test.go"), "w") as f:
        f.write(test_source)
    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    subprocess.run(
        ["go", "test", "-timeout", "5s", "."],
        cwd=td,
        env=env,
        check=True,
        timeout=10,
    )

# Compile and execute the submitted program on unpredictable additional inputs.
binary = os.path.join(tempfile.gettempdir(), "collatz-submission")
subprocess.run(["go", "build", "-o", binary, SOURCE], check=True, timeout=20)

old_inputs = open(INPUTS, "rb").read() if os.path.exists(INPUTS) else None
old_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
try:
    with open(INPUTS, "w") as f:
        for n in values:
            f.write(f"{n}\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    subprocess.run([binary], check=True, timeout=5)
    assert os.path.isfile(OUTPUT), "Running the compiled program did not create output.txt"
    with open(OUTPUT) as f:
        actual = [line.strip() for line in f if line.strip()]

    wanted = [
        f"Input: {n}, Steps: Invalid" if expected[n] == -1
        else f"Input: {n}, Steps: {expected[n]}"
        for n in values
    ]
    assert actual == wanted, f"Additional-input output mismatch. Expected {wanted!r}, got {actual!r}"
finally:
    if old_inputs is None:
        if os.path.exists(INPUTS):
            os.remove(INPUTS)
    else:
        with open(INPUTS, "wb") as f:
            f.write(old_inputs)
    if old_output is None:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
    else:
        with open(OUTPUT, "wb") as f:
            f.write(old_output)
    if os.path.exists(binary):
        os.remove(binary)
DYNAMIC_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_dynamic.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
