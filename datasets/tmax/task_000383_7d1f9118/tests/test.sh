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
import uuid
from pathlib import Path

import pytest
import requests

DOCS_DIR = Path("/home/user/extracted_docs")
PORT = 8080
TOKEN = "DocAuth992"
SIGN_OFF = "Drafted by TechWriter Pro"
BASE_URL = f"http://127.0.0.1:{PORT}"

EXPECTED_BODIES = {
    "docs/intro.txt": "<h1>Introduction</h1>" + chr(92) + "nWelcome to the <strong>legacy</strong> system.",
    "docs/specs.txt": "<h1>System Specs</h1>" + chr(92) + "nHere are the <strong>details</strong>...",
}


def txt_files():
    return sorted(path for path in DOCS_DIR.rglob("*.txt") if path.is_file())


def relative_name(path):
    return path.relative_to(DOCS_DIR).as_posix()


def file_url(path):
    relative = requests.utils.quote(relative_name(path), safe="/")
    return f"{BASE_URL}/{relative}"


def test_extracted_docs_directory_exists():
    assert DOCS_DIR.is_dir(), f"Directory {DOCS_DIR} does not exist. Did you extract the archives correctly?"


def test_txt_files_exist_and_processed():
    files = txt_files()
    assert len(files) > 0, f"No .txt files found recursively in {DOCS_DIR}."

    actual_names = {relative_name(path) for path in files}
    assert actual_names == set(EXPECTED_BODIES), (
        f"Extracted .txt files do not match the archive. Expected {sorted(EXPECTED_BODIES)}, "
        f"got {sorted(actual_names)}"
    )

    for file_path in files:
        content_bytes = file_path.read_bytes()
        try:
            content_str = content_bytes.decode("utf-8")
        except UnicodeDecodeError:
            pytest.fail(f"File {file_path} is not valid UTF-8.")

        assert "[[TITLE:" not in content_str, f"Unreplaced [[TITLE:...]] macro found in {file_path}"
        assert "[[BOLD:" not in content_str, f"Unreplaced [[BOLD:...]] macro found in {file_path}"

        lines = content_str.strip().split("\n")
        assert lines[-1].strip() == SIGN_OFF, f"Sign-off phrase missing or incorrect at the end of {file_path}"

        expected = EXPECTED_BODIES[relative_name(file_path)] + "\n" + SIGN_OFF
        # The final line may or may not have one terminating LF, but no other
        # content differences are permitted.
        comparable = content_str[:-1] if content_str.endswith("\n") else content_str
        assert comparable == expected, f"Normalized contents of {file_path} do not match the archive input and required macros"


def test_server_unauthorized():
    try:
        response = requests.get(f"{BASE_URL}/nonexistent.txt", timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to server on port {PORT}: {exc}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth header, got {response.status_code}"

    headers = {"Authorization": "Bearer InvalidToken123"}
    response = requests.get(f"{BASE_URL}/nonexistent.txt", headers=headers, timeout=2)
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid auth header, got {response.status_code}"

    files = txt_files()
    assert files, "No processed files available for authorization testing"
    response = requests.get(file_url(files[0]), timeout=2)
    assert response.status_code == 401, "A real documentation file was served without authorization"

    response = requests.get(
        file_url(files[0]),
        headers={"Authorization": "Bearer InvalidToken123"},
        timeout=2,
    )
    assert response.status_code == 401, "A real documentation file was served with an invalid token"


def test_server_authorized_and_serves_files():
    files = txt_files()
    assert files, "No .txt files to test server with."
    headers = {"Authorization": f"Bearer {TOKEN}"}

    for file_path in files:
        try:
            response = requests.get(file_url(file_path), headers=headers, timeout=2)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to server on port {PORT}: {exc}")

        assert response.status_code == 200, f"Expected 200 OK for {relative_name(file_path)}, got {response.status_code}"
        assert response.content == file_path.read_bytes(), f"Served content for {relative_name(file_path)} does not match the file on disk."

    # Ensure the server reads the requested artifact dynamically rather than
    # returning a fixed response prepared specifically for the known files.
    probe_file = files[0]
    original = probe_file.read_bytes()
    probe = (f"dynamic-verifier-probe-{uuid.uuid4()}\n{SIGN_OFF}\n").encode("utf-8")
    try:
        probe_file.write_bytes(probe)
        response = requests.get(file_url(probe_file), headers=headers, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK for dynamic probe, got {response.status_code}"
        assert response.content == probe, "Server does not dynamically return the exact current contents of the requested file"
    finally:
        probe_file.write_bytes(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
