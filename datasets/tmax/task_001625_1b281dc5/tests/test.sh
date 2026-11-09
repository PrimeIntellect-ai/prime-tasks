#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest
import requests
import numpy as np
import h5py
import networkx as nx


def simulate_diffusion(k_base=0.015, threshold=0.0002):
    """Recompute results using the specified synchronous update and retain/count the convergent step."""
    G = nx.watts_strogatz_graph(n=200, k=4, p=0.1, seed=42)
    L = nx.laplacian_matrix(G).toarray()

    results = {}
    for r in range(4):
        K_r = k_base + r * 0.01
        x = np.sin(np.arange(200))
        iterations = 0
        while True:
            delta = -K_r * (L @ x)
            x = x + delta
            iterations += 1
            if np.max(np.abs(delta)) < threshold:
                break
        results[r] = {
            'iterations': iterations,
            'final_state': x,
            'k_used': round(K_r, 3)
        }
    return results


@pytest.fixture(scope="module")
def expected_results():
    return simulate_diffusion()


def test_hdf5_file_exists_and_correct(expected_results):
    """Check that the HDF5 file exists and contains the correct results."""
    file_path = "/app/simulation_results.h5"
    assert os.path.exists(file_path), f"HDF5 file {file_path} is missing."

    with h5py.File(file_path, 'r') as f:
        assert 'results' in f, "Group 'results' missing in HDF5 file."
        results_group = f['results']

        for r in range(4):
            rank_name = f"rank_{r}"
            assert rank_name in results_group, f"Subgroup '{rank_name}' missing in 'results'."
            rank_group = results_group[rank_name]

            assert 'final_state' in rank_group, f"Dataset 'final_state' missing in '{rank_name}'."
            assert 'iterations' in rank_group.attrs, f"Attribute 'iterations' missing in '{rank_name}'."

            actual_iterations = rank_group.attrs['iterations']
            expected_iterations = expected_results[r]['iterations']
            assert actual_iterations == expected_iterations, f"Rank {r} iterations mismatch. Expected {expected_iterations}, got {actual_iterations}."

            actual_state = np.array(rank_group['final_state'])
            expected_state = expected_results[r]['final_state']
            np.testing.assert_allclose(actual_state, expected_state, atol=1e-4, err_msg=f"Rank {r} final_state mismatch.")


def test_convergence_plot_exists():
    """Check that the convergence plot was generated."""
    file_path = "/app/convergence_plot.png"
    assert os.path.exists(file_path), f"Convergence plot {file_path} is missing."
    assert os.path.getsize(file_path) > 0, f"Convergence plot {file_path} is empty."


def test_api_unauthorized():
    """Check that the API returns 401 when no API key is provided."""
    url = "http://127.0.0.1:8080/api/status/0"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}."


def test_api_authorized_and_correct(expected_results):
    """Check that the API returns the correct JSON response for all ranks."""
    headers = {"X-API-Key": "netdiff-88"}

    for r in range(4):
        url = f"http://127.0.0.1:8080/api/status/{r}"
        try:
            response = requests.get(url, headers=headers, timeout=5)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to the API for rank {r}: {e}")

        assert response.status_code == 200, f"Expected 200 OK for rank {r}, got {response.status_code}. Response: {response.text}"

        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response for rank {r} is not valid JSON. Response: {response.text}")

        assert "rank" in data, f"'rank' missing in JSON response for rank {r}."
        assert "iterations_to_converge" in data, f"'iterations_to_converge' missing in JSON response for rank {r}."
        assert "k_used" in data, f"'k_used' missing in JSON response for rank {r}."

        assert data["rank"] == r, f"Expected rank {r}, got {data['rank']}."
        assert data["iterations_to_converge"] == expected_results[r]['iterations'], f"Rank {r} iterations mismatch in API. Expected {expected_results[r]['iterations']}, got {data['iterations_to_converge']}."

        actual_k = round(float(data["k_used"]), 3)
        expected_k = expected_results[r]['k_used']
        assert actual_k == expected_k, f"Rank {r} k_used mismatch in API. Expected {expected_k}, got {actual_k}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
