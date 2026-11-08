#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import uuid
import pytest

SCRIPT_PATH = "/home/user/find_affected.sh"
TOPOLOGY_PATH = "/home/user/backup_topology.txt"


def test_highest_indegree():
    file_path = "/home/user/highest_indegree.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "vault-primary", f"Expected 'vault-primary' in {file_path}, got '{content}'"


def test_bidirectional():
    file_path = "/home/user/bidirectional.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "vault-dr vault-primary", f"Expected 'vault-dr vault-primary' in {file_path}, got '{content}'"


def test_affected_dbs():
    file_path = "/home/user/affected_dbs.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    expected = [
        "backup-edge",
        "backup-tier1",
        "backup-tier2",
        "db-analytics",
        "db-edge1",
        "db-edge2",
        "db-legacy",
        "db-main",
        "db-users",
        "vault-primary"
    ]
    with open(file_path, "r") as f:
        content = f.read().splitlines()
    assert content == expected, f"Contents of {file_path} do not match the expected list of affected databases."


def test_find_affected_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    with open(script_path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, \
        f"Script {script_path} must be a Bash executable."


def test_find_affected_script_functionality():
    script_path = SCRIPT_PATH
    # Run the script with "backup-tier1"
    # Expected: db-main, db-analytics
    result = subprocess.run([script_path, "backup-tier1"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute."
    output = result.stdout.strip().splitlines()
    expected = ["db-analytics", "db-main"]
    assert sorted(output) == expected, f"Script output for 'backup-tier1' did not match expected output."


def test_find_affected_script_cyclic_handling():
    script_path = SCRIPT_PATH
    # Run the script with "vault-primary"
    # Should handle cycle with vault-dr
    result = subprocess.run([script_path, "vault-primary"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute on cyclic graph."
    output = result.stdout.strip().splitlines()
    expected = [
        "backup-edge",
        "backup-tier1",
        "backup-tier2",
        "db-analytics",
        "db-edge1",
        "db-edge2",
        "db-legacy",
        "db-main",
        "db-users",
        "vault-dr"
    ]
    assert sorted(output) == expected, f"Script output for 'vault-primary' did not match expected output."


def test_find_affected_script_vault_dr_matches_required_file():
    with open("/home/user/affected_dbs.txt", "r") as f:
        expected = f.read().splitlines()
    result = subprocess.run([SCRIPT_PATH, "vault-dr"], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Script failed for the required vault-dr target."
    assert result.stdout.splitlines() == expected, \
        "find_affected.sh vault-dr must produce the sorted contents of affected_dbs.txt."


def test_find_affected_requires_exactly_one_argument():
    no_args = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=5)
    two_args = subprocess.run([SCRIPT_PATH, "vault-dr", "extra"], capture_output=True, text=True, timeout=5)
    assert no_args.returncode != 0, "Script must reject invocation with no target argument."
    assert two_args.returncode != 0, "Script must reject invocation with more than one argument."


def expected_ancestors(edges, target):
    reverse = {}
    for source, destination in edges:
        reverse.setdefault(destination, set()).add(source)
    seen = {target}
    pending = [target]
    while pending:
        current = pending.pop()
        for source in reverse.get(current, set()):
            if source not in seen:
                seen.add(source)
                pending.append(source)
    seen.discard(target)
    return sorted(seen)


def run_dynamic_case(edges, targets):
    with open(TOPOLOGY_PATH, "w") as f:
        for source, destination in edges:
            f.write(f"{source} {destination}\n")

    for target in targets:
        result = subprocess.run([SCRIPT_PATH, target], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"Script failed for dynamic target {target}."
        actual = result.stdout.splitlines()
        expected = expected_ancestors(edges, target)
        assert actual == expected, \
            f"Dynamic reachability for {target} was {actual}, expected {expected}."
        assert target not in actual, f"Target {target} must be excluded from its own output."


def test_find_affected_is_parameterized_and_reads_topology():
    prefix = "dyn_" + uuid.uuid4().hex
    n = {name: f"{prefix}_{name}" for name in (
        "a", "b", "c", "d", "e", "target", "x", "y", "z", "q", "m", "n"
    )}
    edges = [
        (n["a"], n["b"]),
        (n["a"], n["b"]),  # duplicate edge must not duplicate output
        (n["b"], n["c"]),
        (n["c"], n["b"]),  # cycle upstream of target
        (n["c"], n["target"]),
        (n["d"], n["c"]),
        (n["e"], n["d"]),
        (n["q"], n["target"]),
        (n["target"], n["target"]),  # target self-loop
        (n["target"], n["x"]),       # downstream node is not affected
        (n["y"], n["z"]),            # disconnected component
        (n["m"], n["n"]),
        (n["n"], n["m"]),
        (n["m"], n["target"]),
    ]

    with open(TOPOLOGY_PATH, "rb") as f:
        original = f.read()
    try:
        run_dynamic_case(edges, [n["target"], n["c"], n["z"]])

        # Rewrite the same required input path and ensure the script does not use
        # cached or hardcoded results from the first graph.
        second_edges = [
            (n["x"], n["y"]),
            (n["z"], n["y"]),
            (n["a"], n["x"]),
            (n["y"], n["q"]),
        ]
        run_dynamic_case(second_edges, [n["y"], n["q"]])
    finally:
        with open(TOPOLOGY_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
