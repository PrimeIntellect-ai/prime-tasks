#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import urllib.error
import urllib.request

SOURCE = "/home/user/data/sensor_logs.csv"
OUTPUT = "/home/user/processed_logs.jsonl"
SUMMARY = "/home/user/server_root/summary.json"


def haversine_km(a, b):
    lat1, lon1 = math.radians(a["lat"]), math.radians(a["lon"])
    lat2, lon2 = math.radians(b["lat"]), math.radians(b["lon"])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371.0 * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


def load_source_and_expected():
    assert os.path.isfile(SOURCE), f"The source file {SOURCE} does not exist."
    with open(SOURCE, "r", encoding="cp1252", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["timestamp", "lat", "lon", "temperature"]
        rows = []
        for row in reader:
            rows.append({
                "timestamp": int(row["timestamp"]),
                "lat": float(row["lat"]),
                "lon": float(row["lon"]),
                "temperature": None if row["temperature"] == "" else float(row["temperature"]),
            })

    # Ensure the agent did not replace or rewrite the verifier input.
    base_lat, base_lon = 40.7128, -74.0060
    expected_source = [
        (1600000000, base_lat, base_lon, 20.0),
        (1600000010, base_lat + 0.001, base_lon + 0.001, None),
        (1600000020, base_lat + 0.002, base_lon + 0.002, 22.0),
        (1600000030, base_lat + 10.0, base_lon + 10.0, 99.0),
        (1600000040, base_lat + 0.003, base_lon + 0.003, None),
        (1600000050, base_lat + 0.004, base_lon + 0.004, 25.0),
    ]
    assert len(rows) == len(expected_source), "The source CSV was modified."
    for row, expected in zip(rows, expected_source):
        ts, lat, lon, temp = expected
        assert row["timestamp"] == ts, "The source CSV timestamps were modified."
        assert row["lat"] == lat and row["lon"] == lon, "The source CSV coordinates were modified."
        assert row["temperature"] == temp, "The source CSV temperatures were modified."

    valid = []
    for row in rows:
        if not valid:
            valid.append(dict(row))
            continue
        elapsed = row["timestamp"] - valid[-1]["timestamp"]
        assert elapsed > 0
        speed_mps = haversine_km(valid[-1], row) * 1000.0 / elapsed
        if speed_mps <= 250.0:
            valid.append(dict(row))

    known = [i for i, row in enumerate(valid) if row["temperature"] is not None]
    assert known and known[0] == 0 and known[-1] == len(valid) - 1
    for left, right in zip(known, known[1:]):
        t0 = valid[left]["timestamp"]
        t1 = valid[right]["timestamp"]
        v0 = valid[left]["temperature"]
        v1 = valid[right]["temperature"]
        for i in range(left + 1, right):
            fraction = (valid[i]["timestamp"] - t0) / (t1 - t0)
            valid[i]["temperature"] = v0 + fraction * (v1 - v0)

    for row in valid:
        row["temperature"] = round(row["temperature"], 2)

    distance = round(sum(haversine_km(valid[i - 1], valid[i]) for i in range(1, len(valid))), 2)
    return valid, distance


def read_output():
    assert os.path.isfile(OUTPUT), f"The file {OUTPUT} does not exist."
    with open(OUTPUT, "rb") as f:
        raw = f.read()
    assert raw.endswith(b"\n"), "The JSON Lines file must end with a newline."
    text = raw.decode("utf-8")
    lines = text.splitlines()
    assert all(line.strip() for line in lines), "The JSON Lines file contains a blank line."
    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Line {i + 1} in {OUTPUT} is not valid JSON."
    return lines, records


def test_processed_logs_exist_and_format():
    lines, records = read_output()
    assert len(lines) == 5, f"Expected 5 lines in {OUTPUT}, but found {len(lines)}."
    expected_keys = {"timestamp", "lat", "lon", "temperature"}
    for i, data in enumerate(records):
        assert set(data.keys()) == expected_keys, f"Line {i + 1} has incorrect keys. Expected {expected_keys}, got {set(data.keys())}."
        assert type(data["timestamp"]) is int, f"Line {i + 1} timestamp is not an int."
        assert type(data["lat"]) is float, f"Line {i + 1} lat is not a float."
        assert type(data["lon"]) is float, f"Line {i + 1} lon is not a float."
        assert type(data["temperature"]) is float, f"Line {i + 1} temperature is not a float."
        assert all(math.isfinite(data[k]) for k in ("lat", "lon", "temperature")), f"Line {i + 1} contains a non-finite number."


def test_processed_logs_data():
    expected, _ = load_source_and_expected()
    _, records = read_output()
    assert len(records) == 5, "Expected 5 records."

    # Preserve the original interpolation check for row 2.
    assert abs(records[1]["temperature"] - 21.0) < 0.01, f"Expected temperature 21.0 at row 2, got {records[1]['temperature']}."
    # Timestamp-based interpolation after dropping the anomaly yields 24.0 here.
    assert abs(records[3]["temperature"] - 24.0) < 0.01, f"Expected temperature 24.0 at row 4, got {records[3]['temperature']}."

    for i, (actual, wanted) in enumerate(zip(records, expected), 1):
        assert actual["timestamp"] == wanted["timestamp"], f"Incorrect timestamp on output line {i}."
        assert math.isclose(actual["lat"], wanted["lat"], rel_tol=0.0, abs_tol=1e-12), f"Incorrect latitude on output line {i}."
        assert math.isclose(actual["lon"], wanted["lon"], rel_tol=0.0, abs_tol=1e-12), f"Incorrect longitude on output line {i}."
        assert actual["temperature"] == wanted["temperature"], f"Incorrect temperature on output line {i}."
        assert actual["temperature"] == round(actual["temperature"], 2), f"Temperature on output line {i} is not rounded to 2 decimals."


def test_summary_json():
    expected_records, expected_distance = load_source_and_expected()
    assert os.path.isfile(SUMMARY), f"The file {SUMMARY} does not exist."
    with open(SUMMARY, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {SUMMARY} is not valid JSON."

    assert "final_row_count" in data, "Key 'final_row_count' missing in summary.json."
    assert data["final_row_count"] == 5, f"Expected final_row_count to be 5, got {data['final_row_count']}."
    assert "total_valid_distance_km" in data, "Key 'total_valid_distance_km' missing in summary.json."
    distance = data["total_valid_distance_km"]
    assert isinstance(distance, (int, float)), "total_valid_distance_km must be a number."
    assert 0.55 <= distance <= 0.57, f"Expected total_valid_distance_km to be between 0.55 and 0.57, got {distance}."

    assert set(data) == {"total_valid_distance_km", "final_row_count"}, "summary.json has an incorrect structure."
    assert type(data["final_row_count"]) is int
    assert data["final_row_count"] == len(expected_records)
    assert type(distance) is float and math.isfinite(distance)
    assert distance == expected_distance, f"Expected recomputed distance {expected_distance}, got {distance}."


def test_server_running():
    expected_records, expected_distance = load_source_and_expected()
    url = "http://127.0.0.1:8080/summary.json"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            content = response.read().decode("utf-8")
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to the server at {url}. Is it running? Error: {e}"

    assert status == 200, f"Expected HTTP status 200, got {status}."
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        assert False, f"The response from {url} is not valid JSON."

    assert "final_row_count" in data, "Key 'final_row_count' missing in server response."
    assert data["final_row_count"] == 5, "Server response has incorrect final_row_count."
    assert data == {
        "total_valid_distance_km": expected_distance,
        "final_row_count": len(expected_records),
    }, "The HTTP server is not serving the exact recomputed summary."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
