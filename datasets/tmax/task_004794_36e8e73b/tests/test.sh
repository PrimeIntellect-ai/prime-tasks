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
import math
import os
import subprocess

import h5py
import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:9000/metric"
AUTH = {"Authorization": "Bearer secret-ml-token-99"}


def post(payload, headers=AUTH, timeout=5):
    try:
        return requests.post(URL, json=payload, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server: {exc}")


def oracle_distribution(matrix):
    oracle_input = " ".join(format(float(x), ".17g") for x in matrix.reshape(-1)) + "\n"
    try:
        result = subprocess.run(
            ["/app/oracle_dist"],
            input=oracle_input,
            text=True,
            capture_output=True,
            timeout=5,
            check=False,
        )
    except Exception as exc:
        pytest.fail(f"Failed to execute /app/oracle_dist: {exc}")

    assert result.returncode == 0, f"Oracle failed: {result.stderr}"
    try:
        values = [float(x) for x in result.stdout.split()]
    except ValueError as exc:
        pytest.fail(f"Oracle returned non-numeric output: {exc}")
    assert len(values) == 10, f"Oracle returned {len(values)} values instead of 10"
    assert all(math.isfinite(x) and x >= 0 for x in values)
    return np.asarray(values, dtype=np.float64)


def expected_distances(p, q):
    strict = sum(float(pi) * math.log(float(pi) / float(qi)) for pi, qi in zip(p, q) if pi > 0)
    smoothed = sum(
        float(pi) * math.log((float(pi) + 1e-9) / (float(qi) + 1e-9))
        for pi, qi in zip(p, q)
    )
    return strict, smoothed


def assert_distance_response(response, expected, context, rel_tol=1e-4, abs_tol=2e-5):
    assert response.status_code == 200, (
        f"Expected HTTP 200 for {context}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        body = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f"Server did not return valid JSON for {context}: {response.text}")
    assert isinstance(body, dict) and "distance" in body, (
        f"Response JSON missing distance for {context}: {body}"
    )
    distance = body["distance"]
    assert isinstance(distance, (int, float)) and not isinstance(distance, bool), (
        f"Distance must be a number for {context}"
    )
    assert math.isfinite(distance), f"Distance must be finite for {context}"
    strict, smoothed = expected
    assert (
        math.isclose(distance, strict, rel_tol=rel_tol, abs_tol=abs_tol)
        or math.isclose(distance, smoothed, rel_tol=rel_tol, abs_tol=abs_tol)
    ), f"Distance {distance} for {context} does not match {strict} or {smoothed}"


def listening_socket_inodes():
    exact = set()
    wildcard = set()
    try:
        with open("/proc/net/tcp", "r", encoding="ascii") as handle:
            rows = handle.readlines()[1:]
    except OSError as exc:
        pytest.fail(f"Cannot inspect listening sockets: {exc}")

    for row in rows:
        fields = row.split()
        local, state, inode = fields[1], fields[3], fields[9]
        address, port = local.split(":")
        if port.upper() == "2328" and state == "0A":
            if address.upper() == "0100007F":
                exact.add(inode)
            elif address.upper() == "00000000":
                wildcard.add(inode)
    return exact, wildcard


def owners_of_socket(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(int(entry))
    return owners


def test_server_ready_file():
    assert os.path.exists("/tmp/server_ready"), "The file /tmp/server_ready was not created."


def test_native_server_bound_exactly_to_loopback():
    exact, wildcard = listening_socket_inodes()
    assert exact, "No server is listening on 127.0.0.1:9000"
    assert not wildcard, "The service must not listen on 0.0.0.0:9000"
    owners = owners_of_socket(exact)
    assert owners, "Could not identify the process owning 127.0.0.1:9000"
    native = False
    for pid in owners:
        try:
            with open(f"/proc/{pid}/exe", "rb") as executable:
                if executable.read(4) == b"\x7fELF":
                    native = True
                    break
        except OSError:
            pass
    assert native, "The listening service is not a native compiled executable"


def test_auth_required():
    payload = {"index": 0, "candidate": [0.1] * 10}
    response = post(payload, headers={})
    assert response.status_code == 401, (
        f"Expected HTTP 401 for missing auth, got {response.status_code}"
    )
    response = post(payload, headers={"Authorization": "Bearer wrong-token"})
    assert response.status_code == 401, (
        f"Expected HTTP 401 for bad auth, got {response.status_code}"
    )


def test_original_index_zero_uniform_case():
    with h5py.File("/app/raw_data.h5", "r") as handle:
        matrix_0 = handle["covariances"][0]

    diag = np.diag(matrix_0)
    exp_diag = np.exp(diag - np.max(diag))
    p = exp_diag / np.sum(exp_diag)
    q = np.asarray([0.1] * 10, dtype=np.float64)
    response = post({"index": 0, "candidate": q.tolist()})
    assert_distance_response(
        response,
        expected_distances(p, q),
        "original index 0 uniform candidate",
        rel_tol=1e-3,
        abs_tol=1e-4,
    )


def test_all_matrices_and_varied_candidates_against_oracle():
    with h5py.File("/app/raw_data.h5", "r") as handle:
        assert list(handle.keys()) == ["covariances"]
        matrices = handle["covariances"][:]
    assert matrices.shape == (50, 10, 10)

    for index, matrix in enumerate(matrices):
        p = oracle_distribution(matrix)
        weights = np.asarray(
            [1.0 + ((index + 3) * (j + 5) % 17) + 0.07 * (j + 1) for j in range(10)],
            dtype=np.float64,
        )
        q = weights / np.sum(weights)
        response = post({"index": index, "candidate": q.tolist()})
        assert_distance_response(
            response,
            expected_distances(p, q),
            f"matrix index {index}",
        )


def test_bad_inputs_return_400():
    invalid_payloads = [
        {"index": -1, "candidate": [0.1] * 10},
        {"index": 50, "candidate": [0.1] * 10},
        {"index": 1.5, "candidate": [0.1] * 10},
        {"index": 0, "candidate": [0.1] * 9},
        {"index": 0, "candidate": "not-an-array"},
        {"index": 0},
        {"candidate": [0.1] * 10},
    ]
    for payload in invalid_payloads:
        response = post(payload)
        assert response.status_code == 400, (
            f"Expected HTTP 400 for bad input {payload}, got {response.status_code}: "
            f"{response.text}"
        )

    try:
        response = requests.post(
            URL,
            data="{not valid json",
            headers={**AUTH, "Content-Type": "application/json"},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect for malformed JSON test: {exc}")
    assert response.status_code == 400, (
        f"Expected HTTP 400 for malformed JSON, got {response.status_code}: {response.text}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
