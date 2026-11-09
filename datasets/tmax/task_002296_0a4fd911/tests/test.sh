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
import hashlib
import io
import os
import re
import secrets
import socket
import tarfile

import pytest
import requests

APP_DIR = "/app/micro-tar-server-1.0"
BINARY = os.path.join(APP_DIR, "micro-tar-server")
DATASET_DIR = "/home/user/dataset_active"
SERVER_URL = "http://127.0.0.1:8080/archive"
TOKEN = "ds-secret-token"


def get_file_checksum(filepath):
    hasher = hashlib.sha256()
    with open(filepath, "rb") as f:
        while True:
            chunk = f.read(8192)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest()


def strip_c_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def listening_socket_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    _, port_hex = local_address.rsplit(":", 1)
                    if int(port_hex, 16) == 8080:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def process_owns_socket(pid, socket_inodes):
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in socket_inodes:
                return True
    except OSError:
        return False
    return False


def test_fixed_source_was_compiled_and_is_the_listener():
    assert os.path.isfile(BINARY), "Compiled micro-tar-server executable is missing."
    assert os.access(BINARY, os.X_OK), "micro-tar-server is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "micro-tar-server is not a compiled ELF executable."

    with open(os.path.join(APP_DIR, "server.c"), encoding="utf-8") as f:
        server_source = strip_c_comments(f.read())
    with open(os.path.join(APP_DIR, "tar_stream.c"), encoding="utf-8") as f:
        tar_source = strip_c_comments(f.read())

    assert re.search(r"#\s*define\s+DEFAULT_PORT\s+8080\b", server_source), \
        "server.c does not set the default port to 8080."
    assert re.search(r"\blstat\s*\(", tar_source), \
        "tar_stream.c does not inspect paths with lstat()."
    assert re.search(r"\bS_ISLNK\s*\(", tar_source), \
        "tar_stream.c does not branch on symbolic links."
    assert re.search(r"\breadlink\s*\(", tar_source), \
        "tar_stream.c does not obtain symbolic-link targets."

    binary_mtime = os.stat(BINARY).st_mtime_ns
    for source_name in ("server.c", "tar_stream.c", "tar_stream.h"):
        assert binary_mtime >= os.stat(os.path.join(APP_DIR, source_name)).st_mtime_ns, \
            f"micro-tar-server was not compiled after {source_name} was modified."

    socket_inodes = listening_socket_inodes()
    assert socket_inodes, "Nothing is listening on TCP port 8080."

    matching_pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            executable = os.path.realpath(f"/proc/{entry}/exe")
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().split(b"\0")
        except (OSError, ProcessLookupError):
            continue
        if executable == os.path.realpath(BINARY) and process_owns_socket(entry, socket_inodes):
            matching_pids.append((entry, cmdline))

    assert matching_pids, "The process listening on port 8080 is not the compiled micro-tar-server."
    assert any(os.fsencode(DATASET_DIR) in cmdline for _, cmdline in matching_pids), \
        "The running micro-tar-server was not started with dataset_active as its argument."


def test_authentication_and_live_dynamic_archive():
    try:
        unauthorized = requests.get(SERVER_URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {SERVER_URL}: {exc}")
    assert unauthorized.status_code == 401, \
        f"Expected an unauthenticated request to return 401, got {unauthorized.status_code}."

    nonce = secrets.token_hex(12)
    dynamic_dir = os.path.join(DATASET_DIR, "verify_" + nonce)
    os.mkdir(dynamic_dir)
    dynamic_file = os.path.join(dynamic_dir, "payload_" + nonce + ".bin")
    dynamic_content = secrets.token_bytes(32791)
    with open(dynamic_file, "wb") as f:
        f.write(dynamic_content)
    os.symlink(os.path.basename(dynamic_file), os.path.join(dynamic_dir, "link_" + nonce))
    dangling_target = "missing_" + secrets.token_hex(8)
    os.symlink(dangling_target, os.path.join(dynamic_dir, "dangling_" + nonce))

    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.get(SERVER_URL, headers=headers, timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {SERVER_URL}: {exc}")

    assert response.status_code == 200, \
        f"Expected status code 200, got {response.status_code}. Response: {response.text[:100]}"

    try:
        with tarfile.open(fileobj=io.BytesIO(response.content), mode="r:") as tar:
            tar_members = tar.getmembers()
            assert len(tar_members) > 0, "Tar archive is empty."

            tar_files = {}
            for member in tar_members:
                name = member.name.lstrip("./")
                tar_files[name] = member

            for root, dirs, files in os.walk(DATASET_DIR):
                for name in files + dirs:
                    abs_path = os.path.join(root, name)
                    rel_path = os.path.relpath(abs_path, DATASET_DIR)
                    if rel_path == ".":
                        continue

                    assert rel_path in tar_files, \
                        f"Expected path '{rel_path}' not found in the tar archive."
                    member = tar_files[rel_path]

                    if os.path.islink(abs_path):
                        target = os.readlink(abs_path)
                        assert member.issym(), \
                            f"Expected '{rel_path}' to be a symlink in the tar archive."
                        assert member.linkname == target, \
                            f"Symlink '{rel_path}' target mismatch. Expected '{target}', got '{member.linkname}'."
                    elif os.path.isfile(abs_path):
                        assert member.isfile(), \
                            f"Expected '{rel_path}' to be a regular file in the tar archive."
                        assert member.size == os.path.getsize(abs_path), \
                            f"File size mismatch for '{rel_path}'."
                        f_tar = tar.extractfile(member)
                        assert f_tar is not None, f"Could not extract file '{rel_path}' from tar archive."
                        tar_content = f_tar.read()
                        expected_checksum = get_file_checksum(abs_path)
                        assert hashlib.sha256(tar_content).hexdigest() == expected_checksum, \
                            f"Checksum mismatch for '{rel_path}'."
    except tarfile.ReadError:
        pytest.fail("The response could not be parsed as a valid tar archive.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
