#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

SCRIPT_PATH = "/home/user/generate_synthetic.sh"
OUTPUT_PATH = "/home/user/synthetic_T800.csv"
INPUT_PATH = "/home/user/raw_telemetry.csv"

ORIGINAL_INPUT = """timestamp,sensor_id,status,reading
1620000000,T-800,VALID,10.5
1620000001,T-800,ERROR,99.9
1620000002,T-801,VALID,12.1
1620000003,T-800,VALID,11.2
1620000004,T-800,VALID,10.8
1620000005,T-800,NOISE,15.0
1620000006,T-800,VALID,9.7
1620000007,T-802,VALID,100.5
1620000008,T-800,VALID,10.1
1620000009,T-800,VALID,11.5
"""


def assert_input_unchanged():
    assert os.path.isfile(INPUT_PATH), f"Input file is missing: {INPUT_PATH}"
    with open(INPUT_PATH, "r", newline="") as f:
        actual = f.read()
    assert actual == ORIGINAL_INPUT, f"Input telemetry file was modified: {INPUT_PATH}"


def test_script_exists_and_executable():
    """Test that the bash script exists and has executable permissions."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable. Run chmod +x."
    assert_input_unchanged()


def test_script_execution():
    """Test that the script runs successfully and creates the output file."""
    assert_input_unchanged()

    # Remove output if it exists to ensure the script generates it
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. Return code: {result.returncode}\nStderr: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Script executed but did not create the output file at {OUTPUT_PATH}"
    assert_input_unchanged()


def test_output_content():
    """Test that the generated synthetic data matches the expected Box-Muller output."""
    # Ensure script has been run
    if not os.path.exists(OUTPUT_PATH):
        assert_input_unchanged()
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed to execute. Return code: {result.returncode}\nStderr: {result.stderr}"
        assert_input_unchanged()

    assert os.path.isfile(OUTPUT_PATH), f"Missing output file: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        student_lines = [line.strip() for line in f if line.strip()]

    assert len(student_lines) == 5000, f"Expected exactly 5000 lines in output, got {len(student_lines)}"

    # Generate expected output from the trusted original telemetry, not the
    # writable file that the submitted script can access.
    awk_script = """
    BEGIN {
        pi = 3.14159265359;
    }
    NR>1 && $2=="T-800" && $3=="VALID" {
        val[$1] = $4;
        sum += $4;
        count++;
    }
    END {
        mean = sum / count;
        for (i in val) {
            sq_diff += (val[i] - mean)^2;
        }
        stddev = sqrt(sq_diff / count);

        srand(42);
        for (i=1; i<=5000; i++) {
            u1 = rand();
            while(u1 == 0) u1 = rand(); # avoid log(0)
            u2 = rand();
            z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
            x = mean + z0 * stddev;
            printf "%.4f\\n", x;
        }
    }
    """

    result = subprocess.run(
        ["awk", "-F,", awk_script],
        input=ORIGINAL_INPUT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, "Failed to generate expected data in test."

    expected_lines = [line.strip() for line in result.stdout.split("\n") if line.strip()]
    assert len(expected_lines) == 5000, "Expected data generation failed to produce 5000 lines."

    # Compare lines
    mismatches = 0
    first_mismatch = None

    for i, (student_val, expected_val) in enumerate(zip(student_lines, expected_lines)):
        if student_val != expected_val:
            mismatches += 1
            if first_mismatch is None:
                first_mismatch = (i + 1, expected_val, student_val)

    if mismatches > 0:
        line_num, exp, act = first_mismatch
        pytest.fail(
            f"Output data does not match expected values.\n"
            f"Total mismatches: {mismatches} out of 5000.\n"
            f"First mismatch at line {line_num}:\n"
            f"  Expected: {exp}\n"
            f"  Got:      {act}\n"
            f"Check your mean/stddev calculations, random seed, and Box-Muller implementation."
        )

    assert_input_unchanged()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
