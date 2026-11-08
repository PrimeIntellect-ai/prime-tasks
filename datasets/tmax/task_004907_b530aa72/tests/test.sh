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
import csv
import io
import math
import secrets

import pytest
import requests

URL = "http://127.0.0.1:8000/process"
AUTH_HEADER = {"Authorization": "Bearer ds-secret-token"}

CSV_CONTENT = """patient_id,age,weight
101,25,70.5
102,,80.0
103,40,
"""


def post_csv(content, headers=None):
    files = {"dataset": ("dataset.csv", content, "text/csv")}
    try:
        return requests.post(URL, headers=headers, files=files, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")


def test_missing_auth():
    response = post_csv(CSV_CONTENT)
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {response.status_code}"


def test_invalid_auth():
    response = post_csv(CSV_CONTENT, {"Authorization": "Bearer wrong-token"})
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid auth, got {response.status_code}"


def test_process_dataset():
    response = post_csv(CSV_CONTENT, AUTH_HEADER)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert isinstance(data, list), "Expected response to be a JSON array"
    assert len(data) == 3, f"Expected 3 records, got {len(data)}"

    r1 = data[0]
    assert r1.get("patient_id") == 101
    assert type(r1.get("patient_id")) is int, "patient_id must be an integer"
    assert r1.get("age") == 25
    assert type(r1.get("age")) is int, "age must be an integer"
    assert math.isclose(r1.get("weight"), 70.5, rel_tol=1e-5)
    assert math.isclose(r1.get("proj_1"), -1.6, rel_tol=1e-5)
    assert math.isclose(r1.get("proj_2"), 27.05, rel_tol=1e-5)

    r2 = data[1]
    assert r2.get("patient_id") == 102
    assert r2.get("age") is None, "Missing age must be represented as null"
    assert math.isclose(r2.get("weight"), 80.0, rel_tol=1e-5)
    assert math.isclose(r2.get("proj_1"), -16.0, rel_tol=1e-5)
    assert math.isclose(r2.get("proj_2"), 8.0, rel_tol=1e-5)

    r3 = data[2]
    assert r3.get("patient_id") == 103
    assert r3.get("age") == 40
    assert type(r3.get("age")) is int, "age must be an integer"
    assert r3.get("weight") is None, "Missing weight must be represented as null"
    assert math.isclose(r3.get("proj_1"), 20.0, rel_tol=1e-5)
    assert math.isclose(r3.get("proj_2"), 32.0, rel_tol=1e-5)


def test_randomized_dataset_is_actually_processed():
    rng = secrets.SystemRandom()
    base_id = rng.randrange(200000, 900000)
    rows = []
    for i in range(8):
        age = None if i in (1, 5) else rng.randrange(1, 100)
        weight = None if i in (2, 6) else rng.randrange(3500, 14000) / 100.0 + 0.003
        rows.append((base_id + i * rng.randrange(2, 20), age, weight))

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["patient_id", "age", "weight"])
    for patient_id, age, weight in rows:
        writer.writerow([
            patient_id,
            "" if age is None else age,
            "" if weight is None else format(weight, ".3f"),
        ])

    response = post_csv(out.getvalue(), AUTH_HEADER)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert isinstance(data, list)
    assert len(data) == len(rows)

    with open("/app/transform_matrix.csv", newline="") as matrix_file:
        matrix = [[float(x) for x in row] for row in csv.reader(matrix_file) if row]
    assert len(matrix) == 2 and all(len(row) == 2 for row in matrix)

    for actual, (patient_id, age, weight) in zip(data, rows):
        assert actual.get("patient_id") == patient_id
        assert type(actual.get("patient_id")) is int

        if age is None:
            assert actual.get("age") is None, "Missing nullable integer must be JSON null"
        else:
            assert actual.get("age") == age
            assert type(actual.get("age")) is int, "Nullable integer values must remain integers"

        if weight is None:
            assert actual.get("weight") is None
        else:
            assert math.isclose(actual.get("weight"), weight, rel_tol=1e-9, abs_tol=1e-9)

        age_for_projection = 0 if age is None else age
        weight_for_projection = 0 if weight is None else weight
        expected_1 = age_for_projection * matrix[0][0] + weight_for_projection * matrix[1][0]
        expected_2 = age_for_projection * matrix[0][1] + weight_for_projection * matrix[1][1]
        assert math.isclose(actual.get("proj_1"), expected_1, rel_tol=1e-7, abs_tol=1e-7)
        assert math.isclose(actual.get("proj_2"), expected_2, rel_tol=1e-7, abs_tol=1e-7)


@pytest.mark.parametrize("bad_csv", [
    "patient_id,age,weight\n501,12.5,70.0\n",
    "patient_id,age,weight\n,12,70.0\n",
    "patient_id,age,weight\n501,12,not-a-number\n",
    "patient_id,weight\n501,70.0\n",
])
def test_schema_violations_are_rejected(bad_csv):
    response = post_csv(bad_csv, AUTH_HEADER)
    assert response.status_code >= 400, (
        f"Schema-invalid CSV must be rejected, got {response.status_code}: {response.text}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
