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
import csv
import json
import math
import os
import re
import subprocess
import time
from pathlib import Path

import cv2
import pytest
import requests

STATS_URL = "http://127.0.0.1:9090/stats"
REPORT_URL = "http://127.0.0.1:9090/report"


def wait_for_server(url, timeout=8):
    start = time.time()
    while time.time() - start < timeout:
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.25)
    return False


def expected_data():
    cap = cv2.VideoCapture("/app/server_cam.mp4")
    assert cap.isOpened(), "Could not open the supplied video"

    flashes = []
    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        second = frame_index // 10
        while len(flashes) <= second:
            flashes.append(0)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if float(gray.mean()) > 180.0:
            flashes[second] += 1
        frame_index += 1
    cap.release()

    assert frame_index > 0, "Video contained no frames"

    with open("/home/user/sparse_logs.csv", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert rows, "Sparse log file contained no data"

    log_values = {int(row["timestamp"]): float(row["error_rate"]) for row in rows}
    start_timestamp = int(rows[0]["timestamp"])
    current_error = None
    anomalies = []
    result = []

    for second, flash_count in enumerate(flashes):
        timestamp = start_timestamp + second
        if timestamp in log_values:
            current_error = log_values[timestamp]
        assert current_error is not None, "No error_rate is available for the start of the grid"

        anomaly = flash_count * 0.5 + current_error
        anomalies.append(anomaly)
        window = anomalies[max(0, second - 4):second + 1]
        rolling = sum(window) / len(window)
        result.append({
            "second": second,
            "anomaly_score": anomaly,
            "rolling_avg": rolling,
        })

    return result


def listening_go_process():
    socket_inodes = set()
    with open("/proc/net/tcp") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            host_hex, port_hex = local_address.split(":")
            if int(port_hex, 16) == 9090 and state == "0A":
                assert host_hex == "00000000", "Port 9090 is not bound exactly to IPv4 0.0.0.0"
                socket_inodes.add(inode)

    assert socket_inodes, "No process is listening on 0.0.0.0:9090"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError):
            continue
    pytest.fail("Could not identify the process serving port 9090")


def test_go_service_and_template_source():
    assert wait_for_server(STATS_URL), "Server is not running or /stats is inaccessible"
    pid = listening_go_process()

    completed = subprocess.run(
        ["go", "version", "-m", f"/proc/{pid}/exe"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert completed.returncode == 0 and re.search(r"\bgo1\.", completed.stdout), \
        "The process serving port 9090 is not a compiled Go program"

    roots = {"/app", "/home/user", "/root", "/tmp"}
    try:
        roots.add(os.readlink(f"/proc/{pid}/cwd"))
    except OSError:
        pass

    by_directory = {}
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {".cache", ".git", "go-build", "pkg"}]
            if "/tmp/go-build" in directory:
                continue
            for name in files:
                if not name.endswith(".go"):
                    continue
                path = os.path.join(directory, name)
                try:
                    by_directory.setdefault(directory, "")
                    by_directory[directory] += Path(path).read_text(errors="ignore") + "\n"
                except OSError:
                    pass

    valid_source = any(
        '"text/template"' in source
        and "/stats" in source
        and "/report" in source
        and "Execute" in source
        and ("ListenAndServe" in source or "Serve(" in source)
        for source in by_directory.values()
    )
    assert valid_source, "No self-contained Go service source using text/template was found"


def test_stats_endpoint_all_seconds():
    expected = expected_data()
    assert wait_for_server(STATS_URL), "Server is not running or /stats endpoint is not accessible."

    response = requests.get(STATS_URL, timeout=3)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert isinstance(data, list), "Expected a JSON array"
    assert len(data) >= 20, f"Expected at least 20 elements, got {len(data)}"
    assert len(data) == len(expected), \
        f"Expected exactly one object per video second ({len(expected)}), got {len(data)}"

    for index, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Element {index} is not an object"
        for field in ("second", "anomaly_score", "rolling_avg"):
            assert field in actual, f"Element {index} is missing {field}"
        assert actual["second"] == wanted["second"], \
            f"Expected second {wanted['second']} at index {index}, got {actual['second']}"
        for field in ("anomaly_score", "rolling_avg"):
            assert isinstance(actual[field], (int, float)) and not isinstance(actual[field], bool), \
                f"{field} at second {index} is not numeric"
            assert math.isfinite(float(actual[field])), f"{field} at second {index} is not finite"
            assert math.isclose(float(actual[field]), wanted[field], rel_tol=1e-7, abs_tol=1e-7), \
                f"Wrong {field} at second {index}: expected {wanted[field]}, got {actual[field]}"

    # Preserve the original known-value checks as an additional fixture sanity check.
    assert math.isclose(float(data[6]["anomaly_score"]), 5.0, abs_tol=0.1)
    assert math.isclose(float(data[6]["rolling_avg"]), 3.2, abs_tol=0.1)


def test_report_endpoint_and_generated_file():
    expected = expected_data()
    max_score = max(item["rolling_avg"] for item in expected)
    max_seconds = {
        item["second"] for item in expected
        if math.isclose(item["rolling_avg"], max_score, rel_tol=1e-9, abs_tol=1e-9)
    }

    assert wait_for_server(REPORT_URL), "Server is not running or /report endpoint is not accessible."
    response = requests.get(REPORT_URL, timeout=3)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain"), \
        "/report must return plain text"

    text = response.text
    assert "Maximum Rolling Anomaly Score" in text, \
        "Report missing 'Maximum Rolling Anomaly Score'"
    match = re.fullmatch(
        r"Maximum Rolling Anomaly Score:\s*"
        r"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"
        r"\s+at second\s+(\d+)\s*",
        text,
    )
    assert match, "Report does not have the required template output format"
    reported_score = float(match.group(1))
    reported_second = int(match.group(2))
    assert math.isclose(reported_score, max_score, rel_tol=1e-7, abs_tol=1e-7), \
        f"Expected maximum rolling score {max_score}, got {reported_score}"
    assert reported_second in max_seconds, \
        f"Second {reported_second} does not correspond to the maximum rolling score"

    pid = listening_go_process()
    search_roots = {"/app", "/home/user", "/root", "/tmp"}
    try:
        search_roots.add(os.readlink(f"/proc/{pid}/cwd"))
    except OSError:
        pass

    report_files = []
    for root in search_roots:
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {".cache", ".git", "go-build", "pkg"}]
            if "incident_report.txt" in files:
                report_files.append(os.path.join(directory, "incident_report.txt"))

    assert report_files, "The required incident_report.txt file was not generated"
    assert any(Path(path).read_bytes() == response.content for path in report_files), \
        "/report does not return the raw contents of the generated incident_report.txt"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
