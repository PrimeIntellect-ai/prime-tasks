#!/bin/bash
set +e
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import tempfile
import uuid

import pytest

OUTPUT_PATH = "/home/user/incremental_patch.json"
BINARY_PATH = "/home/user/config_tracker/target/release/config_tracker"


def run_tracker(old_dir, new_dir):
    result = subprocess.run(
        [BINARY_PATH, str(old_dir), str(new_dir)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f"config_tracker failed: {result.stderr}"
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"config_tracker stdout is not valid JSON: {exc}\nstdout: {result.stdout}\nstderr: {result.stderr}")


def test_incremental_patch_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did you run the program and redirect output?"


def test_incremental_patch_valid_json():
    assert os.path.isfile(OUTPUT_PATH), "Output file missing."
    try:
        with open(OUTPUT_PATH, "r") as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {OUTPUT_PATH} does not contain valid JSON.")


def test_incremental_patch_server_json_diff():
    with open(OUTPUT_PATH, "r") as f:
        data = json.load(f)

    assert "server.json" in data, "Missing 'server.json' key in output JSON."
    server_diff = data["server.json"]

    assert server_diff.get("type") == "json", "server.json type should be 'json'"
    assert server_diff.get("added") == {"timeout": 30}, "server.json 'added' diff is incorrect."
    assert server_diff.get("removed") == {"protocol": "http"}, "server.json 'removed' diff is incorrect."
    assert server_diff.get("modified") == {"port": {"old": 8080, "new": 8081}}, "server.json 'modified' diff is incorrect."


def test_incremental_patch_users_csv_diff():
    with open(OUTPUT_PATH, "r") as f:
        data = json.load(f)

    assert "users.csv" in data, "Missing 'users.csv' key in output JSON."
    users_diff = data["users.csv"]

    assert users_diff.get("type") == "csv", "users.csv type should be 'csv'"

    added = users_diff.get("added", [])
    removed = users_diff.get("removed", [])

    assert isinstance(added, list), "users.csv 'added' should be a list"
    assert isinstance(removed, list), "users.csv 'removed' should be a list"

    expected_added = {"id": "3", "name": "alice", "role": "user"}
    expected_removed = {"id": "2", "name": "john", "role": "user"}

    assert expected_added in added, f"Expected {expected_added} in users.csv 'added' list."
    assert expected_removed in removed, f"Expected {expected_removed} in users.csv 'removed' list."

    # Also check exact lengths to ensure no extra rows are reported
    assert len(added) == 1, "users.csv 'added' list should contain exactly 1 item."
    assert len(removed) == 1, "users.csv 'removed' list should contain exactly 1 item."


def test_cli_reproduces_required_fixture_output():
    actual = run_tracker("/home/user/backup/v1", "/home/user/configs")
    with open(OUTPUT_PATH, "r") as f:
        saved = json.load(f)
    assert actual == saved, "The saved patch does not match the Rust CLI's output for the required directories."


def test_cli_handles_additional_generated_inputs():
    token = uuid.uuid4().hex
    json_name = f"settings_{token}.json"
    csv_name = f"accounts_{token}.csv"

    unchanged_key = f"same_{token}"
    modified_key = f"changed_{token}"
    removed_key = f"removed_{token}"
    added_key = f"added_{token}"

    old_json = {
        unchanged_key: True,
        modified_key: 1000 + len(token),
        removed_key: f"old-{token}",
    }
    new_json = {
        unchanged_key: True,
        modified_key: 2000 + len(token),
        added_key: f"new-{token}",
    }

    removed_id = f"removed-{token}"
    stable_id = f"stable-{token}"
    added_id = f"added-{token}"
    old_rows = [
        {"key": stable_id, "label": "before", "active": "yes"},
        {"key": removed_id, "label": f"gone-{token}", "active": "no"},
    ]
    new_rows = [
        {"key": stable_id, "label": "after", "active": "no"},
        {"key": added_id, "label": f"arrived-{token}", "active": "yes"},
    ]

    with tempfile.TemporaryDirectory() as root:
        old_dir = os.path.join(root, "old")
        new_dir = os.path.join(root, "new")
        os.makedirs(old_dir)
        os.makedirs(new_dir)

        with open(os.path.join(old_dir, json_name), "w") as f:
            json.dump(old_json, f)
        with open(os.path.join(new_dir, json_name), "w") as f:
            json.dump(new_json, f)

        for directory, rows in ((old_dir, old_rows), (new_dir, new_rows)):
            with open(os.path.join(directory, csv_name), "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["key", "label", "active"])
                writer.writeheader()
                writer.writerows(rows)

        # Files present on only one side must not be compared.
        with open(os.path.join(old_dir, f"old_only_{token}.json"), "w") as f:
            json.dump({"ignored": 1}, f)
        with open(os.path.join(new_dir, f"new_only_{token}.csv"), "w") as f:
            f.write("id,value\n1,ignored\n")

        actual = run_tracker(old_dir, new_dir)

    expected = {
        json_name: {
            "type": "json",
            "added": {added_key: f"new-{token}"},
            "removed": {removed_key: f"old-{token}"},
            "modified": {
                modified_key: {
                    "old": 1000 + len(token),
                    "new": 2000 + len(token),
                }
            },
        },
        csv_name: {
            "type": "csv",
            "added": [{"key": added_id, "label": f"arrived-{token}", "active": "yes"}],
            "removed": [{"key": removed_id, "label": f"gone-{token}", "active": "no"}],
        },
    }
    assert actual == expected
TEST_EOF

passed=true
PROJECT=/home/user/config_tracker

if [ ! -d "$PROJECT" ] || [ ! -f "$PROJECT/Cargo.toml" ]; then
    echo "Missing Rust project or Cargo.toml at $PROJECT" >&2
    passed=false
fi

if [ "$passed" = true ]; then
    rm -f "$PROJECT/target/release/config_tracker"
    if ! cargo build --release --manifest-path "$PROJECT/Cargo.toml"; then
        passed=false
    fi
fi

if [ "$passed" = true ] && [ ! -x "$PROJECT/target/release/config_tracker" ]; then
    echo "Cargo build did not produce the config_tracker executable" >&2
    passed=false
fi

if [ "$passed" = true ]; then
    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        passed=false
    fi
fi

if [ "$passed" = true ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
