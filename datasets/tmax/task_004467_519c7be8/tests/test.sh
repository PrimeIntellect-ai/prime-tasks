#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import string
import subprocess
import pytest


def test_part1_initial_report():
    report_path = "/home/user/initial_report.json"
    assert os.path.exists(report_path), f"{report_path} does not exist. Did you run the transcription tool?"

    with open(report_path, "r") as f:
        data = f.read().strip()

    expected_json = {
        "id": "A-47",
        "reported_name": "John Doe",
        "expected_name": "Jon Doe",
        "confidence": 0.92,
        "transcript_text": "Agent 47 checking in. Target sighted."
    }

    try:
        actual_json = json.loads(data)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON from {report_path}: {e}")

    assert actual_json == expected_json, f"JSON content in {report_path} does not match the expected transcription output."


def generate_random_string(max_length=100):
    length = random.randint(0, max_length)
    chars = string.ascii_letters + string.digits + string.punctuation + " "
    return ''.join(random.choices(chars, k=length))


def generate_fuzz_input(n=1000):
    random.seed(42)
    lines = []
    for _ in range(n):
        obj = {
            "id": generate_random_string(20) if random.random() > 0.1 else "",
            "reported_name": generate_random_string(50),
            "expected_name": generate_random_string(50),
            "confidence": random.uniform(0.0, 1.0),
            "transcript_text": generate_random_string(100)
        }
        lines.append(json.dumps(obj))
    return "\n".join(lines)


def test_part2_fuzz_equivalence():
    agent_source = "/home/user/etl_processor.go"
    agent_bin = "/home/user/etl_processor"
    oracle_bin = "/tests/etl_processor_oracle"
    source_bin = "/tmp/etl_processor_from_source"

    assert os.path.isfile(agent_source), f"Go source {agent_source} is missing."
    assert os.path.exists(agent_bin), f"Agent binary {agent_bin} is missing. Did you compile your Go program?"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."

    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} is missing."
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable."
    assert not filecmp.cmp(agent_bin, oracle_bin, shallow=False), "Agent binary must not be a byte-identical copy of the oracle."

    build = subprocess.run(
        ["go", "build", "-o", source_bin, agent_source],
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Failed to compile {agent_source}: {build.stderr}"

    fuzz_input = generate_fuzz_input(1000)

    proc_oracle = subprocess.run([oracle_bin], input=fuzz_input, text=True, capture_output=True)
    assert proc_oracle.returncode == 0, f"Oracle failed with error: {proc_oracle.stderr}"
    oracle_out = proc_oracle.stdout

    proc_agent = subprocess.run([agent_bin], input=fuzz_input, text=True, capture_output=True)
    assert proc_agent.returncode == 0, f"Agent binary failed with error: {proc_agent.stderr}"
    agent_out = proc_agent.stdout

    proc_source = subprocess.run([source_bin], input=fuzz_input, text=True, capture_output=True)
    assert proc_source.returncode == 0, f"Program compiled from agent source failed with error: {proc_source.stderr}"
    source_out = proc_source.stdout

    if oracle_out != agent_out:
        for line in fuzz_input.splitlines():
            p_o = subprocess.run([oracle_bin], input=line, text=True, capture_output=True)
            p_a = subprocess.run([agent_bin], input=line, text=True, capture_output=True)
            if p_o.stdout != p_a.stdout:
                pytest.fail(
                    f"Mismatch found!\n"
                    f"Input JSON: {line}\n"
                    f"Expected Output (Oracle): {p_o.stdout.strip() or '<empty>'}\n"
                    f"Actual Output (Agent): {p_a.stdout.strip() or '<empty>'}"
                )
        pytest.fail("Agent output does not match oracle output on fuzzed inputs.")

    assert source_out == oracle_out, "The submitted Go source does not compile to a program matching the required behavior."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
