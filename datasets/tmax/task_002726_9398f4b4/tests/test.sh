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
import ast
import base64
import os
import re
import sqlite3
import subprocess
import tempfile
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9000"
EXPECTED_SCHEMA = [("id", "INTEGER"), ("timestamp", "INTEGER"), ("encoded_payload", "TEXT")]


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)
    return False


def read_database(path):
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            info = conn.execute("PRAGMA table_info(telemetry)").fetchall()
            schema = [(row[1], str(row[2]).upper()) for row in info]
            if schema != EXPECTED_SCHEMA:
                return None
            rows = conn.execute(
                "SELECT id, timestamp, encoded_payload FROM telemetry ORDER BY id"
            ).fetchall()
            if not rows:
                return None
            return rows
        finally:
            conn.close()
    except (sqlite3.Error, OSError):
        return None


def recover_reference_rows():
    image = "/app/telemetry_data.img"
    assert os.path.isfile(image), "Missing telemetry partition image"

    candidates = []
    listing = subprocess.run(
        ["debugfs", "-R", "lsdel", image],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    ).stdout
    for line in listing.splitlines():
        match = re.match(r"^\s*(\d+)\s+", line)
        if match:
            candidates.append(("inode", match.group(1)))
    candidates.append(("path", "/telemetry.db"))

    for index, (kind, value) in enumerate(candidates):
        output = os.path.join(tempfile.gettempdir(), f"verifier_reference_{index}.db")
        try:
            os.unlink(output)
        except FileNotFoundError:
            pass
        target = f"<{value}>" if kind == "inode" else value
        subprocess.run(
            ["debugfs", "-R", f"dump {target} {output}", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if os.path.isfile(output):
            rows = read_database(output)
            if rows is not None:
                return rows
    raise AssertionError("Could not independently recover the telemetry database from the ext4 image")


@pytest.fixture(scope="session")
def expected_records():
    rows = recover_reference_rows()
    result = {}
    for record_id, timestamp, encoded_payload in rows:
        raw = base64.b64decode(encoded_payload, validate=True)
        decoded = bytes(byte ^ 0x5A for byte in raw).decode("utf-8")
        result[record_id] = {
            "id": record_id,
            "timestamp": timestamp,
            "decoded_data": decoded,
        }
    assert set(result) == {1, 2, 3, 4, 5}
    return result


def submission_python_files():
    files = []
    for root in ("/app", "/home", "/root"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, names in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".git"}]
            for name in names:
                if name.endswith(".py"):
                    files.append(os.path.join(directory, name))
    return files


def test_http_server_running():
    """Ensure the HTTP server is listening and responding on port 9000."""
    assert wait_for_server(f"{BASE_URL}/api/v1/record/1"), \
        "HTTP server is not reachable on 127.0.0.1:9000"


def test_api_valid_records(expected_records):
    """Check that the API returns the exact recovered and decoded records."""
    for record_id in range(1, 6):
        resp = requests.get(f"{BASE_URL}/api/v1/record/{record_id}", timeout=2)
        assert resp.status_code == 200, \
            f"Expected HTTP 200 for ID {record_id}, got {resp.status_code}"

        data = resp.json()
        assert "id" in data, "Response missing 'id' field"
        assert "timestamp" in data, "Response missing 'timestamp' field"
        assert "decoded_data" in data, "Response missing 'decoded_data' field"
        assert data["id"] == record_id, f"Expected id {record_id}, got {data['id']}"
        assert isinstance(data["timestamp"], int), "Timestamp should be an integer"
        assert isinstance(data["decoded_data"], str), "Decoded data should be a string"
        assert data == expected_records[record_id], \
            f"Record {record_id} does not match the recovered and independently decoded data"


def test_api_invalid_record():
    """Check that the API returns 404 for a non-existent ID."""
    resp = requests.get(f"{BASE_URL}/api/v1/record/9999", timeout=2)
    assert resp.status_code == 404, \
        f"Expected HTTP 404 for non-existent ID 9999, got {resp.status_code}"


def test_reconstructed_database_matches_image():
    reference = recover_reference_rows()
    matches = []
    for root in ("/app", "/home", "/root"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, names in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".git"}]
            for name in names:
                path = os.path.join(directory, name)
                if path == "/app/telemetry_data.img":
                    continue
                try:
                    if os.path.getsize(path) > 32 * 1024 * 1024:
                        continue
                except OSError:
                    continue
                rows = read_database(path)
                if rows == reference:
                    matches.append(path)
    assert matches, "No reconstructed SQLite telemetry database matching the deleted database was found"


def test_extraction_script_has_exact_schema_assertion():
    qualifying = []
    for path in submission_python_files():
        try:
            source = open(path, "r", encoding="utf-8").read()
            tree = ast.parse(source, filename=path)
        except (OSError, UnicodeError, SyntaxError):
            continue
        lowered = source.lower()
        assertions = [node for node in ast.walk(tree) if isinstance(node, ast.Assert)]
        equality_assertion = any(
            any(isinstance(child, (ast.Eq, ast.NotEq)) for child in ast.walk(node.test))
            for node in assertions
        )
        if (
            assertions
            and equality_assertion
            and "pragma table_info" in lowered
            and "telemetry" in lowered
            and all(column in source for column in ("id", "timestamp", "encoded_payload"))
        ):
            qualifying.append(path)
    assert qualifying, \
        "No Python extraction script with an assertion-based exact telemetry schema check was found"


def test_python_decoder_is_reimplemented_without_runtime_binary():
    qualifying = []
    for path in submission_python_files():
        try:
            source = open(path, "r", encoding="utf-8").read()
            tree = ast.parse(source, filename=path)
        except (OSError, UnicodeError, SyntaxError):
            continue
        lowered = source.lower()
        has_xor = any(isinstance(node, ast.BitXor) for node in ast.walk(tree))
        has_key = any(
            isinstance(node, ast.Constant) and node.value == 0x5A
            for node in ast.walk(tree)
        )
        if "base64" in lowered and has_xor and has_key and "decoder.bin" not in lowered:
            qualifying.append(path)
    assert qualifying, "No Python reimplementation of the base64/XOR decoder was found"

    for path in submission_python_files():
        try:
            source = open(path, "r", encoding="utf-8").read().lower()
        except (OSError, UnicodeError):
            continue
        assert "/app/decoder.bin" not in source, \
            f"Runtime Python code must not invoke decoder.bin: {path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
