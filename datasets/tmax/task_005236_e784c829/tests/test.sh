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
# test_final_state.py
import os
import sys
import secrets
import pytest
import requests
import numpy as np

def test_server_script_exists():
    assert os.path.isfile('/home/user/server.py'), "/home/user/server.py is missing"

def test_seqtools_fixed():
    sys.path.insert(0, '/app')
    try:
        from seqtools.scorer import WEIGHT_MATRIX, score_profile
    except ImportError as e:
        pytest.fail(f"Failed to import seqtools: {e}")

    assert WEIGHT_MATRIX.shape == (4, 4), f"WEIGHT_MATRIX should be 4x4, but is {WEIGHT_MATRIX.shape}"
    assert np.array_equal(WEIGHT_MATRIX, np.eye(4)), "WEIGHT_MATRIX is not a 4x4 identity matrix"

    # Test that score_profile works without ValueError
    try:
        scores = score_profile("ACGT")
        assert len(scores) == 4
    except Exception as e:
        pytest.fail(f"score_profile failed: {e}")

def post_sequence(sequence):
    try:
        return requests.post(
            "http://127.0.0.1:8080/analyze",
            json={"sequence": sequence},
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at 127.0.0.1:8080: {e}")

def test_analyze_endpoint():
    # Test with a uniform sequence (all valid bases, sum = 1.0)
    seq1 = "ACGTACGTACGT"
    payload1 = {"sequence": seq1}

    try:
        resp1 = requests.post("http://127.0.0.1:8080/analyze", json=payload1, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at 127.0.0.1:8080: {e}")

    assert resp1.status_code == 200, f"Expected status code 200, got {resp1.status_code}"
    data1 = resp1.json()
    assert "derivative" in data1, "Response JSON missing 'derivative' key"

    # For a sequence of all valid bases, the scores are all 1.0, so the gradient is all 0.0
    expected_derivative1 = [0.0] * len(seq1)
    np.testing.assert_allclose(
        data1["derivative"],
        expected_derivative1,
        err_msg="Derivative for 'ACGTACGTACGT' is incorrect"
    )

    # Test with a sequence containing an invalid base (sum = 0.0 for 'X')
    seq2 = "ACXGT"
    payload2 = {"sequence": seq2}
    resp2 = requests.post("http://127.0.0.1:8080/analyze", json=payload2, timeout=2)
    assert resp2.status_code == 200
    data2 = resp2.json()

    # Scores: A=1, C=1, X=0, G=1, T=1
    # Gradient of [1, 1, 0, 1, 1]:
    # index 0: 1 - 1 = 0
    # index 1: (0 - 1) / 2 = -0.5
    # index 2: (1 - 1) / 2 = 0.0
    # index 3: (1 - 0) / 2 = 0.5
    # index 4: 1 - 1 = 0
    expected_derivative2 = [0.0, -0.5, 0.0, 0.5, 0.0]
    np.testing.assert_allclose(
        data2["derivative"],
        expected_derivative2,
        err_msg="Derivative for 'ACXGT' is incorrect"
    )

def test_analyze_endpoint_randomized_against_seqtools():
    sys.path.insert(0, '/app')
    from seqtools.scorer import score_profile

    alphabet = "ACGTacgtNXYZ!?"
    invalid = "NXYZ!?"

    # Generate inputs only at verification time so fixed-response servers cannot
    # anticipate them. Ensure every sequence has invalid positions, producing
    # nontrivial gradients, while also exercising lowercase valid bases.
    sequences = []
    for _ in range(10):
        length = 7 + secrets.randbelow(25)
        chars = [secrets.choice(alphabet) for _ in range(length)]
        chars[secrets.randbelow(length)] = secrets.choice(invalid)
        chars[secrets.randbelow(length)] = secrets.choice(invalid)
        chars[secrets.randbelow(length)] = secrets.choice("acgt")
        sequences.append("".join(chars))

    for sequence in sequences:
        expected = np.gradient(score_profile(sequence))
        response = post_sequence(sequence)
        assert response.status_code == 200, (
            f"Expected status code 200 for randomized sequence, got {response.status_code}"
        )
        try:
            data = response.json()
        except ValueError as e:
            pytest.fail(f"Response for randomized sequence was not valid JSON: {e}")
        assert "derivative" in data, "Response JSON missing 'derivative' key"
        assert isinstance(data["derivative"], list), "'derivative' must be a JSON list"
        assert len(data["derivative"]) == len(expected), (
            "Derivative length does not match score profile length"
        )
        np.testing.assert_allclose(
            data["derivative"],
            expected,
            rtol=1e-7,
            atol=1e-9,
            err_msg=f"Derivative is incorrect for randomized sequence {sequence!r}",
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
