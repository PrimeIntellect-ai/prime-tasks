#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import socket
import struct
import subprocess
import time
import pytest

HOST = "127.0.0.1"
SOURCE = "/home/user/mock_authz.c"
SCRIPT = "/home/user/build_and_deploy.sh"
BINARY = "/home/user/mock_authz"
PID_FILE = "/home/user/mock_authz.pid"
STATE = {"pids": set(), "source_process": None}


def read_spec():
    text = subprocess.check_output(
        ["tesseract", "/app/authz_spec.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    port_match = re.search(r"LISTEN_PORT\s*:\s*(\d+)", text)
    token_match = re.search(r"SERVICE_ID\s*:\s*([^\s]+)", text)
    assert port_match, f"Could not extract LISTEN_PORT from image OCR: {text!r}"
    assert token_match, f"Could not extract SERVICE_ID from image OCR: {text!r}"
    return int(port_match.group(1)), token_match.group(1).encode()


PORT, TOKEN = read_spec()
MAGIC = b"AUTZ"
WRONG_TOKEN = b"TKN-0000-WRONG"
WRONG_MAGIC = b"\x00\x00\x00\x00"
OKAY = b"OKAY"
FAIL = b"FAIL"

# Preserve the original task's concrete image-derived assertions.
assert PORT == 8088
assert TOKEN == b"TKN-9942-ALPHA"


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pid_owns_listener(pid, port):
    inodes = listening_inodes(port)
    if not inodes:
        return False
    try:
        for name in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{name}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return True
    except (FileNotFoundError, ProcessLookupError):
        return False
    return False


def terminate_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def kill_port_listeners(port):
    inodes = listening_inodes(port)
    if not inodes:
        return
    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            for fd in os.listdir(f"/proc/{entry}/fd"):
                try:
                    target = os.readlink(f"/proc/{entry}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    for pid in victims:
        terminate_pid(pid)


def wait_for_listener(pid, timeout=4.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pid_owns_listener(pid, PORT):
            return
        if not os.path.exists(f"/proc/{pid}"):
            break
        time.sleep(0.05)
    pytest.fail(f"PID {pid} did not establish the required listener on {HOST}:{PORT}")


def recv_exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            break
        data += chunk
    return data


def send_request(magic, payload, fragmented=False):
    packet = magic + struct.pack(">H", len(payload)) + payload
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(2.0)
        try:
            sock.connect((HOST, PORT))
            if fragmented:
                pos = 0
                while pos < len(packet):
                    amount = random.randint(1, min(5, len(packet) - pos))
                    sock.sendall(packet[pos:pos + amount])
                    pos += amount
            else:
                sock.sendall(packet)
            response = recv_exact(sock, 4)
            assert sock.recv(1) == b"", "Server did not close the connection after replying"
            return response
        except Exception as exc:
            pytest.fail(f"Connection or communication failed: {exc}")


@pytest.fixture(scope="session", autouse=True)
def build_and_start_submission():
    assert os.path.isfile(SOURCE), f"The C source code {SOURCE} is missing."
    assert os.path.isfile(SCRIPT), f"The build script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"The build script {SCRIPT} is not executable."

    # Remove any pre-existing service and artifacts so the submitted script must
    # actually recreate and launch the requested executable.
    if os.path.isfile(PID_FILE):
        try:
            old = open(PID_FILE).read().strip()
            if old.isdigit():
                terminate_pid(int(old))
        except OSError:
            pass
    kill_port_listeners(PORT)
    for path in (BINARY, PID_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT], cwd="/home/user", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=20
    )
    assert result.returncode == 0, "The build_and_deploy.sh script failed"
    assert os.path.isfile(BINARY), "The build script did not create /home/user/mock_authz"
    assert os.access(BINARY, os.X_OK), "The produced mock_authz is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The produced mock_authz is not a compiled ELF executable"

    assert os.path.isfile(PID_FILE), f"The PID file {PID_FILE} is missing."
    pid_text = open(PID_FILE).read().strip()
    assert pid_text.isdigit(), f"PID file {PID_FILE} does not contain a valid numeric PID."
    pid = int(pid_text)
    STATE["pids"].add(pid)
    assert os.path.exists(f"/proc/{pid}"), f"Process with PID {pid} is not running."
    assert os.path.samefile(f"/proc/{pid}/exe", BINARY), \
        f"PID {pid} is not the /home/user/mock_authz executable"
    wait_for_listener(pid)

    yield

    proc = STATE.get("source_process")
    if proc is not None and proc.poll() is None:
        terminate_pid(proc.pid)
    for running_pid in STATE["pids"]:
        terminate_pid(running_pid)
    kill_port_listeners(PORT)


def test_source_code_exists():
    assert os.path.isfile(SOURCE), "The C source code /home/user/mock_authz.c is missing."


def test_build_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"The build script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"The build script {SCRIPT} is not executable."


def test_pid_file_exists():
    assert os.path.isfile(PID_FILE), f"The PID file {PID_FILE} is missing."
    pid = open(PID_FILE).read().strip()
    assert pid.isdigit(), f"PID file {PID_FILE} does not contain a valid numeric PID."
    assert os.path.exists(f"/proc/{pid}"), f"Process with PID {pid} is not running."


def test_valid_request():
    assert send_request(MAGIC, TOKEN) == OKAY


def test_invalid_request_wrong_token():
    assert send_request(MAGIC, WRONG_TOKEN) == FAIL


def test_invalid_request_wrong_magic():
    assert send_request(WRONG_MAGIC, TOKEN) == FAIL


def test_submitted_c_source_compiles_and_handles_generated_packets():
    deployed_pid = int(open(PID_FILE).read().strip())
    terminate_pid(deployed_pid)
    kill_port_listeners(PORT)

    verified_binary = "/tmp/mock_authz_from_submitted_source"
    try:
        os.remove(verified_binary)
    except FileNotFoundError:
        pass
    compilation = subprocess.run(
        ["gcc", "-Wall", "-Wextra", SOURCE, "-o", verified_binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compilation.returncode == 0, f"Submitted C source did not compile:\n{compilation.stderr}"
    with open(verified_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    proc = subprocess.Popen([verified_binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    STATE["source_process"] = proc
    STATE["pids"].add(proc.pid)
    wait_for_listener(proc.pid)

    # Exercise the independently compiled C source, including generated payloads,
    # generated bad magic values, varied lengths, and fragmented TCP delivery.
    assert send_request(MAGIC, TOKEN, fragmented=True) == OKAY
    assert send_request(MAGIC, WRONG_TOKEN, fragmented=True) == FAIL
    assert send_request(WRONG_MAGIC, TOKEN, fragmented=True) == FAIL

    for _ in range(24):
        size = random.randint(0, 300)
        payload = os.urandom(size)
        if payload == TOKEN:
            payload += b"x"
        assert send_request(MAGIC, payload, fragmented=True) == FAIL

    for _ in range(12):
        bad_magic = os.urandom(4)
        while bad_magic == MAGIC:
            bad_magic = os.urandom(4)
        payload = TOKEN if random.choice((True, False)) else os.urandom(random.randint(0, 100))
        assert send_request(bad_magic, payload, fragmented=True) == FAIL
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
