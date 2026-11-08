#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
from datetime import datetime

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
TOKEN = "iron_badger"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}

EXPECTED_CATALOG = [
    {"id": "B-001", "parent_id": None, "timestamp": "2023-10-01T10:00:00Z"},
    {"id": "B-002", "parent_id": "B-001", "timestamp": "2023-10-02T10:00:00Z"},
    {"id": "B-003", "parent_id": "B-002", "timestamp": "2023-10-03T10:00:00Z"},
    {"id": "B-004", "parent_id": "B-003", "timestamp": "2023-10-04T10:00:00Z"},
    {"id": "B-005", "parent_id": "B-004", "timestamp": "2023-10-05T10:00:00Z"},
    {"id": "B-099", "parent_id": "B-001", "timestamp": "2023-10-02T11:00:00Z"},
]

with open("/app/backups.json", "r", encoding="utf-8") as catalog_file:
    CATALOG = json.load(catalog_file)

# Prevent a submission from shrinking or replacing the supplied graph so that
# dynamically generated tests cover fewer nodes.
assert CATALOG == EXPECTED_CATALOG, "/app/backups.json was modified"
NODES = {node["id"]: node for node in CATALOG}


def expected_lineage(backup_id):
    lineage = []
    seen = set()
    current = backup_id
    while current is not None:
        assert current not in seen, "Cycle in supplied backup graph"
        seen.add(current)
        node = NODES[current]
        lineage.append(node)
        current = node["parent_id"]
    lineage.sort(key=lambda node: datetime.fromisoformat(node["timestamp"].replace("Z", "+00:00")))
    return [node["id"] for node in lineage]


def get_lineage(backup_id, headers=HEADERS):
    try:
        return requests.get(
            f"{BASE_URL}/lineage",
            params={"id": backup_id},
            headers=headers,
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:9090")


def test_missing_auth():
    """Test that requests without the Authorization header return 401."""
    try:
        response = requests.get(f"{BASE_URL}/lineage?id=B-005", timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:9090")

    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"


def test_invalid_auth():
    """Test that requests with an incorrect Authorization header return 401."""
    try:
        response = requests.get(
            f"{BASE_URL}/lineage?id=B-005",
            headers={"Authorization": "Bearer wrong_token"},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:9090")

    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}"


def test_valid_request_lineage():
    """Test that a valid request returns the correct lineage, sorted by timestamp."""
    try:
        response = requests.get(f"{BASE_URL}/lineage?id=B-005", headers=HEADERS, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:9090")

    assert response.status_code == 200, f"Expected HTTP 200 for valid request, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "lineage" in data, "Response JSON is missing 'lineage' key"
    expected = ["B-001", "B-002", "B-003", "B-004", "B-005"]
    assert data["lineage"] == expected, f"Expected lineage {expected}, got {data['lineage']}"


def test_nonexistent_id():
    """Test that requesting a non-existent ID returns 404."""
    try:
        response = requests.get(
            f"{BASE_URL}/lineage?id=NON_EXISTENT", headers=HEADERS, timeout=5
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:9090")

    assert response.status_code == 404, f"Expected HTTP 404 for non-existent ID, got {response.status_code}"


@pytest.mark.parametrize("backup_id", [node["id"] for node in CATALOG])
def test_every_catalog_node_has_derived_lineage(backup_id):
    """Exercise every valid ID, including roots, intermediate nodes, and branches."""
    response = get_lineage(backup_id)
    assert response.status_code == 200, (
        f"Expected HTTP 200 for valid ID {backup_id}, got {response.status_code}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response for {backup_id} is not valid JSON")

    assert isinstance(data, dict), f"Response for {backup_id} must be a JSON object"
    assert set(data.keys()) == {"lineage"}, (
        f"Response for {backup_id} must contain exactly the 'lineage' key"
    )
    assert isinstance(data["lineage"], list), f"Lineage for {backup_id} must be an array"

    expected = expected_lineage(backup_id)
    assert data["lineage"] == expected, (
        f"Expected lineage {expected} for {backup_id}, got {data['lineage']}"
    )

    timestamps = [
        datetime.fromisoformat(NODES[node_id]["timestamp"].replace("Z", "+00:00"))
        for node_id in data["lineage"]
    ]
    assert all(a < b for a, b in zip(timestamps, timestamps[1:])), (
        f"Lineage for {backup_id} is not strictly sorted by timestamp"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
