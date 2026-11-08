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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import decimal
import json
import os
import random
import shutil
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time

import requests

VIDEO = "/app/incident.mp4"
DB = "/home/user/telemetry.db"
OUTPUT = "/home/user/incident_data.json"
TRIAGE = "/home/user/triage.sh"
SERVER = "/home/user/server.sh"
URL = "http://127.0.0.1:8080/api/incident"
TOKEN = {"Authorization": "Bearer triage-token-99"}


def critical_frame(video_path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "frame=pkt_duration_time",
            "-of", "default=noprint_wrappers=1:nokey=1", video_path,
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    durations = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line and line != "N/A":
            durations.append(decimal.Decimal(line))
    assert durations, "ffprobe returned no frame durations"

    total = decimal.Decimal("0")
    threshold = decimal.Decimal("5.500000")
    for index, duration in enumerate(durations):
        total += duration
        if total > threshold:
            return index
    raise AssertionError("Video cumulative duration never strictly exceeded 5.500000 seconds")


def expected_rows(db_path, critical):
    with sqlite3.connect(db_path) as connection:
        rows = connection.execute(
            "SELECT frame_idx, timestamp_utc, value FROM events "
            "WHERE frame_idx > ? ORDER BY rowid LIMIT 3",
            (critical,),
        ).fetchall()
    assert len(rows) == 3, f"Fixture did not contain exactly three expected rows: {rows}"
    return [tuple(row) for row in rows]


def load_and_validate_output(expected):
    assert os.path.exists(OUTPUT), f"Output file missing: {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"Expected a file, but found a directory: {OUTPUT}"
    with open(OUTPUT, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {OUTPUT} does not contain valid JSON: {exc}")

    assert isinstance(data, list), "Expected a JSON array in the output file."
    assert len(data) == 3, f"Expected exactly 3 rows in the JSON array, got {len(data)}."

    normalized = []
    frame_indices = []
    for row in data:
        if isinstance(row, dict):
            assert set(row) == {"frame_idx", "timestamp_utc", "value"}, (
                f"Each object must contain exactly frame_idx, timestamp_utc, and value; got {row}"
            )
            normalized_row = (int(row["frame_idx"]), row["timestamp_utc"], row["value"])
        elif isinstance(row, list):
            assert len(row) == 3, f"Each row array must contain all three columns; got {row}"
            normalized_row = (int(row[0]), row[1], row[2])
        else:
            raise AssertionError(f"Unexpected JSON row type: {row!r}")
        frame_indices.append(normalized_row[0])
        normalized.append(normalized_row)

    assert normalized == expected, f"Expected complete telemetry rows {expected}, got {normalized}"
    return data, frame_indices


def run_triage():
    assert os.path.isfile(TRIAGE), f"Missing triage script: {TRIAGE}"
    assert os.access(TRIAGE, os.X_OK), f"Triage script is not executable: {TRIAGE}"
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [TRIAGE], cwd="/home/user", capture_output=True, text=True, timeout=40
    )
    assert result.returncode == 0, (
        f"triage.sh failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "triage.sh did not create incident_data.json"


def listener_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or entry == "1":
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                found.add(int(entry))
                break
    return found


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), "Could not stop the existing listener on port 8080"


def start_server():
    assert os.path.isfile(SERVER), f"Missing server script: {SERVER}"
    assert os.access(SERVER, os.X_OK), f"Server script is not executable: {SERVER}"
    stop_server()
    subprocess.Popen(
        [SERVER], cwd="/home/user", stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("server.sh did not start a persistent listener on 0.0.0.0:8080")


def verify_server(expected_indices):
    try:
        response = requests.get(URL, timeout=2)
    except requests.RequestException as exc:
        raise AssertionError(f"Failed to connect to the server at {URL}: {exc}")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for request without token, got {response.status_code}."
    )

    response = requests.get(
        URL, headers={"Authorization": "Bearer wrong-token"}, timeout=2
    )
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for request with wrong token, got {response.status_code}."
    )

    response = requests.get(URL, headers=TOKEN, timeout=2)
    assert response.status_code == 200, (
        f"Expected 200 OK for authorized request, got {response.status_code}."
    )
    with open(OUTPUT, "rb") as handle:
        exact_file_contents = handle.read()
    assert response.content == exact_file_contents, (
        "Authorized endpoint did not return the exact bytes of incident_data.json"
    )
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Server did not return valid JSON. Response body: {response.text}")
    assert isinstance(data, list), "Expected a JSON array in the server response."
    assert len(data) == 3, (
        f"Expected exactly 3 rows in the JSON array, got {len(data)}."
    )
    indices = []
    for row in data:
        if isinstance(row, dict) and row.get("frame_idx") is not None:
            indices.append(int(row["frame_idx"]))
        elif isinstance(row, list) and row:
            indices.append(int(row[0]))
    assert sorted(indices) == sorted(expected_indices), (
        f"Expected frame indices {expected_indices} in server response, got {indices}."
    )


