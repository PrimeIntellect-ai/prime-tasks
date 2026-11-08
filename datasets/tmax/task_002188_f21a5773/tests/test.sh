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
import importlib.util
import math
import os
import secrets
import sys

import pytest
import requests

REPO = "/home/user/geo_api"
CORE_PATH = "/app/vendored/geomath/core.py"
URL = "http://127.0.0.1:8080/process"
HEADERS = {
    "Authorization": "Bearer sec_r3t_9942xyz",
    "Content-Type": "application/json",
}


def precise_random_float(rng):
    while True:
        value = rng.randrange(-900_000_000_000, 900_000_000_001) / 1_000_000_000
        if value != round(value, 2):
            return value


def post_coords(coords):
    try:
        response = requests.post(URL, json={"coords": coords}, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {URL}. Is the server running? Error: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "result" in data, f"Response JSON missing 'result' key. Got: {data}"
    assert isinstance(data["result"], list), (
        f"Expected 'result' to be a list, got {type(data['result'])}"
    )
    return data["result"]


def load_repaired_modules():
    assert os.path.isfile(CORE_PATH), f"Vendored geometry module is missing: {CORE_PATH}"
    processor_path = os.path.join(REPO, "processor.py")
    assert os.path.isfile(processor_path), f"Processor module is missing: {processor_path}"

    core_spec = importlib.util.spec_from_file_location("core", CORE_PATH)
    assert core_spec is not None and core_spec.loader is not None
    core = importlib.util.module_from_spec(core_spec)
    core_spec.loader.exec_module(core)
    assert callable(getattr(core, "compute_series", None)), "compute_series is not callable"

    sys.modules["core"] = core
    processor_spec = importlib.util.spec_from_file_location("verified_processor", processor_path)
    assert processor_spec is not None and processor_spec.loader is not None
    processor = importlib.util.module_from_spec(processor_spec)
    processor_spec.loader.exec_module(processor)
    assert callable(getattr(processor, "process_data", None)), "process_data is not callable"
    return core, processor


def test_token_file_recovered():
    token_path = "/home/user/geo_api/token.key"
    assert os.path.exists(token_path), f"Token file {token_path} is missing. Did you recover it from git history?"
    with open(token_path, "r") as f:
        content = f.read().strip()
    assert content == "sec_r3t_9942xyz", f"Token file content is incorrect. Expected 'sec_r3t_9942xyz', got '{content}'"


def test_repaired_core_and_processor_directly():
    core, processor = load_repaired_modules()
    rng = secrets.SystemRandom()

    inputs = {1, 2, 5, rng.randrange(3, 9), rng.randrange(3, 9)}
    for n in inputs:
        assert core.compute_series(n) == math.factorial(n), (
            f"compute_series({n}) did not produce {math.factorial(n)}"
        )

    for _ in range(4):
        coords = [precise_random_float(rng) for _ in range(rng.randrange(1, 7))]
        result = processor.process_data(coords)
        assert isinstance(result, list)
        assert result == coords + [math.factorial(5)], (
            f"processor.py did not preserve coordinate precision: input={coords}, result={result}"
        )


def test_api_process_endpoint():
    payload_coords = [45.123456789, -122.987654321]
    result = post_coords(payload_coords)

    assert len(result) == 3, f"Expected 3 items in result array, got {len(result)}: {result}"
    assert result[0] == 45.123456789, f"First coordinate lost precision or is incorrect. Expected 45.123456789, got {result[0]}"
    assert result[1] == -122.987654321, f"Second coordinate lost precision or is incorrect. Expected -122.987654321, got {result[1]}"
    assert result[2] == 120, f"Math computation result is incorrect. Expected 120 (from compute_series(5)), got {result[2]}"


def test_api_process_endpoint_with_unpredictable_inputs():
    rng = secrets.SystemRandom()
    for _ in range(5):
        coords = [precise_random_float(rng) for _ in range(rng.randrange(1, 7))]
        result = post_coords(coords)
        expected = coords + [math.factorial(5)]
        assert len(result) == len(expected), (
            f"Expected {len(expected)} result items, got {len(result)}: {result}"
        )
        assert result == expected, (
            f"API did not preserve dynamically generated coordinates: input={coords}, result={result}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
