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
import pathlib
import random
import secrets

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
AUTH_HEADER = {"Authorization": "Bearer MLOPS_SECRET_2024"}
PROJECT = pathlib.Path("/home/user/mlops_tracker")


def assert_probability(value, expected):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), "Probability must be numeric"
    assert math.isfinite(float(value)), "Probability must be finite"
    assert math.isclose(float(value), expected, rel_tol=1e-7, abs_tol=1e-9), \
        f"Expected probability {expected}, got {value}"


def listener_executable():
    """Return the executable owning the IPv4 listener on 127.0.0.1:9090."""
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1] == "0100007F:2382" and fields[3] == "0A":
                inodes.add(fields[9])

    assert inodes, "No process is listening on 127.0.0.1:9090"
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return pathlib.Path(os.readlink(proc / "exe"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    pytest.fail("Could not identify the process owning 127.0.0.1:9090")


def test_rust_service_artifact_is_running():
    assert PROJECT.is_dir(), "Missing /home/user/mlops_tracker project"
    assert (PROJECT / "Cargo.toml").is_file(), "Missing Cargo.toml"
    assert (PROJECT / "src" / "main.rs").is_file(), "Missing src/main.rs"
    assert (PROJECT / "Cargo.toml").stat().st_size > 0
    assert (PROJECT / "src" / "main.rs").stat().st_size > 0

    exe = listener_executable()
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Listener is not a compiled ELF executable: {exe}"


def test_posterior_auth_missing():
    try:
        response = requests.get(f"{BASE_URL}/posterior", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {BASE_URL}: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"


def test_posterior_auth_invalid():
    response = requests.get(
        f"{BASE_URL}/posterior",
        headers={"Authorization": "Bearer WRONG"},
        timeout=2,
    )
    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}"


def test_ingest_schema_enforcement():
    response = requests.post(f"{BASE_URL}/ingest", json={"artifact_id": "123"}, timeout=2)
    assert response.status_code == 400, f"Expected HTTP 400 for missing transcript, got {response.status_code}"

    response = requests.post(f"{BASE_URL}/ingest", json={"transcript": "test"}, timeout=2)
    assert response.status_code == 400, f"Expected HTTP 400 for missing artifact_id, got {response.status_code}"

    response = requests.post(
        f"{BASE_URL}/ingest",
        json={"transcript": "", "artifact_id": "123"},
        timeout=2,
    )
    assert response.status_code == 400, f"Expected HTTP 400 for empty transcript, got {response.status_code}"

    response = requests.post(
        f"{BASE_URL}/ingest",
        json={"transcript": "test", "artifact_id": ""},
        timeout=2,
    )
    assert response.status_code == 400, f"Expected HTTP 400 for empty artifact_id, got {response.status_code}"


def test_initial_ingestion_and_general_bayesian_logic():
    # Beta(1,1), followed by the required single ingestion of artifact 091 whose
    # transcript contains the exact word "success", must produce Beta(2,1).
    initial = requests.get(f"{BASE_URL}/posterior", headers=AUTH_HEADER, timeout=2)
    assert initial.status_code == 200, f"Expected HTTP 200 for valid auth, got {initial.status_code}"
    initial_json = initial.json()
    assert "expected_success_probability" in initial_json, "Response missing expected_success_probability"
    assert_probability(initial_json["expected_success_probability"], 2.0 / 3.0)

    alpha = 2.0
    beta = 1.0

    # Retain the original fixed failure and success checks.
    payload_fail = {"transcript": "Failure mode detected", "artifact_id": "092"}
    resp_fail = requests.post(f"{BASE_URL}/ingest", json=payload_fail, timeout=2)
    assert resp_fail.status_code == 200, f"Expected HTTP 200 for valid ingest, got {resp_fail.status_code}"
    data_fail = resp_fail.json()
    assert "alpha" in data_fail and "beta" in data_fail, "Response missing alpha or beta"
    assert data_fail.get("status") == "ingested", "Response must contain status='ingested'"
    alpha1 = data_fail["alpha"]
    beta1 = data_fail["beta"]
    beta += 1.0
    assert alpha1 == alpha and beta1 == beta, f"Expected state ({alpha}, {beta}), got ({alpha1}, {beta1})"

    payload_success = {"transcript": "This was a huge SuCcEsS!", "artifact_id": "093"}
    resp_success = requests.post(f"{BASE_URL}/ingest", json=payload_success, timeout=2)
    assert resp_success.status_code == 200, f"Expected HTTP 200 for valid ingest, got {resp_success.status_code}"
    data_success = resp_success.json()
    assert data_success.get("status") == "ingested", "Response must contain status='ingested'"
    alpha2 = data_success["alpha"]
    beta2 = data_success["beta"]
    assert alpha2 == alpha1 + 1, f"Expected alpha to increment by 1, got {alpha2} vs {alpha1}"
    assert beta2 == beta1, f"Expected beta to remain unchanged, got {beta2} vs {beta1}"
    alpha += 1.0

    resp_post = requests.get(f"{BASE_URL}/posterior", headers=AUTH_HEADER, timeout=2)
    assert resp_post.status_code == 200, f"Expected HTTP 200 for valid auth, got {resp_post.status_code}"
    data_post = resp_post.json()
    assert "expected_success_probability" in data_post, "Response missing expected_success_probability"
    expected_prob = alpha2 / (alpha2 + beta2)
    assert_probability(data_post["expected_success_probability"], expected_prob)

    # Exercise unpredictable transcripts and artifact IDs. Near-matches must not
    # count as the exact word, while punctuation and arbitrary casing must count.
    nonce = secrets.token_hex(12)
    success_cases = []
    for index in range(5):
        spelling = "".join(
            ch.upper() if secrets.randbelow(2) else ch.lower() for ch in "success"
        )
        repeats = 1 + secrets.randbelow(4)
        success_cases.append((f"{nonce} " + (f"({spelling}), " * repeats) + f"trial{index}", True))

    failure_cases = [
        (f"{nonce} unsuccessful run", False),
        (f"{nonce} successes were discussed", False),
        (f"{nonce} successful result", False),
        (f"{nonce} preSUCCESSpost token", False),
        (f"{nonce} ordinary stable pipeline", False),
    ]
    cases = success_cases + failure_cases
    random.SystemRandom().shuffle(cases)

    for index, (transcript, is_success) in enumerate(cases):
        artifact_id = f"dynamic-{nonce}-{index}-{secrets.token_hex(4)}"
        response = requests.post(
            f"{BASE_URL}/ingest",
            json={"transcript": transcript, "artifact_id": artifact_id},
            timeout=2,
        )
        assert response.status_code == 200, f"Valid randomized ingest returned {response.status_code}"
        body = response.json()
        assert body.get("status") == "ingested", "Response must contain status='ingested'"
        assert "alpha" in body and "beta" in body, "Response missing alpha or beta"

        if is_success:
            alpha += 1.0
        else:
            beta += 1.0
        assert body["alpha"] == alpha, f"Expected alpha {alpha}, got {body['alpha']}"
        assert body["beta"] == beta, f"Expected beta {beta}, got {body['beta']}"

    final = requests.get(f"{BASE_URL}/posterior", headers=AUTH_HEADER, timeout=2)
    assert final.status_code == 200
    final_json = final.json()
    assert "expected_success_probability" in final_json
    assert_probability(final_json["expected_success_probability"], alpha / (alpha + beta))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
