#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import collections
import os
import random
import socket
import struct
import subprocess
import time
from pathlib import Path

import pytest

LIBDIR = Path("/app/libgraphdump-1.2.0")
SOURCE = Path("/home/user/backup_verifier.c")
BACKUP = Path("/home/user/backup.dat")
EXECUTABLE = Path("/tmp/backup_verifier_submission")
SERVER = None


def kill_port_8080_listeners():
    """Kill any process currently listening on TCP port 8080."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(proc.name))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in victims:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def stop_server():
    global SERVER
    if SERVER is not None:
        if SERVER.poll() is None:
            SERVER.terminate()
            try:
                SERVER.wait(timeout=2)
            except subprocess.TimeoutExpired:
                SERVER.kill()
                SERVER.wait(timeout=2)
        SERVER = None
    kill_port_8080_listeners()


atexit.register(stop_server)


def start_server():
    global SERVER
    stop_server()
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = str(LIBDIR) + ":" + env.get("LD_LIBRARY_PATH", "")
    SERVER = subprocess.Popen(
        [str(EXECUTABLE)],
        cwd="/home/user",
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if SERVER.poll() is not None:
            error = SERVER.stderr.read().decode("utf-8", "replace")
            pytest.fail(f"Compiled server exited before listening: {error}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("Compiled C server did not listen on 127.0.0.1:8080")


def ensure_server():
    if SERVER is None or SERVER.poll() is not None:
        start_server()


def send_query(query: str) -> str:
    """Helper to send a query to the TCP server and return the response."""
    ensure_server()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(("127.0.0.1", 8080))
        s.sendall(query.encode("ascii"))
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
        response = b"".join(chunks).decode("ascii")
    except Exception as e:
        pytest.fail(f"Failed to communicate with the server on 127.0.0.1:8080. Error: {e}")
    finally:
        s.close()
    return response


def test_c_source_exists():
    """Check that the student created the C program."""
    path = "/home/user/backup_verifier.c"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_library_build_and_compiled_server():
    stop_server()
    subprocess.run(["make", "clean"], cwd=LIBDIR, check=True, timeout=20)
    subprocess.run(["make"], cwd=LIBDIR, check=True, timeout=20)

    library = LIBDIR / "libgraphdump.so"
    assert library.is_file(), "make did not produce libgraphdump.so"
    header = subprocess.check_output(["readelf", "-h", str(library)], text=True)
    assert "DYN (Shared object file)" in header, "libgraphdump.so is not an ELF shared library"
    exports = subprocess.check_output(["nm", "-D", str(library)], text=True)
    assert " parse_graph_dump" in exports, "libgraphdump.so does not export parse_graph_dump"

    subprocess.run([
        "gcc", "-std=c11", "-Wall", "-Wextra",
        "-I", str(LIBDIR), str(SOURCE),
        "-L", str(LIBDIR), "-Wl,-rpath," + str(LIBDIR),
        "-lgraphdump", "-o", str(EXECUTABLE),
    ], check=True, timeout=30)

    needed = subprocess.check_output(["readelf", "-d", str(EXECUTABLE)], text=True)
    assert "libgraphdump.so" in needed, "Compiled server is not dynamically linked to libgraphdump.so"
    symbols = subprocess.check_output(["nm", "-D", str(EXECUTABLE)], text=True)
    assert " U parse_graph_dump" in symbols, "Compiled server does not reference parse_graph_dump"
    start_server()


def test_degree_queries():
    """Test the DEGREE command for various nodes."""
    resp = send_query("DEGREE 0\n")
    assert resp.strip() == "1", f"Expected DEGREE 0 to be 1, got {resp!r}"

    resp = send_query("DEGREE 1\n")
    assert resp.strip() == "2", f"Expected DEGREE 1 to be 2, got {resp!r}"

    resp = send_query("DEGREE 5\n")
    assert resp.strip() == "1", f"Expected DEGREE 5 to be 1, got {resp!r}"


def test_path_queries():
    """Test the PATH command for various node pairs."""
    resp = send_query("PATH 0 5\n")
    assert resp.strip() == "5", f"Expected PATH 0 5 to be 5, got {resp!r}"

    resp = send_query("PATH 2 4\n")
    assert resp.strip() == "2", f"Expected PATH 2 4 to be 2, got {resp!r}"

    resp = send_query("PATH 3 3\n")
    assert resp.strip() == "0", f"Expected PATH 3 3 to be 0, got {resp!r}"

    resp = send_query("PATH 5 0\n")
    assert resp.strip() == "5", f"Expected PATH 5 0 to be 5, got {resp!r}"


def expected_distances(n, edges):
    adjacency = [[] for _ in range(n)]
    for u, v in edges:
        adjacency[u].append(v)
        adjacency[v].append(u)
    result = {}
    for source in range(n):
        distance = [-1] * n
        distance[source] = 0
        queue = collections.deque([source])
        while queue:
            u = queue.popleft()
            for v in adjacency[u]:
                if distance[v] == -1:
                    distance[v] = distance[u] + 1
                    queue.append(v)
        for target in range(n):
            result[(source, target)] = distance[target]
    return adjacency, result


def test_responses_are_derived_from_backup_data():
    original = BACKUP.read_bytes()
    rng = random.SystemRandom()
    n = 9
    labels = list(range(n))
    rng.shuffle(labels)
    split = rng.randint(3, 6)
    groups = (labels[:split], labels[split:])
    edges = set()

    # Build two independently connected components with randomized topology.
    for group in groups:
        order = list(group)
        rng.shuffle(order)
        for index in range(1, len(order)):
            parent = rng.choice(order[:index])
            edges.add(tuple(sorted((order[index], parent))))
        for i, u in enumerate(group):
            for v in group[i + 1:]:
                if rng.random() < 0.30:
                    edges.add(tuple(sorted((u, v))))

    edge_list = list(edges)
    rng.shuffle(edge_list)
    payload = b"GDB1" + struct.pack("<ii", n, len(edge_list))
    payload += b"".join(struct.pack("<ii", u, v) for u, v in edge_list)
    adjacency, distances = expected_distances(n, edge_list)

    stop_server()
    try:
        BACKUP.write_bytes(payload)
        start_server()
        for node in range(n):
            response = send_query(f"DEGREE {node}\n")
            assert response.strip() == str(len(adjacency[node])), (
                f"Random-backup DEGREE {node}: expected {len(adjacency[node])}, got {response!r}"
            )
        for source in range(n):
            for target in range(n):
                expected = distances[(source, target)]
                response = send_query(f"PATH {source} {target}\n")
                assert response.strip() == str(expected), (
                    f"Random-backup PATH {source} {target}: expected {expected}, got {response!r}"
                )
    finally:
        stop_server()
        BACKUP.write_bytes(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
