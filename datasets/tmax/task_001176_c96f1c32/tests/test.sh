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
import os
import random
import re
import string

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
INVENTORY_PATH = "/home/user/server_inventory.bin"
EXPECTED_TRANSCRIPT = "The anomaly was detected on server cluster delta prime."


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def load_inventory():
    with open(INVENTORY_PATH, "r", encoding="utf-16le") as f:
        return [line.strip() for line in f if line.strip()]


def post_match(query):
    try:
        response = requests.post(
            f"{BASE_URL}/api/match", json={"query": query}, timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /api/match: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /api/match is not valid JSON")

    assert "closest_match" in data, "Response JSON missing 'closest_match' key"
    assert "distance" in data, "Response JSON missing 'distance' key"
    return data


def test_api_transcript():
    try:
        response = requests.get(f"{BASE_URL}/api/transcript", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /api/transcript: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /api/transcript is not valid JSON")

    assert "transcript" in data, "Response JSON missing 'transcript' key"

    transcript = data["transcript"].lower()
    transcript_clean = re.sub(r'[^\w\s]', '', transcript)
    assert "cluster delta prime" in transcript_clean, f"Expected 'cluster delta prime' in transcript, got: {transcript}"

    assert data["transcript"] == EXPECTED_TRANSCRIPT, (
        f"Expected exact transcript {EXPECTED_TRANSCRIPT!r}, got {data['transcript']!r}"
    )


def test_api_match_cluster_delta_prime():
    data = post_match("cluster delta prime")
    assert data["closest_match"] == "cluster-delta-prime", f"Expected closest_match 'cluster-delta-prime', got {data['closest_match']}"
    assert data["distance"] == 2, f"Expected distance 2, got {data['distance']}"


def test_api_match_alpha_node_1():
    data = post_match("alpha node 1")
    assert data["closest_match"] == "alpha-node-01", f"Expected closest_match 'alpha-node-01', got {data['closest_match']}"
    assert data["distance"] == 3, f"Expected distance 3, got {data['distance']}"


def test_general_levenshtein_matching_against_inventory():
    inventory = load_inventory()
    assert inventory, "Inventory is empty"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = string.ascii_lowercase + string.digits + " -_."
    queries = []

    # Exercise every inventory entry with unpredictable edits.
    for hostname in inventory:
        for _ in range(3):
            chars = list(hostname)
            operation = rng.choice(("insert", "delete", "replace"))
            if operation == "insert":
                chars.insert(rng.randrange(len(chars) + 1), rng.choice(alphabet))
            elif operation == "delete" and chars:
                del chars[rng.randrange(len(chars))]
            elif chars:
                pos = rng.randrange(len(chars))
                choices = alphabet.replace(chars[pos], "")
                chars[pos] = rng.choice(choices)
            queries.append("".join(chars))

    # Also use unrelated, verifier-generated strings to prevent a fixed lookup table.
    for _ in range(20):
        queries.append("".join(rng.choice(alphabet) for _ in range(rng.randint(1, 32))))

    for query in queries:
        distances = [levenshtein(query, hostname) for hostname in inventory]
        expected_distance = min(distances)
        expected_match = inventory[distances.index(expected_distance)]
        data = post_match(query)

        assert data["closest_match"] == expected_match, (
            f"For query {query!r}, expected {expected_match!r}, "
            f"got {data['closest_match']!r}"
        )
        assert type(data["distance"]) is int, "distance must be a JSON integer"
        assert data["distance"] == expected_distance, (
            f"For query {query!r}, expected distance {expected_distance}, "
            f"got {data['distance']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
