#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest

AUDIT = "/home/user/audit.go"
REPORT = "/home/user/report.json"
METADATA = "/home/user/backup_metadata"
EXPECTED_KEYS = {
    "total_valid_chains",
    "largest_chain_start_id",
    "largest_chain_size",
    "orphan_count",
}


def load_report():
    assert os.path.isfile(REPORT), "The file /home/user/report.json does not exist."
    try:
        with open(REPORT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("/home/user/report.json is not a valid JSON file.")
    assert isinstance(data, dict), "/home/user/report.json must contain a JSON object."
    actual_keys = set(data.keys())
    assert EXPECTED_KEYS.issubset(actual_keys), (
        f"Missing keys in report.json. Expected: {EXPECTED_KEYS}, Found: {actual_keys}"
    )
    return data


def assert_metrics(data, expected):
    for key, value in expected.items():
        assert data[key] == value, f"Expected {key} to be {value!r}, got {data[key]!r}"


def derive_expected(records):
    by_id = {record["id"]: record for record in records}
    valid_memo = {}
    visiting = set()

    def is_valid(backup_id):
        if backup_id in valid_memo:
            return valid_memo[backup_id]
        record = by_id.get(backup_id)
        if record is None or backup_id in visiting:
            return False
        visiting.add(backup_id)
        if record.get("type") == "full":
            result = record.get("status") == "success"
        elif record.get("type") == "incremental":
            parent = record.get("parent_id")
            result = record.get("status") == "success" and parent in by_id and is_valid(parent)
        else:
            result = False
        visiting.remove(backup_id)
        valid_memo[backup_id] = result
        return result

    orphan_memo = {}
    orphan_visiting = set()

    def is_orphan(backup_id):
        if backup_id in orphan_memo:
            return orphan_memo[backup_id]
        record = by_id[backup_id]
        if record.get("type") != "incremental":
            orphan_memo[backup_id] = False
            return False
        if backup_id in orphan_visiting:
            orphan_memo[backup_id] = True
            return True
        orphan_visiting.add(backup_id)
        parent = by_id.get(record.get("parent_id"))
        result = parent is None or parent.get("status") == "failed"
        if not result and parent.get("type") == "incremental":
            result = is_orphan(parent["id"])
        orphan_visiting.remove(backup_id)
        orphan_memo[backup_id] = result
        return result

    roots = [
        r for r in records
        if r.get("type") == "full" and r.get("status") == "success"
    ]
    sizes = {r["id"]: r["size_bytes"] for r in roots}

    for record in records:
        if record.get("type") != "incremental" or not is_valid(record["id"]):
            continue
        current = record
        while current.get("type") == "incremental":
            current = by_id[current["parent_id"]]
        sizes[current["id"]] += record["size_bytes"]

    largest_id = max(sizes, key=sizes.get)
    return {
        "total_valid_chains": len(roots),
        "largest_chain_start_id": largest_id,
        "largest_chain_size": sizes[largest_id],
        "orphan_count": sum(
            1 for r in records
            if r.get("type") == "incremental" and is_orphan(r["id"])
        ),
    }


def make_hidden_case():
    rng = random.SystemRandom()
    records = []

    def new_id():
        return "x_" + secrets.token_hex(8)

    root_count = rng.randint(2, 5)
    roots = []
    for index in range(root_count):
        root = new_id()
        roots.append(root)
        records.append({
            "id": root,
            "type": "full",
            "parent_id": None,
            "size_bytes": (index + 1) * 100000 + rng.randint(1, 1000),
            "status": "success",
        })

        parent = root
        for _ in range(rng.randint(1, 4)):
            child = new_id()
            records.append({
                "id": child,
                "type": "incremental",
                "parent_id": parent,
                "size_bytes": rng.randint(1, 500),
                "status": "success",
            })
            parent = child

        branch = new_id()
        records.append({
            "id": branch,
            "type": "incremental",
            "parent_id": root,
            "size_bytes": rng.randint(1, 500),
            "status": "success",
        })

        failed = new_id()
        records.append({
            "id": failed,
            "type": "incremental",
            "parent_id": root,
            "size_bytes": rng.randint(1, 500),
            "status": "failed",
        })
        records.append({
            "id": new_id(),
            "type": "incremental",
            "parent_id": failed,
            "size_bytes": rng.randint(1, 500),
            "status": "success",
        })

    failed_full = new_id()
    records.append({
        "id": failed_full,
        "type": "full",
        "parent_id": None,
        "size_bytes": rng.randint(1, 1000),
        "status": "failed",
    })
    records.append({
        "id": new_id(),
        "type": "incremental",
        "parent_id": failed_full,
        "size_bytes": rng.randint(1, 500),
        "status": "success",
    })

    missing = new_id()
    orphan1 = new_id()
    orphan2 = new_id()
    records.extend([
        {
            "id": orphan1,
            "type": "incremental",
            "parent_id": missing,
            "size_bytes": rng.randint(1, 500),
            "status": "success",
        },
        {
            "id": orphan2,
            "type": "incremental",
            "parent_id": orphan1,
            "size_bytes": rng.randint(1, 500),
            "status": "failed",
        },
        {
            "id": new_id(),
            "type": "incremental",
            "parent_id": orphan2,
            "size_bytes": rng.randint(1, 500),
            "status": "success",
        },
    ])
    rng.shuffle(records)
    return records


def install_case(records):
    shutil.rmtree(METADATA)
    os.makedirs(METADATA)
    for record in records:
        filename = secrets.token_hex(8) + ".json"
        with open(os.path.join(METADATA, filename), "w") as f:
            json.dump(record, f)


def run_program(binary):
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [binary], cwd="/home/user", text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, (
        f"audit.go exited with status {result.returncode}. "
        f"stdout: {result.stdout} stderr: {result.stderr}"
    )
    return load_report()


def test_complete_submission():
    # Preserve the original verifier's file and submitted-report assertions.
    assert os.path.isfile(REPORT), "The file /home/user/report.json does not exist."
    submitted = load_report()
    original_expected = {
        "total_valid_chains": 2,
        "largest_chain_start_id": "b4",
        "largest_chain_size": 210,
        "orphan_count": 3,
    }
    assert_metrics(submitted, original_expected)
    assert os.path.isfile(AUDIT), (
        "The file /home/user/audit.go does not exist. You must write the Go program."
    )

    saved_dir = tempfile.mkdtemp(prefix="audit-verifier-")
    saved_metadata = os.path.join(saved_dir, "backup_metadata")
    shutil.copytree(METADATA, saved_metadata)
    with open(REPORT, "rb") as f:
        saved_report = f.read()
    binary = os.path.join(saved_dir, "audit-program")

    try:
        build = subprocess.run(
            ["go", "build", "-o", binary, AUDIT],
            cwd="/home/user", text=True, capture_output=True, timeout=30
        )
        assert build.returncode == 0, (
            f"/home/user/audit.go does not compile. stdout: {build.stdout} stderr: {build.stderr}"
        )

        # Execute the submitted program against the original metadata too.
        assert_metrics(run_program(binary), original_expected)

        # Exercise fresh, unpredictable graphs and derive their expected results.
        for _ in range(2):
            records = make_hidden_case()
            expected = derive_expected(records)
            install_case(records)
            assert_metrics(run_program(binary), expected)
    finally:
        if os.path.exists(METADATA):
            shutil.rmtree(METADATA)
        shutil.copytree(saved_metadata, METADATA)
        with open(REPORT, "wb") as f:
            f.write(saved_report)
        shutil.rmtree(saved_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
