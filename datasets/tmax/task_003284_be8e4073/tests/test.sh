#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import pytest

UPTIME_DIR = "/home/user/uptime"
C_FILE = os.path.join(UPTIME_DIR, "log_parser.c")
EXE_FILE = os.path.join(UPTIME_DIR, "log_parser")
PY_FILE = os.path.join(UPTIME_DIR, "aggregator.py")
RAW_FILE = os.path.join(UPTIME_DIR, "raw_logs.txt")
SUMMARY_FILE = "/home/user/downtime_summary.txt"
EXPECTED_PARSED = {
    "region_us": {"east": 45, "west": [10, 5, {"node1": 2}]},
    "region_eu": [20, 15],
    "region_ap": 8,
}


def run_aggregator(data):
    result = subprocess.run(
        ["python3", PY_FILE],
        input=json.dumps(data).encode(),
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"aggregator.py failed to run: {result.stderr.decode()}"
    output = result.stdout.decode().strip()
    assert re.fullmatch(r"-?\d+", output), f"aggregator.py did not output one integer: {output!r}"
    return int(output)


def recursive_sum(data):
    if isinstance(data, int):
        return data
    if isinstance(data, list):
        return sum(recursive_sum(item) for item in data)
    if isinstance(data, dict):
        return sum(recursive_sum(value) for value in data.values())
    raise AssertionError(f"Unexpected generated value: {data!r}")


def test_log_parser_builds_and_runs():
    assert os.path.isfile(C_FILE), "log_parser.c is missing."

    if os.path.exists(EXE_FILE):
        os.remove(EXE_FILE)
    build_result = subprocess.run(["make", "-C", UPTIME_DIR], capture_output=True, timeout=20)
    assert build_result.returncode == 0, f"make failed: {build_result.stderr.decode()}"
    assert os.path.isfile(EXE_FILE), "log_parser executable was not created."
    assert os.access(EXE_FILE, os.X_OK), "log_parser is not executable."

    run_result = subprocess.run([EXE_FILE], input=b"test\n", capture_output=True, timeout=10)
    assert run_result.returncode == 0, "log_parser crashed when running."
    try:
        data = json.loads(run_result.stdout.decode())
        assert isinstance(data, dict), "log_parser output is not a JSON dictionary."
    except json.JSONDecodeError:
        pytest.fail("log_parser did not output valid JSON.")
    assert data == EXPECTED_PARSED, f"log_parser produced the wrong parsed structure: {data!r}"


def test_aggregator_fixed():
    assert os.path.isfile(PY_FILE), "aggregator.py is missing."

    test_json = '{"region_us": {"east": 45, "west": [10, 5, {"node1": 2}]}, "region_eu": [20, 15], "region_ap": 8}\n'
    run_result = subprocess.run(
        ["python3", PY_FILE], input=test_json.encode(), capture_output=True, timeout=10
    )
    assert run_result.returncode == 0, f"aggregator.py failed to run: {run_result.stderr.decode()}"
    assert run_result.stdout.decode().strip() == "105", "aggregator.py did not output the correct sum."


def test_aggregator_recursively_sums_unseen_inputs():
    rng = random.SystemRandom()
    values = [rng.randint(-5000, 5000) for _ in range(30)]
    cases = [
        values[0],
        [values[1], values[2], values[3]],
        {"a": values[4], "b": [values[5], {"c": values[6]}]},
        {
            "left": [[values[7]], {"x": [values[8], values[9]]}],
            "right": {"y": values[10], "z": [values[11], {"q": values[12]}]},
        },
        [],
        {},
    ]

    deep = values[13]
    for index in range(120):
        if index % 2:
            deep = {f"level_{index}_{rng.randrange(1 << 30)}": deep}
        else:
            deep = [deep, values[14 + (index % 16)]]
    cases.append(deep)

    for data in cases:
        expected = recursive_sum(data)
        assert run_aggregator(data) == expected, f"Incorrect recursive sum for {data!r}"


def test_pipeline_and_downtime_summary():
    assert os.path.isfile(RAW_FILE), "raw_logs.txt is missing."
    with open(RAW_FILE, "rb") as raw_file:
        raw_logs = raw_file.read()

    parser_result = subprocess.run(
        [EXE_FILE], input=raw_logs, capture_output=True, timeout=10
    )
    assert parser_result.returncode == 0, f"log_parser failed on raw_logs.txt: {parser_result.stderr.decode()}"
    try:
        parsed = json.loads(parser_result.stdout.decode())
    except json.JSONDecodeError:
        pytest.fail("log_parser did not produce valid JSON for raw_logs.txt.")
    assert parsed == EXPECTED_PARSED, "raw_logs.txt was not converted to the required parsed structure."

    aggregate_result = subprocess.run(
        ["python3", PY_FILE],
        input=parser_result.stdout,
        capture_output=True,
        timeout=10,
    )
    assert aggregate_result.returncode == 0, f"pipeline aggregation failed: {aggregate_result.stderr.decode()}"
    pipeline_output = aggregate_result.stdout.decode().strip()
    assert pipeline_output == "105", f"Pipeline produced {pipeline_output!r} instead of '105'."

    assert os.path.isfile(SUMMARY_FILE), f"File {SUMMARY_FILE} is missing. Did you save the final output?"
    with open(SUMMARY_FILE, "r") as summary_file:
        raw_content = summary_file.read()
    content = raw_content.strip()
    assert content == "105", f"Expected downtime summary to be '105', but got '{content}'."
    assert re.fullmatch(r"105\n?", raw_content), "The summary file must contain only the total integer value."
    assert content == pipeline_output, "The saved summary does not match a fresh run of the pipeline."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
