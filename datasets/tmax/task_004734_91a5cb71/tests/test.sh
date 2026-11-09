#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/uptime_monitor"
OUTPUT_FILE = "/home/user/calculated_sla.txt"
ORIGINAL_DATA = os.path.join(PROJECT, "data/ping_logs.csv")
NUMBER_RE = re.compile(r"^[+-]?\d+\.\d{6}$")


def parse_single_number(text, source):
    text = text.strip()
    assert NUMBER_RE.fullmatch(text), f"{source} must contain exactly one number with six decimal places; got {text!r}"
    return float(text)


def test_calculated_sla_accuracy():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as a float in {OUTPUT_FILE}.")

    truth = 99.999142
    error = abs(val - truth)
    threshold = 1e-6

    assert error < threshold, f"Calculated SLA {val} is not accurate enough. Error {error} >= threshold {threshold}."


@pytest.fixture(scope="session")
def built_executable():
    cmake_file = os.path.join(PROJECT, "CMakeLists.txt")
    source_file = os.path.join(PROJECT, "src/uptime_calculator.cpp")
    assert os.path.isfile(cmake_file), f"Missing {cmake_file}"
    assert os.path.isfile(source_file), f"Missing {source_file}"
    assert not os.path.islink(cmake_file), "CMakeLists.txt must be a regular submitted file"
    assert not os.path.islink(source_file), "uptime_calculator.cpp must be a regular submitted file"

    build_dir = tempfile.mkdtemp(prefix="uptime-build-")
    configured = subprocess.run(
        ["cmake", "-S", PROJECT, "-B", build_dir],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert configured.returncode == 0, f"cmake configuration failed:\n{configured.stdout}"

    compiled = subprocess.run(
        ["make", "-C", build_dir, "-j2"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert compiled.returncode == 0, f"make failed:\n{compiled.stdout}"

    executable = os.path.join(build_dir, "uptime_monitor")
    assert os.path.isfile(executable), "Build did not produce the uptime_monitor executable"
    assert os.access(executable, os.X_OK), "Built uptime_monitor is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built uptime_monitor is not an ELF executable"
    return executable


def run_calculator(executable, csv_path):
    result = subprocess.run(
        [executable, csv_path], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180
    )
    assert result.returncode == 0, f"uptime_monitor failed: {result.stderr}"
    return parse_single_number(result.stdout, "uptime_monitor stdout")


def test_built_program_produces_required_original_result(built_executable):
    assert os.path.isfile(ORIGINAL_DATA), f"Missing input data {ORIGINAL_DATA}"
    actual = run_calculator(built_executable, ORIGINAL_DATA)
    truth = 99.999142
    assert abs(actual - truth) < 1e-6, f"Built executable produced {actual}, expected {truth}"

    with open(OUTPUT_FILE, "r") as f:
        saved = float(f.read().strip())
    assert actual == saved, "calculated_sla.txt does not match the freshly built executable's output"


def test_built_program_handles_unseen_precision_case(built_executable):
    seed = int.from_bytes(secrets.token_bytes(8), "big")
    count = 350000 + seed % 50001
    state = seed or 1
    total_units = 0

    fd, csv_path = tempfile.mkstemp(prefix="unseen-pings-", suffix=".csv")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("duration_ms\n")
            for _ in range(count):
                state = (6364136223846793005 * state + 1442695040888963407) & ((1 << 64) - 1)
                units = 250001 + (state % 9)  # Exact units of 0.0001 ms.
                total_units += units
                f.write(f"{units // 10000}.{units % 10000:04d}\n")

        # SLA = (sum(units / 10000) / 10000000) * 100.
        expected = total_units / 1_000_000_000.0
        actual = run_calculator(built_executable, csv_path)
        assert abs(actual - expected) <= 0.500001e-6, (
            f"Precision test produced {actual}, expected {expected:.9f}"
        )
    finally:
        os.unlink(csv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
