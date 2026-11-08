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
import sys
import secrets

import numpy as np
import pytest
import requests
from scipy.integrate import solve_ivp
from scipy.stats import wasserstein_distance

SIM_PATH = "/app/vendored_bio_sim/sim.py"
PDB_PATH = "/app/data/input.pdb"
URL = "http://127.0.0.1:8888/simulate"
AUTH = {"Authorization": "Bearer sim-token-42"}


def independently_simulate(initial_x):
    initial_x = np.asarray(initial_x, dtype=float)

    def ode_system(t, x):
        return -0.1 * x**3 + np.sin(t)

    sol = solve_ivp(ode_system, (0, 10), initial_x, method="RK45")
    assert sol.success, f"Independent integration failed: {sol.message}"
    return sol.y[:, -1]


def expected_distance(initial_x):
    final_x = independently_simulate(initial_x)
    return float(wasserstein_distance(initial_x, final_x))


def assert_distance_response(response, expected):
    assert response.status_code == 200, (
        f"Expected status code 200 for valid auth, but got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Server did not return valid JSON. Response body: {response.text}")

    assert "distance" in data, "The JSON response is missing the 'distance' key."
    distance = data["distance"]
    assert isinstance(distance, float), (
        f"Expected 'distance' to be a float, but got {type(distance).__name__}."
    )
    assert distance > 0.0, (
        f"Expected 'distance' to be greater than 0.0, but got {distance}."
    )
    assert np.isfinite(distance), f"Expected a finite distance, but got {distance}."
    assert distance == pytest.approx(expected, rel=1e-7, abs=1e-7), (
        f"Incorrect Wasserstein distance: expected {expected}, got {distance}."
    )


def rewrite_pdb_x_coordinates(original_text, coordinates):
    lines = original_text.splitlines(keepends=True)
    atom_indices = [i for i, line in enumerate(lines) if line.startswith("ATOM")]
    assert len(atom_indices) == len(coordinates)
    for index, x in zip(atom_indices, coordinates):
        line = lines[index]
        assert len(line) >= 38
        lines[index] = line[:30] + f"{x:8.3f}" + line[38:]
    return "".join(lines)


def test_sim_py_fixed_and_functional():
    """Check that the perturbation is removed and the vendored artifact really runs."""
    assert os.path.isfile(SIM_PATH), f"{SIM_PATH} is missing."

    with open(SIM_PATH, "r") as f:
        content = f.read()

    assert "first_step=1000.0" not in content, (
        "The deliberate perturbation 'first_step=1000.0' is still present in sim.py."
    )

    sys.path.insert(0, "/app")
    import vendored_bio_sim

    assert callable(vendored_bio_sim.parse_pdb_x_coords)
    assert callable(vendored_bio_sim.run_simulation)

    parsed = vendored_bio_sim.parse_pdb_x_coords(PDB_PATH)
    np.testing.assert_allclose(parsed, np.array([10.0, 11.5, 12.0, 11.5]))

    initial_x, final_x = vendored_bio_sim.run_simulation(PDB_PATH)
    np.testing.assert_allclose(initial_x, parsed)
    np.testing.assert_allclose(
        final_x,
        independently_simulate(parsed),
        rtol=1e-7,
        atol=1e-8,
    )


def test_server_unauthorized():
    """Check that the server returns 401 when the Authorization header is missing."""
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code == 401, (
        f"Expected status code 401 for missing auth, but got {response.status_code}."
    )


def test_server_invalid_auth():
    """Check that the server returns 401 when the Authorization header is invalid."""
    headers = {"Authorization": "Bearer invalid-token"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code == 401, (
        f"Expected status code 401 for invalid auth, but got {response.status_code}."
    )


def test_server_success():
    """Check the real endpoint result against an independently derived answer."""
    original_x = np.array([10.0, 11.5, 12.0, 11.5])
    try:
        response = requests.get(URL, headers=AUTH, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert_distance_response(response, expected_distance(original_x))


def test_server_reloads_pdb_and_computes_simulation():
    """Exercise parsing, integration, and Wasserstein calculation on unpredictable inputs."""
    with open(PDB_PATH, "r") as f:
        original_text = f.read()

    rng = secrets.SystemRandom()
    coordinate_sets = [
        np.array([round(rng.uniform(0.5, 6.0), 3) for _ in range(4)]),
        np.array([round(rng.uniform(7.0, 15.0), 3) for _ in range(4)]),
    ]

    try:
        for coordinates in coordinate_sets:
            changed_pdb = rewrite_pdb_x_coordinates(original_text, coordinates)
            with open(PDB_PATH, "w") as f:
                f.write(changed_pdb)

            expected = expected_distance(coordinates)
            try:
                response = requests.get(URL, headers=AUTH, timeout=10)
            except requests.exceptions.RequestException as e:
                pytest.fail(f"Failed to connect to the server at {URL}: {e}")

            assert_distance_response(response, expected)
    finally:
        with open(PDB_PATH, "w") as f:
            f.write(original_text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
