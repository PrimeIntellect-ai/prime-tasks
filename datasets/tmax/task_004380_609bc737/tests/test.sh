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
import csv
import json
import os
import secrets
import socket
import subprocess
import tempfile
import time

import pytest
import requests

BINARY = "/usr/local/bin/archive_server"
CONFIG = "/etc/backup_config.json"


def assert_binary_exists():
    assert os.path.exists(BINARY), f"Binary {BINARY} does not exist. Did you compile your C++ code to this location?"
    assert os.path.isfile(BINARY), f"{BINARY} is not a file."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled native executable."


def get_expected_files(csv_path, dat_path):
    assert os.path.exists(csv_path), f"Missing {csv_path}"
    assert os.path.exists(dat_path), f"Missing {dat_path}"

    files = {}
    with open(csv_path, newline="") as f:
        for row in csv.reader(f):
            if not row or len(row) < 3:
                continue
            filename, offset, length = row[0], int(row[1]), int(row[2])
            files[filename] = (offset, length)

    expected = {}
    with open(dat_path, "rb") as f:
        for filename, (offset, length) in files.items():
            f.seek(offset)
            data = f.read(length)
            expected[filename] = bytes(b ^ 0x5A for b in data)
    return expected


def request(url, timeout=2):
    try:
        return requests.get(url, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP service at {url}. Is the server running? Error: {exc}")


def check_service(port, expected, missing_name):
    assert expected, "No files found in the archive to test."
    for filename, expected_data in expected.items():
        url = f"http://127.0.0.1:{port}/file/{filename}"
        response = request(url)
        assert response.status_code == 200, f"Expected status code 200 for {filename}, got {response.status_code}"
        assert response.content == expected_data, f"Content mismatch for {filename}. Expected {expected_data!r}, got {response.content!r}"

    url = f"http://127.0.0.1:{port}/file/{missing_name}"
    response = request(url)
    assert response.status_code == 404, f"Expected status code 404 for nonexistent file, got {response.status_code}"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for_server(port, missing_name, process):
    url = f"http://127.0.0.1:{port}/file/{missing_name}"
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"archive_server exited during startup with status {process.returncode}")
        try:
            requests.get(url, timeout=0.3)
            return
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"archive_server did not listen on configured port {port}: {last_error}")


def test_archive_server_end_to_end():
    assert_binary_exists()

    # Preserve the original assertions against the service the agent was required
    # to leave running and the production archive supplied by the task.
    production = get_expected_files(
        "/var/backups/production.csv", "/var/backups/production.dat"
    )
    check_service(9000, production, "this_file_does_not_exist_12345.txt")

    # Build a fresh archive with unpredictable names, contents, paths, and port,
    # then restart the submitted artifact so it must read the current config/index.
    original_config = open(CONFIG, "rb").read()
    token = secrets.token_hex(12)
    process = None
    with tempfile.TemporaryDirectory(prefix="archive_verify_") as tempdir:
        source_dir = os.path.join(tempdir, "input")
        os.mkdir(source_dir)
        generated = {
            f"alpha_{token}.txt": b"dynamic archive test: " + secrets.token_bytes(37),
            f"binary_{token}.bin": bytes(range(256)) + secrets.token_bytes(513),
            f"large_{token}.dat": secrets.token_bytes(65539),
            f"empty_{token}.dat": b"",
        }
        for name, content in generated.items():
            with open(os.path.join(source_dir, name), "wb") as f:
                f.write(content)

        archive_path = os.path.join(tempdir, f"archive_{token}.dat")
        index_path = os.path.join(tempdir, f"index_{token}.csv")
        subprocess.run(
            ["/app/legacy_archiver", source_dir, archive_path, index_path],
            check=True,
        )
        expected = get_expected_files(index_path, archive_path)
        assert expected == generated

        port = free_port()
        missing = f"missing_{secrets.token_hex(16)}.txt"
        with open(CONFIG, "w") as f:
            json.dump(
                {"archive_path": archive_path, "index_path": index_path, "port": port},
                f,
            )
            f.flush()
            os.fsync(f.fileno())

        subprocess.run(
            ["pkill", "-f", BINARY],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        time.sleep(0.2)

        try:
            process = subprocess.Popen(
                [BINARY],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            wait_for_server(port, missing, process)
            check_service(port, expected, missing)
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
            subprocess.run(
                ["pkill", "-f", BINARY],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            with open(CONFIG, "wb") as f:
                f.write(original_config)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
