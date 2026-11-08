#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import tarfile
import time
from pathlib import PurePosixPath

import pytest

DOCS_DIR = "/home/user/docs_clean"
SCRIPT_PATH = "/home/user/serve.sh"
ARCHIVE_PATH = "/home/user/patch.tar.gz"

EXPECTED_DOCS = {
    "index.md": b"# Main Index\nDRAFT_STATUS: FINAL\nWelcome to the project v2.\n",
    "api.md": b"# API\nDRAFT_STATUS: FINAL\nAPI is stable.\n",
    "new_feature.md": b"# New Feature\nDRAFT_STATUS: FINAL\nThis is a new feature.\n",
}

CORRECT_REQUEST = b"PROJECT_CODE: blue flying eagle\n"
EXPECTED_GRANTED = b"ACCESS_GRANTED\n" + EXPECTED_DOCS["index.md"]
EXPECTED_DENIED = b"ACCESS_DENIED\n"


def _port_listener_pids(port=8000):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def _kill_existing_listeners():
    pids = _port_listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in _port_listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _process_name(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            comm = f.read().strip()
    except OSError:
        comm = ""
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        exe = ""
    return comm, exe


def _is_descendant_or_self(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                data = f.read()
            pid = int(data[data.rfind(")") + 2:].split()[1])
        except (OSError, ValueError, IndexError):
            return False
    return False


def _request(payload):
    with socket.create_connection(("127.0.0.1", 8000), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(payload)
        response = bytearray()
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                pytest.fail("TCP server did not close the connection after its response.")
            if not chunk:
                return bytes(response)
            response.extend(chunk)


@pytest.fixture(scope="session")
def running_server():
    assert os.path.isfile(SCRIPT_PATH), f"Required Bash server script {SCRIPT_PATH} is missing."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a real script, not a symlink."

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        script = f.read()

    first_line = script.splitlines()[0] if script.splitlines() else ""
    assert re.match(r"^#!.*\b(?:bash|/bin/bash)\b", first_line), \
        "serve.sh must identify Bash as its interpreter."

    code_without_comments = "\n".join(
        line.split("#", 1)[0] for line in script.splitlines()[1:]
    )
    assert re.search(r"(^|[;&|()\s])(?:nc|netcat|socat)(?=$|[;&|()\s])", code_without_comments), \
        "serve.sh must actually invoke nc/netcat or socat."
    assert re.search(r"\b(?:while|until)\b", code_without_comments), \
        "serve.sh must contain a continuous Bash loop."
    assert not re.search(r"(^|[;&|()\s])(?:python(?:3)?|node|nodejs)(?=$|[;&|()\s])", code_without_comments), \
        "External programming languages may not be used by the server."

    _kill_existing_listeners()
    proc = subprocess.Popen(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    listener_pids = set()
    deadline = time.time() + 6
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"serve.sh exited before establishing the listener (status {proc.returncode}).")
        listener_pids = _port_listener_pids()
        if listener_pids:
            break
        time.sleep(0.1)

    assert listener_pids, "serve.sh did not bind TCP port 8000."
    valid_listener = False
    details = []
    for pid in listener_pids:
        comm, exe = _process_name(pid)
        details.append((pid, comm, exe))
        is_net_tool = any(
            name == "socat" or name == "nc" or name == "netcat" or name.startswith("nc.")
            for name in (comm, exe)
        )
        if is_net_tool and _is_descendant_or_self(pid, proc.pid):
            valid_listener = True
    assert valid_listener, \
        f"Port 8000 must be listened on by nc/netcat or socat launched by serve.sh; found {details}."

    yield proc

    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_no_path_traversal():
    """Ensure the malicious file was not extracted outside the target directory."""
    path = "/home/user/hacked.txt"
    assert not os.path.exists(path), f"Path traversal vulnerability triggered: {path} exists."


def test_docs_clean_files_and_content():
    """Verify the complete intended tree was safely extracted and exactly edited."""
    assert os.path.isdir(DOCS_DIR), f"Expected directory {DOCS_DIR} is missing."
    found = set()
    for root, dirs, files in os.walk(DOCS_DIR, followlinks=False):
        for name in dirs:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symlink in documentation tree: {path}"
        for name in files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symlink in documentation tree: {path}"
            rel = os.path.relpath(path, DOCS_DIR).replace(os.sep, "/")
            found.add(rel)

    assert found == set(EXPECTED_DOCS), \
        f"docs_clean must contain exactly the intended files; found {sorted(found)}"

    for rel, expected in EXPECTED_DOCS.items():
        filepath = os.path.join(DOCS_DIR, rel)
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing."
        with open(filepath, "rb") as f:
            content = f.read()
        assert content == expected, f"File {filepath} was not fully and exactly preserved/edited."
        assert b"DRAFT_STATUS: FINAL" in content, f"File {filepath} lacks DRAFT_STATUS: FINAL."
        assert b"DRAFT_STATUS: INCOMPLETE" not in content, f"File {filepath} remains incomplete."
        if rel == "index.md":
            assert b"Welcome to the project v2." in content


def test_patch_tar_gz_exists_and_contents():
    """Verify the incremental archive contains exactly the changed/new files and their bytes."""
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} is missing."
    seen = {}
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and ".." not in path.parts, \
                f"Unsafe path in patch archive: {member.name}"
            assert not member.issym() and not member.islnk(), \
                f"Links are not valid documentation backups: {member.name}"
            if member.isdir():
                continue
            assert member.isfile(), f"Unexpected non-file archive entry: {member.name}"
            basename = path.name
            assert basename in EXPECTED_DOCS, f"Unchanged or unrelated file in patch: {member.name}"
            assert basename not in seen, f"Duplicate documentation file in patch: {member.name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            seen[basename] = extracted.read()

    expected_basenames = set(EXPECTED_DOCS)
    assert set(seen) == expected_basenames, \
        f"Patch entries differ from changed/new file set: found {sorted(seen)}"
    for basename, expected in EXPECTED_DOCS.items():
        assert seen[basename] == expected, \
            f"Patch contains incorrect content for {basename}."


def test_tcp_server_correct_code(running_server):
    """Verify exact grant response and complete canonical index content."""
    response = _request(CORRECT_REQUEST)
    assert response == EXPECTED_GRANTED, f"Incorrect successful response: {response!r}"

    # A second input line must not produce a second response or alter the first-line result.
    response = _request(CORRECT_REQUEST + b"THIS SECOND LINE MUST BE IGNORED\n")
    assert response == EXPECTED_GRANTED, f"Server did not process exactly one request line: {response!r}"


def test_tcp_server_incorrect_code(running_server):
    """Verify exact denial responses and continuous operation."""
    for payload in (
        b"PROJECT_CODE: wrong code\n",
        b"PROJECT_CODE: blue flying eaglE\n",
        b"unrelated request\n",
    ):
        response = _request(payload)
        assert response == EXPECTED_DENIED, f"Expected exact ACCESS_DENIED response, got: {response!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
