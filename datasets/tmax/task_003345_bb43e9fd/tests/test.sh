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
import json
import random
import secrets
import string

import pytest
import requests

URL = "http://127.0.0.1:8080/deploy"
TOKEN = "DEPLOY_SECRET_99X"
AUTHORIZED_HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def assert_sorted_json(response):
    try:
        parsed_pairs = json.loads(response.text, object_pairs_hook=list)
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    keys = [pair[0] for pair in parsed_pairs]
    assert keys == sorted(keys), f"Expected JSON keys to be sorted alphabetically. Got keys: {keys}"


def interpret(script):
    config = {"version": "1.0", "environment": "production", "debug": False}
    for line in script.splitlines():
        if not line:
            continue
        if line.startswith("SET "):
            _, key, value = line.split(" ", 2)
            config[key] = value
        elif line.startswith("NUM "):
            _, key, value = line.split(" ", 2)
            config[key] = int(value)
        elif line.startswith("MERGE "):
            config.update(json.loads(line[len("MERGE "):]))
        elif line.startswith("DELETE "):
            config.pop(line[len("DELETE "):], None)
    return dict(sorted(config.items()))


def post_authorized(payload):
    try:
        return requests.post(URL, headers=AUTHORIZED_HEADERS, data=payload, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:8080")


def test_unauthorized_missing_header():
    """Test that a request without the Authorization header returns 401."""
    try:
        response = requests.post(URL, data="SET test val", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:8080")

    assert response.status_code == 401, f"Expected status code 401 for missing header, got {response.status_code}"


def test_unauthorized_wrong_header():
    """Test that a request with an incorrect Authorization header returns 401."""
    headers = {"Authorization": "Bearer WRONG_TOKEN"}
    try:
        response = requests.post(URL, headers=headers, data="SET test val", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:8080")

    assert response.status_code == 401, f"Expected status code 401 for wrong header, got {response.status_code}"


def test_authorized_valid_payload():
    """Retain the original fixed integration case."""
    payload = """SET region us-east-1
NUM workers 5
MERGE {"features": {"beta": true}, "timeout": 30}
DELETE debug"""

    response = post_authorized(payload)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    expected_data = {
        "environment": "production",
        "features": {"beta": True},
        "region": "us-east-1",
        "timeout": 30,
        "version": "1.0",
        "workers": 5,
    }
    assert data == expected_data, f"Expected JSON response {expected_data}, got {data}"
    assert_sorted_json(response)


def random_word(rng, prefix):
    return prefix + "_" + "".join(rng.choice(string.ascii_lowercase) for _ in range(10))


def make_random_script(rng):
    set_key = random_word(rng, "set")
    num_key = random_word(rng, "num")
    merge_key = random_word(rng, "merge")
    victim_key = random_word(rng, "victim")

    # Every generated case necessarily exercises all four commands, including
    # overwrites, deletion of present and absent keys, and ignored empty lines.
    lines = [
        f"SET {set_key} {random_word(rng, 'value')}",
        f"NUM {num_key} {rng.randint(-100000, 100000)}",
        f"SET {victim_key} temporary",
        "MERGE " + json.dumps({
            merge_key: {
                "enabled": rng.choice([True, False]),
                "items": [rng.randint(0, 20), random_word(rng, "item")],
            },
            set_key: random_word(rng, "overwritten"),
            "version": random_word(rng, "release"),
        }, separators=(",", ":")),
        f"DELETE {victim_key}",
        "DELETE debug",
        f"DELETE {random_word(rng, 'absent')}",
        f"NUM {num_key} {rng.randint(-100000, 100000)}",
    ]

    for _ in range(8):
        operation = rng.choice(["SET", "NUM", "MERGE", "DELETE"])
        if operation == "SET":
            lines.append(f"SET {random_word(rng, 'key')} {random_word(rng, 'text')}")
        elif operation == "NUM":
            lines.append(f"NUM {random_word(rng, 'number')} {rng.randint(-1000000, 1000000)}")
        elif operation == "MERGE":
            key = rng.choice([set_key, num_key, random_word(rng, "merged")])
            value = rng.choice([
                rng.randint(-5000, 5000),
                random_word(rng, "jsontext"),
                None,
                [rng.randint(0, 9), rng.choice([True, False])],
                {"nested": random_word(rng, "value")},
            ])
            lines.append("MERGE " + json.dumps({key: value}, separators=(",", ":")))
        else:
            key = rng.choice([set_key, num_key, merge_key, random_word(rng, "missing")])
            lines.append(f"DELETE {key}")

    # Insert empty lines without changing command semantics.
    for _ in range(3):
        lines.insert(rng.randrange(len(lines) + 1), "")
    return "\n".join(lines)


def test_randomized_dsl_interpretation():
    # The seed is created only after the submitted service is running, preventing
    # a service from passing by returning responses for a fixed payload corpus.
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))

    for _ in range(10):
        payload = make_random_script(rng)
        expected = interpret(payload)
        response = post_authorized(payload)

        assert response.status_code == 200, (
            f"Expected status code 200, got {response.status_code}. "
            f"Payload: {payload!r}. Response: {response.text}"
        )
        try:
            actual = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

        assert actual == expected, (
            f"Incorrect DSL result for payload {payload!r}. "
            f"Expected {expected}, got {actual}"
        )
        assert_sorted_json(response)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
