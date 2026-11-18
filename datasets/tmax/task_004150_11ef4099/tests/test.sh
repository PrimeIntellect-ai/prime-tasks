#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid

import pytest


def run_script(path, *args):
    result = subprocess.run([path, *map(str, args)], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Execution of {path} {' '.join(map(str, args))} failed with return code "
        f"{result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )


def load_plan():
    output_file = "/home/user/recovery_plan.json"
    assert os.path.isfile(output_file), f"Output file {output_file} was not created."
    try:
        with open(output_file, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {output_file} does not contain valid JSON.")


def derive_expected_plan(timestamp):
    records = []
    for name in os.listdir("/home/user/backups"):
        if name.endswith(".json"):
            with open(os.path.join("/home/user/backups", name), "r") as f:
                records.append(json.load(f))

    eligible = [record for record in records if record["timestamp"] <= timestamp]
    assert eligible, "Verifier fixture unexpectedly has no eligible backup"
    current = max(eligible, key=lambda record: record["timestamp"])
    by_id = {record["id"]: record for record in records}

    reverse_chain = []
    seen = set()
    while True:
        assert current["id"] not in seen, "Verifier fixture unexpectedly contains a cycle"
        seen.add(current["id"])
        reverse_chain.append(current)
        if current["type"] == "full":
            assert current["parent_id"] is None
            break
        current = by_id[current["parent_id"]]

    return [
        {"id": record["id"], "type": record["type"], "file": record["file"]}
        for record in reversed(reverse_chain)
    ]


def test_build_index_script_exists_and_executable():
    script_path = "/home/user/build_index.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_build_index_execution_and_output():
    script_path = "/home/user/build_index.sh"
    run_script(script_path)

    index_dir = "/home/user/backup_index"
    assert os.path.isdir(index_dir), f"Directory {index_dir} was not created."

    expected_symlinks = {
        "1000-A1.json": "A1.json",
        "1010-A2.json": "A2.json",
        "1020-A3.json": "A3.json",
        "2000-B1.json": "B1.json",
        "2010-B2.json": "B2.json",
        "2020-B3.json": "B3.json",
    }

    actual_files = os.listdir(index_dir)
    for symlink_name, target_name in expected_symlinks.items():
        assert symlink_name in actual_files, f"Expected symlink {symlink_name} not found in {index_dir}."
        symlink_path = os.path.join(index_dir, symlink_name)
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
        target_path = os.readlink(symlink_path)
        absolute_target = os.path.abspath(os.path.join(index_dir, target_path))
        expected_absolute_target = os.path.abspath(f"/home/user/backups/{target_name}")
        assert absolute_target == expected_absolute_target, (
            f"Symlink {symlink_name} points to {absolute_target}, "
            f"expected {expected_absolute_target}."
        )


def test_get_chain_script_exists_and_executable():
    script_path = "/home/user/get_chain.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_get_chain_execution_and_output():
    script_path = "/home/user/get_chain.sh"
    run_script(script_path, "2015")

    expected_data = [
        {"id": "B1", "type": "full", "file": "backup_B1.tar.gz"},
        {"id": "B2", "type": "incremental", "file": "backup_B2.tar.gz"},
    ]
    data = load_plan()
    assert data == expected_data, (
        f"JSON content in /home/user/recovery_plan.json does not match the expected output. Got: {data}"
    )


def test_scripts_handle_new_runtime_backup_graph():
    base = random.SystemRandom().randint(100000, 900000000)
    ids = [str(uuid.uuid4()) for _ in range(3)]
    records = [
        {
            "id": ids[0], "type": "full", "timestamp": base,
            "file": f"runtime_{ids[0]}.tar.gz", "parent_id": None,
        },
        {
            "id": ids[1], "type": "incremental", "timestamp": base + 17,
            "file": f"runtime_{ids[1]}.tar.gz", "parent_id": ids[0],
        },
        {
            "id": ids[2], "type": "incremental", "timestamp": base + 39,
            "file": f"runtime_{ids[2]}.tar.gz", "parent_id": ids[1],
        },
    ]

    for record in records:
        path = os.path.join("/home/user/backups", f"{record['id']}.json")
        with open(path, "w") as f:
            json.dump(record, f)

    run_script("/home/user/build_index.sh")
    index_dir = "/home/user/backup_index"

    # Verify indexing for every metadata file, including records unknown before verification.
    for name in os.listdir("/home/user/backups"):
        if not name.endswith(".json"):
            continue
        source = os.path.join("/home/user/backups", name)
        with open(source, "r") as f:
            record = json.load(f)
        link = os.path.join(index_dir, f"{record['timestamp']}-{record['id']}.json")
        assert os.path.lexists(link), f"Missing dynamically derived index entry {link}"
        assert os.path.islink(link), f"{link} is not a symlink"
        assert os.path.realpath(link) == os.path.realpath(source), (
            f"{link} does not point to its source metadata file {source}"
        )

    # Exercise full-only, partial-chain, and complete-chain projections.
    for query_timestamp in (base, base + 20, base + 100):
        expected = derive_expected_plan(query_timestamp)
        run_script("/home/user/get_chain.sh", query_timestamp)
        actual = load_plan()
        assert actual == expected, (
            f"Incorrect recovery chain for timestamp {query_timestamp}. "
            f"Expected {expected}, got {actual}"
        )
        assert isinstance(actual, list)
        for item in actual:
            assert set(item.keys()) == {"id", "type", "file"}, (
                f"Recovery-plan object has incorrect schema: {item}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
