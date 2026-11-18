#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import urllib.request
import hashlib


def test_result_log_success():
    """Verify that env-tester created a success log."""
    log_path = "/home/user/test-env/result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did you run env-tester?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "SUCCESS" in content, f"Expected 'SUCCESS' in {log_path}, but got: {content}"


def test_mock_server_exists():
    """Verify that the mock_server.js file was created."""
    mock_server_path = "/home/user/test-env/mock_server.js"
    assert os.path.isfile(mock_server_path), f"File {mock_server_path} does not exist."


def test_pyproject_toml_fixed():
    """Verify that the conflicting urllib3 constraint was changed in pyproject.toml."""
    toml_path = "/home/user/test-env/python-pkg/pyproject.toml"
    assert os.path.isfile(toml_path), f"File {toml_path} does not exist."

    with open(toml_path, "r") as f:
        content = f.read()

    assert "urllib3==1.25.1" not in content, "The conflicting urllib3==1.25.1 constraint is still in pyproject.toml."


def test_mock_server_endpoint_behavior():
    """Verify that the submitted server returns the exact payload and derived checksum."""
    req = urllib.request.Request("http://localhost:8080/config")
    with urllib.request.urlopen(req, timeout=2) as response:
        status_code = response.getcode()
        body = response.read().decode("utf-8")
        checksum_header = response.headers.get("X-Checksum")

    assert status_code == 200, f"Expected status code 200, got {status_code}"
    expected_body = '{"status":"ready","version":"1.0.0"}'
    assert body == expected_body, f"Expected body '{expected_body}', got '{body}'"

    expected_checksum = hashlib.sha256(
        (expected_body + "QA_ENV_SALT_123").encode("utf-8")
    ).hexdigest()
    assert checksum_header == expected_checksum, (
        f"Expected X-Checksum header '{expected_checksum}', got '{checksum_header}'"
    )
TEST_EOF

(
    set -e

    # Prove the repaired package can actually be installed.
    cd /home/user/test-env/python-pkg
    python3 -m pip install .

    # Ensure the submitted artifact, rather than a previously running process,
    # owns the service used by the checks.
    pkill -9 -f '[m]ock_server.js' 2>/dev/null || true
    sleep 1
    rm -f /home/user/test-env/result.log

    node /home/user/test-env/mock_server.js >/tmp/mock_server.out 2>/tmp/mock_server.err &
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
    sleep 1
    kill -0 "$server_pid"

    # Run the installed console script and require it to create a fresh log.
    command -v env-tester >/dev/null
    timeout 15s env-tester

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
)
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
