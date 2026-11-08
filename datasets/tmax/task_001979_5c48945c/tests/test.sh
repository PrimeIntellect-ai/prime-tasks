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
import pytest
import requests
import pandas as pd

RAW_PATH = '/app/raw_data.csv'
CLEAN_PATH = '/app/clean_data.csv'
COLUMNS = ['alpha', 'beta', 'gamma', 'target']


def expected_clean_data():
    raw = pd.read_csv(RAW_PATH)
    mask = (
        (raw['alpha'] >= 0.0)
        & (raw['beta'] <= 100.0)
        & raw['gamma'].isin([0, 1])
        & (raw['target'] > 0.0)
    )
    return raw.loc[mask, COLUMNS].reset_index(drop=True)


def assert_matches_expected(actual):
    expected = expected_clean_data()
    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )


def test_clean_data_csv_exists_and_valid():
    """Test that /app/clean_data.csv exists and contains valid, correctly filtered data."""
    path = CLEAN_PATH
    assert os.path.exists(path), f"Expected file {path} does not exist."
    assert os.path.isfile(path), f"Expected {path} to be a file."

    df = pd.read_csv(path)

    # Check constraints
    assert (df['alpha'] >= 0.0).all(), "Some rows in clean_data.csv violate alpha >= 0.0"
    assert (df['beta'] <= 100.0).all(), "Some rows in clean_data.csv violate beta <= 100.0"
    assert df['gamma'].isin([0, 1]).all(), "Some rows in clean_data.csv violate gamma in [0, 1]"
    assert (df['target'] > 0.0).all(), "Some rows in clean_data.csv violate target > 0.0"

    # Check exact count based on truth
    assert len(df) == 139, f"Expected 139 rows in clean_data.csv, found {len(df)}"

    # Check that these are exactly the rows obtained by filtering raw_data.csv.
    assert list(df.columns) == COLUMNS, f"Expected columns {COLUMNS}, got {list(df.columns)}"
    assert_matches_expected(df)


def test_api_stats_endpoint():
    """Test the GET /stats endpoint."""
    url = "http://127.0.0.1:8080/stats"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 from /stats, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /stats is not valid JSON.")

    assert "initial_rows" in data, "Key 'initial_rows' missing in /stats response."
    assert "cleaned_rows" in data, "Key 'cleaned_rows' missing in /stats response."

    assert data["initial_rows"] == 1000, f"Expected initial_rows to be 1000, got {data['initial_rows']}"
    assert data["cleaned_rows"] == 139, f"Expected cleaned_rows to be 139, got {data['cleaned_rows']}"

    raw = pd.read_csv(RAW_PATH)
    expected = expected_clean_data()
    assert data["initial_rows"] == len(raw)
    assert data["cleaned_rows"] == len(expected)


def test_api_data_endpoint():
    """Test the GET /data endpoint."""
    url = "http://127.0.0.1:8080/data"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 from /data, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /data is not valid JSON.")

    assert isinstance(data, list), "Expected response from /data to be a JSON array."
    assert len(data) == 139, f"Expected 139 items in /data response, got {len(data)}"

    for i, row in enumerate(data):
        assert 'alpha' in row, f"Row {i} missing 'alpha'"
        assert 'beta' in row, f"Row {i} missing 'beta'"
        assert 'gamma' in row, f"Row {i} missing 'gamma'"
        assert 'target' in row, f"Row {i} missing 'target'"

        assert row['alpha'] >= 0.0, f"Row {i} violates alpha >= 0.0: {row['alpha']}"
        assert row['beta'] <= 100.0, f"Row {i} violates beta <= 100.0: {row['beta']}"
        assert row['gamma'] in [0, 1], f"Row {i} violates gamma in [0, 1]: {row['gamma']}"
        assert row['target'] > 0.0, f"Row {i} violates target > 0.0: {row['target']}"

    api_df = pd.DataFrame(data)
    assert list(api_df.columns) == COLUMNS, f"Expected API columns {COLUMNS}, got {list(api_df.columns)}"
    assert_matches_expected(api_df)

    csv_df = pd.read_csv(CLEAN_PATH)
    pd.testing.assert_frame_equal(
        api_df.reset_index(drop=True),
        csv_df.reset_index(drop=True),
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
