#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import signal
import socket
import subprocess
import tempfile
import time

import pytest

HOST = "127.0.0.1"
PORT = 8080
SOURCE = "/home/user/topology_server.cpp"
BINARY = "/home/user/topology_server"
REBUILT = "/tmp/topology_server_rebuilt"


def send_command(cmd: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((HOST, PORT))
        s.sendall(cmd.encode("utf-8"))
        response = b""
        while b"\n" not in response:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
        return response.decode("utf-8")


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == PORT:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pids():
    inodes = listener_inodes()
    pids = set()
    if not inodes:
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_listener():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2.0
        while time.time() < deadline and listener_pids():
            time.sleep(0.05)


def start_server(path):
    stop_listener()
    proc = subprocess.Popen(
        [path], cwd="/home/user", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 5.0
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                return proc
        except OSError:
            if proc.poll() is not None and not listener_pids():
                pytest.fail(f"{path} exited before opening 127.0.0.1:8080")
            time.sleep(0.05)
    proc.terminate()
    pytest.fail(f"{path} did not listen on 127.0.0.1:8080")


def extract_graph():
    with tempfile.TemporaryDirectory() as d:
        pattern = os.path.join(d, "frame_%02d.png")
        subprocess.run(
            ["ffmpeg", "-v", "error", "-i", "/app/backup_topology.mp4",
             "-vf", "fps=1", pattern],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        payloads = []
        for name in sorted(os.listdir(d)):
            if not name.endswith(".png"):
                continue
            result = subprocess.run(
                ["zbarimg", "--quiet", "--raw", os.path.join(d, name)],
                check=True, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            for line in result.stdout.splitlines():
                line = line.strip()
                if line:
                    payloads.append(json.loads(line))

    assert payloads, "No QR payloads could be decoded from the supplied video"
    graph = {}
    for payload in payloads:
        assert isinstance(payload, dict) and isinstance(payload.get("edges"), list)
        for edge in payload["edges"]:
            assert isinstance(edge, list) and len(edge) == 3
            a, b, weight = edge
            assert isinstance(a, str) and isinstance(b, str)
            assert isinstance(weight, int) and weight >= 0
            graph.setdefault(a, {})[b] = weight
            graph.setdefault(b, {})[a] = weight
    return graph


def shortest_path(graph, src, dst):
    queue = [(0, (src,), src)]
    best = {src: 0}
    while queue:
        distance, path, node = heapq.heappop(queue)
        if distance != best.get(node):
            continue
        if node == dst:
            return list(path), distance
        for neighbor, weight in graph[node].items():
            candidate = distance + weight
            if candidate < best.get(neighbor, float("inf")):
                best[neighbor] = candidate
                heapq.heappush(queue, (candidate, path + (neighbor,), neighbor))
    raise AssertionError(f"No path from {src} to {dst}")


def exercise_server(graph):
    responses = {}
    nodes = sorted(graph)

    # Cover every valid degree query and every ordered source/destination pair.
    for node in nodes:
        response = send_command(f"DEGREE {node}\n")
        expected = f"{len(graph[node])}\n"
        assert response == expected, (
            f"DEGREE {node}: expected {expected!r}, got {response!r}"
        )
        responses[("DEGREE", node)] = response

    for src in nodes:
        for dst in nodes:
            path, distance = shortest_path(graph, src, dst)
            expected = f"{','.join(path)} {distance}\n"
            response = send_command(f"PATH {src} {dst}\n")
            assert response == expected, (
                f"PATH {src} {dst}: expected {expected!r}, got {response!r}"
            )
            responses[("PATH", src, dst)] = response

    # Preserve the original verifier's exact assertions.
    assert responses[("PATH", "db1", "db5")] == "db1,db2,db5 35\n"
    assert responses[("PATH", "db3", "db2")] == "db3,db1,db2 25\n"
    assert responses[("DEGREE", "db4")] == "3\n"
    assert responses[("DEGREE", "db1")] == "2\n"

    # Malformed requests must not produce arbitrary client output or kill the service.
    for malformed in ("\n", "BOGUS db1\n", "PATH db1\n", "DEGREE db1 extra\n"):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.4)
            s.connect((HOST, PORT))
            s.sendall(malformed.encode("utf-8"))
            s.shutdown(socket.SHUT_WR)
            try:
                data = s.recv(4096)
            except socket.timeout:
                data = b""
            assert data == b"", f"Malformed request produced output: {data!r}"

    node = nodes[0]
    assert send_command(f"DEGREE {node}\n") == f"{len(graph[node])}\n"


def test_source_and_binary_exist_and_compile():
    assert os.path.exists(SOURCE), "C++ source file /home/user/topology_server.cpp is missing"
    assert os.path.isfile(SOURCE), "C++ source path is not a regular file"
    assert os.path.exists(BINARY), "Compiled binary /home/user/topology_server is missing"
    assert os.path.isfile(BINARY), "Compiled binary path is not a regular file"
    assert os.access(BINARY, os.X_OK), "Binary /home/user/topology_server is not executable"

    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-pthread", SOURCE, "-o", REBUILT],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"C++ source failed to compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_complete_topology_service():
    graph = extract_graph()
    assert set(graph) == {"db1", "db2", "db3", "db4", "db5"}

    # Test both the submitted executable and a fresh build of the submitted source.
    for executable in (BINARY, REBUILT):
        proc = start_server(executable)
        try:
            exercise_server(graph)
        finally:
            try:
                proc.terminate()
                proc.wait(timeout=1.0)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
            stop_listener()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
