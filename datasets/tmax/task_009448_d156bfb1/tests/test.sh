#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import json
import pytest

SCRIPT_PATH = "/home/user/api.sh"
SRC_PATH = "/home/user/src"

def run_script(method, uri, stdin=""):
    result = subprocess.run(
        [SCRIPT_PATH, method, uri],
        input=stdin,
        text=True,
        capture_output=True
    )
    return result.stdout

def parse_http(output):
    parts = output.split("\r\n\r\n", 1)
    if len(parts) == 1:
        parts = output.split("\n\n", 1)

    headers = parts[0]
    body = parts[1] if len(parts) > 1 else ""
    return headers, body.strip()

def test_script_exists_and_executable():
    """Verify the script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

def test_get_files():
    """Test the GET endpoint returns correct JSON for .sh files."""
    output = run_script("GET", "/files?ext=sh")
    headers, body = parse_http(output)
    assert "HTTP/1.1 200 OK" in headers, "Expected 200 OK for GET /files"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Body is not valid JSON: {body}")

    assert "files" in data, "JSON response missing 'files' key"
    assert data["files"] == ["script.sh"], f"Expected ['script.sh'], got {data['files']}"

def test_post_evaluate():
    """Test the POST endpoint evaluates the mathematical expression correctly."""
    stdin = "LINES(app.py) * 2 + SIZE(script.sh)"
    app_path = os.path.join(SRC_PATH, "app.py")
    script_path = os.path.join(SRC_PATH, "script.sh")
    with open(app_path, "rb") as f:
        app_lines = sum(1 for _ in f)
    expected = app_lines * 2 + os.path.getsize(script_path)

    output = run_script("POST", "/evaluate", stdin=stdin)
    headers, body = parse_http(output)
    assert "HTTP/1.1 200 OK" in headers, "Expected 200 OK for POST /evaluate"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Body is not valid JSON: {body}")

    assert "result" in data, "JSON response missing 'result' key"
    assert data["result"] == expected, f"Expected {expected}, got {data['result']}"

def test_404_not_found():
    """Test that an unrecognized endpoint/method returns 404."""
    output = run_script("PUT", "/files")
    headers, body = parse_http(output)
    assert "HTTP/1.1 404 Not Found" in headers, "Expected 404 Not Found for PUT /files"

def test_400_bad_request():
    """Test that referencing a missing file in evaluate returns 400."""
    stdin = "SIZE(missing.txt)"
    output = run_script("POST", "/evaluate", stdin=stdin)
    headers, body = parse_http(output)
    assert "HTTP/1.1 400 Bad Request" in headers, "Expected 400 Bad Request for missing file"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
