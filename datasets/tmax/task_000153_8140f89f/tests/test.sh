#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import pytest


def test_fuzz_status_pass():
    status_file = "/home/user/fuzz_status.txt"
    assert os.path.isfile(status_file), f"File not found: {status_file}. Did you run the fuzz.sh script?"

    with open(status_file, 'r') as f:
        content = f.read().strip()

    assert content == "PASS", f"Expected fuzz_status.txt to contain 'PASS', but found '{content}'"


def test_sensor_stat_executable_exists():
    exe_file = "/home/user/sensor_stat"
    assert os.path.isfile(exe_file), f"Executable not found: {exe_file}. Did you compile the program?"
    assert os.access(exe_file, os.X_OK), f"File is not executable: {exe_file}"


def test_sensor_stat_c_fixes():
    src_file = "/home/user/sensor_stat.c"
    assert os.path.isfile(src_file), f"Source file not found: {src_file}"

    with open(src_file, 'r') as f:
        content = f.read()

    assert "<math.h>" in content, "math.h is not included in sensor_stat.c"
    assert "double" in content, "The program should use 'double' precision variables instead of 'float'"

    # A two-pass array algorithm must traverse the readings at least twice.
    code = re.sub(r'/\*.*?\*/|//[^\n]*', '', content, flags=re.S)
    loops = re.findall(r'\b(?:for|while)\s*\(', code)
    assert len(loops) >= 2, "The source does not contain the two loops required for a two-pass variance algorithm"


def test_build_sh_fixes():
    build_file = "/home/user/build.sh"
    assert os.path.isfile(build_file), f"Build script not found: {build_file}"

    with open(build_file, 'r') as f:
        content = f.read()

    assert "-lm" in content, "The build script should include the '-lm' flag to link the math library"


def test_fuzz_results_log_exists():
    log_file = "/home/user/fuzz_results.log"
    assert os.path.isfile(log_file), f"Log file not found: {log_file}. Did you run the fuzz.sh script?"


def expected_sample_stddev(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((value - mean) ** 2 for value in values) / (len(values) - 1)
    return math.sqrt(variance)


def run_sensor(arguments):
    result = subprocess.run(
        ["/home/user/sensor_stat", *arguments],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, f"sensor_stat exited with {result.returncode}: {result.stderr}"
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"sensor_stat did not print one numeric result: {output!r}")
    assert math.isfinite(value), f"sensor_stat printed a non-finite result: {output!r}"
    return value


def test_clean_build_and_independent_standard_deviation_results():
    exe_file = "/home/user/sensor_stat"

    # Ensure build.sh really creates the submitted executable from the fixed source.
    os.remove(exe_file)
    built = subprocess.run(
        ["/bin/bash", "/home/user/build.sh"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert built.returncode == 0, f"build.sh failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(exe_file), "build.sh did not create /home/user/sensor_stat"
    assert os.access(exe_file, os.X_OK), "The rebuilt sensor_stat is not executable"
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sensor_stat is not a compiled ELF executable"

    cases = [
        ["1", "2", "3"],
        ["2.5", "4.5"],
        ["10000000.10", "10000000.20", "10000000.40", "10000000.80", "10000000.90"],
        ["1000000000000.00", "1000000000000.25", "1000000000000.50", "1000000000000.75", "1000000000001.00"],
        ["-999999999999.75", "-1000000000000.00", "-1000000000000.25", "-1000000000000.50"],
        ["42.125", "42.125", "42.125", "42.125"],
    ]

    for arguments in cases:
        values = [float(item) for item in arguments]
        expected = expected_sample_stddev(values)
        actual = run_sensor(arguments)
        assert actual == pytest.approx(expected, abs=2e-6, rel=2e-6), (
            f"Incorrect sample standard deviation for {arguments}: "
            f"expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