def test_complete_pipeline_and_server():
    original_critical = critical_frame(VIDEO)
    original_expected = expected_rows(DB, original_critical)

    # Preserve the original verifier's final-state assertions before executing artifacts.
    _, initial_indices = load_and_validate_output(original_expected)
    assert sorted(initial_indices) == [166, 167, 168], (
        f"Expected frame indices 166, 167, 168, but got {initial_indices}."
    )

    backup_dir = tempfile.mkdtemp(prefix="triage-verifier-")
    video_backup = os.path.join(backup_dir, "incident.mp4")
    db_backup = os.path.join(backup_dir, "telemetry.db")
    output_backup = os.path.join(backup_dir, "incident_data.json")
    shutil.copy2(VIDEO, video_backup)
    shutil.copy2(OUTPUT, output_backup)
    with sqlite3.connect(DB) as source, sqlite3.connect(db_backup) as destination:
        source.backup(destination)

    try:
        # Execute the submitted pipeline against the real task inputs.
        run_triage()
        _, original_indices = load_and_validate_output(original_expected)
        assert sorted(original_indices) == [166, 167, 168], (
            f"Expected frame indices 166, 167, 168, but got {original_indices}."
        )
        start_server()
        verify_server([166, 167, 168])

        # Replace both inputs with a verifier-created case whose critical frame and
        # telemetry values cannot be satisfied by a fabricated fixed output.
        subprocess.run(
            [
                "ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                "-i", "testsrc=duration=6:size=160x120:rate=20",
                "-c:v", "libx264", VIDEO,
            ],
            check=True,
            timeout=40,
        )
        dynamic_critical = critical_frame(VIDEO)
        assert dynamic_critical != original_critical, "Dynamic video did not change critical frame"

        for suffix in ("", "-wal", "-shm"):
            try:
                os.unlink(DB + suffix)
            except FileNotFoundError:
                pass
        rng = random.SystemRandom()
        secret_values = [rng.randrange(100000, 900000) / 10.0 for _ in range(3)]
        secret_ms = [rng.randrange(100, 999) for _ in range(3)]
        with sqlite3.connect(DB) as connection:
            connection.execute(
                "CREATE TABLE events (frame_idx INTEGER, timestamp_utc TEXT, value REAL)"
            )
            connection.execute(
                "INSERT INTO events VALUES (?, ?, ?)",
                (dynamic_critical - 1, "2040-01-01T00:00:00.001Z", -1.0),
            )
            connection.execute(
                "INSERT INTO events VALUES (?, ?, ?)",
                (dynamic_critical, "2040-01-01T00:00:00.002Z", -2.0),
            )
            for offset, (value, millis) in enumerate(zip(secret_values, secret_ms), 1):
                connection.execute(
                    "INSERT INTO events VALUES (?, ?, ?)",
                    (
                        dynamic_critical + offset,
                        f"2040-01-01T00:00:0{offset}.{millis:03d}Z",
                        value,
                    ),
                )
            connection.commit()

        dynamic_expected = expected_rows(DB, dynamic_critical)
        run_triage()
        _, dynamic_indices = load_and_validate_output(dynamic_expected)
        start_server()
        verify_server(dynamic_indices)
    finally:
        stop_server()
        shutil.copy2(video_backup, VIDEO)
        for suffix in ("", "-wal", "-shm"):
            try:
                os.unlink(DB + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(db_backup, DB)
        shutil.copy2(output_backup, OUTPUT)
        try:
            start_server()
        except Exception:
            pass
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
