#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat

import pytest
import requests

SERVER_URL = "http://127.0.0.1:8080/analyze"


def get_expected_status(module_name: str) -> str:
    h = hashlib.md5(module_name.encode()).hexdigest()
    first_char = h[0]
    if int(first_char, 16) % 2 == 0:
        return "APPROVED"
    else:
        return "REJECTED"


def post_payload(payload):
    try:
        return requests.post(
            SERVER_URL,
            data=payload,
            headers={"Content-Type": "text/plain"},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the HTTP server at 127.0.0.1:8080. Is it running?")
    except requests.exceptions.Timeout:
        pytest.fail("Request to 127.0.0.1:8080/analyze timed out.")


def parse_response(response):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except (json.JSONDecodeError, ValueError):
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "failing_modules" in data, "Response JSON is missing 'failing_modules' key"
    assert "checker_results" in data, "Response JSON is missing 'checker_results' key"
    return data


def test_01_analyze_endpoint_original_case():
    assert os.path.isfile("/home/user/server.py"), "/home/user/server.py is missing or is not a regular file"

    payload = """Compiling artifact_manager v0.1.0 (/home/user/project)
error[E0106]: missing lifetime specifier
  --> src/state_machine.rs:22:12
   |
22 |     parser: &Parser,
   |             ^ expected named lifetime parameter

error[E0502]: cannot borrow `*pipeline` as mutable because it is also borrowed as immutable
  --> src/cicd_runner.rs:45:5
"""

    data = parse_response(post_payload(payload))

    expected_modules = ["state_machine", "cicd_runner"]
    assert set(data["failing_modules"]) == set(expected_modules), \
        f"Expected failing_modules to contain {expected_modules}, got {data['failing_modules']}"

    expected_results = {
        mod: get_expected_status(mod) for mod in expected_modules
    }
    assert data["checker_results"] == expected_results, \
        f"Expected checker_results to be {expected_results}, got {data['checker_results']}"


def test_02_randomized_parsing_and_binary_integration():
    module_names = ["mod_" + secrets.token_hex(7) for _ in range(4)]
    expected_results = {
        name: ("REJECTED" if get_expected_status(name) == "APPROVED" else "APPROVED")
        for name in module_names
    }

    binary = "/app/module_checker"
    backup = f"/tmp/module_checker.original.{os.getpid()}"
    call_log = f"/tmp/module_checker.calls.{os.getpid()}"
    open(call_log, "w").close()
    os.chmod(call_log, 0o666)

    os.replace(binary, backup)
    try:
        wrapper = f'''#!/usr/bin/env python3
import json
import sys

statuses = {expected_results!r}
with open({call_log!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")

if len(sys.argv) == 3 and sys.argv[1] == "-target" and sys.argv[2] in statuses:
    print("STATUS: " + statuses[sys.argv[2]])
    sys.exit(0)
print("Usage: module_checker -target <module_name>")
sys.exit(0)
'''
        with open(binary, "w") as f:
            f.write(wrapper)
        os.chmod(binary, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                         stat.S_IRGRP | stat.S_IXGRP |
                         stat.S_IROTH | stat.S_IXOTH)

        payload = f"""Compiling randomized_workspace v0.1.0 (/tmp/randomized)
warning: unrelated source location
  --> src/ignore_{secrets.token_hex(4)}.rs:1:1

error[E0597]: value does not live long enough
  --> src/{module_names[0]}.rs:14:5
   |
14 | temporary code

error[E0106]: missing lifetime specifier
  --> src/{module_names[1]}.rs:27:9

note: another unrelated location
  --> src/ignore_{secrets.token_hex(4)}.rs:31:2

error[E0502]: cannot borrow as mutable
  --> src/{module_names[2]}.rs:45:5

error: aborting due to previous error
  --> src/{module_names[3]}.rs:99:3
"""
        data = parse_response(post_payload(payload))

        assert set(data["failing_modules"]) == set(module_names), (
            f"Expected randomized failing modules {module_names}, got {data['failing_modules']}"
        )
        assert data["checker_results"] == expected_results, (
            f"Expected checker_results from module_checker to be {expected_results}, "
            f"got {data['checker_results']}"
        )

        with open(call_log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        invoked_targets = {
            args[1] for args in calls
            if len(args) == 2 and args[0] == "-target"
        }
        assert set(module_names).issubset(invoked_targets), (
            "The server did not invoke /app/module_checker -target for every extracted module. "
            f"Observed calls: {calls}"
        )
    finally:
        try:
            if os.path.lexists(binary):
                os.unlink(binary)
        finally:
            os.replace(backup, binary)
        try:
            os.unlink(call_log)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
