#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import socket
import stat
import pytest

HOST = "127.0.0.1"
PORT = 9090
RNG = secrets.SystemRandom()
RANDOM_POINTS = [
    (RNG.randint(1, 999999) / 1000000.0, RNG.randint(1, 999999) / 1000000.0)
    for _ in range(12)
]

def get_matrix(x, y):
    return [
        [math.cos(x) * (y + 1.0), -math.sin(x) * (y + 1.0), x * y],
        [math.sin(x) * (y + 1.0), math.cos(x) * (y + 1.0), x + y],
        [0.1, 0.2, math.exp(-(x*x + y*y))]
    ]

def mat_vec_mul(M, v):
    return [sum(M[i][j] * v[j] for j in range(3)) for i in range(3)]

def vec_norm(v):
    return math.sqrt(sum(val * val for val in v))

def power_iteration(M, num_iter=1000):
    v = [1.0, 1.0, 1.0]
    for _ in range(num_iter):
        v = mat_vec_mul(M, v)
        norm = vec_norm(v)
        if norm == 0:
            break
        v = [val / norm for val in v]
    Mv = mat_vec_mul(M, v)
    return sum(v[i] * Mv[i] for i in range(3)) / sum(v[i] * v[i] for i in range(3))

def qr_decomposition_r_diag(M):
    a1 = [M[0][0], M[1][0], M[2][0]]
    a2 = [M[0][1], M[1][1], M[2][1]]
    a3 = [M[0][2], M[1][2], M[2][2]]

    def dot(u, v):
        return sum(x * y for x, y in zip(u, v))

    def proj(u, v):
        c = dot(u, v) / dot(u, u)
        return [c * x for x in u]

    def sub(u, v):
        return [x - y for x, y in zip(u, v)]

    u1 = a1
    e1 = [x / vec_norm(u1) for x in u1]
    u2 = sub(a2, proj(e1, a2))
    e2 = [x / vec_norm(u2) for x in u2]
    u3 = sub(sub(a3, proj(e1, a3)), proj(e2, a3))
    e3 = [x / vec_norm(u3) for x in u3]
    return dot(e1, a1), dot(e2, a2), dot(e3, a3)

def send_tcp_request(req):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2.0)
            s.connect((HOST, PORT))
            s.sendall(req.encode("utf-8"))
            data = b""
            while b"\n" not in data and len(data) <= 4096:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
            assert b"\n" in data, "Response was not newline-terminated"
            line, remainder = data.split(b"\n", 1)
            assert not remainder.strip(), "Server returned extra response data"
            return line.decode("utf-8").strip()
    except Exception as e:
        pytest.fail(f"TCP request failed for {req.strip()}: {e}")

def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == "0100007F:2382" and fields[3] == "0A":
                inodes.add(fields[9])
    pids = []
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
                    pids.append(int(name))
                    break
        except OSError:
            pass
    return pids

def has_cpp_source():
    roots = ["/home/user", "/app", "/root", "/workspace"]
    cpp_tokens = ("std::", "#include <iostream", "#include <string", "#include <vector", "#include <thread")
    server_tokens = ("socket", "listen", "accept", "9090")
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "node_modules", "__pycache__"}]
            for filename in files:
                if not filename.lower().endswith((".cpp", ".cc", ".cxx", ".c++")):
                    continue
                path = os.path.join(directory, filename)
                try:
                    with open(path, "r", errors="ignore") as f:
                        text = f.read(1000000)
                except OSError:
                    continue
                if all(token in text for token in server_tokens) and any(token in text for token in cpp_tokens):
                    return True
    return False

