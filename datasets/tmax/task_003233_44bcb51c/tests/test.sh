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
import pytest
import requests

PORT = 9055
BASE_URL = f"http://127.0.0.1:{PORT}"
TOKEN = "XyZ99_ConfigAuth"

EXPECTED_FILES = {
    "webserver.conf": rf"api_key={TOKEN}\nlisten=80",
    "database.conf": rf"[db]\npass={TOKEN}\nhost=localhost",
    "cache.conf": f"redis_url=redis://:{TOKEN}@localhost:6379"
}

def test_processed_directory_exists():
    assert os.path.isdir("/app/processed"), "/app/processed/ directory does not exist"

@pytest.mark.parametrize("filename, expected_content", EXPECTED_FILES.items())
def test_http_server_serves_processed_files(filename, expected_content):
    url = f"{BASE_URL}/{filename}"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}. Is the server running on port {PORT}? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for {url}, got {response.status_code}"

    # Check that the response is valid UTF-8
    try:
        text_content = response.content.decode('utf-8')
    except UnicodeDecodeError:
        pytest.fail(f"Response from {url} is not valid UTF-8")

    assert TOKEN in text_content, f"Token '{TOKEN}' not found in the response of {url}"
    assert "REPLACE_ME_TOKEN" not in text_content, f"'REPLACE_ME_TOKEN' was not replaced in {url}"

    # Check exact content to ensure proper decoding of original files
    # Strip whitespace to avoid issues with newlines from different OS/editors
    assert text_content.strip() == expected_content.strip(), f"Content of {url} does not match expected output"

def test_processed_files_on_disk():
    # Verify the files are actually in /app/processed/ with correct names and content
    for filename, expected_content in EXPECTED_FILES.items():
        filepath = os.path.join("/app/processed", filename)
        assert os.path.exists(filepath), f"File {filepath} does not exist on disk"

        with open(filepath, 'rb') as f:
            raw_content = f.read()

        try:
            text_content = raw_content.decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail(f"File {filepath} is not valid UTF-8 on disk")

        assert TOKEN in text_content, f"Token '{TOKEN}' not found in {filepath}"
        assert "REPLACE_ME_TOKEN" not in text_content, f"'REPLACE_ME_TOKEN' was not replaced in {filepath}"
        assert text_content.strip() == expected_content.strip(), f"Content of {filepath} does not match expected output"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
