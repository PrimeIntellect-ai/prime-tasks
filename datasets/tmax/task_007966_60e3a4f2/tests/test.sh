#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import stat
import subprocess

import pytest

GET_ENDPOINTS = "/home/user/get_endpoints.py"
DIAGNOSE = "/home/user/diagnose.py"
REGISTRY = "/home/user/registry_cli.py"
FAILING_IPS = "/home/user/failing_ips.txt"
DIAG_REPORT = "/home/user/diag_report.json"
ORIGINAL_IPS = ["10.0.5.12", "10.0.5.19", "10.0.5.24"]


def run_script(path):
    result = subprocess.run(
        ["python3", path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def assert_uses_pexpect_spawn(path):
    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    module_aliases = set()
    spawn_aliases = set()
    imported_pexpect = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    imported_pexpect = True
                    module_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            imported_pexpect = True
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or "spawn")
                elif alias.name == "*":
                    spawn_aliases.add("spawn")

    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in spawn_aliases:
            uses_spawn = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "spawn"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in module_aliases
        ):
            uses_spawn = True

    assert imported_pexpect, f"{path} must import the pexpect library."
    assert uses_spawn, f"{path} must use pexpect.spawn to drive the registry console."


def test_scripts_execute_and_generate_outputs():
    assert os.path.isfile(GET_ENDPOINTS), f"Script {GET_ENDPOINTS} is missing or not a regular file."
    assert os.path.isfile(DIAGNOSE), f"Script {DIAGNOSE} is missing or not a regular file."
    assert_uses_pexpect_spawn(GET_ENDPOINTS)

    nonce = secrets.randbelow(150) + 50
    challenge_ips = [f"172.29.{nonce}.11", f"172.29.{nonce}.37", f"172.29.{nonce}.203"]
    audit_path = f"/tmp/registry_audit_{secrets.token_hex(8)}.json"

    with open(REGISTRY, "rb") as f:
        original_registry = f.read()
    original_mode = stat.S_IMODE(os.stat(REGISTRY).st_mode)

    challenge_source = f'''#!/usr/bin/env python3
import json
import sys

events = []
user = input("Username: ")
events.append(["username", user])
if user != "admin":
    sys.exit(3)
pwd = input("Password: ")
events.append(["password", pwd])
if pwd != "micro_pass_42":
    sys.exit(4)
while True:
    cmd = input("registry> ")
    events.append(["command", cmd])
    if cmd == "get-failing-nodes":
        for ip in {challenge_ips!r}:
            print(ip)
    elif cmd == "exit":
        break
    else:
        print("Unknown command.")
with open({audit_path!r}, "w") as audit:
    json.dump(events, audit)
'''

    try:
        with open(REGISTRY, "w") as f:
            f.write(challenge_source)
        os.chmod(REGISTRY, 0o755)
        for path in (FAILING_IPS, audit_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        run_script(GET_ENDPOINTS)

        assert os.path.exists(audit_path), "The registry interaction did not reach the exit command."
        with open(audit_path, "r") as f:
            events = json.load(f)
        assert events == [
            ["username", "admin"],
            ["password", "micro_pass_42"],
            ["command", "get-failing-nodes"],
            ["command", "exit"],
        ], f"Unexpected registry interaction sequence: {events}"

        with open(FAILING_IPS, "r") as f:
            generated_ips = [line.strip() for line in f if line.strip()]
        assert generated_ips == challenge_ips, (
            "get_endpoints.py did not derive failing_ips.txt from the interactive console; "
            f"got {generated_ips}"
        )

        try:
            os.remove(DIAG_REPORT)
        except FileNotFoundError:
            pass
        run_script(DIAGNOSE)
        with open(DIAG_REPORT, "r") as f:
            dynamic_report = json.load(f)
        assert dynamic_report == {ip: "unreachable" for ip in challenge_ips}, (
            f"diagnose.py did not generate its report from failing_ips.txt: {dynamic_report}"
        )
    finally:
        with open(REGISTRY, "wb") as f:
            f.write(original_registry)
        os.chmod(REGISTRY, original_mode)
        try:
            os.remove(audit_path)
        except FileNotFoundError:
            pass

    # Re-run both submitted artifacts against the original environment so the
    # requested final files are also left in their expected final state.
    run_script(GET_ENDPOINTS)
    run_script(DIAGNOSE)


def test_failing_ips_file():
    path = "/home/user/failing_ips.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_ips = ["10.0.5.12", "10.0.5.19", "10.0.5.24"]
    assert lines == expected_ips, f"Contents of {path} do not match the expected IPs. Got: {lines}"


def test_failing_errors_file():
    path = "/home/user/failing_errors.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_errors = ["ERR-503", "ERR-RESET", "ERR-TIMEOUT"]
    assert lines == expected_errors, f"Contents of {path} do not match the expected error codes. Got: {lines}"


def test_container_fstab_file():
    path = "/home/user/container_fstab"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 1, f"{path} should contain exactly one line, but found {len(lines)} lines."

    fields = lines[0].split()
    assert len(fields) >= 6, f"The line in {path} does not have enough fields."

    assert fields[0] == "/home/user/shared_data", f"Expected source directory '/home/user/shared_data', got {fields[0]}"
    assert fields[1] == "/mnt/service_data", f"Expected target directory '/mnt/service_data', got {fields[1]}"
    assert fields[2] == "bind", f"Expected filesystem type 'bind', got {fields[2]}"
    assert fields[3] == "ro,nosuid", f"Expected mount options 'ro,nosuid', got {fields[3]}"
    assert fields[4] == "0", f"Expected dump value '0', got {fields[4]}"
    assert fields[5] == "0", f"Expected pass value '0', got {fields[5]}"


def test_diag_report_json():
    path = "/home/user/diag_report.json"
    assert os.path.exists(path), f"File {path} is missing."

    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} does not contain valid JSON.")

    expected_data = {
        "10.0.5.12": "unreachable",
        "10.0.5.19": "unreachable",
        "10.0.5.24": "unreachable"
    }

    assert data == expected_data, f"Contents of {path} do not match the expected JSON structure. Got: {data}"


def test_scripts_exist():
    get_endpoints_path = "/home/user/get_endpoints.py"
    diagnose_path = "/home/user/diagnose.py"

    assert os.path.exists(get_endpoints_path), f"Script {get_endpoints_path} is missing."
    assert os.path.exists(diagnose_path), f"Script {diagnose_path} is missing."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