def test_server_is_native_cpp():
    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:9090"
    cpp_binary_evidence = False
    native_executables = []
    for pid in pids:
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
            mode = os.stat(f"/proc/{pid}/exe").st_mode
            with open(f"/proc/{pid}/exe", "rb") as f:
                data = f.read()
            if stat.S_ISREG(mode) and data.startswith(b"\x7fELF"):
                native_executables.append(exe)
                if any(marker in data for marker in (b"GLIBCXX_", b"CXXABI_", b"__gxx_personality", b"_ZSt")):
                    cpp_binary_evidence = True
            try:
                with open(f"/proc/{pid}/maps", "r", errors="ignore") as f:
                    maps = f.read()
                if "libstdc++" in maps or "libc++.so" in maps:
                    cpp_binary_evidence = True
            except OSError:
                pass
        except OSError:
            continue
    assert native_executables, "The listening service is not a native executable"
    assert cpp_binary_evidence or has_cpp_source(), "No evidence that the TCP service was implemented in C++"

def test_tcp_eigen():
    test_points = [(0.5, 0.5), (0.0, 0.0), (1.0, 0.2)] + RANDOM_POINTS
    for x, y in test_points:
        expected = power_iteration(get_matrix(x, y))
        resp = send_tcp_request(f"EIGEN {x:.12g} {y:.12g}\n")
        try:
            actual = float(resp)
        except ValueError:
            pytest.fail(f"Invalid EIGEN response: {resp}")
        assert math.isfinite(actual), f"Non-finite EIGEN response: {resp}"
        assert abs(actual - expected) < 0.05, \
            f"EIGEN mismatch at {x},{y}: expected ~{expected:.4f}, got {actual:.4f}"

def test_tcp_qr_r():
    test_points = [(0.5, 0.5), (0.0, 0.0), (0.8, 0.1)] + RANDOM_POINTS
    for x, y in test_points:
        expected_r = qr_decomposition_r_diag(get_matrix(x, y))
        resp = send_tcp_request(f"QR_R {x:.12g} {y:.12g}\n")
        parts = resp.split()
        assert len(parts) == 3, f"Expected 3 values for QR_R, got {len(parts)} in '{resp}'"
        for i in range(3):
            try:
                actual = float(parts[i])
            except ValueError:
                pytest.fail(f"Invalid QR_R response value: {parts[i]}")
            assert math.isfinite(actual), f"Non-finite QR_R response value: {parts[i]}"
            assert abs(abs(actual) - abs(expected_r[i])) < 0.05, \
                f"QR_R mismatch at {x},{y} index {i}: expected ~{expected_r[i]:.4f}, got {actual:.4f}"

def test_csv_visualization():
    csv_path = "/home/user/eigen_vis.csv"
    assert os.path.exists(csv_path), f"CSV file missing at {csv_path}"

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["x", "y", "eigenvalue"], f"Invalid CSV header: {header}"
        rows = list(reader)

    assert len(rows) == 121, f"Expected 121 rows in CSV, got {len(rows)}"
    found = {}
    for row in rows:
        assert len(row) == 3, f"Invalid row format: {row}"
        try:
            x, y, eigen = map(float, row)
        except ValueError:
            pytest.fail(f"Invalid numeric CSV row: {row}")
        assert all(math.isfinite(v) for v in (x, y, eigen)), f"Non-finite CSV row: {row}"
        assert 0.0 <= x <= 1.0, f"x value out of bounds: {x}"
        assert 0.0 <= y <= 1.0, f"y value out of bounds: {y}"

        ix, iy = round(x * 10), round(y * 10)
        assert 0 <= ix <= 10 and abs(x - ix / 10.0) < 1e-8, f"x is not on the 0.1 grid: {x}"
        assert 0 <= iy <= 10 and abs(y - iy / 10.0) < 1e-8, f"y is not on the 0.1 grid: {y}"
        key = (ix, iy)
        assert key not in found, f"Duplicate CSV grid coordinate: {x},{y}"
        found[key] = eigen

        expected = power_iteration(get_matrix(ix / 10.0, iy / 10.0))
        assert abs(eigen - expected) < 0.05, \
            f"CSV Eigenvalue mismatch at {x},{y}: expected ~{expected:.4f}, got {eigen:.4f}"

    expected_keys = {(ix, iy) for ix in range(11) for iy in range(11)}
    assert set(found) == expected_keys, "CSV does not contain the complete 0.1 grid"

    origin_expected = power_iteration(get_matrix(0.0, 0.0))
    assert abs(found[(0, 0)] - origin_expected) < 0.05
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
