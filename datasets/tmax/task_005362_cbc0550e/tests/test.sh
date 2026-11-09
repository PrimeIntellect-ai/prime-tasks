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
import importlib.util
import json
import math
import os
import secrets
import shutil
import sqlite3

import cv2
import numpy as np
import pytest
import requests

SERVICE_DIR = "/app/video_service"
VIDEO_PATH = "/app/test_video.mp4"
SECRET = "sec_99abf210d"


def test_config_json_secret_recovered():
    config_path = "/app/video_service/config.json"
    assert os.path.isfile(config_path), f"File {config_path} does not exist."

    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{config_path} is not valid JSON.")

    assert "api_secret" in config, "Key 'api_secret' not found in config.json."
    assert config["api_secret"] == SECRET, "The recovered API secret is incorrect."


def test_database_recovered():
    db_path = "/app/video_service/db/settings.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = None
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM thresholds")
        rows = cursor.fetchall()
        assert len(rows) > 0, "The 'thresholds' table is empty. Database recovery might have failed."

        cursor.execute("PRAGMA integrity_check")
        assert cursor.fetchone() == ("ok",), "Recovered database fails SQLite integrity_check."

        cursor.execute("PRAGMA table_info(thresholds)")
        columns = cursor.fetchall()
        expected_columns = [
            (0, "id", "INTEGER", 0, None, 1),
            (1, "color", "TEXT", 0, None, 0),
            (2, "min_r", "INTEGER", 0, None, 0),
        ]
        assert columns == expected_columns, f"Unexpected thresholds schema: {columns}"

        cursor.execute("SELECT id, color, min_r FROM thresholds ORDER BY id")
        recovered_rows = cursor.fetchall()
        assert recovered_rows == [(1, "red", 200)], \
            f"The original thresholds state was not recovered: {recovered_rows}"
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Failed to read 'thresholds' table from database: {e}")
    finally:
        if conn is not None:
            conn.close()


def test_log_file_contents():
    log_path = "/app/video_service/found_timestamps.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.read().splitlines()

    floats = []
    for line in lines:
        line = line.strip()
        if line:
            try:
                floats.append(float(line))
            except ValueError:
                pytest.fail(f"Log file contains non-float value: {line}")

    expected = [1.5, 3.0, 4.5]
    assert len(floats) == len(expected), f"Expected {len(expected)} timestamps, found {len(floats)}."

    for f_val, e_val in zip(floats, expected):
        assert math.isclose(f_val, e_val, abs_tol=0.01), f"Expected timestamp ~{e_val}, found {f_val}."


def test_service_running_and_responds():
    url = "http://127.0.0.1:8080/api/events"
    headers = {"Authorization": f"Bearer {SECRET}"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "events" in data, "Response JSON does not contain 'events' key."
    events = data["events"]
    assert isinstance(events, list), "'events' should be a list."

    expected = [1.5, 3.0, 4.5]
    assert len(events) == len(expected), f"Expected {len(expected)} events, got {len(events)}."

    for f_val, e_val in zip(events, expected):
        assert isinstance(f_val, (int, float)), f"Event value {f_val} is not a number."
        assert math.isclose(f_val, e_val, abs_tol=0.01), f"Expected event ~{e_val}, found {f_val}."


def _make_unpredictable_video(path):
    rng = secrets.SystemRandom()
    fps = rng.choice([24, 30])
    total_frames = rng.randint(72, 110)
    candidates = [
        i for i in range(4, total_frames - 4)
        if abs((i / fps) - round(i / fps, 2)) > 0.002
    ]
    event_frames = sorted(rng.sample(candidates, rng.randint(2, 4)))

    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), float(fps), (96, 96))
    assert writer.isOpened(), "Verifier could not create a temporary test video."
    try:
        for index in range(total_frames):
            frame = np.zeros((96, 96, 3), dtype=np.uint8)
            if index in event_frames:
                frame[:, :] = (0, 0, 255)
            writer.write(frame)
    finally:
        writer.release()

    assert os.path.getsize(path) > 0, "Temporary test video is empty."
    return [index / float(fps) for index in event_frames]


def _assert_precise_events(actual, expected):
    assert isinstance(actual, list), f"Analyzer result must be a list, got {type(actual).__name__}."
    assert len(actual) == len(expected), f"Expected {len(expected)} generated events, got {len(actual)}: {actual}"
    for value, wanted in zip(actual, expected):
        assert isinstance(value, float), f"Analyzer timestamp must remain a float, got {value!r}."
        assert math.isclose(value, wanted, rel_tol=0.0, abs_tol=0.001), \
            f"Expected generated timestamp {wanted:.6f}, got {value!r}."


def test_analyzer_artifact_and_service_on_unpredictable_video():
    analyzer_path = os.path.join(SERVICE_DIR, "analyzer.py")
    assert os.path.isfile(analyzer_path), f"File {analyzer_path} does not exist."

    dynamic_path = f"/tmp/verifier_video_{secrets.token_hex(8)}.mp4"
    backup_path = f"/tmp/original_video_{secrets.token_hex(8)}.mp4"
    expected = _make_unpredictable_video(dynamic_path)

    try:
        spec = importlib.util.spec_from_file_location("submitted_analyzer", analyzer_path)
        assert spec is not None and spec.loader is not None, "analyzer.py is not a loadable Python module."
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert callable(getattr(module, "analyze_video", None)), "analyzer.py does not define analyze_video()."

        direct_events = module.analyze_video(dynamic_path)
        _assert_precise_events(direct_events, expected)

        shutil.copy2(VIDEO_PATH, backup_path)
        try:
            shutil.copy2(dynamic_path, VIDEO_PATH)
            response = requests.get(
                "http://127.0.0.1:8080/api/events",
                headers={"Authorization": f"Bearer {SECRET}"},
                timeout=10,
            )
            assert response.status_code == 200, \
                f"Service failed on generated video: {response.status_code} {response.text}"
            try:
                payload = response.json()
            except ValueError:
                pytest.fail(f"Generated-video response is not valid JSON: {response.text}")
            assert isinstance(payload, dict) and "events" in payload, \
                "Generated-video response lacks an events field."
            _assert_precise_events(payload["events"], expected)
        finally:
            if os.path.exists(backup_path):
                os.replace(backup_path, VIDEO_PATH)
    finally:
        if os.path.exists(dynamic_path):
            os.unlink(dynamic_path)
        if os.path.exists(backup_path):
            os.unlink(backup_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
