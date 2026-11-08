#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
from collections import defaultdict

SCRIPT_PATH = "/home/user/process_graph.sh"
INPUT_PATH = "/home/user/server_logs.jsonl"
OUTPUT_PATH = "/home/user/top_targets.json"


def compute_expected(input_path):
    in_degrees = defaultdict(int)
    with open(input_path, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("status") == "OK":
                target = record.get("target")
                if target:
                    in_degrees[target] += 1

    sorted_targets = sorted(in_degrees.items(), key=lambda x: (-x[1], x[0]))
    return [
        {"server": server, "in_degree": count}
        for server, count in sorted_targets[:3]
    ]


def assert_output_matches(expected_output):
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {OUTPUT_PATH} is not valid JSON."

    assert isinstance(actual_output, list), f"Output in {OUTPUT_PATH} must be a JSON array."
    assert len(actual_output) == len(expected_output), (
        f"Expected {len(expected_output)} items, got {len(actual_output)}."
    )

    for i, (expected, actual) in enumerate(zip(expected_output, actual_output)):
        assert actual == expected, (
            f"Mismatch at index {i}: expected {expected}, got {actual}."
        )


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=20,
    )


def test_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_output_json_correctness():
    """Execute the script and test its output for the supplied logs."""
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    expected_output = compute_expected(INPUT_PATH)
    run_script()
    assert_output_matches(expected_output)


def test_script_processes_new_input():
    """Ensure the script implements the ETL rather than emitting fixture-specific output."""
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    token = secrets.token_hex(8)
    target_a = f"node_a_{token}"
    target_b = f"node_b_{token}"
    target_c = f"node_c_{token}"
    target_d = f"node_d_{token}"

    records = []
    for i in range(5):
        records.append({"source": f"src_a_{i}_{token}", "target": target_a, "status": "OK"})
    for i in range(4):
        records.append({"source": f"src_b_{i}_{token}", "target": target_b, "status": "OK"})
        records.append({"source": f"src_c_{i}_{token}", "target": target_c, "status": "OK"})
    for i in range(2):
        records.append({"source": f"src_d_{i}_{token}", "target": target_d, "status": "OK"})
    for i in range(7):
        records.append({"source": f"failed_{i}_{token}", "target": target_d, "status": "FAIL"})
    records.append({"source": f"lowercase_{token}", "target": target_d, "status": "ok"})

    secrets.SystemRandom().shuffle(records)

    try:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        expected_output = compute_expected(INPUT_PATH)
        run_script()
        assert_output_matches(expected_output)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
