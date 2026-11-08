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
import py_compile
import random
import secrets
import time
import uuid

import pytest
import redis
import requests

BASE_URL = "http://127.0.0.1:5000"


def wait_for_service(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url)
            return True
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)
    return False


def assert_uuid(value):
    assert isinstance(value, str), "build_id must be a string"
    try:
        uuid.UUID(value)
    except (ValueError, TypeError, AttributeError) as exc:
        pytest.fail(f"build_id is not a valid UUID: {value!r}: {exc}")


def redis_clients_with_key(key):
    matches = []
    for db in range(16):
        client = redis.Redis(host="127.0.0.1", port=6379, db=db)
        if client.exists(key):
            matches.append(client)
    return matches


def assert_plan(flow, nodes, dependencies):
    response = requests.post(f"{BASE_URL}/api/v1/builds", json={"flow": flow})
    assert response.status_code == 200, response.text
    data = response.json()
    assert "build_id" in data, "Response JSON missing 'build_id'"
    build_id = data["build_id"]
    assert_uuid(build_id)

    key = f"build:{build_id}"
    redis_matches = redis_clients_with_key(key)
    assert redis_matches, f"Execution plan was not stored in Redis under {key}"

    get_response = requests.get(f"{BASE_URL}/api/v1/builds/{build_id}")
    assert get_response.status_code == 200, get_response.text
    get_data = get_response.json()
    assert "steps" in get_data, "Response JSON missing 'steps'"
    steps = get_data["steps"]
    assert isinstance(steps, list), "steps must be a list"
    assert len(steps) == len(nodes), f"Expected {len(nodes)} steps, got {steps}"
    assert set(steps) == set(nodes), f"Returned steps do not match the DSL: {steps}"
    assert len(steps) == len(set(steps)), f"Execution plan contains duplicates: {steps}"

    positions = {name: index for index, name in enumerate(steps)}
    for step, requirements in dependencies.items():
        for requirement in requirements:
            assert positions[requirement] < positions[step], (
                f"Dependency {requirement} must precede {step}; got {steps}"
            )

    # Removing the exact Redis key must make the build unavailable. This checks
    # that GET retrieval depends on Redis rather than an in-memory fabricated plan.
    for client in redis_matches:
        client.delete(key)
    missing_response = requests.get(f"{BASE_URL}/api/v1/builds/{build_id}")
    assert missing_response.status_code == 404, (
        "GET still returned a plan after its Redis key was deleted"
    )
    return build_id


@pytest.fixture(scope="module", autouse=True)
def check_service_up():
    assert os.path.isfile("/app/build_service.py"), "/app/build_service.py is missing"
    assert os.path.getsize("/app/build_service.py") > 0, "/app/build_service.py is empty"
    py_compile.compile("/app/build_service.py", doraise=True)
    assert wait_for_service(f"{BASE_URL}/api/v1/builds/nonexistent"), "Flask service is not running on 127.0.0.1:5000"


def test_valid_flow():
    payload = {
        "flow": "STEP app\nREQUIRES lib\nSTEP lib\nREQUIRES base\nSTEP base"
    }
    response = requests.post(f"{BASE_URL}/api/v1/builds", json=payload)
    assert response.status_code == 200, f"Expected 200 OK for valid flow, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "build_id" in data, "Response JSON missing 'build_id'"
    build_id = data["build_id"]
    assert_uuid(build_id)

    redis_matches = redis_clients_with_key(f"build:{build_id}")
    assert redis_matches, f"Execution plan was not stored in Redis under build:{build_id}"

    # Fetch the build plan
    get_response = requests.get(f"{BASE_URL}/api/v1/builds/{build_id}")
    assert get_response.status_code == 200, f"Expected 200 OK when fetching build plan, got {get_response.status_code}"

    get_data = get_response.json()
    assert "steps" in get_data, "Response JSON missing 'steps'"

    # Check topological sort
    expected_steps = ["base", "lib", "app"]
    assert get_data["steps"] == expected_steps, f"Expected steps {expected_steps}, got {get_data['steps']}"


def test_circular_dependency():
    payload = {
        "flow": "STEP ios\nREQUIRES macos\nSTEP macos\nREQUIRES ios"
    }
    response = requests.post(f"{BASE_URL}/api/v1/builds", json=payload)
    assert response.status_code == 400, f"Expected 400 Bad Request for circular dependency, got {response.status_code}"

    data = response.json()
    assert "error" in data, "Response JSON missing 'error' key"
    assert "circular dependency detected" in data["error"].lower(), f"Expected circular dependency error message, got: {data['error']}"


def test_get_nonexistent_build():
    response = requests.get(f"{BASE_URL}/api/v1/builds/invalid-uuid-1234")
    assert response.status_code == 404, f"Expected 404 Not Found for invalid build_id, got {response.status_code}"


def test_randomized_valid_graphs_and_unique_uuids():
    build_ids = []
    for _ in range(3):
        suffix = secrets.token_hex(6)
        nodes = [f"node_{suffix}_{index}" for index in range(7)]
        dependencies = {
            nodes[0]: [],
            nodes[1]: [nodes[0]],
            nodes[2]: [nodes[0]],
            nodes[3]: [nodes[1], nodes[2]],
            nodes[4]: [],
            nodes[5]: [nodes[2], nodes[4]],
            nodes[6]: [nodes[3], nodes[5]],
        }
        definition_order = list(nodes)
        random.SystemRandom().shuffle(definition_order)
        lines = []
        for node in definition_order:
            lines.append(f"STEP {node}")
            for requirement in dependencies[node]:
                lines.append(f"REQUIRES {requirement}")
        build_ids.append(assert_plan("\n".join(lines), nodes, dependencies))

    assert len(set(build_ids)) == len(build_ids), "build_id values must be independently generated"


def test_randomized_cycles():
    for _ in range(3):
        suffix = secrets.token_hex(6)
        nodes = [f"cycle_{suffix}_{index}" for index in range(4)]
        dependencies = {
            nodes[0]: [nodes[1]],
            nodes[1]: [nodes[2]],
            nodes[2]: [nodes[0]],
            nodes[3]: [nodes[0]],
        }
        definition_order = list(nodes)
        random.SystemRandom().shuffle(definition_order)
        lines = []
        for node in definition_order:
            lines.append(f"STEP {node}")
            for requirement in dependencies[node]:
                lines.append(f"REQUIRES {requirement}")

        response = requests.post(
            f"{BASE_URL}/api/v1/builds", json={"flow": "\n".join(lines)}
        )
        assert response.status_code == 400, response.text
        data = response.json()
        assert "error" in data, "Response JSON missing 'error' key"
        assert "circular dependency detected" in data["error"].lower()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
