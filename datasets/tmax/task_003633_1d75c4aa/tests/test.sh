#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shlex
import subprocess
import uuid
import xml.etree.ElementTree as ET
from collections import defaultdict, deque

import pytest

INCOMING_DIR = "/home/user/data/incoming"
ARCHIVE_DIR = "/home/user/data/archive"
OUTPUT_JSON = "/home/user/data/output/metrics.json"
OUTPUT_XML = "/home/user/data/output/metrics.xml"

EXPECTED_METRICS = {
    "e1": {"timestamp": "2023-10-01T10:00:00Z", "device_id": "devA", "sensor_value": 10.0, "rolling_avg": 10.0},
    "e2": {"timestamp": "2023-10-01T10:01:00Z", "device_id": "devB", "sensor_value": 20.0, "rolling_avg": 20.0},
    "e3": {"timestamp": "2023-10-01T10:02:00Z", "device_id": "devA", "sensor_value": 15.0, "rolling_avg": 12.5},
    "e4": {"timestamp": "2023-10-01T10:03:00Z", "device_id": "devA", "sensor_value": 20.0, "rolling_avg": 15.0},
    "e5": {"timestamp": "2023-10-01T10:04:00Z", "device_id": "devA", "sensor_value": 25.0, "rolling_avg": 20.0},
    "e6": {"timestamp": "2023-10-01T10:05:00Z", "device_id": "devB", "sensor_value": 30.0, "rolling_avg": 25.0},
    "e7": {"timestamp": "2023-10-01T10:06:00Z", "device_id": "devB", "sensor_value": 40.0, "rolling_avg": 30.0},
}


def read_user_cron():
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab or no crontab exists for user.")
    return result.stdout


def scheduled_commands(crontab_output):
    commands = []
    for raw_line in crontab_output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" in line.split()[0]:
            continue
        parts = line.split(None, 5)
        if len(parts) < 6:
            continue
        minute = parts[0]
        if "*/5" in minute or "0,5,10,15,20,25,30,35,40,45,50,55" in minute:
            commands.append(parts[5])
    return commands


def find_pipeline_script(command):
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None

    suffixes = (".py", ".sh", ".pl", ".rb", ".js", ".php", ".lua")
    for token in tokens:
        token = token.strip(";|&()")
        if not token or token.startswith("-"):
            continue
        if os.path.isabs(token):
            candidate = os.path.normpath(token)
        else:
            candidate = os.path.normpath(os.path.join("/home/user", token))
        if not candidate.startswith("/home/user/") or not os.path.isfile(candidate):
            continue
        try:
            with open(candidate, "rb") as f:
                prefix = f.read(128)
        except OSError:
            continue
        if candidate.endswith(suffixes) or os.access(candidate, os.X_OK) or prefix.startswith(b"#!"):
            return candidate
    return None


def test_incoming_directory_empty():
    assert os.path.isdir(INCOMING_DIR), f"Directory missing: {INCOMING_DIR}"
    files = os.listdir(INCOMING_DIR)
    csv_files = [f for f in files if f.endswith('.csv')]
    assert len(csv_files) == 0, f"Incoming directory is not empty, found: {csv_files}"


def test_archive_directory_contains_files():
    assert os.path.isdir(ARCHIVE_DIR), f"Directory missing: {ARCHIVE_DIR}"
    files = os.listdir(ARCHIVE_DIR)
    assert "batch1.csv" in files, "batch1.csv is missing from the archive directory"
    assert "batch2.csv" in files, "batch2.csv is missing from the archive directory"


