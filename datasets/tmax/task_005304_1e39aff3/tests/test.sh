#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import socket
import subprocess
import time

import pytest
import requests

SNAPSHOT_EXPECTED = {}


def get_canonical_id(raw_id: int) -> int:
    """Use the actual binary to derive expected canonical IDs."""
    process = subprocess.Popen(
        ['/app/id_mapper'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True
    )
    stdout, _ = process.communicate(input=f"{raw_id}\n")
    assert process.returncode == 0
    return int(stdout.strip())


def get_aggregate(canon_id: int):
    try:
        resp = requests.get(
            "http://127.0.0.1:9001/aggregate",
            params={"id": canon_id},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("HTTP API server is not listening on 127.0.0.1:9001")

    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code} for id {canon_id}"
    data = resp.json()
    assert "canonical_id" in data, f"Response missing 'canonical_id': {data}"
    assert "total_duration" in data, f"Response missing 'total_duration': {data}"
    assert set(data) == {"canonical_id", "total_duration"}, f"Unexpected response fields: {data}"
    assert type(data["canonical_id"]) is int, f"canonical_id must be a JSON integer: {data}"
    assert type(data["total_duration"]) is int, f"total_duration must be a JSON integer: {data}"
    assert data["canonical_id"] == canon_id, f"Expected canonical_id {canon_id}, got {data['canonical_id']}"
    return data


def send_payload(payload: bytes):
    try:
        with socket.create_connection(("127.0.0.1", 9000), timeout=5) as sock:
            sock.sendall(payload)
    except ConnectionRefusedError:
        pytest.fail("TCP server is not listening on 127.0.0.1:9000")
    except Exception as e:
        pytest.fail(f"Failed to send data to TCP server: {e}")


def wait_for_exact(expected, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = {cid: get_aggregate(cid)["total_duration"] for cid in expected}
        if last == expected:
            return
        time.sleep(0.2)
    assert last == expected, f"Aggregates did not reach exact expected values: expected {expected}, got {last}"


def test_pipeline_processing():
    # Preserve the original fixed-data assertions.
    test_data = [
        {"raw_id": 1050, "duration": 42},
        {"raw_id": 1050, "duration": 10},
        {"raw_id": 9999, "duration": 100},
        {"raw_id": 123456, "duration": 5},
    ]

    expected_aggregations = {}
    for item in test_data:
        canon_id = get_canonical_id(item["raw_id"])
        expected_aggregations[canon_id] = expected_aggregations.get(canon_id, 0) + item["duration"]

    payload = "".join(
        f"2023-10-10T10:00:00Z,{item['raw_id']},action,{item['duration']}\n"
        for item in test_data
    ).encode("utf-8")
    send_payload(payload)
    time.sleep(2)

    for canon_id, expected_duration in expected_aggregations.items():
        data = get_aggregate(canon_id)
        assert int(data["canonical_id"]) == canon_id
        assert int(data["total_duration"]) >= expected_duration, (
            f"Expected total_duration >= {expected_duration}, got {data['total_duration']}"
        )

    # Preserve the original unseen-ID check.
    unseen_id = 9999999
    data = get_aggregate(unseen_id)
    assert int(data["canonical_id"]) == unseen_id
    assert int(data["total_duration"]) == 0, (
        f"Expected total_duration 0 for unseen id, got {data['total_duration']}"
    )

    # Exercise unpredictable raw IDs and require exact state deltas. This prevents
    # fixed-ID responders and services that merely return an arbitrarily large value.
    rng = secrets.SystemRandom()
    raw_ids = []
    while len(raw_ids) < 8:
        candidate = rng.randrange(1_000_000, 2_000_000_000)
        if candidate not in raw_ids:
            raw_ids.append(candidate)

    random_records = []
    additions = {}
    for raw_id in raw_ids:
        for _ in range(rng.randrange(1, 4)):
            duration = rng.randrange(1, 500)
            random_records.append((raw_id, duration))
            cid = get_canonical_id(raw_id)
            additions[cid] = additions.get(cid, 0) + duration

    baselines = {cid: get_aggregate(cid)["total_duration"] for cid in additions}
    exact_expected = {cid: baselines[cid] + amount for cid, amount in additions.items()}
    rng.shuffle(random_records)
    random_payload = "".join(
        f"2026-09-11T12:34:56Z,{raw_id},random_action,{duration}\n"
        for raw_id, duration in random_records
    ).encode("utf-8")
    send_payload(random_payload)
    wait_for_exact(exact_expected)

    # Record the actual current state that the snapshot must contain.
    checked_ids = set(expected_aggregations) | set(exact_expected)
    for cid in checked_ids:
        SNAPSHOT_EXPECTED[str(cid)] = get_aggregate(cid)["total_duration"]


def test_cron_job_configured():
    try:
        spool_file = "/var/spool/cron/crontabs/user"
        if os.path.exists(spool_file):
            with open(spool_file, "r") as f:
                crontab_content = f.read()
        else:
            process = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
            crontab_content = process.stdout

        assert "* * * * *" in crontab_content, "Cron job does not seem to be configured to run every minute (* * * * *)"
        assert "snapshot.json" in crontab_content, "Cron job does not reference snapshot.json"
    except Exception as e:
        pytest.fail(f"Failed to verify cron job: {e}")

    # Locate a real, uncommented every-minute entry for the requested user.
    cron_lines = []
    for line in crontab_content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        fields = stripped.split(None, 5)
        if len(fields) == 6 and fields[:5] == ['*', '*', '*', '*', '*']:
            cron_lines.append(fields[5])
    snapshot_commands = [cmd for cmd in cron_lines if 'snapshot.json' in cmd]
    assert snapshot_commands, "No active every-minute cron command writes snapshot.json"

    snapshot_path = "/home/user/snapshot.json"
    try:
        os.remove(snapshot_path)
    except FileNotFoundError:
        pass

    # Run the configured cron command as the target user rather than trusting text
    # in the crontab, then verify that it creates a usable snapshot of live state.
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', '/bin/sh', '-c', snapshot_commands[0]],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Snapshot cron command failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    deadline = time.time() + 5
    snapshot = None
    while time.time() < deadline:
        try:
            with open(snapshot_path, 'r') as f:
                snapshot = json.load(f)
            break
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.2)

    assert isinstance(snapshot, dict), "Cron command did not create a valid JSON object at /home/user/snapshot.json"
    for cid, expected_total in SNAPSHOT_EXPECTED.items():
        assert cid in snapshot, f"Snapshot is missing canonical_id {cid}"
        assert type(snapshot[cid]) is int, f"Snapshot value for {cid} must be an integer"
        assert snapshot[cid] == expected_total, (
            f"Snapshot value for {cid} is stale or incorrect: expected {expected_total}, got {snapshot[cid]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
