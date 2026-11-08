#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import secrets
import subprocess


def compute_expected_power(dna_str):
    mapping = {'A': 1, 'C': 2, 'G': 3, 'T': 4}
    X = 0.0
    Y = 0.0
    for n, char in enumerate(dna_str):
        if char not in mapping:
            continue
        val = mapping[char]
        angle = 2 * math.pi * n / 3
        X += val * math.cos(angle)
        Y += val * math.sin(angle)
    return X**2 + Y**2


def test_analyze_cpp_exists():
    cpp_path = "/home/user/analyze.cpp"
    assert os.path.isfile(cpp_path), f"The C++ source file {cpp_path} does not exist."


def test_power_txt_output():
    dna_path = "/home/user/dna.txt"
    power_path = "/home/user/power.txt"

    assert os.path.isfile(dna_path), f"The input file {dna_path} is missing."
    assert os.path.isfile(power_path), f"The output file {power_path} is missing. Did you run your C++ program?"

    with open(dna_path, 'r') as f:
        dna_content = f.read().strip()

    expected_power = compute_expected_power(dna_content)
    expected_str = f"{expected_power:.2f}"

    with open(power_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_str, \
        f"Incorrect power value in {power_path}. Expected '{expected_str}', got '{actual_content}'."


def test_source_compiles_and_computes_fresh_inputs():
    cpp_path = "/home/user/analyze.cpp"
    binary_path = "/tmp/analyze_submission"
    dna_path = "/home/user/dna.txt"
    power_path = "/home/user/power.txt"

    assert os.path.isfile(cpp_path), f"The C++ source file {cpp_path} does not exist."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", cpp_path, "-o", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, \
        f"analyze.cpp did not compile successfully:\n{compile_result.stderr}"
    assert os.path.isfile(binary_path), "Compilation did not produce an executable."

    with open(dna_path, "rb") as f:
        original_dna = f.read()
    power_existed = os.path.isfile(power_path)
    original_power = None
    if power_existed:
        with open(power_path, "rb") as f:
            original_power = f.read()

    cases = ["A", "ACG", "TTTT", "ACGTACGTA", "GATTACA"]
    alphabet = "ACGT"
    for _ in range(8):
        length = secrets.randbelow(200) + 1
        cases.append(''.join(secrets.choice(alphabet) for _ in range(length)))

    try:
        for dna in cases:
            with open(dna_path, "w") as f:
                f.write(dna)
            if os.path.exists(power_path):
                os.remove(power_path)

            run_result = subprocess.run(
                [binary_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            assert run_result.returncode == 0, \
                f"Compiled program failed for a test DNA sequence:\n{run_result.stderr}"
            assert os.path.isfile(power_path), \
                "Compiled program did not create /home/user/power.txt."

            with open(power_path, "r") as f:
                actual = f.read().strip()
            expected = f"{compute_expected_power(dna):.2f}"
            assert actual == expected, \
                f"Compiled program produced '{actual}' for a fresh input; expected '{expected}'."
    finally:
        with open(dna_path, "wb") as f:
            f.write(original_dna)
        if power_existed:
            with open(power_path, "wb") as f:
                f.write(original_power)
        elif os.path.exists(power_path):
            os.remove(power_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
