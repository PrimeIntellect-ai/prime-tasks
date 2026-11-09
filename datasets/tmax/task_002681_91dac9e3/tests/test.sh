#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import random
import subprocess
import tempfile


def compute_expected_log(raw_data):
    vals = {item["pos"]: item["val"] for item in raw_data}
    expected_lines = []

    for bin_idx in range(10):
        start = bin_idx * 100
        end = start + 99
        bin_vals = [vals[i] for i in range(start, end + 1)]
        sum_val = sum(bin_vals)

        tvd = 0.0
        n = len(bin_vals)
        for v in bin_vals:
            p_i = v / sum_val
            u_i = 1.0 / n
            tvd += abs(p_i - u_i)
        tvd *= 0.5

        if tvd > 0.15:
            mid = start + 49
            bins_to_integrate = [(start, mid), (mid + 1, end)]
        else:
            bins_to_integrate = [(start, end)]

        for b_start, b_end in bins_to_integrate:
            integral = 0.0
            for i in range(b_start, b_end):
                integral += (vals[i] + vals[i + 1]) / 2.0
            expected_lines.append(f"{b_start} {b_end} {integral:.2f}")

    return "\n".join(expected_lines) + "\n"


def test_processed_scores_txt():
    raw_path = "/home/user/raw_data.json"
    processed_path = "/home/user/processed_scores.txt"

    assert os.path.isfile(processed_path), f"Missing required file: {processed_path}"

    with open(raw_path, "r") as f:
        raw_data = json.load(f)

    with open(processed_path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == len(raw_data), f"Expected {len(raw_data)} lines in {processed_path}, got {len(lines)}"

    for i, line in enumerate(lines):
        parts = line.strip().split()
        assert len(parts) == 2, f"Line {i+1} in {processed_path} does not have exactly 2 columns"
        assert int(parts[0]) == raw_data[i]["pos"], f"Position mismatch at line {i+1}"
        assert math.isclose(float(parts[1]), raw_data[i]["val"], rel_tol=1e-5), f"Value mismatch at line {i+1}"


def test_cpp_file_exists():
    cpp_path = "/home/user/analyze_flex.cpp"
    assert os.path.isfile(cpp_path), f"Missing required C++ source file: {cpp_path}"


def test_integrated_flexibility_log():
    raw_path = "/home/user/raw_data.json"
    log_path = "/home/user/integrated_flexibility.log"

    assert os.path.isfile(log_path), f"Missing required log file: {log_path}"

    with open(raw_path, "r") as f:
        raw_data = json.load(f)

    expected_log = compute_expected_log(raw_data)

    with open(log_path, "r") as f:
        actual_log = f.read()

    assert actual_log.strip() == expected_log.strip(), f"Content of {log_path} does not match expected output.\nExpected:\n{expected_log}\nActual:\n{actual_log}"


def test_cpp_program_compiles_and_processes_fresh_inputs():
    cpp_path = "/home/user/analyze_flex.cpp"
    processed_path = "/home/user/processed_scores.txt"
    log_path = "/home/user/integrated_flexibility.log"

    with tempfile.TemporaryDirectory(prefix="flex_verifier_") as temp_dir:
        binary_path = os.path.join(temp_dir, "analyze_flex")
        compiled = subprocess.run(
            ["g++", "-std=c++17", cpp_path, "-o", binary_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compiled.returncode == 0, f"C++ source failed to compile:\n{compiled.stderr}"

        with open(processed_path, "rb") as f:
            original_processed = f.read()
        with open(log_path, "rb") as f:
            original_log = f.read()

        rng = random.SystemRandom()
        try:
            for trial in range(2):
                challenge = []
                for bin_idx in range(10):
                    start = bin_idx * 100
                    if (bin_idx + trial) % 2 == 0:
                        value = rng.randint(3, 40)
                        bin_values = [value] * 100
                    else:
                        bin_values = [rng.randint(1, 4)] * 100
                        spike_offset = rng.randrange(100)
                        bin_values[spike_offset] = rng.randint(500, 900)

                    for offset, value in enumerate(bin_values):
                        challenge.append({"pos": start + offset, "val": value})

                with open(processed_path, "w") as f:
                    for item in challenge:
                        f.write(f"{item['pos']} {item['val']}\n")

                if os.path.exists(log_path):
                    os.remove(log_path)

                executed = subprocess.run(
                    [binary_path],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                assert executed.returncode == 0, (
                    f"Compiled C++ program failed on verifier input with exit code "
                    f"{executed.returncode}. stderr:\n{executed.stderr}"
                )
                assert os.path.isfile(log_path), "Compiled C++ program did not create integrated_flexibility.log"

                with open(log_path, "r") as f:
                    actual = f.read()
                expected = compute_expected_log(challenge)
                assert actual.strip() == expected.strip(), (
                    "Compiled C++ program produced incorrect output for fresh verifier input."
                    f"\nExpected:\n{expected}\nActual:\n{actual}"
                )
        finally:
            with open(processed_path, "wb") as f:
                f.write(original_processed)
            with open(log_path, "wb") as f:
                f.write(original_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
