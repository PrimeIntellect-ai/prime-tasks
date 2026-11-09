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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import socket
import time
import zipfile

import pytest
import requests

RAW_DIR = "/home/user/raw_logs"
ARCHIVE_DIR = "/home/user/archived_logs"
STAMP = "20991231_235959"
LOG_PATH = os.path.join(RAW_DIR, f"log_{STAMP}.log")
DONE_PATH = os.path.join(RAW_DIR, f"log_{STAMP}.done")
ARCHIVE_PATH = os.path.join(ARCHIVE_DIR, f"archive_{STAMP}.zip")
LATEST_PATH = os.path.join(ARCHIVE_DIR, "latest.zip")
PAYLOAD = bytes((i * 37 + 11) % 256 for i in range(250123))


def recv_line(command):
    with socket.create_connection(("127.0.0.1", 9090), timeout=5) as sock:
        sock.sendall(command.encode("ascii") + b"\n")
        sock.settimeout(5)
        data = b""
        while not data.endswith(b"\n"):
            part = sock.recv(1024)
            assert part, "TCP server closed the connection before sending a newline"
            data += part
            assert len(data) < 4096, "TCP response is unexpectedly large"
        return data.decode("utf-8")


def archive_names():
    return sorted(
        name for name in os.listdir(ARCHIVE_DIR)
        if name.startswith("archive_") and name.endswith(".zip")
        and os.path.isfile(os.path.join(ARCHIVE_DIR, name))
    )


def stable_latest_target():
    for _ in range(20):
        assert os.path.islink(LATEST_PATH), "latest.zip must be a symbolic link"
        before = os.readlink(LATEST_PATH)
        target = os.path.realpath(LATEST_PATH)
        names = archive_names()
        after = os.readlink(LATEST_PATH)
        if before == after and names:
            assert os.path.dirname(target) == os.path.realpath(ARCHIVE_DIR), "latest.zip points outside archived_logs"
            assert os.path.isfile(target), "latest.zip points to a missing archive"
            newest = max(names, key=lambda n: os.path.getmtime(os.path.join(ARCHIVE_DIR, n)))
            if os.path.basename(target) == newest:
                return os.path.basename(target)
        time.sleep(0.2)
    pytest.fail("latest.zip does not stably point to the most recently created archive")


def test_complete_pipeline_and_services():
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(ARCHIVE_DIR, exist_ok=True)

    for path in (DONE_PATH, LOG_PATH, ARCHIVE_PATH):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    with open(LOG_PATH, "wb") as f:
        f.write(PAYLOAD)
        f.flush()
        os.fsync(f.fileno())
    with open(DONE_PATH, "wb"):
        pass

    deadline = time.time() + 30
    while time.time() < deadline:
        if os.path.isfile(ARCHIVE_PATH) and not os.path.exists(LOG_PATH) and not os.path.exists(DONE_PATH):
            try:
                with zipfile.ZipFile(ARCHIVE_PATH) as z:
                    if z.testzip() is None:
                        break
            except (OSError, zipfile.BadZipFile):
                pass
        time.sleep(0.25)
    else:
        pytest.fail("The canary .done file was not processed, archived, and cleaned up")

    assert not os.path.exists(LOG_PATH), "Processed original .log file was not deleted"
    assert not os.path.exists(DONE_PATH), "Processed .done marker was not deleted"

    with zipfile.ZipFile(ARCHIVE_PATH) as z:
        file_list = sorted(z.namelist())
        assert len(file_list) > 0, "The ZIP archive is empty"
        assert all(not z.getinfo(name).is_dir() for name in file_list), "Archive contains directory entries instead of chunks"
        assert len(file_list) == 3, "250123 bytes must be split into exactly three chunks"
        rebuilt = b""
        for i, filename in enumerate(file_list):
            info = z.getinfo(filename)
            if i < len(file_list) - 1:
                assert info.file_size == 102400, f"Chunk {filename} is {info.file_size} bytes, expected 102400 bytes"
            else:
                assert info.file_size <= 102400, f"Last chunk {filename} is {info.file_size} bytes, expected <= 102400 bytes"
                assert info.file_size == 45323, f"Last chunk {filename} has the wrong size"
            rebuilt += z.read(filename)
        assert rebuilt == PAYLOAD, "Archived chunks do not reconstruct the processed log byte-for-byte"

    latest_name = stable_latest_target()
    assert latest_name.startswith("archive_") and latest_name.endswith(".zip")

    count_verified = False
    for _ in range(10):
        before = archive_names()
        response = recv_line("COUNT")
        after = archive_names()
        assert response.endswith("\n"), "COUNT response must end with a newline"
        count_str = response.strip()
        assert count_str.isdigit(), f"COUNT response must be a number, got: {count_str}"
        assert int(count_str) > 0, "COUNT must be greater than 0 since the generator is running"
        if before == after and int(count_str) == len(after):
            count_verified = True
            break
        time.sleep(0.2)
    assert count_verified, "COUNT does not equal the number of archive ZIP files"

    latest_verified = False
    for _ in range(10):
        before = stable_latest_target()
        response = recv_line("LATEST")
        after = stable_latest_target()
        assert response.endswith("\n"), "LATEST response must end with a newline"
        latest_str = response.strip()
        assert latest_str.startswith("archive_") and latest_str.endswith(".zip"), f"LATEST response must be an archive filename, got: {latest_str}"
        if before == after and latest_str == after:
            latest_verified = True
            break
        time.sleep(0.2)
    assert latest_verified, "LATEST does not report the basename targeted by latest.zip"

    response = None
    downloaded_name = None
    for _ in range(10):
        try:
            before = stable_latest_target()
            candidate = requests.get("http://127.0.0.1:8080/latest.zip", timeout=5)
            after = stable_latest_target()
            if candidate.status_code == 200 and before == after:
                response = candidate
                downloaded_name = after
                break
        except requests.RequestException:
            pass
        time.sleep(0.5)
    assert response is not None, "Failed to fetch a stable latest.zip via HTTP GET"
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    with open(os.path.join(ARCHIVE_DIR, downloaded_name), "rb") as f:
        assert response.content == f.read(), "HTTP latest.zip does not match the archive targeted by the symlink"

    try:
        with zipfile.ZipFile(io.BytesIO(response.content)) as z:
            file_list = sorted(z.namelist())
            assert len(file_list) > 0, "The ZIP archive is empty"
            for i, filename in enumerate(file_list):
                info = z.getinfo(filename)
                if i < len(file_list) - 1:
                    assert info.file_size == 102400, f"Chunk {filename} is {info.file_size} bytes, expected 102400 bytes"
                else:
                    assert info.file_size <= 102400, f"Last chunk {filename} is {info.file_size} bytes, expected <= 102400 bytes"
    except zipfile.BadZipFile:
        pytest.fail("The downloaded payload is not a valid ZIP archive")

    assert os.path.isdir(RAW_DIR), f"Directory {RAW_DIR} does not exist"
    done_files = [f for f in os.listdir(RAW_DIR) if f.endswith(".done")]
    assert len(done_files) < 10, "Cleanup does not appear to be working; too many .done files left behind"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
