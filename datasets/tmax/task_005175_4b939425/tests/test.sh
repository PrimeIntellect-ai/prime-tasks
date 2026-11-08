#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import stat
import subprocess
import pytest

RISK_DIR = "/home/user/risk_engine"
DATA_PATH = os.path.join(RISK_DIR, "data.txt")
ORIGINAL_DATA = b"100000000.001\n100000000.002\n100000000.003\n100000000.002\n100000000.001\n"
EXPECTED_SECRET = "TRADEX-9922-8811-SECRET"


def assert_original_data():
    assert os.path.isfile(DATA_PATH), "data.txt is missing."
    assert stat.S_ISREG(os.lstat(DATA_PATH).st_mode), "data.txt must be a regular file."
    with open(DATA_PATH, "rb") as f:
        actual = f.read()
    assert actual == ORIGINAL_DATA, "data.txt was modified from the original fixture."


def stable_sample_stddev(data):
    assert len(data) > 1
    mean = math.fsum(data) / len(data)
    variance = math.fsum((x - mean) ** 2 for x in data) / (len(data) - 1)
    return math.sqrt(variance)


def get_expected_stddev():
    data = [float(line) for line in ORIGINAL_DATA.decode("ascii").splitlines() if line]
    return stable_sample_stddev(data)


def get_expected_secret():
    return EXPECTED_SECRET


def run_calc():
    return subprocess.run(
        ["./calc_variance"],
        cwd=RISK_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_data_fixture_unchanged():
    assert_original_data()


def test_build_script_succeeds():
    assert_original_data()
    build_script = os.path.join(RISK_DIR, "build.sh")
    assert os.path.isfile(build_script), "build.sh is missing."
    result = subprocess.run(["./build.sh"], cwd=RISK_DIR, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"build.sh failed to execute successfully. Error: {result.stderr}"
    assert_original_data()


def test_calc_variance_executable_works():
    assert_original_data()
    executable = os.path.join(RISK_DIR, "calc_variance")
    assert os.path.isfile(executable), "calc_variance executable was not created."
    assert os.access(executable, os.X_OK), "calc_variance is not executable."

    result = run_calc()
    assert result.returncode == 0, f"calc_variance failed to run. Error: {result.stderr}"

    output = result.stdout.strip()
    expected_stddev = get_expected_stddev()
    assert expected_stddev is not None, "data.txt is missing or empty, cannot compute expected stddev."

    try:
        output_val = float(output)
        assert math.isfinite(output_val), f"calc_variance output was not finite: '{output}'"
        assert math.isclose(output_val, expected_stddev, rel_tol=1e-3), \
            f"calc_variance output '{output_val}' does not match expected standard deviation '{expected_stddev:.4f}'"
    except ValueError:
        pytest.fail(f"calc_variance did not output a valid float. Output was: '{output}'")

    assert_original_data()


def test_calc_variance_handles_unseen_high_offset_inputs():
    executable = os.path.join(RISK_DIR, "calc_variance")
    assert os.path.isfile(executable), "calc_variance executable was not created."
    assert os.access(executable, os.X_OK), "calc_variance is not executable."

    cases = [
        [1000000000000.0, 1000000000001.0, 1000000000002.0,
         1000000000003.0, 1000000000004.0],
        [100000000000000.0, 100000000000000.25, 100000000000000.5,
         100000000000000.75, 100000000000001.0, 100000000000002.0],
    ]

    try:
        for values in cases:
            with open(DATA_PATH, "w", encoding="ascii") as f:
                for value in values:
                    f.write(f"{value:.10f}\n")

            result = run_calc()
            assert result.returncode == 0, f"calc_variance failed on a high-offset dataset. Error: {result.stderr}"
            output = result.stdout.strip()
            try:
                output_val = float(output)
            except ValueError:
                pytest.fail(f"calc_variance did not output a valid float. Output was: '{output}'")

            expected = stable_sample_stddev(values)
            assert math.isfinite(output_val), f"calc_variance returned a non-finite result: '{output}'"
            assert math.isclose(output_val, expected, rel_tol=1e-3, abs_tol=5e-5), \
                f"calc_variance output '{output_val}' does not match expected standard deviation '{expected}'"
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(ORIGINAL_DATA)

    assert_original_data()


def test_resolution_log_format_and_content():
    assert_original_data()
    log_path = "/home/user/resolution.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_secret = get_expected_secret()
    expected_stddev = get_expected_stddev()
    assert expected_stddev is not None, "data.txt is missing or empty."

    expected_content = f"SECRET: {expected_secret}\nSTDDEV: {expected_stddev:.4f}"

    assert content == expected_content, \
        f"{log_path} content is incorrect.\nExpected:\n{expected_content}\n\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
