#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import csv
import io
import pytest

AGENT_BIN = "/app/log-processor/target/release/log-processor"
ORACLE_BIN = "/opt/oracle/log_processor_oracle"


def generate_csv_data(seed):
    random.seed(seed)
    num_rows = random.randint(50, 500)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["timestamp", "ip", "message", "cpu_temp", "gpu_temp"])

    emojis = ["🚨", "📊", "🔥", "❄️", "💻"]

    for _ in range(num_rows):
        timestamp = f"2023-10-01T{random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}Z"
        ip = f"{random.randint(1,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,255)}"

        msg_len = random.randint(5, 50)
        msg_chars = random.choices(string.ascii_letters + string.digits + " ", k=msg_len)
        if random.random() < 0.3:
            msg_chars.insert(random.randint(0, len(msg_chars)), "\n")
        if random.random() < 0.2:
            msg_chars.append(random.choice(emojis))
        message = "".join(msg_chars)

        cpu_temp = "" if random.random() < 0.15 else f"{random.uniform(30.0, 90.0):.2f}"
        gpu_temp = "" if random.random() < 0.15 else f"{random.uniform(40.0, 100.0):.2f}"

        writer.writerow([timestamp, ip, message, cpu_temp, gpu_temp])

    return output.getvalue().encode("utf-8")


def expected_output(csv_data):
    source = io.StringIO(csv_data.decode("utf-8"), newline="")
    reader = csv.reader(source)
    header = next(reader)
    assert header == ["timestamp", "ip", "message", "cpu_temp", "gpu_temp"]

    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["timestamp", "ip", "message", "sensor_type", "temperature"])

    last_cpu = None
    last_gpu = None

    for row in reader:
        assert len(row) == 5
        timestamp, ip, message, cpu_temp, gpu_temp = row
        masked_ip = ip.rsplit(".", 1)[0] + ".XXX"

        if cpu_temp == "":
            cpu_output = last_cpu if last_cpu is not None else "0.0"
        else:
            last_cpu = cpu_temp
            cpu_output = cpu_temp

        if gpu_temp == "":
            gpu_output = last_gpu if last_gpu is not None else "0.0"
        else:
            last_gpu = gpu_temp
            gpu_output = gpu_temp

        writer.writerow([timestamp, masked_ip, message, "cpu", cpu_output])
        writer.writerow([timestamp, masked_ip, message, "gpu", gpu_output])

    return output.getvalue().encode("utf-8")


def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}. Did you build in release mode?"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable."


def test_oracle_binary_exists():
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}."
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary at {ORACLE_BIN} is not executable."


@pytest.mark.parametrize("seed", range(200))
def test_fuzz_equivalence(seed):
    csv_data = generate_csv_data(seed)

    oracle_proc = subprocess.run(
        [ORACLE_BIN],
        input=csv_data,
        capture_output=True,
        check=False
    )
    assert oracle_proc.returncode == 0, f"Oracle failed on seed {seed} with stderr: {oracle_proc.stderr.decode(errors='replace')}"

    agent_proc = subprocess.run(
        [AGENT_BIN],
        input=csv_data,
        capture_output=True,
        check=False
    )
    assert agent_proc.returncode == 0, f"Agent failed on seed {seed} with stderr: {agent_proc.stderr.decode(errors='replace')}"

    expected_stdout = expected_output(csv_data)
    agent_stdout = agent_proc.stdout

    if expected_stdout != agent_stdout:
        expected_lines = expected_stdout.decode(errors="replace").splitlines()
        agent_lines = agent_stdout.decode(errors="replace").splitlines()

        diff_idx = -1
        for i, (expected_line, agent_line) in enumerate(zip(expected_lines, agent_lines)):
            if expected_line != agent_line:
                diff_idx = i
                break
        if diff_idx == -1 and len(expected_lines) != len(agent_lines):
            diff_idx = min(len(expected_lines), len(agent_lines))

        error_msg = f"Mismatch on seed {seed}.\n"
        if diff_idx != -1:
            expected_line = expected_lines[diff_idx] if diff_idx < len(expected_lines) else "EOF"
            agent_line = agent_lines[diff_idx] if diff_idx < len(agent_lines) else "EOF"
            error_msg += f"First diff at line {diff_idx + 1}:\n"
            error_msg += f"Expected: {expected_line}\n"
            error_msg += f"Agent   : {agent_line}\n"

        pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
