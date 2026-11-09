#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import socket
import subprocess
import pytest

BASE_DIR = "/home/user/math_service"
SERVER_BIN = os.path.join(BASE_DIR, "math_server")
LIB_PATH = os.path.join(BASE_DIR, "libmathcore.so")


def test_patch_applied():
    mathcore_path = os.path.join(BASE_DIR, "mathcore.c")
    assert os.path.isfile(mathcore_path), f"{mathcore_path} is missing."
    with open(mathcore_path, "r") as f:
        content = f.read()
    assert "compute_factors_adv" in content, "The feature patch was not applied to mathcore.c"
    assert "ADVANCED" in content, "The patch content is missing from mathcore.c"


def test_server_c_validation():
    server_path = os.path.join(BASE_DIR, "server.c")
    assert os.path.isfile(server_path), f"{server_path} is missing."
    with open(server_path, "r") as f:
        content = f.read()
    assert "ERR_NEGATIVE" in content, "server.c does not contain the required 'ERR_NEGATIVE' string for validation."
    assert "< 0" in content or "<0" in content, "server.c does not seem to check if n < 0."


def test_binaries_exist():
    assert os.path.isfile(LIB_PATH), "libmathcore.so was not built or is missing."
    assert os.path.isfile(SERVER_BIN), "math_server was not built or is missing."


def test_rpath_configured():
    assert os.path.isfile(SERVER_BIN), "math_server binary is missing."
    try:
        output = subprocess.check_output(["readelf", "-d", SERVER_BIN], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run readelf on math_server: {e.output}")
    except FileNotFoundError:
        pytest.fail("readelf command not found. Cannot verify rpath.")

    has_rpath = False
    for line in output.splitlines():
        if "(RPATH)" in line or "(RUNPATH)" in line:
            if "ORIGIN" in line or BASE_DIR in line or "." in line:
                has_rpath = True
                break
    assert has_rpath, "math_server does not have correctly configured RPATH/RUNPATH pointing to the library location."


def test_shared_library_is_actually_linked():
    server_dynamic = subprocess.check_output(["readelf", "-d", SERVER_BIN], text=True, stderr=subprocess.STDOUT)
    assert re.search(r"\(NEEDED\).*\[libmathcore\.so\]", server_dynamic), \
        "math_server is not dynamically linked against libmathcore.so."

    server_symbols = subprocess.check_output(["readelf", "-Ws", SERVER_BIN], text=True, stderr=subprocess.STDOUT)
    assert re.search(r"\bUND\b.*\bcompute_factors_adv\b", server_symbols), \
        "math_server does not use compute_factors_adv from the shared library."

    lib_header = subprocess.check_output(["readelf", "-h", LIB_PATH], text=True, stderr=subprocess.STDOUT)
    assert "DYN (Shared object file)" in lib_header, "libmathcore.so is not an ELF shared library."
    lib_symbols = subprocess.check_output(["readelf", "-Ws", LIB_PATH], text=True, stderr=subprocess.STDOUT)
    assert re.search(r"\bGLOBAL\b.*\bcompute_factors_adv\b", lib_symbols), \
        "libmathcore.so does not export compute_factors_adv; ENABLE_ADV_MATH may be missing."


def test_test_results_log():
    log_path = os.path.join(BASE_DIR, "test_results.log")
    assert os.path.isfile(log_path), "test_results.log is missing."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "test_results.log does not contain at least 2 lines of output."
    assert lines[0] == "ERR_NEGATIVE", f"Expected first line to be 'ERR_NEGATIVE', got '{lines[0]}'."
    assert lines[1] == "ADVANCED:30", f"Expected second line to be 'ADVANCED:30', got '{lines[1]}'."


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    state = fields[3]
                    if local_port == port and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def listener_pids(port):
    wanted = {f"socket:[{inode}]" for inode in listening_socket_inodes(port)}
    found = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(os.path.join(proc_dir, "fd", "*")):
            try:
                if os.readlink(fd) in wanted:
                    found.add(int(proc_dir.rsplit("/", 1)[1]))
                    break
            except (FileNotFoundError, PermissionError, OSError):
                pass
    return found


def request(payload):
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
        sock.settimeout(2)
        sock.sendall(payload)
        chunks = []
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                pytest.fail("Server did not close the connection after responding.")
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)


def test_server_running():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        result = s.connect_ex(("127.0.0.1", 8080))
        assert result == 0, "Server is not running or listening on 127.0.0.1:8080."
    finally:
        s.close()


def test_math_server_binary_owns_listener():
    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080."
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", SERVER_BIN):
                matching.append(pid)
        except (FileNotFoundError, PermissionError, OSError):
            pass
    assert matching, "The process listening on port 8080 is not the built math_server executable."


def test_live_validation_and_advanced_calculation():
    rng = random.SystemRandom()
    positives = rng.sample(range(2, 1000000), 5)
    negatives = [-value for value in rng.sample(range(1, 1000000), 4)]

    for value in negatives:
        actual = request(f"{value}\n".encode("ascii"))
        assert actual == b"ERR_NEGATIVE\n", \
            f"Negative input {value} returned {actual!r}, not the required validation response."

    for value in positives:
        actual = request(f"{value}\n".encode("ascii"))
        expected = f"ADVANCED:{value * 2}\n".encode("ascii")
        assert actual == expected, \
            f"Positive input {value} returned {actual!r}; expected {expected!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
