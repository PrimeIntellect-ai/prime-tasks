#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import pytest

def generate_fuzz_data(n=10000, seed=42):
    random.seed(seed)
    metrics = ["latency", "throughput", "error_rate", "cpu_usage", "memory_usage"]
    locales = ["en_US", "fr_FR", "de_DE", "es_ES", "ru_RU", "it_IT", "pt_BR", "zh_CN", "ja_JP", "ko_KR"]

    def format_value(val, locale):
        s = f"{val:,.2f}"
        if locale in ["fr_FR", "ru_RU"]:
            s = s.replace(",", " ").replace(".", ",")
            if locale == "fr_FR":
                s = s.replace(" ", "\u00A0")
            else:
                s = s.replace(" ", "\u202F")
        elif locale in ["de_DE", "es_ES", "it_IT", "pt_BR"]:
            s = s.replace(",", "X").replace(".", ",").replace("X", ".")
        return s

    lines = []
    ts = 1679900000
    for _ in range(n):
        ts += random.randint(1, 10)
        metric = random.choice(metrics)
        locale = random.choice(locales)
        val = random.uniform(0.01, 10000.00)
        raw_value = format_value(val, locale)

        record = {
            "timestamp": ts,
            "locale": locale,
            "raw_value": raw_value,
            "metric": metric
        }
        lines.append(json.dumps(record))
    return "\n".join(lines) + "\n"

def test_executable_exists():
    agent_script = "/home/user/normalize_stream.sh"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

def test_fuzz_equivalence():
    agent_script = "/home/user/normalize_stream.sh"
    oracle_script = "/tests/reference_parser.py"

    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} missing."

    input_data = generate_fuzz_data(n=10000, seed=1337)
    input_bytes = input_data.encode('utf-8')

    # Run Oracle
    oracle_proc = subprocess.run(
        ["python3", oracle_script],
        input=input_bytes,
        capture_output=True,
        timeout=30
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr.decode()}"
    oracle_out = oracle_proc.stdout.decode('utf-8')

    # Run Agent
    agent_proc = subprocess.run(
        [agent_script],
        input=input_bytes,
        capture_output=True,
        timeout=30
    )
    assert agent_proc.returncode == 0, f"Agent script failed: {agent_proc.stderr.decode()}"
    agent_out = agent_proc.stdout.decode('utf-8')

    # Compare
    oracle_lines = oracle_out.strip().split('\n')
    agent_lines = agent_out.strip().split('\n')

    assert len(oracle_lines) == len(agent_lines), f"Line count mismatch: Oracle={len(oracle_lines)}, Agent={len(agent_lines)}"

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, (
            f"Mismatch at line {i+1}.\n"
            f"Input JSON: {input_data.strip().split(chr(10))[i]}\n"
            f"Expected (Oracle): {o_line}\n"
            f"Actual (Agent):    {a_line}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
