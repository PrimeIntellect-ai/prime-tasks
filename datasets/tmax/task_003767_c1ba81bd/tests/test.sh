#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def compute_desired_deps(ops_file):
    state = {}
    with open(ops_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0]
            if cmd == "INSTALL":
                pkg, ver = parts[1].split('@')
                state[pkg] = ver
            elif cmd == "REMOVE":
                pkg = parts[1]
                state.pop(pkg, None)
            elif cmd == "REPLACE":
                old_pkg = parts[1]
                new_pkg, new_ver = parts[2].split('@')
                state.pop(old_pkg, None)
                state[new_pkg] = new_ver
    return sorted([f"{pkg}@{ver}" for pkg, ver in state.items()])

def get_current_deps(curr_file):
    with open(curr_file, 'r') as f:
        return [line.strip() for line in f if line.strip()]

@pytest.fixture(scope="module")
def expected_state():
    ops_file = "/home/user/legacy_script.ops"
    curr_file = "/home/user/current_deps.txt"

    assert os.path.exists(ops_file), f"Missing {ops_file}"
    assert os.path.exists(curr_file), f"Missing {curr_file}"

    desired = compute_desired_deps(ops_file)
    current = get_current_deps(curr_file)

    desired_set = set(desired)
    current_set = set(current)

    install = sorted(list(desired_set - current_set))
    uninstall = sorted(list(current_set - desired_set))

    return {
        "desired": desired,
        "install": install,
        "uninstall": uninstall
    }

def test_desired_deps_txt(expected_state):
    target_file = "/home/user/desired_deps.txt"
    assert os.path.exists(target_file), f"File {target_file} was not created."

    with open(target_file, 'r') as f:
        actual_desired = [line.strip() for line in f if line.strip()]

    assert actual_desired == expected_state["desired"], (
        f"Contents of {target_file} do not match the expected desired state.\n"
        f"Expected: {expected_state['desired']}\n"
        f"Got: {actual_desired}"
    )

def test_deployment_plan_json(expected_state):
    target_file = "/home/user/deployment_plan.json"
    assert os.path.exists(target_file), f"File {target_file} was not created."

    with open(target_file, 'r') as f:
        try:
            plan = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {target_file} is not valid JSON.")

    assert "install" in plan, f"Key 'install' missing from {target_file}."
    assert "uninstall" in plan, f"Key 'uninstall' missing from {target_file}."

    assert isinstance(plan["install"], list), "'install' must be a list of strings."
    assert isinstance(plan["uninstall"], list), "'uninstall' must be a list of strings."

    assert plan["install"] == expected_state["install"], (
        f"Install list mismatch in {target_file}.\n"
        f"Expected: {expected_state['install']}\n"
        f"Got: {plan['install']}"
    )

    assert plan["uninstall"] == expected_state["uninstall"], (
        f"Uninstall list mismatch in {target_file}.\n"
        f"Expected: {expected_state['uninstall']}\n"
        f"Got: {plan['uninstall']}"
    )

    assert len(plan) == 2, "The JSON file should have exactly two keys: 'install' and 'uninstall'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
