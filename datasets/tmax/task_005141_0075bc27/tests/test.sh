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
import subprocess
import tarfile
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8333"
LOG_DIR = "/app/live_logs"
ACTIVE_LOG = os.path.join(LOG_DIR, "active.jsonl")
ROTATED_LOG = os.path.join(LOG_DIR, "active.jsonl.1")
FRAMES_CSV = "/home/user/frames.csv"
ARCHIVE_DIR = "/home/user/archive"


def wait_for_server():
    for _ in range(30):
        try:
            response = requests.get(f"{BASE_URL}/stats", timeout=1)
            if response.status_code == 200:
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.5)
    pytest.fail("Server did not start or become reachable on port 8333 within 15 seconds.")


def expected_keyframe_timestamps():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_frames", "-show_entries",
            "frame=key_frame,best_effort_timestamp_time", "-of", "json",
            "/app/evidence.mp4",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    frames = json.loads(result.stdout)["frames"]
    return [
        float(frame["best_effort_timestamp_time"])
        for frame in frames
        if int(frame.get("key_frame", 0)) == 1
    ]


def assert_frames_csv(expected):
    assert os.path.isfile(FRAMES_CSV), f"Missing {FRAMES_CSV}"
    with open(FRAMES_CSV, "r", encoding="utf-8") as handle:
        rows = [line.rstrip("\r\n") for line in handle]

    assert rows, "frames.csv is empty"
    assert all(row and "," not in row for row in rows), \
        "frames.csv must contain one timestamp per line with no header"
    try:
        actual = [float(row) for row in rows]
    except ValueError as exc:
        pytest.fail(f"frames.csv contains a non-numeric timestamp: {exc}")

    assert len(actual) == len(expected), \
        f"Expected {len(expected)} keyframe timestamps, found {len(actual)}"
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert abs(got - wanted) <= 1e-6, \
            f"Incorrect keyframe timestamp at row {index + 1}: got {got}, expected {wanted}"


def write_records(path, records, mode="w"):
    with open(path, mode, encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")


def post_backup():
    try:
        response = requests.post(f"{BASE_URL}/backup", timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"POST /backup failed: {exc}")
    assert response.status_code == 200, \
        f"Expected 200 OK for /backup, got {response.status_code}: {response.text}"


def assert_archive(path, expected_records):
    assert os.path.isfile(path), f"Missing archive {path}"
    try:
        with tarfile.open(path, "r:gz") as archive:
            regular = [member for member in archive.getmembers() if member.isfile()]
            frame_members = [m for m in regular if os.path.basename(m.name) == "frames.csv"]
            log_members = [m for m in regular if os.path.basename(m.name) != "frames.csv"]

            assert len(frame_members) == 1, \
                f"{path} must contain exactly one frames.csv file"
            assert len(log_members) == 1, \
                f"{path} must contain exactly one temporary log file, found {len(log_members)}"

            archived_frames = archive.extractfile(frame_members[0])
            archived_log = archive.extractfile(log_members[0])
            assert archived_frames is not None and archived_log is not None
            archived_frames_data = archived_frames.read()
            archived_log_data = archived_log.read().decode("utf-8")
    except (tarfile.TarError, UnicodeDecodeError) as exc:
        pytest.fail(f"Failed to read archive {path}: {exc}")

    with open(FRAMES_CSV, "rb") as handle:
        assert archived_frames_data == handle.read(), \
            f"The frames.csv stored in {path} does not match /home/user/frames.csv"

    lines = archived_log_data.splitlines()
    assert len(lines) == len(expected_records), \
        f"Expected exactly {len(expected_records)} log lines in {path}, found {len(lines)}"
    try:
        actual_records = [json.loads(line) for line in lines]
    except json.JSONDecodeError as exc:
        pytest.fail(f"Archive {path} contains an invalid JSONL line: {exc}")
    assert actual_records == expected_records, \
        f"Archived JSON objects in {path} do not match the newly written log objects"


def test_backup_and_stats():
    wait_for_server()

    expected_frames = expected_keyframe_timestamps()
    assert len(expected_frames) == 11, \
        f"Fixture unexpectedly contains {len(expected_frames)} keyframes instead of 11"
    assert_frames_csv(expected_frames)

    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    for path in (ACTIVE_LOG, ROTATED_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    for name in ("backup_1.tar.gz", "backup_2.tar.gz"):
        try:
            os.unlink(os.path.join(ARCHIVE_DIR, name))
        except FileNotFoundError:
            pass

    nonce = uuid.uuid4().hex
    first_records = [
        {"sequence": i, "batch": "initial", "nonce": nonce, "value": uuid.uuid4().hex}
        for i in range(5)
    ]
    rotated_unread = [
        {"sequence": i, "batch": "rotated-unread", "nonce": nonce, "value": uuid.uuid4().hex}
        for i in range(5, 7)
    ]
    new_active = [
        {"sequence": i, "batch": "new-active", "nonce": nonce, "value": uuid.uuid4().hex}
        for i in range(7, 9)
    ]

    write_records(ACTIVE_LOG, first_records)
    post_backup()
    assert_archive(os.path.join(ARCHIVE_DIR, "backup_1.tar.gz"), first_records)

    # Add unread data to the old inode before rotating it. A correct incremental
    # reader must collect these records from active.jsonl.1, then read the new file.
    write_records(ACTIVE_LOG, rotated_unread, mode="a")
    os.rename(ACTIVE_LOG, ROTATED_LOG)
    write_records(ACTIVE_LOG, new_active)

    post_backup()
    assert_archive(
        os.path.join(ARCHIVE_DIR, "backup_2.tar.gz"),
        rotated_unread + new_active,
    )

    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"GET /stats failed: {exc}")
    assert response.status_code == 200, \
        f"Expected 200 OK for /stats, got {response.status_code}: {response.text}"
    try:
        stats = response.json()
    except ValueError:
        pytest.fail(f"GET /stats did not return valid JSON. Response: {response.text}")

    assert set(stats.keys()) == {"total_backed_up_lines", "total_keyframes"}, \
        f"/stats returned the wrong schema: {stats}"
    assert stats["total_backed_up_lines"] == 9, \
        f"Expected 9 backed up lines, got {stats['total_backed_up_lines']}"
    assert stats["total_keyframes"] == 11, \
        f"Expected 11 keyframes, got {stats['total_keyframes']}"
    assert type(stats["total_backed_up_lines"]) is int
    assert type(stats["total_keyframes"]) is int
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
