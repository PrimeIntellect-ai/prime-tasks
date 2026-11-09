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
import ctypes
import math
import os
import sqlite3
import subprocess

import cv2
import pytest
import requests

LIB_PATH = '/home/user/mathlib/libmathops.so'
VIDEO_PATH = '/app/video.mp4'
DB_PATH = '/home/user/db/metrics.db'


def read_brightness_values():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open video {VIDEO_PATH}"

    values = []
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            values.append(float(gray.sum(dtype='float64') / gray.size))
    finally:
        cap.release()

    assert len(values) >= 5, "The video must contain at least five decodable frames."
    return values


def python_max_variation(values, window_size=5):
    maxima = []
    for start in range(len(values) - window_size + 1):
        window = values[start:start + window_size]
        mean = sum(window) / window_size
        variance = sum((value - mean) ** 2 for value in window) / window_size
        maxima.append(math.sqrt(variance))
    return max(maxima)


def load_compute_function():
    try:
        library = ctypes.CDLL(LIB_PATH)
    except OSError as exc:
        pytest.fail(f"Failed to load {LIB_PATH}: {exc}")

    try:
        function = library.compute_max_variation
    except AttributeError:
        pytest.fail("libmathops.so does not export compute_max_variation")

    function.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_int]
    function.restype = ctypes.c_double
    return library, function


def test_c_library_linked_correctly_and_functional():
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} does not exist. Did you recompile the library?"

    result = subprocess.run(['ldd', LIB_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"ldd failed for {LIB_PATH}: {result.stderr}"
    assert 'libm.so' in result.stdout, "libmathops.so is not linked against the standard math library (libm.so). Check your Makefile."

    values = read_brightness_values()
    expected = python_max_variation(values, 5)
    library, function = load_compute_function()
    array = (ctypes.c_double * len(values))(*values)
    actual = function(array, len(values), 5)

    assert math.isfinite(actual), "compute_max_variation returned a non-finite value"
    assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-7), (
        f"compute_max_variation returned {actual}, but independently computed value is {expected}"
    )
    assert library is not None


def test_database_schema_migrated():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(video_stats);")
        columns = [col[1] for col in cursor.fetchall()]
    finally:
        conn.close()

    assert 'max_variation' in columns, "Column 'max_variation' was not added to the video_stats table."


def test_api_process_and_database_insertion():
    values = read_brightness_values()
    expected = python_max_variation(values, 5)

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COALESCE(MAX(id), 0) FROM video_stats;")
        previous_max_id = cursor.fetchone()[0]
    finally:
        conn.close()

    url = "http://127.0.0.1:8000/api/v1/process"
    try:
        response = requests.get(url, timeout=15)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the FastAPI service at {url}. Is it running? Error: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert data.get("status") == "ok", f"Expected status 'ok', got '{data.get('status')}'"
    assert "max_variation" in data, "Response JSON is missing the 'max_variation' key."

    api_max_variation = data["max_variation"]
    assert isinstance(api_max_variation, (int, float)) and not isinstance(api_max_variation, bool), (
        f"Expected max_variation to be a number, got {type(api_max_variation)}"
    )
    assert math.isfinite(api_max_variation), "API max_variation must be finite"
    assert math.isclose(api_max_variation, expected, rel_tol=1e-7, abs_tol=1e-5), (
        f"API max_variation ({api_max_variation}) does not match the independently computed video value ({expected})."
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id, filename, max_variation FROM video_stats "
            "WHERE filename = 'video.mp4' AND id > ? ORDER BY id DESC LIMIT 1;",
            (previous_max_id,),
        )
        row = cursor.fetchone()
    finally:
        conn.close()

    assert row is not None, "No new row found for 'video.mp4' after calling the API."
    _, db_filename, db_max_variation = row
    assert db_filename == 'video.mp4', f"Expected filename 'video.mp4', got '{db_filename}'"
    assert isinstance(db_max_variation, (int, float)), "Database max_variation is not numeric"
    assert math.isfinite(db_max_variation), "Database max_variation must be finite"
    assert abs(db_max_variation - api_max_variation) < 1e-5, (
        f"Database max_variation ({db_max_variation}) does not match API response ({api_max_variation})."
    )
    assert math.isclose(db_max_variation, expected, rel_tol=1e-7, abs_tol=1e-5), (
        f"Database max_variation ({db_max_variation}) does not match the independently computed video value ({expected})."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
