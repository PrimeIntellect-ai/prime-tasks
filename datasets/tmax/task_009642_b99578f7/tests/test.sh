#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_crashing_id_txt():
    path = "/home/user/crashing_id.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "2899", f"Expected crashing ID to be '2899', but found '{content}' in {path}"


def test_filter_users_py_exists():
    path = "/home/user/filter_users.py"
    assert os.path.isfile(path), f"Missing script: {path}. You need to write a script that filters the users."


def test_safe_users_txt():
    path = "/home/user/safe_users.txt"
    assert os.path.isfile(path), f"Missing file: {path}. Did you run your filter script?"

    expected_safe_users = ["10", "450", "1999", "2147"]

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_safe_users, f"Expected safe users to be {expected_safe_users}, but found {lines} in {path}"


def test_filter_script_dynamically_filters_overflows():
    script_path = "/home/user/filter_users.py"
    users_path = "/home/user/users.txt"
    output_path = "/home/user/safe_users.txt"
    assert os.path.isfile(script_path)

    int32_min = -(2 ** 31)
    int32_max = 2 ** 31 - 1
    multiplier = 1_000_000
    largest_safe_positive = int32_max // multiplier

    with open(users_path, "rb") as f:
        original_users = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    rng = random.SystemRandom()
    try:
        # Run more than once with fresh, mixed inputs so a fixed output or a
        # script that only removes the known crashing ID cannot pass.
        for _ in range(2):
            safe_values = [0, largest_safe_positive]
            safe_values.extend(rng.sample(range(1, largest_safe_positive), 5))

            overflow_values = [largest_safe_positive + 1, 2899, 5000]
            overflow_values.extend(
                rng.sample(range(largest_safe_positive + 2, 2_000_000_000), 5)
            )

            values = safe_values + overflow_values
            rng.shuffle(values)
            expected = [
                str(uid)
                for uid in values
                if int32_min <= uid * multiplier <= int32_max
            ]

            with open(users_path, "w") as f:
                f.write("\n".join(str(uid) for uid in values) + "\n")
            if os.path.exists(output_path):
                os.remove(output_path)

            result = subprocess.run(
                ["python3", script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"filter_users.py exited with {result.returncode}. "
                f"stderr: {result.stderr}"
            )
            assert os.path.isfile(output_path), (
                "filter_users.py did not create /home/user/safe_users.txt"
            )

            with open(output_path, "r") as f:
                actual = [line.strip() for line in f if line.strip()]

            assert actual == expected, (
                "filter_users.py did not dynamically remove every ID whose "
                f"multiplication by {multiplier} exceeds signed 32-bit limits. "
                f"Input: {values}; expected: {expected}; actual: {actual}"
            )
    finally:
        with open(users_path, "wb") as f:
            f.write(original_users)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