def test_json_output():
    assert os.path.isfile(OUTPUT_JSON), f"JSON output file missing: {OUTPUT_JSON}"
    try:
        with open(OUTPUT_JSON, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("metrics.json is not valid JSON")

    assert isinstance(data, list), "JSON root must be an array"
    assert len(data) == 7, f"Expected 7 records in JSON, found {len(data)}"
    assert [r.get("event_id") for r in data] == list(EXPECTED_METRICS), \
        "JSON records must be unique and chronologically ordered"

    for record in data:
        event_id = record.get("event_id")
        assert event_id in EXPECTED_METRICS, f"Unexpected event_id in JSON: {event_id}"
        expected = EXPECTED_METRICS[event_id]
        assert record.get("timestamp") == expected["timestamp"], f"Incorrect timestamp for {event_id}"
        assert record.get("device_id") == expected["device_id"], f"Incorrect device_id for {event_id}"
        assert float(record.get("sensor_value")) == expected["sensor_value"], f"Incorrect sensor_value for {event_id}"
        assert float(record.get("rolling_avg")) == expected["rolling_avg"], f"Incorrect rolling_avg for {event_id}"


def test_xml_output():
    assert os.path.isfile(OUTPUT_XML), f"XML output file missing: {OUTPUT_XML}"
    try:
        root = ET.parse(OUTPUT_XML).getroot()
    except ET.ParseError:
        pytest.fail("metrics.xml is not valid XML")

    assert root.tag == "metrics", "XML root element must be <metrics>"
    metrics = root.findall("metric")
    assert len(metrics) == 7, f"Expected 7 <metric> elements in XML, found {len(metrics)}"
    assert [m.findtext("event_id") for m in metrics] == list(EXPECTED_METRICS), \
        "XML records must be unique and chronologically ordered"

    for metric in metrics:
        event_id = metric.findtext("event_id")
        assert event_id in EXPECTED_METRICS, f"Unexpected event_id in XML: {event_id}"
        expected = EXPECTED_METRICS[event_id]
        assert metric.findtext("timestamp") == expected["timestamp"], f"Incorrect timestamp for {event_id}"
        assert metric.findtext("device_id") == expected["device_id"], f"Incorrect device_id for {event_id}"
        assert float(metric.findtext("sensor_value")) == expected["sensor_value"], f"Incorrect sensor_value for {event_id}"
        assert float(metric.findtext("rolling_avg")) == expected["rolling_avg"], f"Incorrect rolling_avg for {event_id}"


def test_cron_job_scheduled_for_user():
    commands = scheduled_commands(read_user_cron())
    assert commands, "Could not find a cron job for user scheduled to run every 5 minutes."
    assert any(find_pipeline_script(command) for command in commands), \
        "The user's five-minute cron job must invoke an existing pipeline script."


def test_pipeline_on_new_inputs():
    commands = scheduled_commands(read_user_cron())
    runnable = [(command, find_pipeline_script(command)) for command in commands]
    runnable = [(command, script) for command, script in runnable if script]
    assert runnable, "No five-minute user cron command invokes an existing pipeline script"

    token = uuid.uuid4().hex[:10]
    dev_a = "dynamicA_" + token
    dev_b = "dynamicB_" + token
    ids = [f"dyn_{token}_{i}" for i in range(8)]
    chronological = [
        {"event_id": ids[0], "timestamp": "2041-06-01T09:00:00Z", "device_id": dev_a, "sensor_value": 11.0},
        {"event_id": ids[1], "timestamp": "2041-06-01T09:01:00Z", "device_id": dev_b, "sensor_value": 7.0},
        {"event_id": ids[2], "timestamp": "2041-06-01T09:02:00Z", "device_id": dev_a, "sensor_value": 17.0},
        {"event_id": ids[3], "timestamp": "2041-06-01T09:03:00Z", "device_id": dev_a, "sensor_value": 29.0},
        {"event_id": ids[4], "timestamp": "2041-06-01T09:04:00Z", "device_id": dev_b, "sensor_value": 19.0},
        {"event_id": ids[5], "timestamp": "2041-06-01T09:05:00Z", "device_id": dev_a, "sensor_value": 41.0},
        {"event_id": ids[6], "timestamp": "2041-06-01T09:06:00Z", "device_id": dev_b, "sensor_value": 31.0},
        {"event_id": ids[7], "timestamp": "2041-06-01T09:07:00Z", "device_id": dev_b, "sensor_value": 43.0},
    ]

    # Deliberately distribute records out of chronological order and duplicate one
    # event across files. The duplicate is identical so the unspecified choice of
    # which duplicate to retain cannot affect the expected result.
    batches = [
        [chronological[5], chronological[1], chronological[3], chronological[6]],
        [chronological[7], chronological[2], chronological[0], chronological[4], chronological[3]],
    ]
    filenames = [f"dynamic_{token}_a.csv", f"dynamic_{token}_b.csv"]
    fields = ["event_id", "timestamp", "device_id", "sensor_value"]
    for filename, rows in zip(filenames, batches):
        path = os.path.join(INCOMING_DIR, filename)
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        os.chown(path, 1000, 1000)

    command, script = runnable[0]
    assert os.path.getsize(script) > 0, "Pipeline script is empty"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-lc", command],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"Pipeline command failed with code {result.returncode}: {result.stderr}"

    assert not [f for f in os.listdir(INCOMING_DIR) if f.endswith(".csv")], \
        "Pipeline did not move all newly processed CSV files out of incoming"
    for filename in filenames:
        assert os.path.isfile(os.path.join(ARCHIVE_DIR, filename)), \
            f"Newly processed file was not archived: {filename}"

    windows = defaultdict(lambda: deque(maxlen=3))
    expected = []
    for row in chronological:
        window = windows[row["device_id"]]
        window.append(row["sensor_value"])
        expected.append({
            **row,
            "rolling_avg": round(sum(window) / len(window), 2),
        })

    with open(OUTPUT_JSON, "r") as f:
        json_data = json.load(f)
    assert len(json_data) == len(expected), "JSON must contain exactly the deduplicated new records"
    assert [r.get("event_id") for r in json_data] == [r["event_id"] for r in expected], \
        "JSON records are not deduplicated and chronologically sorted"
    for actual, wanted in zip(json_data, expected):
        assert set(actual) == {"event_id", "timestamp", "device_id", "sensor_value", "rolling_avg"}
        assert actual["event_id"] == wanted["event_id"]
        assert actual["timestamp"] == wanted["timestamp"]
        assert actual["device_id"] == wanted["device_id"]
        assert float(actual["sensor_value"]) == wanted["sensor_value"]
        assert isinstance(actual["rolling_avg"], float), "JSON rolling_avg must be a float"
        assert actual["rolling_avg"] == pytest.approx(wanted["rolling_avg"])

    root = ET.parse(OUTPUT_XML).getroot()
    assert root.tag == "metrics"
    xml_metrics = root.findall("metric")
    assert len(xml_metrics) == len(expected), "XML must contain exactly the deduplicated new records"
    assert [m.findtext("event_id") for m in xml_metrics] == [r["event_id"] for r in expected]
    required_tags = ["event_id", "timestamp", "device_id", "sensor_value", "rolling_avg"]
    for metric, wanted in zip(xml_metrics, expected):
        assert [child.tag for child in metric] == required_tags
        assert metric.findtext("timestamp") == wanted["timestamp"]
        assert metric.findtext("device_id") == wanted["device_id"]
        assert float(metric.findtext("sensor_value")) == wanted["sensor_value"]
        assert float(metric.findtext("rolling_avg")) == pytest.approx(wanted["rolling_avg"])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
