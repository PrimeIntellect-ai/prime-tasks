#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import subprocess
import time
import urllib.request


def read_config():
    config_path = "/app/perf_env/config.env"
    assert os.path.isfile(config_path), f"Config file {config_path} not found."

    values = {}
    with open(config_path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            assert "=" in line, f"Invalid config line: {line}"
            key, value = line.split("=", 1)
            key = key.strip()
            assert key not in values, f"Duplicate config key: {key}"
            values[key] = value.strip()
    return values


def stop_services():
    subprocess.run(
        ["redis-cli", "-p", "6380", "shutdown", "nosave"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        timeout=5,
    )
    subprocess.run(
        ["pkill", "-f", "python3 /app/perf_env/api.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.5)


def test_service_configuration_and_execution():
    values = read_config()
    assert values.get("REDIS_PORT") == "6380", "REDIS_PORT must be 6380"
    assert values.get("FLASK_PORT") == "5000", "FLASK_PORT must be 5000"
    assert values.get("API_URL") == "http://127.0.0.1:5000", \
        "API_URL must target http://127.0.0.1:5000"

    start_script = "/app/perf_env/start_services.sh"
    assert os.path.isfile(start_script), f"Startup script {start_script} not found."
    assert os.access(start_script, os.X_OK), f"Startup script {start_script} is not executable."

    stop_services()
    log_path = "/home/user/load_gen.log"
    if os.path.exists(log_path):
        os.remove(log_path)

    try:
        result = subprocess.run(
            [start_script],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
        assert result.returncode == 0, "start_services.sh failed"

        redis_ping = subprocess.run(
            ["redis-cli", "-p", "6380", "ping"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert redis_ping.returncode == 0 and redis_ping.stdout.strip() == "PONG", \
            "Redis is not running correctly on port 6380"

        with urllib.request.urlopen("http://127.0.0.1:5000/", timeout=5) as response:
            body = response.read().decode().strip()
            assert response.status == 200 and body == "OK", \
                "Flask API did not successfully communicate with Redis"
    finally:
        stop_services()


def test_load_gen_log():
    log_path = "/home/user/load_gen.log"
    assert os.path.isfile(log_path), f"Log file {log_path} not found. Did the services run?"
    with open(log_path, "r") as f:
        content = f.read()
    assert "Flow Complete" in content, f"'Flow Complete' not found in {log_path}. The services might still be misconfigured."


def test_analyze_metrics_fuzz_equivalence():
    agent_script = "/home/user/analyze_metrics.sh"
    oracle_script = "/tests/analyze_metrics_oracle"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable. Run chmod +x."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} not found."
    assert not filecmp.cmp(agent_script, oracle_script, shallow=False), \
        "Agent submission must not be byte-identical to the reference implementation."

    random.seed(42)
    for i in range(100):
        args = [f"{random.uniform(0.01, 100.00):.2f}" for _ in range(10)]

        agent_res = subprocess.run([agent_script] + args, capture_output=True, text=True)
        oracle_res = subprocess.run([oracle_script] + args, capture_output=True, text=True)

        assert agent_res.returncode == 0, f"Agent script failed on input: {' '.join(args)}\nStderr: {agent_res.stderr}"
        assert oracle_res.returncode == 0, f"Oracle script failed on input: {' '.join(args)}\nStderr: {oracle_res.stderr}"

        agent_out = agent_res.stdout.strip()
        oracle_out = oracle_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on fuzz iteration {i+1} with input: {' '.join(args)}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
