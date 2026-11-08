#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

METRICS = "/home/user/logs/metrics.log"
SOURCE = "/home/user/aggregator/aggregate.cpp"
EXECUTABLE = "/home/user/aggregator/aggregate"
FINAL = "/home/user/final_metrics.txt"
REBUILT = "/tmp/aggregate_rebuilt_by_verifier"

CANONICAL_LOG = """1700000000|app-container-1|OK|120
1700000005|app-container-2|OK|115
1700000010|db-container-1|OK|45
1700000015|cache-container-1|OK|12
1700000020|app-container-1|TIMEOUT|
1700000025|app-container-3|OK|130
1700000030|db-container-1|OK|40
1700000035|app-container-2|TIMEOUT|
1700000040|cache-container-1|OK|15
"""

@pytest.fixture(scope="session", autouse=True)
def preserve_metrics_log():
    original = None
    mode = None
    if os.path.exists(METRICS):
        with open(METRICS, "rb") as f:
            original = f.read()
        mode = os.stat(METRICS).st_mode
    yield
    if original is None:
        if os.path.exists(METRICS):
            os.unlink(METRICS)
    else:
        with open(METRICS, "wb") as f:
            f.write(original)
        os.chmod(METRICS, mode)

@pytest.fixture(scope="session")
def rebuilt_executable():
    result = subprocess.run(
        ["g++", "-O2", "-o", REBUILT, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"aggregate.cpp does not compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)
    return REBUILT

def write_log(content):
    with open(METRICS, "w") as f:
        f.write(content)

def run_aggregate(path, content):
    write_log(content)
    result = subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{path} terminated with status {result.returncode}. stderr:\n{result.stderr}"
    )
    return result.stdout.strip()

def test_final_metrics_file_exists():
    assert os.path.isfile(FINAL), f"The output file {FINAL} was not created."

def test_final_metrics_content():
    assert os.path.isfile(FINAL), f"The output file {FINAL} is missing."
    with open(FINAL, "r") as f:
        content = f.read().strip()
    expected_string = "Average Latency: 68 ms"
    assert expected_string in content, f"Expected '{expected_string}' in {FINAL}, but got:\n{content}"

def test_aggregate_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"The executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {EXECUTABLE} is not a compiled ELF executable."

def test_cpp_source_exists():
    assert os.path.isfile(SOURCE), f"The source file {SOURCE} is missing."

def test_submitted_program_produces_recorded_result():
    actual = run_aggregate(EXECUTABLE, CANONICAL_LOG)
    assert actual == "Average Latency: 68 ms"
    with open(FINAL, "r") as f:
        recorded = f.read().strip()
    assert recorded == actual, "final_metrics.txt is not the exact output of the corrected program."

def test_source_and_submitted_binary_handle_unseen_logs(rebuilt_executable):
    rng = random.SystemRandom()
    for case in range(3):
        valid = [rng.randint(10, 900) for _ in range(rng.randint(3, 7))]
        ignored_numeric = rng.randint(2000, 9000)
        lines = []
        timestamp = rng.randint(1800000000, 1900000000)
        for i, latency in enumerate(valid):
            lines.append(f"{timestamp + i}|generated-{case}-{i}|OK|{latency}")
        lines.extend([
            f"{timestamp + 20}|timeout-{case}|TIMEOUT|",
            f"{timestamp + 21}|failed-{case}|ERROR|{ignored_numeric}",
            f"{timestamp + 22}|missing-{case}|TIMEOUT",
            f"{timestamp + 23}|ok-missing-{case}|OK|",
        ])
        rng.shuffle(lines)
        content = "\n".join(lines) + "\n"
        expected = f"Average Latency: {sum(valid) // len(valid)} ms"
        assert run_aggregate(EXECUTABLE, content) == expected
        assert run_aggregate(rebuilt_executable, content) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
