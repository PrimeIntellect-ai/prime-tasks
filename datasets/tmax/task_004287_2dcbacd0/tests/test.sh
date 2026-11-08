#!/bin/bash
set -e
mkdir -p /logs/verifier

passed=1

# The requested artifact must be a real file and must generate the outputs itself.
if [ ! -f /home/user/operator.py ] || [ -L /home/user/operator.py ]; then
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    rm -rf /home/user/proxy_config.json /home/user/operator.log
    if ! timeout 20s python3 /home/user/operator.py; then
        passed=0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

MANIFESTS_DIR = "/home/user/manifests"
PROXY_CONFIG_PATH = "/home/user/proxy_config.json"
LOG_PATH = "/home/user/operator.log"

def compute_expected_state():
    if not os.path.isdir(MANIFESTS_DIR):
        return {}, [], []

    files = sorted(os.listdir(MANIFESTS_DIR))
    config = {}
    json_errors = []
    schema_errors = []

    for filename in files:
        if not filename.endswith(".json"):
            continue

        filepath = os.path.join(MANIFESTS_DIR, filename)
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)
        except json.JSONDecodeError:
            json_errors.append(filename)
            continue

        if not isinstance(data, dict):
            schema_errors.append(filename)
            continue

        if set(data.keys()) != {"route", "target_port", "allowed_ips"}:
            schema_errors.append(filename)
            continue

        if (not isinstance(data["route"], str) or
            not isinstance(data["target_port"], int) or
            not isinstance(data["allowed_ips"], list) or
            not all(isinstance(ip, str) for ip in data["allowed_ips"])):
            schema_errors.append(filename)
            continue

        config[data["route"]] = {
            "target_port": data["target_port"],
            "allowed_ips": data["allowed_ips"]
        }

    return config, json_errors, schema_errors

def test_proxy_config_exists_and_correct():
    assert os.path.isfile(PROXY_CONFIG_PATH), f"Expected configuration file {PROXY_CONFIG_PATH} does not exist."

    with open(PROXY_CONFIG_PATH, 'r') as f:
        try:
            actual_config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PROXY_CONFIG_PATH} is not valid JSON.")

    expected_config, _, _ = compute_expected_state()
    assert actual_config == expected_config, f"Contents of {PROXY_CONFIG_PATH} do not match the expected configuration."

def test_operator_log_correct():
    assert os.path.isfile(LOG_PATH), f"Expected log file {LOG_PATH} does not exist."

    with open(LOG_PATH, 'r') as f:
        log_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(log_lines) > 0, f"Log file {LOG_PATH} is empty."
    assert log_lines[0] == "OPERATOR RUN STARTED", "Log file must start with 'OPERATOR RUN STARTED'."
    assert log_lines[-1] == "OPERATOR RUN COMPLETED", "Log file must end with 'OPERATOR RUN COMPLETED'."

    expected_config, json_errors, schema_errors = compute_expected_state()

    middle_lines = log_lines[1:-1]

    for err_file in json_errors:
        expected_err = f"ERROR: Invalid JSON in {err_file}"
        assert expected_err in middle_lines, f"Missing expected error log for JSON decode failure: {expected_err}"

    for err_file in schema_errors:
        expected_err = f"ERROR: Invalid schema in {err_file}"
        assert expected_err in middle_lines, f"Missing expected error log for schema validation failure: {expected_err}"

    success_lines = [line for line in middle_lines if line.startswith("SUCCESS:")]
    expected_success_lines = []
    for route in sorted(expected_config.keys()):
        port = expected_config[route]["target_port"]
        expected_success_lines.append(f"SUCCESS: Configured route {route} to port {port}")

    assert success_lines == expected_success_lines, "SUCCESS log lines are either incorrect or not in alphabetical order by route."
TEST_EOF

if [ "$passed" -eq 1 ]; then
    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
        passed=0
    fi
fi

# Exercise the submitted operator against manifests created only at verification time.
cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_operator.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

MANIFESTS = "/home/user/manifests"
OPERATOR = "/home/user/operator.py"
CONFIG = "/home/user/proxy_config.json"
LOG = "/home/user/operator.log"

token = secrets.token_hex(8)
backup = tempfile.mkdtemp(prefix="operator-manifests-")
os.rmdir(backup)
os.rename(MANIFESTS, backup)
os.mkdir(MANIFESTS)

route_a = f"/dynamic-{token}-z"
route_b = f"/dynamic-{token}-a"
low_name = f"10_{token}.json"
high_name = f"90_{token}.json"
other_name = f"40_{token}.json"
broken_name = f"30_broken_{token}.json"
schema_name = f"50_schema_{token}.json"
types_name = f"60_types_{token}.json"

expected = {
    route_a: {"target_port": 32102, "allowed_ips": ["192.0.2.10", "198.51.100.0/24"]},
    route_b: {"target_port": 32103, "allowed_ips": []},
}

try:
    def write_json(name, value):
        with open(os.path.join(MANIFESTS, name), "w") as f:
            json.dump(value, f)

    write_json(low_name, {
        "route": route_a,
        "target_port": 32101,
        "allowed_ips": ["203.0.113.1"],
    })
    write_json(high_name, {
        "route": route_a,
        "target_port": 32102,
        "allowed_ips": ["192.0.2.10", "198.51.100.0/24"],
    })
    write_json(other_name, {
        "route": route_b,
        "target_port": 32103,
        "allowed_ips": [],
    })
    with open(os.path.join(MANIFESTS, broken_name), "w") as f:
        f.write('{"route": "unterminated"')
    write_json(schema_name, {
        "route": f"/missing-{token}",
        "target_port": 32104,
    })
    write_json(types_name, {
        "route": f"/wrong-type-{token}",
        "target_port": "32105",
        "allowed_ips": ["127.0.0.1"],
    })
    with open(os.path.join(MANIFESTS, f"ignored_{token}.txt"), "w") as f:
        f.write("not a manifest")

    def run_and_check():
        for path in (CONFIG, LOG):
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)

        result = subprocess.run(
            ["python3", OPERATOR],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"operator.py failed on runtime manifests: {result.stderr}"
        )
        assert os.path.isfile(CONFIG), "operator.py did not create proxy_config.json"
        assert os.path.isfile(LOG), "operator.py did not create operator.log"

        with open(CONFIG) as f:
            actual = json.load(f)
        assert actual == expected, "operator.py produced the wrong dynamic configuration"

        with open(LOG) as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines, "operator.log is empty"
        assert lines[0] == "OPERATOR RUN STARTED"
        assert lines[-1] == "OPERATOR RUN COMPLETED"
        middle = lines[1:-1]
        assert f"ERROR: Invalid JSON in {broken_name}" in middle
        assert f"ERROR: Invalid schema in {schema_name}" in middle
        assert f"ERROR: Invalid schema in {types_name}" in middle
        successes = [line for line in middle if line.startswith("SUCCESS:")]
        expected_successes = [
            f"SUCCESS: Configured route {route} to port {expected[route]['target_port']}"
            for route in sorted(expected)
        ]
        assert successes == expected_successes

    run_and_check()
    run_and_check()
finally:
    if os.path.lexists(MANIFESTS):
        if os.path.isdir(MANIFESTS) and not os.path.islink(MANIFESTS):
            shutil.rmtree(MANIFESTS)
        else:
            os.unlink(MANIFESTS)
    os.rename(backup, MANIFESTS)
DYNAMIC_EOF

if [ "$passed" -eq 1 ]; then
    if ! python3 /tmp/test_dynamic_operator.py; then
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
