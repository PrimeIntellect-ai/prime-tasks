#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import itertools
import secrets

import cv2
import jsonschema
import pytest
import requests

URL = "http://127.0.0.1:8080/api/investigate"
RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "suspect_drivers": {
            "type": "array",
            "items": {"type": "string"},
        }
    },
    "required": ["suspect_drivers"],
}


def post_investigate(payload):
    try:
        return requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API service at {URL}. Is the service running? Error: {e}")


def test_api_investigate_endpoint():
    url = "http://127.0.0.1:8080/api/investigate"
    payload = {"video_ping_ids": [45, 120, 315]}

    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API service at {url}. Is the service running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, but got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "suspect_drivers" in data, f"Key 'suspect_drivers' missing from response. Response data: {data}"

    expected_drivers = ["Alice", "Charlie"]
    actual_drivers = data["suspect_drivers"]

    assert isinstance(actual_drivers, list), f"Expected 'suspect_drivers' to be a list, got {type(actual_drivers)}"
    assert actual_drivers == expected_drivers, f"Expected suspect drivers {expected_drivers}, but got {actual_drivers}"


def load_graph():
    node_rows = None
    edge_rows = None
    for path in glob.glob("/home/user/logistics_data/*.csv"):
        with open(path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            headers = {h.strip().lower() for h in (reader.fieldnames or [])}
            rows = list(reader)
        if {"id", "type", "name"}.issubset(headers):
            assert node_rows is None, "Multiple node CSV files found"
            node_rows = rows
        if {"source", "target", "relation"}.issubset(headers):
            assert edge_rows is None, "Multiple edge CSV files found"
            edge_rows = rows

    assert node_rows is not None, "Could not identify the nodes CSV"
    assert edge_rows is not None, "Could not identify the edges CSV"

    nodes = {
        row["id"]: {"type": row["type"].strip().lower(), "name": row["name"].strip()}
        for row in node_rows
    }
    drivers_by_vehicle = {}
    vehicles_by_ping = {}

    for row in edge_rows:
        source = row["source"]
        target = row["target"]
        relation = row["relation"].strip().lower()
        assert source in nodes and target in nodes, f"Edge references an unknown node: {row}"
        endpoints = (source, target)

        if relation == "drove":
            driver = next((n for n in endpoints if nodes[n]["type"] == "driver"), None)
            vehicle = next((n for n in endpoints if nodes[n]["type"] == "vehicle"), None)
            assert driver and vehicle, f"Malformed drove edge: {row}"
            drivers_by_vehicle.setdefault(vehicle, set()).add(nodes[driver]["name"])
        elif relation == "detected_at":
            vehicle = next((n for n in endpoints if nodes[n]["type"] == "vehicle"), None)
            ping = next((n for n in endpoints if nodes[n]["type"] == "ping"), None)
            assert vehicle and ping, f"Malformed detected_at edge: {row}"
            ping_id = int(nodes[ping]["name"])
            vehicles_by_ping.setdefault(ping_id, set()).add(vehicle)

    return drivers_by_vehicle, vehicles_by_ping


def expected_for(ids, drivers_by_vehicle, vehicles_by_ping):
    matched = set()
    for ping_id in ids:
        for vehicle in vehicles_by_ping.get(ping_id, set()):
            matched.update(drivers_by_vehicle.get(vehicle, set()))
    return sorted(matched)


def extract_video_ping_ids():
    capture = cv2.VideoCapture("/app/traffic_sensor.mp4")
    assert capture.isOpened(), "Could not open /app/traffic_sensor.mp4"
    result = []
    frame_number = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        if float(frame.mean()) > 200:
            result.append(frame_number)
        frame_number += 1
    capture.release()
    return result


def test_endpoint_uses_request_values_and_graph():
    drivers_by_vehicle, vehicles_by_ping = load_graph()
    known_ping_ids = sorted(vehicles_by_ping)
    video_ping_ids = extract_video_ping_ids()
    assert video_ping_ids == [45, 120, 315]

    cases = [list(combo) for size in range(len(known_ping_ids) + 1)
             for combo in itertools.combinations(known_ping_ids, size)]

    rng = secrets.SystemRandom()
    known_set = set(known_ping_ids)
    for _ in range(8):
        requested = [ping for ping in known_ping_ids if rng.choice([True, False])]
        unknown = rng.randrange(10000, 1000000)
        while unknown in known_set:
            unknown = rng.randrange(10000, 1000000)
        requested.append(unknown)
        rng.shuffle(requested)
        cases.append(requested)

    cases.append(video_ping_ids)

    for requested_ids in cases:
        response = post_investigate({"video_ping_ids": requested_ids})
        assert response.status_code == 200, (
            f"Expected HTTP 200 for {requested_ids}, got {response.status_code}: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response for {requested_ids} is not valid JSON: {response.text}")

        jsonschema.validate(instance=data, schema=RESPONSE_SCHEMA)
        actual = data["suspect_drivers"]
        expected = expected_for(requested_ids, drivers_by_vehicle, vehicles_by_ping)
        assert actual == sorted(actual), f"Driver array is not alphabetically sorted for {requested_ids}: {actual}"
        assert actual == expected, f"For ping IDs {requested_ids}, expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
