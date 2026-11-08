#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest
import requests

def test_extracted_metrics_file():
    """Test that the overprovisioned_hours.txt file has the correct count."""
    file_path = '/home/user/overprovisioned_hours.txt'
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == '14', f"Expected overprovisioned_hours to be 14, but got: {content}"

def test_git_hook_enforcement():
    """Test the pre-receive hook in the bare Git repository."""
    repo_path = '/home/user/finops_rules.git'
    assert os.path.isdir(repo_path), f"Git repo not found at {repo_path}"

    with tempfile.TemporaryDirectory() as tmpdir:
        # Clone the repo
        clone_cmd = ['git', 'clone', repo_path, tmpdir]
        subprocess.run(clone_cmd, check=True, capture_output=True)

        # Configure git
        subprocess.run(['git', 'config', 'user.name', 'Tester'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'config', 'user.email', 'test@test.com'], cwd=tmpdir, check=True)

        # Test safe commit
        safe_file = os.path.join(tmpdir, 'config.txt')
        with open(safe_file, 'w') as f:
            f.write('Normal config\n')

        subprocess.run(['git', 'add', 'config.txt'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'commit', '-m', 'Init'], cwd=tmpdir, check=True)

        push_safe = subprocess.run(['git', 'push', 'origin', 'master'], cwd=tmpdir, capture_output=True, text=True)
        assert push_safe.returncode == 0, f"Failed to push safe commit. Output: {push_safe.stderr}"

        # Test bad commit
        with open(safe_file, 'w') as f:
            f.write('START_EXPENSIVE_VM\n')

        subprocess.run(['git', 'add', 'config.txt'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'commit', '-m', 'Bad commit'], cwd=tmpdir, check=True)

        push_bad = subprocess.run(['git', 'push', 'origin', 'master'], cwd=tmpdir, capture_output=True, text=True)
        assert push_bad.returncode != 0, "Pushing bad commit should have been rejected by the pre-receive hook."
        assert "Cost limit exceeded" in push_bad.stderr or "Cost limit exceeded" in push_bad.stdout, \
            f"Expected 'Cost limit exceeded' in hook output, got: {push_bad.stderr}"

def test_api_metrics_endpoint():
    """Test the GET /metrics endpoint."""
    url = "http://127.0.0.1:9090/metrics"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")

    assert "overprovisioned_hours" in data, "Key 'overprovisioned_hours' not found in JSON response"
    assert data["overprovisioned_hours"] == 14, f"Expected overprovisioned_hours to be 14, got {data['overprovisioned_hours']}"

def test_api_webhook_endpoint_auth():
    """Test the POST /webhook endpoint with and without valid authentication."""
    url = "http://127.0.0.1:9090/webhook"

    # Valid token
    headers_valid = {"Authorization": "Bearer finops-cost-token"}
    try:
        resp_valid = requests.post(url, headers=headers_valid, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    assert resp_valid.status_code == 200, f"Expected HTTP 200 for valid token, got {resp_valid.status_code}"

    # Missing token
    resp_missing = requests.post(url, timeout=2)
    assert resp_missing.status_code == 401, f"Expected HTTP 401 for missing token, got {resp_missing.status_code}"

    # Invalid token
    headers_invalid = {"Authorization": "Bearer wrong-token"}
    resp_invalid = requests.post(url, headers=headers_invalid, timeout=2)
    assert resp_invalid.status_code == 401, f"Expected HTTP 401 for invalid token, got {resp_invalid.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
