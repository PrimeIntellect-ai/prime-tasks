#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"

# Verification-only copy of the legacy records. Expected results are derived
# algorithmically below rather than stored as endpoint response fixtures.
ENTITIES = [
    {"entity_id": "E1", "name": "Alice"},
    {"entity_id": "E2", "name": "Bob"},
    {"entity_id": "E3", "name": "Charlie"},
    {"entity_id": "E4", "name": "Diana"},
]
ACCOUNTS = [
    {"account_id": "A1", "owner_id": "E1"},
    {"account_id": "A2", "owner_id": "E1"},
    {"account_id": "A3", "owner_id": "E2"},
    {"account_id": "A4", "owner_id": "E3"},
    {"account_id": "A5", "owner_id": "E4"},
]
TRANSACTIONS = [
    {"tx_id": "T1", "from_acc": "A1", "to_acc": "A3", "amount": 100},
    {"tx_id": "T2", "from_acc": "A3", "to_acc": "A4", "amount": 50},
    {"tx_id": "T3", "from_acc": "A2", "to_acc": "A5", "amount": 200},
    {"tx_id": "T4", "from_acc": "A5", "to_acc": "A1", "amount": 25},
    {"tx_id": "T5", "from_acc": "A3", "to_acc": "A1", "amount": 10},
]

ENTITY_IDS = [row["entity_id"] for row in ENTITIES]
NODE_IDS = set(ENTITY_IDS) | {row["account_id"] for row in ACCOUNTS}
ADJ = {node: set() for node in NODE_IDS}
OWNED = collections.defaultdict(set)

for row in ACCOUNTS:
    entity = row["owner_id"]
    account = row["account_id"]
    OWNED[entity].add(account)
    ADJ[entity].add(account)
    ADJ[account].add(entity)

for row in TRANSACTIONS:
    left = row["from_acc"]
    right = row["to_acc"]
    ADJ[left].add(right)
    ADJ[right].add(left)


def wait_for_service():
    last_error = None
    for _ in range(20):
        try:
            requests.get(f"{BASE_URL}/", timeout=1)
            return
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.5)
    pytest.fail(f"Student API did not become available: {last_error}")


@pytest.fixture(autouse=True, scope="session")
def setup():
    wait_for_service()


def shortest_distance(src, dst):
    queue = collections.deque([(src, 0)])
    seen = {src}
    while queue:
        node, distance = queue.popleft()
        if node == dst:
            return distance
        for neighbor in ADJ[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def expected_exposure(entity_id):
    volumes = collections.defaultdict(float)
    owned = OWNED[entity_id]
    for tx in TRANSACTIONS:
        src = tx["from_acc"]
        dst = tx["to_acc"]
        amount = tx["amount"]
        if src in owned:
            volumes[dst] += amount
        if dst in owned:
            volumes[src] += amount
    return sorted(volumes, key=lambda account: (-volumes[account], account))


def get_json(endpoint, params):
    response = requests.get(f"{BASE_URL}{endpoint}", params=params, timeout=5)
    assert response.status_code == 200, (
        f"Expected 200 OK for {endpoint} with {params}, got "
        f"{response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response was not JSON for {endpoint} with {params}: {response.text}")


# Preserve the original verifier's exact-result assertions.
def test_shortest_path_e2_e3():
    response = requests.get(f"{BASE_URL}/shortest_path", params={"src_entity": "E2", "dst_entity": "E3"}, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "path" in data, f"Missing 'path' key in response: {data}"
    expected_path = ["E2", "A3", "A4", "E3"]
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"


def test_shortest_path_e2_e4():
    response = requests.get(f"{BASE_URL}/shortest_path", params={"src_entity": "E2", "dst_entity": "E4"}, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "path" in data, f"Missing 'path' key in response: {data}"
    expected_path = ["E2", "A3", "A1", "A5", "E4"]
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"


def test_exposure_e1_full():
    response = requests.get(f"{BASE_URL}/exposure", params={"entity_id": "E1", "limit": 10, "offset": 0}, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "accounts" in data, f"Missing 'accounts' key in response: {data}"
    expected_accounts = ["A5", "A3"]
    assert data["accounts"] == expected_accounts, f"Expected accounts {expected_accounts}, got {data['accounts']}"


def test_exposure_e1_pagination():
    response = requests.get(f"{BASE_URL}/exposure", params={"entity_id": "E1", "limit": 1, "offset": 1}, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "accounts" in data, f"Missing 'accounts' key in response: {data}"
    expected_accounts = ["A3"]
    assert data["accounts"] == expected_accounts, f"Expected accounts {expected_accounts}, got {data['accounts']}"


@pytest.mark.parametrize("src", ENTITY_IDS)
@pytest.mark.parametrize("dst", ENTITY_IDS)
def test_all_entity_shortest_paths(src, dst):
    data = get_json("/shortest_path", {"src_entity": src, "dst_entity": dst})
    assert set(data) == {"path"}, f"Unexpected shortest_path response schema: {data}"
    path = data["path"]
    assert isinstance(path, list), f"path must be a list, got: {path!r}"

    distance = shortest_distance(src, dst)
    if distance is None:
        assert path == [], f"Expected no path from {src} to {dst}, got {path}"
        return

    assert path, f"Expected a path from {src} to {dst}"
    assert path[0] == src and path[-1] == dst, f"Wrong path endpoints: {path}"
    assert len(path) - 1 == distance, f"Path is not shortest from {src} to {dst}: {path}"
    assert all(node in NODE_IDS for node in path), f"Path contains an unknown node: {path}"
    assert all(right in ADJ[left] for left, right in zip(path, path[1:])), (
        f"Path uses a nonexistent edge: {path}"
    )


@pytest.mark.parametrize("entity_id", ENTITY_IDS)
def test_all_exposures_and_pagination(entity_id):
    complete = expected_exposure(entity_id)
    cases = {(10, 0), (1, 0), (1, 1), (2, 0), (2, 1)}
    for offset in range(len(complete) + 3):
        for limit in (1, 2, 10):
            cases.add((limit, offset))

    for limit, offset in sorted(cases):
        data = get_json(
            "/exposure",
            {"entity_id": entity_id, "limit": limit, "offset": offset},
        )
        assert set(data) == {"accounts"}, f"Unexpected exposure response schema: {data}"
        expected = complete[offset:offset + limit]
        assert data["accounts"] == expected, (
            f"Wrong exposure for entity={entity_id}, limit={limit}, offset={offset}: "
            f"expected {expected}, got {data['accounts']}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
