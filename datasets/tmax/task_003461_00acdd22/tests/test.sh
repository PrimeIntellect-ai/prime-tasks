#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import pytest
import requests

def test_api_artifact_endpoint():
    """Verify that the API endpoint returns the correct JSON response."""
    url = "http://127.0.0.1:8080/api/artifact"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Is it running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Body: {response.text}")

    assert "author" in data, "JSON response missing 'author' key."
    assert "transcription_keyword" in data, "JSON response missing 'transcription_keyword' key."

    expected_author = "Dr. Aris Thorne"
    expected_keyword = "sunflower"

    assert data["author"] == expected_author, f"Expected author '{expected_author}', got '{data['author']}'"
    assert data["transcription_keyword"] == expected_keyword, f"Expected transcription_keyword '{expected_keyword}', got '{data['transcription_keyword']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
