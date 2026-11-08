#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile


def expected_rms(values):
    # Emulate: scale=4; sqrt(sum_sq / count)
    # First truncate the division to four decimal places, then truncate sqrt.
    sum_sq = sum(v * v for v in values)
    scaled_mean = (sum_sq * 10000) // len(values)
    scaled_root = math.isqrt(scaled_mean * 10000)
    return f"{scaled_root // 10000}.{scaled_root % 10000:04d}"


def run_script(path, values):
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("".join(f"{value}\n" for value in values))
        input_path = f.name
    try:
        return subprocess.run(
            [path, input_path], capture_output=True, text=True, timeout=10
        )
    finally:
        os.unlink(input_path)


def test_crash_input_file():
    path = "/home/user/crash_input.txt"
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"

    with open(path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 3, f"Expected exactly 3 lines in {path}, got {len(lines)}"

    sum_sq = 0
    for i, line in enumerate(lines):
        line = line.strip()
        assert line.isdigit(), f"Line {i+1} is not a positive integer: '{line}'"
        val = int(line)
        assert val > 0, f"Line {i+1} must be positive, got {val}"
        sum_sq += val * val

    max_int64 = 9223372036854775807
    assert sum_sq > max_int64, (
        f"The sum of squares ({sum_sq}) does not exceed 64-bit signed max "
        f"({max_int64}) to cause an overflow."
    )

    # Execute the original vulnerable implementation to prove that this exact
    # input reaches its negative-overflow assertion under Bash arithmetic.
    vulnerable = """#!/bin/bash
file=$1
sum_sq=0
count=0
while read -r val; do
    sum_sq=$((sum_sq + val * val))
    if [ "$sum_sq" -lt 0 ]; then
        echo "Assertion failed: sum_sq negative due to overflow" >&2
        exit 1
    fi
    count=$((count + 1))
done < "$file"
rms=$(echo "scale=4; sqrt($sum_sq / $count)" | bc)
echo "$rms"
"""
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(vulnerable)
        vulnerable_path = f.name
    os.chmod(vulnerable_path, 0o755)
    try:
        result = subprocess.run(
            [vulnerable_path, path], capture_output=True, text=True, timeout=10
        )
    finally:
        os.unlink(vulnerable_path)

    assert result.returncode != 0, "Crash input did not make the vulnerable script fail"
    assert "Assertion failed: sum_sq negative due to overflow" in result.stderr, (
        "Crash input did not trigger the vulnerable script's overflow assertion; "
        f"stderr was: {result.stderr!r}"
    )


def test_process_logs_script_fixed():
    path = "/home/user/process_logs.sh"
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "bc" in content or "awk" in content, (
        "Script must use 'bc' or 'awk' to handle large number arithmetic."
    )

    latencies_path = "/home/user/latencies.txt"
    assert os.path.exists(latencies_path), f"Missing {latencies_path}"

    result = subprocess.run(
        [path, latencies_path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    output = result.stdout.strip()
    expected = "2867403006.2066"
    assert output == expected, f"Script output incorrect. Expected {expected}, got {output}"

    # Exercise the submitted artifact on fresh, non-fixed inputs. Expected
    # answers are derived independently with exact integer arithmetic.
    dynamic_cases = [
        [secrets.randbelow(4000000000) + 2000000000 for _ in range(3)],
        [secrets.randbelow(5000000000) + 1000000000 for _ in range(5)],
        [secrets.randbelow(7000000000) + 2500000000 for _ in range(7)],
        [secrets.randbelow(3000000000) + 3000000000 for _ in range(2)],
    ]
    for values in dynamic_cases:
        result = run_script(path, values)
        expected = expected_rms(values)
        assert result.returncode == 0, (
            f"Script failed on generated input {values}: {result.stderr}"
        )
        assert result.stdout.strip() == expected, (
            f"Incorrect RMS for generated input {values}. "
            f"Expected {expected}, got {result.stdout.strip()!r}"
        )


def test_result_file():
    path = "/home/user/result.txt"
    assert os.path.exists(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "2867403006.2066"
    assert content == expected, f"Contents of {path} incorrect. Expected {expected}, got {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
