#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import socket
import struct
import subprocess
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from io import BytesIO

SERVER_SOURCE = "/home/user/artifact_server.c"
SERVER_BINARY = "/home/user/artifact_server"
EXTRACTED_DIR = "/home/user/extracted_artifacts"
BASE_URL = "http://127.0.0.1:8888/curate"
TOKEN = "omega cipher nine"


def request(artifact, token=TOKEN):
    query = urllib.parse.urlencode({"artifact": artifact, "token": token})
    req = urllib.request.Request(BASE_URL + "?" + query, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=7) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
        raise AssertionError(f"Failed to contact service on port 8888: {exc}")


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def make_artifact(path, nonce, trailing=b""):
    elf_magic = b"\x7fELF"
    root_name = f"root_{nonce}"
    deep_name = f"deep_{nonce}"
    nested_name = f"zipped_{nonce}"
    text_name = f"notes_{nonce}.txt"
    zip_name = f"bundle_{nonce}.zip"

    files = {
        root_name: elf_magic + os.urandom(37),
        deep_name: elf_magic + os.urandom(53),
        nested_name: elf_magic + os.urandom(29),
        text_name: b"ordinary text " + os.urandom(17),
    }

    zip_buffer = BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"inside/{nested_name}", files[nested_name])
        zf.writestr(f"inside/zip_text_{nonce}.txt", b"not an executable")

    tar_buffer = BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w:gz") as tar:
        members = {
            root_name: files[root_name],
            f"sub/dir/{deep_name}": files[deep_name],
            text_name: files[text_name],
            f"archives/{zip_name}": zip_buffer.getvalue(),
        }
        for member_name, contents in members.items():
            info = tarfile.TarInfo(member_name)
            info.size = len(contents)
            info.mode = 0o755 if contents.startswith(elf_magic) else 0o644
            tar.addfile(info, BytesIO(contents))

    payload = tar_buffer.getvalue()
    with open(path, "wb") as f:
        f.write(b"ARTF" + struct.pack("<I", len(payload)) + payload + trailing)

    expected = {root_name, deep_name, nested_name}
    forbidden = {text_name, zip_name, f"zip_text_{nonce}.txt"}
    return expected, forbidden, files


def assert_success(path, expected, forbidden):
    status, body = request(path)
    assert status == 200, f"Expected HTTP 200 for {path}, got {status}: {body}"
    try:
        result = json.loads(body)
    except ValueError as exc:
        raise AssertionError(f"Response is not valid JSON: {body}") from exc
    assert isinstance(result, list), f"Expected a JSON array, got {type(result).__name__}"
    assert all(isinstance(item, str) for item in result), "All returned filenames must be strings"
    actual = set(result)
    assert expected.issubset(actual), f"Expected response to contain {expected}, got {actual}"
    assert actual.isdisjoint(forbidden), f"Non-ELF files were reported as executables: {actual & forbidden}"


def assert_extracted(expected, file_data):
    assert os.path.isdir(EXTRACTED_DIR), "Extraction directory was not created"
    found = {}
    for root, _, names in os.walk(EXTRACTED_DIR):
        for name in names:
            if name in expected:
                with open(os.path.join(root, name), "rb") as f:
                    found[name] = f.read()
    assert set(found) == expected, f"Not all ELF files were physically extracted; found {set(found)}"
    for name in expected:
        assert found[name] == file_data[name], f"Extracted contents of {name} do not match the archive"


def test_c_artifact_and_running_server():
    assert os.path.isfile(SERVER_SOURCE), f"Missing C source: {SERVER_SOURCE}"
    assert os.path.isfile(SERVER_BINARY), f"Missing compiled server: {SERVER_BINARY}"
    assert os.access(SERVER_BINARY, os.X_OK), "Compiled server is not executable"
    with open(SERVER_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "artifact_server is not an ELF binary"

    syntax = subprocess.run(
        ["gcc", "-fsyntax-only", SERVER_SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert syntax.returncode == 0, f"artifact_server.c is not valid C:\n{syntax.stderr}"

    pids = listening_pids(8888)
    assert pids, "No process is listening on TCP port 8888"
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", SERVER_BINARY):
                matching.append(pid)
        except OSError:
            pass
    assert matching, "The process listening on port 8888 is not /home/user/artifact_server"


def test_varied_artifacts_validation_and_extraction():
    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    os.makedirs(EXTRACTED_DIR, mode=0o777, exist_ok=True)
    os.chmod(EXTRACTED_DIR, 0o777)

    nonce1 = uuid.uuid4().hex[:12]
    artifact1 = f"/tmp/{uuid.uuid4().hex}.artf"
    expected1, forbidden1, data1 = make_artifact(artifact1, nonce1)
    assert_success(artifact1, expected1, forbidden1)
    assert_extracted(expected1, data1)

    status, _ = request(artifact1, "wrong-" + uuid.uuid4().hex)
    assert status == 401, f"Expected HTTP 401 for an invalid token, got {status}"

    nonexistent = f"/tmp/missing-{uuid.uuid4().hex}.artf"
    status, _ = request(nonexistent)
    assert status == 400, f"Expected HTTP 400 for a nonexistent artifact, got {status}"

    bad_magic = f"/tmp/{uuid.uuid4().hex}.artf"
    with open(bad_magic, "wb") as f:
        f.write(b"NOPE" + struct.pack("<I", 4) + b"junk")
    status, _ = request(bad_magic)
    assert status == 400, f"Expected HTTP 400 for invalid ARTF magic, got {status}"

    truncated = f"/tmp/{uuid.uuid4().hex}.artf"
    with open(truncated, "wb") as f:
        f.write(b"ARTF" + struct.pack("<I", 4096) + b"short")
    status, _ = request(truncated)
    assert status == 400, f"Expected HTTP 400 when declared payload bytes are missing, got {status}"

    nonce2 = uuid.uuid4().hex[:12]
    artifact2 = f"/tmp/{uuid.uuid4().hex}.artf"
    expected2, forbidden2, data2 = make_artifact(
        artifact2, nonce2, trailing=b"TRAILING-DATA-OUTSIDE-PAYLOAD-" + os.urandom(31)
    )
    assert_success(artifact2, expected2, forbidden2)
    assert_extracted(expected2, data2)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
