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
import requests
import pytest

EXPECTED_ORGANIZED = {
    "logs/app.log": b"log data",
    "src/main.py": b'print("hello")',
    "README.md": b"readme",
}

EXPECTED_EXTRACTED = {
    "app.log": b"log data",
    "main.py": b'print("hello")',
    "README.md": b"readme",
}


def actual_files(root):
    result = set()
    for directory, dirnames, filenames in os.walk(root):
        for name in filenames:
            result.add(os.path.relpath(os.path.join(directory, name), root))
    return result


def assert_exact_regular_files(root, expected):
    assert os.path.isdir(root), f"Directory not found at {root}"
    assert actual_files(root) == set(expected), (
        f"Unexpected file layout in {root}: got {sorted(actual_files(root))}, "
        f"expected {sorted(expected)}"
    )
    for rel_path, expected_content in expected.items():
        full_path = os.path.join(root, rel_path)
        assert os.path.isfile(full_path), f"Expected file not found at {full_path}"
        assert not os.path.islink(full_path), f"Expected a regular file, not a symlink: {full_path}"
        with open(full_path, "rb") as handle:
            assert handle.read() == expected_content, f"Incorrect content in {full_path}"


def test_extracted_archive_contents():
    """Verify that the archive was extracted with its original files and bytes."""
    assert_exact_regular_files("/home/user/extracted_project", EXPECTED_EXTRACTED)


def test_organized_directory_structure():
    """Verify that the organized directory structure exists and contains the expected files."""
    organized_dir = "/home/user/organized_project"

    assert os.path.isdir(organized_dir), f"Organized directory not found at {organized_dir}"

    expected_files = [
        "logs/app.log",
        "src/main.py",
        "README.md"
    ]

    for rel_path in expected_files:
        full_path = os.path.join(organized_dir, rel_path)
        assert os.path.isfile(full_path), f"Expected file not found at {full_path}"

    assert_exact_regular_files(organized_dir, EXPECTED_ORGANIZED)
    expected_dirs = {"logs", "src"}
    actual_dirs = {
        os.path.relpath(os.path.join(directory, name), organized_dir)
        for directory, dirnames, filenames in os.walk(organized_dir)
        for name in dirnames
    }
    assert actual_dirs == expected_dirs, (
        f"Unexpected directory layout: got {sorted(actual_dirs)}, expected {sorted(expected_dirs)}"
    )


def test_http_server_serving_files():
    """Verify that the HTTP server is running and serving the expected files."""
    base_url = "http://127.0.0.1:8080"

    endpoints = [
        "/logs/app.log",
        "/src/main.py",
        "/README.md"
    ]

    for endpoint in endpoints:
        url = f"{base_url}{endpoint}"
        try:
            response = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to HTTP server at {url}. Error: {e}")

        assert response.status_code == 200, f"Expected 200 OK for {url}, got {response.status_code}"
        assert len(response.content) > 0, f"Response content for {url} is empty"
        rel_path = endpoint.lstrip("/")
        assert response.content == EXPECTED_ORGANIZED[rel_path], (
            f"HTTP response for {url} does not contain the recovered file bytes"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
