#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
from datetime import datetime, timedelta

AGENT_SCRIPT = "/home/user/process_line.py"
BASH_SCRIPT = "/home/user/run_pipeline.sh"
ORACLE_SCRIPT = "/tests/oracle_processor.py"
PIPELINE_LOG = "/home/user/pipeline.log"


def test_files_exist():
    """Verify that the required scripts were created."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.path.isfile(BASH_SCRIPT), f"Bash script missing: {BASH_SCRIPT}"


def generate_valid_string():
    year = random.randint(2000, 2025)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    hour = random.randint(0, 23)
    minute = random.randint(0, 58)
    second = random.randint(0, 58)

    start_dt = datetime(year, month, day, hour, minute, second)
    end_dt = start_dt + timedelta(seconds=random.randint(0, 60))

    val = round(random.uniform(-1000.0, 1000.0), 2)
    status_len = random.randint(2, 8)
    status = "".join(random.choices("ABCDEFGHIJKLMNOPQRSTUVWXYZ", k=status_len))

    start_str = start_dt.strftime('%Y-%m-%dT%H:%M:%S')
    end_str = end_dt.strftime('%Y-%m-%dT%H:%M:%S')

    return f"[{start_str}] TO [{end_str}] VALUE: {val} STATUS: {status}"


def generate_invalid_string():
    base = generate_valid_string()
    corruption_type = random.randint(0, 5)
    if corruption_type == 0:
        return base.replace("TO", "UNTIL")
    if corruption_type == 1:
        return base.replace("[", "", 1)
    if corruption_type == 2:
        return base + " EXTRA"
    if corruption_type == 3:
        return base.replace("VALUE:", "VAL:")
    if corruption_type == 4:
        return base.replace("STATUS:", "STAT:")
    return "completely invalid string with random data 12345"


def run_script(script_path, input_str):
    result = subprocess.run(
        ["python3", script_path],
        input=input_str.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    return result.stdout.decode("utf-8").strip()


def test_fuzz_equivalence():
    """Fuzz test the agent script against the oracle script."""
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle missing: {ORACLE_SCRIPT}"

    random.seed(42)
    inputs = [generate_valid_string() for _ in range(250)]
    inputs.extend(generate_invalid_string() for _ in range(250))
    random.shuffle(inputs)

    for i, test_input in enumerate(inputs):
        oracle_output = run_script(ORACLE_SCRIPT, test_input)
        agent_output = run_script(AGENT_SCRIPT, test_input)
        assert oracle_output == agent_output, (
            f"Output mismatch on iteration {i}.\n"
            f"Input:\n{test_input}\n"
            f"Expected (Oracle):\n{oracle_output}\n"
            f"Got (Agent):\n{agent_output}"
        )


def test_pipeline_behavior_and_append():
    """Verify the orchestration script processes every line and appends output."""
    lines = [
        "[2024-02-29T23:59:59] TO [2024-03-01T00:00:01] VALUE: -12.50 STATUS: OK",
        "not a sensor record",
        "[2021-01-01T00:00:00] TO [2021-01-01T00:00:00] VALUE: 0.0 STATUS: READY",
    ]
    expected_batch = "".join(run_script(ORACLE_SCRIPT, line) + "\n" for line in lines)
    prefix = "PREEXISTING\n"

    with tempfile.NamedTemporaryFile("w", delete=False) as source:
        source.write("\n".join(lines) + "\n")
        source_path = source.name

    try:
        with open(PIPELINE_LOG, "w", encoding="utf-8") as log_file:
            log_file.write(prefix)

        for _ in range(2):
            result = subprocess.run(
                ["bash", BASH_SCRIPT, source_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert result.returncode == 0, (
                f"Pipeline exited with {result.returncode}: "
                f"{result.stderr.decode('utf-8', errors='replace')}"
            )

        with open(PIPELINE_LOG, "r", encoding="utf-8") as log_file:
            actual = log_file.read()
        assert actual == prefix + expected_batch + expected_batch
    finally:
        os.unlink(source_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
