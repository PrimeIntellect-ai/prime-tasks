#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import re
import stat
import subprocess
import uuid

SOURCE = "/home/user/config_diff.c"
REPORT = "/home/user/diff_report.json"
BINARY = "/tmp/config_diff_verified"
FIELDS = ["nginx_config", "ssh_keys", "env_vars"]


def derive_expected():
    old = {}
    new = {}

    for directory, destination in [
        ("/home/user/old_configs", old),
        ("/home/user/new_configs", new),
    ]:
        for path in sorted(glob.glob(os.path.join(directory, "*.csv"))):
            with open(path, "r", encoding="utf-8", newline="") as handle:
                reader = csv.DictReader(handle)
                assert reader.fieldnames == ["server_id"] + FIELDS, \
                    f"Unexpected CSV columns in {path}: {reader.fieldnames}"
                for row in reader:
                    destination[row["server_id"]] = {field: row[field] for field in FIELDS}

    result = []
    for server_id in sorted(set(old) & set(new)):
        changes = []
        for field in sorted(FIELDS):
            old_value = old[server_id][field]
            new_value = new[server_id][field]
            if old_value != new_value:
                changes.append({
                    "field": field,
                    "old_length": len(old_value.encode("utf-8")),
                    "new_length": len(new_value.encode("utf-8")),
                })
        if changes:
            result.append({"server_id": server_id, "changes": changes})
    return result


def verify_report(expected):
    assert os.path.isfile(REPORT), f"{REPORT} is missing."
    try:
        with open(REPORT, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{REPORT} does not contain valid JSON: {exc}")

    assert isinstance(data, list), "JSON root should be an array."
    assert len(data) == len(expected), \
        f"Expected {len(expected)} servers with changes, got {len(data)}."

    actual_ids = [item.get("server_id", "") for item in data]
    expected_ids = [item["server_id"] for item in expected]
    assert actual_ids == expected_ids, \
        f"Servers must be sorted by server_id. Expected {expected_ids}, got {actual_ids}."

    for actual_server, expected_server in zip(data, expected):
        assert actual_server.get("server_id") == expected_server["server_id"]
        actual_changes = actual_server.get("changes", [])
        assert isinstance(actual_changes, list), "changes must be an array."
        actual_fields = [change.get("field", "") for change in actual_changes]
        expected_fields = [change["field"] for change in expected_server["changes"]]
        assert actual_fields == expected_fields, \
            f"Fields for {expected_server['server_id']} are not sorted correctly."
        assert actual_changes == expected_server["changes"], \
            f"Changes for {expected_server['server_id']} do not match. " \
            f"Expected {expected_server['changes']}, got {actual_changes}."


def run_program(expected):
    if os.path.exists(REPORT):
        os.remove(REPORT)
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=20)
    verify_report(expected)


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["server_id"] + FIELDS)
        writer.writerows(rows)


def main():
    assert os.path.exists(SOURCE), f"{SOURCE} is missing."
    source_stat = os.stat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} is not a regular file."
    assert source_stat.st_size > 0, f"{SOURCE} is empty."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as handle:
        source_text = handle.read()
    assert re.search(r"\bpthread_create\s*\(", source_text), \
        "The program does not create pthread worker threads."

    subprocess.run(
        ["gcc", "-pthread", "-o", BINARY, SOURCE],
        check=True,
        timeout=30,
    )
    symbols = subprocess.run(
        ["nm", "-D", BINARY], capture_output=True, text=True, check=True
    ).stdout
    assert "pthread_create" in symbols, \
        "The compiled program does not call pthread_create."

    base_expected = derive_expected()
    canonical_expected = [
        {
            "server_id": "srv-101",
            "changes": [
                {"field": "nginx_config", "old_length": 57, "new_length": 61},
                {"field": "ssh_keys", "old_length": 33, "new_length": 58},
            ],
        },
        {
            "server_id": "srv-201",
            "changes": [
                {"field": "env_vars", "old_length": 20, "new_length": 20},
            ],
        },
        {
            "server_id": "srv-202",
            "changes": [
                {"field": "nginx_config", "old_length": 23, "new_length": 28},
            ],
        },
    ]
    assert base_expected == canonical_expected, \
        f"The supplied fixture data was modified or parsed unexpectedly: {base_expected}"

    token = uuid.uuid4().hex
    filename = f"zz-audit-{token}.csv"
    old_path = os.path.join("/home/user/old_configs", filename)
    new_path = os.path.join("/home/user/new_configs", filename)
    changed_id = f"srv-audit-{token}"
    unchanged_id = f"srv-unchanged-{token}"

    old_rows = [
        [changed_id, 'alpha,one\n"quoted"', "key-A\nkey-B", f"TOKEN={token}\nMODE=old"],
        [unchanged_id, "same\nvalue", "same-key", "SAME=1"],
    ]
    new_rows = [
        [changed_id, 'alpha,one\n"quoted"\nextra', "key-A\nkey-B", f"TOKEN={token}\nMODE=new"],
        [unchanged_id, "same\nvalue", "same-key", "SAME=1"],
    ]

    try:
        write_csv(old_path, old_rows)
        write_csv(new_path, new_rows)
        challenged_expected = derive_expected()
        run_program(challenged_expected)
    finally:
        for path in (old_path, new_path):
            if os.path.exists(path):
                os.remove(path)

    run_program(base_expected)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
