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
import random
import re
import requests
import pytest

EXPECTED_VERSIONS = [
    "v0.9.5",
    "v1.0.1",
    "v1.1.0",
    "v2.0.0-rc.1",
    "v2.0.0",
    "v3.1.2"
]

SEMVER_RE = re.compile(
    r"^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

def semver_key(version):
    match = SEMVER_RE.fullmatch(version)
    assert match is not None, f"Invalid semantic version in test data: {version}"
    major, minor, patch = map(int, match.group(1, 2, 3))
    prerelease = match.group(4)
    if prerelease is None:
        prerelease_key = (1,)
    else:
        identifiers = []
        for identifier in prerelease.split("."):
            if identifier.isdigit():
                identifiers.append((0, int(identifier)))
            else:
                identifiers.append((1, identifier))
        prerelease_key = (0, tuple(identifiers))
    return major, minor, patch, prerelease_key

def expected_newer_than(query):
    query_key = semver_key(query)
    return [version for version in EXPECTED_VERSIONS if semver_key(version) > query_key]

def get_json(url, **kwargs):
    try:
        response = requests.get(url, timeout=5, **kwargs)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {url}: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")

def test_extracted_versions_file():
    """Test that the extracted_versions.txt file exists and contains the correct sorted versions."""
    file_path = "/home/user/project_files/extracted_versions.txt"
    assert os.path.isfile(file_path), f"Output file is missing: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    versions = [line.strip() for line in content if line.strip()]
    assert versions == EXPECTED_VERSIONS, f"Extracted versions do not match expected. Found: {versions}"

def test_api_latest_version():
    """Test that the REST API returns the correct latest version."""
    url = "http://127.0.0.1:8080/api/versions/latest"
    data = get_json(url)
    assert "latest" in data, "Response JSON missing 'latest' key"
    assert data["latest"] == "v3.1.2", f"Expected latest version 'v3.1.2', got '{data['latest']}'"

def test_api_newer_than():
    """Retain the original newer-than assertion."""
    url = "http://127.0.0.1:8080/api/versions/newer_than?v=1.1.0"
    data = get_json(url)
    assert "versions" in data, "Response JSON missing 'versions' key"
    expected_newer = ["v2.0.0-rc.1", "v2.0.0", "v3.1.2"]
    assert data["versions"] == expected_newer, f"Expected versions {expected_newer}, got {data['versions']}"

def test_api_newer_than_arbitrary_queries():
    """Exercise semantic comparison using unpredictable query values."""
    rng = random.SystemRandom()
    queries = {
        f"{rng.randrange(0, 5)}.{rng.randrange(0, 5)}.{rng.randrange(0, 10)}"
        for _ in range(20)
    }
    # Include important semantic-version boundaries, including prerelease ordering.
    queries.update({"0.0.0", "0.9.5", "1.0.0", "1.0.1", "1.1.1", "2.0.0-rc.0", "2.0.0-rc.1", "2.0.0", "3.1.1", "3.1.2", "9.0.0"})

    url = "http://127.0.0.1:8080/api/versions/newer_than"
    for query in queries:
        data = get_json(url, params={"v": query})
        assert "versions" in data, f"Response JSON missing 'versions' key for query {query}"
        expected = expected_newer_than(query)
        assert data["versions"] == expected, (
            f"For query {query}, expected versions {expected}, got {data['versions']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
