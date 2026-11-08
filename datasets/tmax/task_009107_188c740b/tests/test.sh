#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/chain_size.sh"
METADATA_PATH = "/home/user/backup_metadata.json"


def run_script(backup_id):
    try:
        return subprocess.run(
            [SCRIPT_PATH, backup_id],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed when running with {backup_id}. Error: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script timed out when running with {backup_id}.")


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


@pytest.mark.parametrize("backup_id, expected_size", [
    ("bkp_001", "8950"),
    ("bkp_002", "2150"),
    ("bkp_006", "10500"),
    ("bkp_008", "500"),
])
def test_script_output(backup_id, expected_size):
    result = run_script(backup_id)
    output = result.stdout.strip()
    assert output == expected_size, (
        f"Expected output for {backup_id} to be '{expected_size}', "
        f"but got '{output}'."
    )


def test_general_recursive_behavior_on_generated_metadata():
    token = secrets.token_hex(8)
    ids = [f"generated_{token}_{i:02d}" for i in range(18)]

    # An acyclic forest containing deep chains, branches, and a second root.
    parent_indexes = [
        None, 0, 1, 2, 0, 4, 1, 6, 3,
        None, 9, 10, 9, 12, 5, 14, 7, 16,
    ]
    sizes = [secrets.randbelow(9000) + 1 for _ in ids]
    records = []
    for i, backup_id in enumerate(ids):
        parent_index = parent_indexes[i]
        records.append({
            "backup_id": backup_id,
            "type": "full" if parent_index is None else "incremental",
            "parent_id": None if parent_index is None else ids[parent_index],
            "size_mb": sizes[i],
        })

    children = {backup_id: [] for backup_id in ids}
    for record in records:
        if record["parent_id"] is not None:
            children[record["parent_id"]].append(record["backup_id"])
    size_by_id = {record["backup_id"]: record["size_mb"] for record in records}

    def expected_total(backup_id):
        return size_by_id[backup_id] + sum(
            expected_total(child) for child in children[backup_id]
        )

    with open(METADATA_PATH, "rb") as f:
        original_metadata = f.read()

    try:
        temp_path = METADATA_PATH + ".verifier_tmp"
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(records, f)
        os.replace(temp_path, METADATA_PATH)

        for backup_id in ids:
            expected = str(expected_total(backup_id))
            result = run_script(backup_id)
            output = result.stdout.strip()
            assert output == expected, (
                f"Expected generated chain total for {backup_id} to be "
                f"'{expected}', but got '{output}'."
            )
    finally:
        with open(METADATA_PATH, "wb") as f:
            f.write(original_metadata)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
