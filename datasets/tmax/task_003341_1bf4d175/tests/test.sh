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
import struct
import requests
import socket
import pytest

def get_all_records():
    """Parse all generated WAL data files to extract records."""
    records = {}
    wal_dir = "/app/wal_data"
    if not os.path.isdir(wal_dir):
        return records

    for fname in os.listdir(wal_dir):
        fpath = os.path.join(wal_dir, fname)
        is_generated_wal = (
            fname.startswith("wal_")
            and fname.endswith(".dat")
            and fname[4:-4].isdigit()
        )
        if os.path.isfile(fpath) and not os.path.islink(fpath) and is_generated_wal:
            with open(fpath, "rb") as f:
                while True:
                    header = f.read(4)
                    if not header:
                        break
                    if header != b"WALR":
                        break
                    meta = f.read(8)
                    if len(meta) < 8:
                        break
                    rec_id, length = struct.unpack("<II", meta)
                    payload = f.read(length)
                    if len(payload) < length:
                        break
                    records[rec_id] = payload.decode('ascii')
    return records

def test_archive_service_files_exist():
    """Check if the C++ source and binary exist."""
    assert os.path.isfile("/home/user/archive_service.cpp"), "Source file /home/user/archive_service.cpp is missing."
    assert os.path.isfile("/home/user/archive_service"), "Compiled binary /home/user/archive_service is missing."
    assert os.access("/home/user/archive_service", os.X_OK), "/home/user/archive_service is not executable."

def test_services_listening():
    """Check if ports 8000 (nginx) and 8080 (C++ service) are open."""
    def is_port_open(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            return s.connect_ex(('127.0.0.1', port)) == 0

    assert is_port_open(8000), "Nginx is not listening on port 8000."
    assert is_port_open(8080), "C++ archive service is not listening on port 8080."

def test_nginx_proxy_valid_records():
    """Test that nginx correctly proxies valid record requests to the C++ service."""
    records = get_all_records()
    assert records, "No records found in WAL files to test against."

    # Test a few records
    test_ids = list(records.keys())[:5]
    for rec_id in test_ids:
        expected_payload = records[rec_id]
        url = f"http://127.0.0.1:8000/api/record/{rec_id}"

        try:
            response = requests.get(url, timeout=2)
        except requests.RequestException as e:
            pytest.fail(f"Request to {url} failed: {e}")

        assert response.status_code == 200, f"Expected status 200 for record {rec_id}, got {response.status_code}"
        assert response.text == expected_payload, f"Payload mismatch for record {rec_id}. Expected '{expected_payload}', got '{response.text}'"

def test_nginx_proxy_invalid_record():
    """Test that requesting a non-existent record returns 404."""
    records = get_all_records()
    # Find an ID that definitely doesn't exist
    invalid_id = 99999999
    while invalid_id in records:
        invalid_id += 1

    url = f"http://127.0.0.1:8000/api/record/{invalid_id}"
    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Request to {url} failed: {e}")

    assert response.status_code == 404, f"Expected status 404 for invalid record {invalid_id}, got {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
