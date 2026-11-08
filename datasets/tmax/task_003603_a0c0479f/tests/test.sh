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
import pytest
import requests


def test_api_records_endpoint():
    """Verify that the API is running and returning the correctly processed data."""
    url = "http://127.0.0.1:8000/api/records"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), "Expected the JSON response to be a list of objects"
    assert len(data) == 5, f"Expected 5 records, got {len(data)}"

    expected_tokens = {
        1: "EVT_500",
        2: "EVT_UNK",
        3: "EVT_502",
        4: "EVT_404",
        5: "EVT_UNK"
    }
    expected_event_codes = {
        1: 500,
        2: None,
        3: 502,
        4: 404,
        5: None
    }

    seen_ids = []
    for row in data:
        assert isinstance(row, dict), "Each record must be a JSON object"
        assert "id" in row, "Missing 'id' field in record"
        assert "event_code" in row, "Missing 'event_code' field in record"
        assert "token" in row, "Missing 'token' field in record"
        assert "video_frames" in row, "Missing 'video_frames' field in record"

        row_id = row["id"]
        assert row_id in expected_tokens, f"Unexpected id {row_id} in record"
        seen_ids.append(row_id)

        expected_token = expected_tokens[row_id]
        actual_token = row["token"]
        assert actual_token == expected_token, f"For id {row_id}, expected token '{expected_token}', got '{actual_token}'"

        expected_event_code = expected_event_codes[row_id]
        actual_event_code = row["event_code"]
        assert actual_event_code == expected_event_code, (
            f"For id {row_id}, expected event_code {expected_event_code!r}, "
            f"got {actual_event_code!r}"
        )

        actual_frames = row["video_frames"]
        assert actual_frames == 120, f"For id {row_id}, expected video_frames to be 120, got {actual_frames}"

    assert len(set(seen_ids)) == 5, "Record IDs must be unique"
    assert set(seen_ids) == set(expected_tokens), "API must return every source record exactly once"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
