#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess

AGENT_SCRIPT = "/home/user/process_telemetry"
ORACLE_SCRIPT = "/tests/oracle_processor"
FINAL_ANALYSIS = "/home/user/final_analysis.csv"


def generate_fuzz_input(seed):
    random.seed(seed)
    num_lines = random.randint(10, 50)
    lines = []
    sensors_list = ["alpha", "beta", "gamma", "delta"]

    for _ in range(num_lines):
        time = random.randint(1000000, 1001000)
        if lines and random.random() < 0.1:
            time = json.loads(random.choice(lines))["time"]

        sensors = {}
        num_sensors = random.randint(1, 4)
        chosen_sensors = random.sample(sensors_list, num_sensors)
        for sensor in chosen_sensors:
            sensors[sensor] = round(random.uniform(-100.0, 100.0), 4)

        lines.append(json.dumps({"time": time, "sensors": sensors}))

    return "\n".join(lines) + "\n"


def run_script(path, input_data):
    return subprocess.run(
        [path],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=30,
    )


def test_final_analysis_csv_exists_and_is_correct():
    assert os.path.isfile(FINAL_ANALYSIS), f"Missing final output file: {FINAL_ANALYSIS}"
    with open(FINAL_ANALYSIS, "r") as f:
        actual = f.read()
    assert len(actual.strip()) > 0, f"File {FINAL_ANALYSIS} is empty."

    with open("/app/historical_logs.jsonl", "r") as f:
        combined = f.read()
    if combined and not combined.endswith("\n"):
        combined += "\n"

    # Entries spoken in /app/intercept.wav.
    combined += json.dumps({
        "time": 1600000010,
        "sensors": {"alpha": 15.0, "beta": 9.5},
    }) + "\n"
    combined += json.dumps({
        "time": 1600000015,
        "sensors": {"alpha": 20.0},
    }) + "\n"

    oracle_proc = run_script(ORACLE_SCRIPT, combined)
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"

    agent_proc = run_script(AGENT_SCRIPT, combined)
    assert agent_proc.returncode == 0, f"Agent script failed on merged telemetry: {agent_proc.stderr}"
    assert agent_proc.stdout == oracle_proc.stdout, (
        "Agent script produced incorrect output for the historical and recovered telemetry."
    )
    assert actual == oracle_proc.stdout, (
        f"{FINAL_ANALYSIS} is not the normalized result of combining the historical logs "
        "with the entries recovered from the audio intercept."
    )


def test_process_telemetry_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Missing agent script: {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script is not executable: {AGENT_SCRIPT}"

    assert os.path.isfile(ORACLE_SCRIPT), f"Missing oracle script: {ORACLE_SCRIPT}"
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script is not executable: {ORACLE_SCRIPT}"

    with open(AGENT_SCRIPT, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_SCRIPT, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent script must not be a byte-identical copy of the reference implementation."

    for i in range(100):
        input_data = generate_fuzz_input(seed=42 + i)

        oracle_proc = run_script(ORACLE_SCRIPT, input_data)
        assert oracle_proc.returncode == 0, (
            f"Oracle failed on input:\n{input_data}\nStderr: {oracle_proc.stderr}"
        )

        agent_proc = run_script(AGENT_SCRIPT, input_data)
        assert agent_proc.returncode == 0, (
            f"Agent script failed on input:\n{input_data}\nStderr: {agent_proc.stderr}"
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on fuzz iteration {i}.\n"
            f"Input JSONL:\n{input_data}\n"
            f"Oracle Output:\n{oracle_proc.stdout}\n"
            f"Agent Output:\n{agent_proc.stdout}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
