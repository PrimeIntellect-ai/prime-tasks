#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_ecosystem.py
import os
import random
import re
import signal
import socket
import stat
import string
import subprocess
import time
import traceback

HOST = "127.0.0.1"
PORT = 8080
AUTH = b"AUTH: ecoweb2024\n"
SOURCE = "/home/user/ecosystem_server.cpp"
BINARY = "/home/user/server"
TRANSCRIPT = "/home/user/transcript.txt"
TEST_BINARY = "/tmp/verifier_ecosystem_server"
EXPECTED_EDGES = {
    ("Fox", "Rabbit"),
    ("Rabbit", "Grass"),
    ("Fox", "Mouse"),
    ("Owl", "Mouse"),
    ("Owl", "Fox"),
}


def assert_submission_files():
    assert os.path.isfile(SOURCE), f"Missing C++ source: {SOURCE}"
    assert not os.path.islink(SOURCE), "C++ source must be a regular file"
    assert os.path.getsize(SOURCE) > 0, "C++ source is empty"

    assert os.path.isfile(TRANSCRIPT), f"Missing transcript: {TRANSCRIPT}"
    assert not os.path.islink(TRANSCRIPT), "Transcript must be a regular file"
    with open(TRANSCRIPT, "r", encoding="utf-8", errors="replace") as f:
        transcript = f.read()
    assert transcript.strip(), "Transcript is empty"

    found = {
        (a.capitalize(), b.capitalize())
        for a, b in re.findall(r"\b([A-Za-z]+)\s+eats\s+([A-Za-z]+)\b", transcript, re.I)
    }
    assert found == EXPECTED_EDGES, (
        f"Transcript relationships do not match the audio. Found: {sorted(found)}"
    )

    assert os.path.isfile(BINARY), f"Missing compiled server: {BINARY}"
    mode = os.stat(BINARY).st_mode
    assert stat.S_ISREG(mode), "Compiled server is not a regular file"
    assert mode & 0o111, "Compiled server is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled server is not an ELF executable"
    return found


def compile_source():
    result = subprocess.run(
        ["g++", SOURCE, "-o", TEST_BINARY, "-pthread"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, f"C++ source failed to compile:\n{result.stdout}"


def listener_inodes():
    wanted = f"{PORT:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    return inodes


def kill_port_listener():
    inodes = listener_inodes()
    if not inodes:
        return
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(entry), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    time.sleep(0.2)


def wait_for_server(proc):
    deadline = time.time() + 6
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Compiled server exited early with status {proc.returncode}")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Could not connect to server at {HOST}:{PORT}. Is it running?")


def connect():
    sock = socket.create_connection((HOST, PORT), timeout=3)
    sock.settimeout(3)
    return sock


def read_line(sock):
    response = b""
    while b"\n" not in response:
        chunk = sock.recv(1024)
        if not chunk:
            break
        response += chunk
    return response.decode("utf-8")


def query(sock, node):
    sock.sendall(f"MATCH {node}\n".encode())
    return read_line(sock)


def test_original_assertions():
    with connect() as sock:
        sock.sendall(AUTH)
        resp = query(sock, "Fox")
        assert resp == "Mouse,Rabbit\n", f"Expected 'Mouse,Rabbit\\n' for Fox, got {resp!r}"
        resp = query(sock, "Owl")
        assert resp == "Fox,Mouse\n", f"Expected 'Fox,Mouse\\n' for Owl, got {resp!r}"
        resp = query(sock, "Rabbit")
        assert resp == "Grass\n", f"Expected 'Grass\\n' for Rabbit, got {resp!r}"
        resp = query(sock, "Grass")
        assert resp == "NONE\n", f"Expected 'NONE\\n' for Grass, got {resp!r}"
        resp = query(sock, "Bear")
        assert resp == "NONE\n", f"Expected 'NONE\\n' for Bear, got {resp!r}"


def test_all_transcribed_nodes(edges):
    graph = {}
    nodes = set()
    for source, target in edges:
        graph.setdefault(source, set()).add(target)
        nodes.update((source, target))

    unknown = "Unknown" + "".join(random.SystemRandom().choices(string.ascii_letters, k=16))
    requested = list(nodes) + [unknown]
    random.SystemRandom().shuffle(requested)

    with connect() as sock:
        # Fragment authentication to ensure the implementation processes complete lines.
        sock.sendall(b"AUTH: eco")
        sock.sendall(b"web2024\n")
        for node in requested:
            expected = ",".join(sorted(graph.get(node, ()))) + "\n" if graph.get(node) else "NONE\n"
            assert query(sock, node) == expected, f"Incorrect response for {node}"

    # Explicitly cover Mouse, which the old verifier omitted.
    with connect() as sock:
        sock.sendall(AUTH)
        sock.sendall(b"MATCH Mou")
        sock.sendall(b"se\n")
        assert read_line(sock) == "NONE\n"


def assert_connection_dropped(first_line):
    with connect() as sock:
        try:
            sock.sendall(first_line)
            sock.sendall(b"MATCH Fox\n")
            data = sock.recv(1024)
            assert data == b"", f"Server should close connection on invalid or missing auth, but responded: {data!r}"
        except (ConnectionResetError, BrokenPipeError):
            pass


def test_authentication():
    assert_connection_dropped(b"AUTH: badtoken\n")
    assert_connection_dropped(b"MATCH Fox\n")


def main():
    edges = assert_submission_files()
    compile_source()
    kill_port_listener()
    proc = subprocess.Popen(
        [TEST_BINARY],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_server(proc)
        test_original_assertions()
        test_all_transcribed_nodes(edges)
        test_authentication()
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        kill_port_listener()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        raise
PY_EOF

if python3 /tmp/verify_ecosystem.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
