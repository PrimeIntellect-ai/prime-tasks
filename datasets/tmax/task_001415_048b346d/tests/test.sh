#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys
from pathlib import Path

import pytest

REPORT_PATH = "/home/user/capacity_report.json"
SCRIPT_PATH = "/home/user/net_capacity.py"
PASSWD_PATH = "/home/user/mock_state/passwd"
GROUP_PATH = "/home/user/mock_state/group"
NET_TCP_PATH = "/home/user/mock_state/net_tcp"


def get_expected_state():
    # Parse group file
    gid_to_group = {}
    with open(GROUP_PATH, "r") as f:
        for line in f:
            parts = line.strip().split(":")
            if len(parts) >= 3:
                group_name = parts[0]
                gid = parts[2]
                gid_to_group[gid] = group_name

    # Parse passwd file
    uid_to_group = {}
    with open(PASSWD_PATH, "r") as f:
        for line in f:
            parts = line.strip().split(":")
            if len(parts) >= 4:
                uid = parts[2]
                gid = parts[3]
                if gid in gid_to_group:
                    uid_to_group[uid] = gid_to_group[gid]

    # Parse net_tcp file
    group_counts = {}
    with open(NET_TCP_PATH, "r") as f:
        lines = f.readlines()
        for line in lines[1:]:  # Skip header
            parts = line.split()
            if len(parts) > 7:
                uid = parts[7]
                if uid in uid_to_group:
                    group = uid_to_group[uid]
                    group_counts[group] = group_counts.get(group, 0) + 1

    status = "CRITICAL" if any(count > 10 for count in group_counts.values()) else "OK"
    return {"status": status, "group_counts": group_counts}


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"The script exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(REPORT_PATH), f"The script did not create {REPORT_PATH}."


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")


def assert_report_matches(expected_data):
    report_data = load_report()

    assert "status" in report_data, "The JSON report is missing the 'status' key."
    assert "group_counts" in report_data, "The JSON report is missing the 'group_counts' key."

    assert report_data["status"] == expected_data["status"], \
        f"Expected status '{expected_data['status']}', but got '{report_data['status']}'."

    assert isinstance(report_data["group_counts"], dict), "The 'group_counts' key must be a dictionary."

    expected_counts = expected_data["group_counts"]
    actual_counts = report_data["group_counts"]

    for group, count in expected_counts.items():
        assert group in actual_counts, f"Group '{group}' is missing from 'group_counts'."
        assert actual_counts[group] == count, \
            f"Expected {count} connections for group '{group}', but got {actual_counts[group]}."

    for group in actual_counts:
        assert group in expected_counts, f"Group '{group}' should not be in 'group_counts' as it has 0 connections or is invalid."


@pytest.fixture(scope="session", autouse=True)
def restore_fixture_files():
    paths = [PASSWD_PATH, GROUP_PATH, NET_TCP_PATH, REPORT_PATH]
    originals = {}
    for path in paths:
        p = Path(path)
        originals[path] = p.read_bytes() if p.exists() else None
    yield
    for path, contents in originals.items():
        p = Path(path)
        if contents is None:
            if p.exists():
                p.unlink()
        else:
            p.write_bytes(contents)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not found."


def test_script_executes_on_original_fixture():
    run_script()


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The output report {REPORT_PATH} was not found. Did you run your script?"


def test_report_format_and_content():
    assert os.path.isfile(REPORT_PATH), f"The output report {REPORT_PATH} was not found."
    assert_report_matches(get_expected_state())


def write_dynamic_state(counts):
    token = secrets.token_hex(5)
    base_uid = 20000 + secrets.randbelow(10000)
    base_gid = 30000 + secrets.randbelow(10000)

    groups = [f"team_{token}_a", f"team_{token}_b", f"team_{token}_c"]
    gids = [base_gid, base_gid + 1, base_gid + 2]
    uids = [base_uid, base_uid + 1, base_uid + 2, base_uid + 3]

    Path(GROUP_PATH).write_text(
        "".join(f"{name}:x:{gid}:\n" for name, gid in zip(groups, gids))
    )
    Path(PASSWD_PATH).write_text(
        f"alpha_{token}:x:{uids[0]}:{gids[0]}:Alpha:/tmp:/bin/sh\n"
        f"beta_{token}:x:{uids[1]}:{gids[0]}:Beta:/tmp:/bin/sh\n"
        f"gamma_{token}:x:{uids[2]}:{gids[1]}:Gamma:/tmp:/bin/sh\n"
        f"delta_{token}:x:{uids[3]}:{gids[2]}:Delta:/tmp:/bin/sh\n"
    )

    connection_uids = []
    for uid, count in zip(uids, counts):
        connection_uids.extend([uid] * count)
    # Unknown UIDs must not create a reported group.
    connection_uids.extend([base_uid + 999] * 2)

    lines = ["  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n"]
    for index, uid in enumerate(connection_uids):
        separator = "\t" if index % 2 else "   "
        lines.append(
            f"{separator}{index}: 0100007F:{1000 + index:04X} 00000000:0000 0A "
            f"00000000:00000000 00:00000000 00000000{separator}{uid} 0 {50000 + index}\n"
        )
    Path(NET_TCP_PATH).write_text("".join(lines))


def test_script_behavior_on_changed_inputs():
    # Exactly 10 is still OK; the third group has no connections and is omitted.
    write_dynamic_state([4, 6, 7, 0])
    expected = get_expected_state()
    assert expected["status"] == "OK"
    run_script()
    assert_report_matches(expected)

    # Two users sharing one primary group jointly exceed the threshold.
    write_dynamic_state([5, 6, 10, 1])
    expected = get_expected_state()
    assert expected["status"] == "CRITICAL"
    run_script()
    assert_report_matches(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
