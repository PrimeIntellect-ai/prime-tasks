#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import datetime
import pytest

def test_pipeline_script_exists():
    """Verify that the pipeline script exists and contains the expected command."""
    script_path = '/home/user/pipeline.sh'
    assert os.path.isfile(script_path), f"Pipeline script {script_path} does not exist"

    with open(script_path, 'r') as f:
        content = f.read()

    expected_fragments = [
        'cat /home/user/data.jsonl',
        'python3 /home/user/stream_cleaner.py',
        '> /home/user/cleaned_output.txt'
    ]
    for fragment in expected_fragments:
        assert fragment in content, f"Pipeline script is missing expected command fragment: '{fragment}'"

def test_crontab_configured():
    """Verify that the crontab is configured to run the pipeline script every 5 minutes."""
    result = subprocess.run(['crontab', '-u', 'user', '-l'], capture_output=True, text=True)
    if result.returncode != 0:
        # Fallback to current user if running as user
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)

    assert result.returncode == 0, "Failed to read crontab"

    crontab_content = result.stdout
    assert '/home/user/pipeline.sh' in crontab_content, "Crontab does not run /home/user/pipeline.sh"

    # Check for 5 minute interval (*/5 or explicit list)
    valid_intervals = ['*/5 * * * *', '0,5,10,15,20,25,30,35,40,45,50,55 * * * *']
    has_valid_interval = any(interval in crontab_content for interval in valid_intervals)
    assert has_valid_interval, "Crontab is not configured to run exactly every 5 minutes"

def generate_fuzz_data(n=500, seed=42):
    """Generate fuzzed JSONL data according to the distribution."""
    random.seed(seed)
    lines = []
    sensors = ["A", "B", "C", "D", "E"]
    base_time = datetime.datetime(2023, 1, 1, 12, 0, 0)

    for i in range(n):
        if random.random() < 0.05:
            # Invalid line injection (5%)
            err_type = random.choice(['missing', 'malformed', 'bad_type'])
            if err_type == 'missing':
                d = {"sensor_id": random.choice(sensors), "timestamp": (base_time + datetime.timedelta(seconds=i)).isoformat()}
                lines.append(json.dumps(d))
            elif err_type == 'malformed':
                lines.append('{"sensor_id": "A", "timestamp": "2023-01-01T12:00:00", "value": 100.0')
            else:
                d = {"sensor_id": random.choice(sensors), "timestamp": (base_time + datetime.timedelta(seconds=i)).isoformat(), "value": "not-a-float"}
                lines.append(json.dumps(d))
        else:
            # Valid line
            d = {
                "sensor_id": random.choice(sensors),
                "timestamp": (base_time + datetime.timedelta(seconds=i)).isoformat(),
                "value": round(random.uniform(10.0, 1000.0), 2)
            }
            lines.append(json.dumps(d))
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    """Run both the oracle and the agent's script on fuzzed input and assert exact match."""
    agent_script = "/home/user/stream_cleaner.py"
    oracle_script = "/opt/oracle_cleaner.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found"
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} not found"

    # Generate 500 lines of data
    input_data = generate_fuzz_data(500, seed=1337)

    # Run oracle
    oracle_proc = subprocess.run(
        ['python3', oracle_script],
        input=input_data,
        capture_output=True,
        text=True,
        check=True
    )
    oracle_out = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        ['python3', agent_script],
        input=input_data,
        capture_output=True,
        text=True
    )

    assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"

    agent_out = agent_proc.stdout

    if oracle_out != agent_out:
        oracle_lines = oracle_out.splitlines()
        agent_lines = agent_out.splitlines()

        diff_msg = "Output mismatch between Oracle and Agent.\n"
        for i, (ol, al) in enumerate(zip(oracle_lines, agent_lines)):
            if ol != al:
                diff_msg += f"First mismatch at line {i+1}:\nOracle: {ol}\nAgent : {al}\n"
                break

        if len(oracle_lines) != len(agent_lines):
            diff_msg += f"\nLength mismatch: Oracle produced {len(oracle_lines)} lines, Agent produced {len(agent_lines)} lines."

        pytest.fail(diff_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
