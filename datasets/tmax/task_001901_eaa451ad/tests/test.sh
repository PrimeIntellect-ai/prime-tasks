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
import math
import os
import secrets
import time
import uuid

import pytest
import requests

SERVICE_URL = "http://127.0.0.1:9090"
AUTH_TOKEN = "Baye$ian2023"
HEADERS = {"Authorization": f"Bearer {AUTH_TOKEN}"}


def wait_for_service(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(f"{url}/aggregate", headers=HEADERS, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def expected_posterior(payload):
    prior_var = payload["prior_sigma"] ** 2
    likelihood_var = payload["likelihood_sigma"] ** 2
    posterior_var = 1.0 / (1.0 / prior_var + 1.0 / likelihood_var)
    posterior_mu = (
        payload["prior_mu"] / prior_var
        + payload["likelihood_mu"] / likelihood_var
    ) * posterior_var
    return posterior_mu, math.sqrt(posterior_var)


def assert_posterior(response_data, payload):
    assert "posterior_mu" in response_data, "Response missing 'posterior_mu'"
    assert "posterior_sigma" in response_data, "Response missing 'posterior_sigma'"
    assert isinstance(response_data["posterior_mu"], (int, float))
    assert isinstance(response_data["posterior_sigma"], (int, float))

    expected_mu, expected_sigma = expected_posterior(payload)
    assert math.isclose(response_data["posterior_mu"], expected_mu, rel_tol=1e-10, abs_tol=1e-10), (
        f"Incorrect posterior_mu: expected {expected_mu}, got {response_data['posterior_mu']}"
    )
    assert math.isclose(response_data["posterior_sigma"], expected_sigma, rel_tol=1e-10, abs_tol=1e-10), (
        f"Incorrect posterior_sigma: expected {expected_sigma}, got {response_data['posterior_sigma']}"
    )


def test_service_log_exists():
    """Verify that the service log file was created."""
    log_path = "/home/user/service.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you redirect stdout/stderr?"


def test_service_running_and_authenticated():
    """Verify the service is running at the correct host/port and accepts the auth token."""
    assert wait_for_service(SERVICE_URL), f"Service is not reachable at {SERVICE_URL} within the timeout."

    resp = requests.get(f"{SERVICE_URL}/aggregate", timeout=2)
    assert resp.status_code in (401, 403), f"Expected 401/403 for unauthorized request, got {resp.status_code}"


def test_record_and_aggregate():
    """Preserve the original fixed request while checking its actual Bayesian result."""
    assert wait_for_service(SERVICE_URL), f"Service is not reachable at {SERVICE_URL}"

    payload = {
        "experiment_id": "test_exp_001",
        "prior_mu": 0.0,
        "prior_sigma": 1.0,
        "likelihood_mu": 1.0,
        "likelihood_sigma": 1.0,
    }

    post_resp = requests.post(f"{SERVICE_URL}/record", json=payload, headers=HEADERS, timeout=2)
    assert post_resp.status_code == 200, f"POST /record failed with status {post_resp.status_code}. Response: {post_resp.text}"
    assert_posterior(post_resp.json(), payload)

    get_resp = requests.get(f"{SERVICE_URL}/aggregate", headers=HEADERS, timeout=2)
    assert get_resp.status_code == 200, f"GET /aggregate failed with status {get_resp.status_code}. Response: {get_resp.text}"

    agg_data = get_resp.json()
    assert isinstance(agg_data, list), f"Expected /aggregate to return a JSON array, got {type(agg_data)}"
    found = any(exp.get("experiment_id") == "test_exp_001" for exp in agg_data)
    assert found, "The recorded experiment 'test_exp_001' was not found in the /aggregate response."


def test_dynamic_bayesian_updates_schema_and_aggregation():
    """Exercise derived Bayesian values, schema rejection, and exact stored records."""
    rng = secrets.SystemRandom()
    run_id = uuid.uuid4().hex
    payloads = []

    for index in range(4):
        payload = {
            "experiment_id": f"verify_{run_id}_{index}",
            "prior_mu": rng.uniform(-20.0, 20.0),
            "prior_sigma": rng.uniform(0.25, 6.0),
            "likelihood_mu": rng.uniform(-20.0, 20.0),
            "likelihood_sigma": rng.uniform(0.25, 6.0),
        }
        payloads.append(payload)
        response = requests.post(f"{SERVICE_URL}/record", json=payload, headers=HEADERS, timeout=2)
        assert response.status_code == 200, response.text
        assert_posterior(response.json(), payload)

    invalid_ids = [f"invalid_{run_id}_{i}" for i in range(3)]
    invalid_requests = [
        {
            "experiment_id": invalid_ids[0],
            "prior_mu": 1.0,
            "prior_sigma": 2.0,
            "likelihood_mu": 3.0,
        },
        {
            "experiment_id": invalid_ids[1],
            "prior_mu": "not-a-number",
            "prior_sigma": 2.0,
            "likelihood_mu": 3.0,
            "likelihood_sigma": 4.0,
        },
    ]
    for invalid_payload in invalid_requests:
        response = requests.post(f"{SERVICE_URL}/record", json=invalid_payload, headers=HEADERS, timeout=2)
        assert response.status_code == 400, (
            f"Invalid schema was not rejected: status={response.status_code}, body={response.text}"
        )

    malformed = requests.post(
        f"{SERVICE_URL}/record",
        data='{"experiment_id":"' + invalid_ids[2] + '","prior_mu":',
        headers={**HEADERS, "Content-Type": "application/json"},
        timeout=2,
    )
    assert malformed.status_code == 400, f"Malformed JSON was not rejected: {malformed.status_code}"

    aggregate_response = requests.get(f"{SERVICE_URL}/aggregate", headers=HEADERS, timeout=2)
    assert aggregate_response.status_code == 200
    aggregate = aggregate_response.json()
    assert isinstance(aggregate, list)

    for payload in payloads:
        matches = [row for row in aggregate if isinstance(row, dict) and row.get("experiment_id") == payload["experiment_id"]]
        assert len(matches) == 1, f"Expected exactly one aggregated row for {payload['experiment_id']}"
        row = matches[0]
        assert set(row) == set(payload), f"Aggregated row has the wrong schema: {row}"
        for field in ("prior_mu", "prior_sigma", "likelihood_mu", "likelihood_sigma"):
            assert math.isclose(row[field], payload[field], rel_tol=1e-12, abs_tol=1e-12), (
                f"Aggregated field {field} was altered"
            )

    aggregated_ids = {
        row.get("experiment_id") for row in aggregate if isinstance(row, dict)
    }
    assert not (set(invalid_ids) & aggregated_ids), "Schema-invalid records were incorrectly aggregated"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
