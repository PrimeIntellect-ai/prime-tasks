#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import string
import subprocess
import pytest


def find_agent_script():
    candidates = [p for p in glob.glob("/home/user/log_filter.*") if os.path.isfile(p)]
    assert candidates, "Agent script /home/user/log_filter.py (or another extension such as .pl or .sh) is missing."

    for extension in (".py", ".pl", ".sh"):
        preferred = "/home/user/log_filter" + extension
        if preferred in candidates:
            return preferred
    return sorted(candidates)[0]


def agent_command(script):
    if os.access(script, os.X_OK):
        return [script]
    if script.endswith(".py"):
        return ["python3", script]
    if script.endswith(".pl"):
        return ["perl", script]
    if script.endswith(".sh"):
        return ["bash", script]
    pytest.fail(f"Agent script is not executable: {script}")


def generate_random_log(num_records):
    levels = ["INFO", "WARN", "ERROR", "TRACE"]
    log_bytes = bytearray()
    for _ in range(num_records):
        year = random.randint(2000, 2025)
        month = random.randint(1, 12)
        day = random.randint(1, 28)
        hour = random.randint(0, 23)
        minute = random.randint(0, 59)
        sec = random.randint(0, 59)
        level = random.choice(levels)

        header = f"[{year:04d}-{month:02d}-{day:02d} {hour:02d}:{minute:02d}:{sec:02d}] [{level}]\n"
        log_bytes.extend(header.encode("utf-8"))

        num_lines = random.randint(1, 10)
        for _ in range(num_lines):
            line_len = random.randint(10, 50)
            line = "".join(random.choice(string.ascii_letters + string.digits + " \t.,;:'\"!?\xC0\xC1\xC2\xC3\xC4\xC5\xE0\xE1\xE2\xE3\xE4\xE5") for _ in range(line_len))
            log_bytes.extend(line.encode("iso-8859-1"))
            log_bytes.extend(b"\n")

    return bytes(log_bytes)


def test_agent_script_exists():
    assert os.path.isfile(find_agent_script())


def test_fuzz_equivalence():
    agent_script = find_agent_script()
    oracle_script = "/tests/log_filter_oracle.py"

    assert os.path.isfile(agent_script), "Agent script not found."
    assert os.path.isfile(oracle_script), "Oracle script not found."

    random.seed(42)

    for i in range(100):
        num_records = random.randint(5, 50)
        input_data = generate_random_log(num_records)

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test case {i}:\n{oracle_proc.stderr.decode(errors='replace')}"
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            agent_command(agent_script),
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        assert agent_proc.returncode == 0, f"Agent script failed on test case {i}:\n{agent_proc.stderr.decode(errors='replace')}"
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            input_preview = input_data[:200].decode(errors="replace")
            oracle_preview = oracle_out[:200].decode(errors="replace")
            agent_preview = agent_out[:200].decode(errors="replace")
            pytest.fail(
                f"Mismatch on test case {i}.\n"
                f"Input preview:\n{input_preview}...\n\n"
                f"Expected output preview:\n{oracle_preview}...\n\n"
                f"Agent output preview:\n{agent_preview}..."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
