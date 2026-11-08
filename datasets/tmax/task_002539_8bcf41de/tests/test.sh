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
import glob
import hashlib
import os
import re
from pathlib import Path

import pytest
import requests

CATEGORIES = ["syslogs", "metrics", "traces"]


def expected_entry(i):
    cat = CATEGORIES[i % 3]
    ts = 1680000000 + i
    rel_path = f"{cat}/{ts}.log"
    content = (
        f"CATEGORY: {cat}\n"
        f"TIMESTAMP: {ts}\n"
        "PAYLOAD data line 1\n"
        "PAYLOAD data line 2\n"
    ).encode()
    return cat, ts, rel_path, content


def test_organized_data_files():
    # Verify all 50 files are regular files containing the complete original data.
    expected_paths = set()
    for i in range(1, 51):
        cat, ts, rel_path, expected_content = expected_entry(i)
        file_path = f"/app/organized_data/{rel_path}"
        expected_paths.add(rel_path)
        assert os.path.isfile(file_path), f"Expected file {file_path} is missing."
        assert not os.path.islink(file_path), f"Expected moved regular file, got symlink: {file_path}"

        with open(file_path, "r") as f:
            lines = f.readlines()
            assert lines[0].strip() == f"CATEGORY: {cat}"
            assert lines[1].strip() == f"TIMESTAMP: {ts}"

        with open(file_path, "rb") as f:
            assert f.read() == expected_content, f"Complete content mismatch for {file_path}"

    actual_paths = {
        str(path.relative_to("/app/organized_data"))
        for path in Path("/app/organized_data").rglob("*.log")
        if str(path.relative_to("/app/organized_data")) != "processed.log"
    }
    assert actual_paths == expected_paths, (
        f"Organized .log file set differs: missing={expected_paths - actual_paths}, "
        f"unexpected={actual_paths - expected_paths}"
    )


def test_originals_were_moved():
    assert os.path.isdir("/app/raw_data"), "/app/raw_data is missing"
    remaining = glob.glob("/app/raw_data/dump_*.dat")
    assert remaining == [], f"Raw dump files were not moved: {remaining}"
    for i in range(1, 51):
        assert not os.path.lexists(f"/app/raw_data/dump_{i}.dat")


def test_processed_log():
    log_path = "/app/organized_data/processed.log"
    assert os.path.isfile(log_path), "processed.log is missing."

    with open(log_path, "r") as f:
        lines = f.readlines()

    assert len(lines) == 50, f"Expected 50 lines in processed.log, got {len(lines)}"

    # Check that all 50 expected complete lines are present (order may vary due to concurrency).
    expected_lines = set()
    for i in range(1, 51):
        cat, ts, _, _ = expected_entry(i)
        expected_lines.add(f"MOVED dump_{i}.dat TO {cat}/{ts}.log\n")

    actual_lines = set(lines)
    missing = expected_lines - actual_lines
    assert not missing, f"processed.log is missing expected entries: {missing}"
    assert actual_lines == expected_lines, f"Unexpected or malformed processed.log entries: {actual_lines - expected_lines}"


def test_manifest_file():
    manifest_path = "/app/organized_data/manifest.sha256"
    assert os.path.isfile(manifest_path), "manifest.sha256 is missing."

    with open(manifest_path, "r") as f:
        manifest_lines = f.readlines()

    assert len(manifest_lines) == 50, f"Expected 50 entries in manifest.sha256, got {len(manifest_lines)}"

    # Recompute hashes from the fully validated files.
    expected_hashes = {}
    for i in range(1, 51):
        _, _, rel_path, _ = expected_entry(i)
        abs_path = f"/app/organized_data/{rel_path}"
        with open(abs_path, "rb") as f:
            expected_hashes[rel_path] = hashlib.sha256(f.read()).hexdigest()

    parsed_manifest = {}
    for line in manifest_lines:
        assert line.endswith("\n"), f"Manifest entry lacks newline: {line!r}"
        match = re.fullmatch(r"([0-9a-f]{64})  ((?:\./)?[^\n]+)\n", line)
        assert match, f"Invalid standard sha256sum line format: {line!r}"
        h, p = match.groups()
        if p.startswith("./"):
            p = p[2:]
        assert p not in parsed_manifest, f"Duplicate manifest entry: {p}"
        parsed_manifest[p] = h

    for p, h in expected_hashes.items():
        assert p in parsed_manifest, f"File {p} missing from manifest"
        assert parsed_manifest[p] == h, f"Hash mismatch for {p}: expected {h}, got {parsed_manifest[p]}"
    assert set(parsed_manifest) == set(expected_hashes), "Manifest contains missing or unexpected paths"


def test_http_server_valid_token():
    url = "http://127.0.0.1:9090/manifest.sha256"
    headers = {"Authorization": "Bearer secret-token-88"}
    try:
        resp = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code} with body: {resp.text}"
    assert "syslogs/1680000003.log" in resp.text, "Manifest content missing from response"
    with open("/app/organized_data/manifest.sha256", "rb") as f:
        assert resp.content == f.read(), "Server did not return the organized manifest exactly"


def test_http_server_serves_complete_data_file():
    _, _, rel_path, expected_content = expected_entry(1)
    url = f"http://127.0.0.1:9090/{rel_path}"
    headers = {"Authorization": "Bearer secret-token-88"}
    try:
        resp = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert resp.status_code == 200
    assert resp.content == expected_content


def test_http_server_invalid_token():
    url = "http://127.0.0.1:9090/manifest.sha256"
    headers = {"Authorization": "Bearer fake-token"}
    try:
        resp = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")

    assert resp.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {resp.status_code}"


def test_http_server_missing_file():
    url = "http://127.0.0.1:9090/doesnotexist.log"
    headers = {"Authorization": "Bearer secret-token-88"}
    try:
        resp = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")

    assert resp.status_code == 404, f"Expected 404 Not Found, got {resp.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
