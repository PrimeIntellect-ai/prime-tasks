#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import socket
import subprocess

import pytest

LIB_DIR = "/app/libcurvefit-1.0"
LIB_PATH = os.path.join(LIB_DIR, "libcurvefit.so")
SERVER_SOURCE = "/home/user/server.c"
HOST = "127.0.0.1"
PORT = 8080


def exchange(curves, timeout=5):
    payload = str(len(curves)) + "\n"
    payload += "".join(" ".join(f"{x:.2f}" for x in curve) + "\n" for curve in curves)

    try:
        with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(payload.encode("utf-8"))
            response = b""
            while response.count(b"\n") < len(curves):
                data = sock.recv(4096)
                if not data:
                    break
                response += data
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to TCP server at {HOST}:{PORT}. Is it running?")
    except socket.timeout:
        pytest.fail(f"Connection to TCP server at {HOST}:{PORT} timed out.")

    return response.decode("utf-8").strip().split("\n") if response.strip() else []


def listening_pid():
    wanted = f"{PORT:04X}"
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            address, port = local_address.split(":")
            if address == "0100007F" and port == wanted and state == "0A":
                inodes.add(fields[9])

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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    return int(name)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return None


def strip_c_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def expected_tm(curve):
    max_diff = 0.0
    max_idx = 0
    for i in range(1, len(curve)):
        diff = curve[i] - curve[i - 1]
        if diff > max_diff:
            max_diff = diff
            max_idx = i
    return 20.0 + max_idx - 0.5


def test_01_libcurvefit_compiled():
    """Retain the original assertion that the requested shared library exists."""
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not found. Did you compile it?"


def test_02_makefile_is_fixed_and_library_is_valid():
    dry_run = subprocess.run(
        ["make", "-B", "-n", "libcurvefit.so"], cwd=LIB_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert dry_run.returncode == 0, dry_run.stdout
    link_lines = [line for line in dry_run.stdout.splitlines() if "-shared" in line and "libcurvefit.so" in line]
    assert link_lines, f"Makefile did not emit a shared-library link command:\n{dry_run.stdout}"
    assert any(re.search(r"(?:^|\s)-lm(?:\s|$)", line) for line in link_lines), (
        "The shared-library link command still does not link the math library (-lm)."
    )

    build = subprocess.run(
        ["make", "-B", "libcurvefit.so"], cwd=LIB_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert build.returncode == 0, f"Rebuilding libcurvefit.so failed:\n{build.stdout}"

    library = ctypes.CDLL(LIB_PATH)
    fit = library.fit_melting_curve
    fit.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.c_int, ctypes.POINTER(ctypes.c_float)]
    fit.restype = ctypes.c_int
    values = [0.12] * 37 + [0.91] * 63
    array = (ctypes.c_float * 100)(*values)
    tm = ctypes.c_float()
    assert fit(array, 100, ctypes.byref(tm)) == 0
    assert tm.value == pytest.approx(56.5, abs=0.001)


def test_03_running_listener_is_linked_to_curvefit_and_openmp():
    pid = listening_pid()
    assert pid is not None, f"No process is listening on {HOST}:{PORT}"

    with open(f"/proc/{pid}/maps", "r", encoding="utf-8") as handle:
        maps = handle.read()
    assert LIB_PATH in maps, "The listening server has not loaded the vendored libcurvefit.so"
    assert "libgomp" in maps, "The listening server has not loaded the GNU OpenMP runtime"

    dynamic = subprocess.run(
        ["readelf", "-d", f"/proc/{pid}/exe"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert dynamic.returncode == 0, dynamic.stdout
    assert re.search(r"Shared library: \[libcurvefit\.so", dynamic.stdout), dynamic.stdout
    assert re.search(r"Shared library: \[libgomp\.so", dynamic.stdout), dynamic.stdout

    symbols = subprocess.run(
        ["nm", "-D", f"/proc/{pid}/exe"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert symbols.returncode == 0, symbols.stdout
    assert re.search(r"\bU\s+fit_melting_curve(?:@|\s|$)", symbols.stdout), symbols.stdout
    assert re.search(r"\bU\s+GOMP_parallel(?:@|\s|$)", symbols.stdout), (
        "The running server executable does not contain an OpenMP parallel region."
    )


def test_04_server_source_contains_required_library_call_and_openmp_loop():
    assert os.path.isfile(SERVER_SOURCE), f"Required source file {SERVER_SOURCE} was not found"
    with open(SERVER_SOURCE, "r", encoding="utf-8") as handle:
        source = strip_c_comments(handle.read())
    assert re.search(r'#\s*include\s*[<\"](?:/app/libcurvefit-1\.0/)?curvefit\.h[>\"]', source)
    assert re.search(r"#\s*pragma\s+omp\s+parallel\s+for\b", source), (
        "server.c does not use the required '#pragma omp parallel for'."
    )
    assert re.search(r"\bfit_melting_curve\s*\(", source), (
        "server.c does not call fit_melting_curve."
    )


def test_05_original_tcp_server_protocol_case():
    """Retain the original fixed protocol assertions."""
    curve0 = [0.1] * 100
    for i in range(45, 100):
        curve0[i] = 1.0
    curve1 = [0.1] * 100
    for i in range(60, 100):
        curve1[i] = 1.0
    curve2 = [0.1] * 100
    for i in range(20, 100):
        curve2[i] = 1.0

    lines = exchange([curve0, curve1, curve2])
    response_str = "\n".join(lines)
    assert len(lines) == 3, f"Expected 3 lines of output, got {len(lines)}. Response: {response_str}"
    assert "Curve 0: Tm = 64.50" in lines[0], f"Expected Curve 0 Tm to be 64.50, got: {lines[0]}"
    assert "Curve 1: Tm = 79.50" in lines[1], f"Expected Curve 1 Tm to be 79.50, got: {lines[1]}"
    assert "Curve 2: Tm = 39.50" in lines[2], f"Expected Curve 2 Tm to be 39.50, got: {lines[2]}"


def test_06_runtime_generated_requests_are_processed():
    rng = secrets.SystemRandom()
    for batch_size in (1, rng.randint(4, 7), rng.randint(9, 13)):
        curves = []
        for _ in range(batch_size):
            jump = rng.randint(1, 99)
            low = [rng.randint(5, 20) / 100.0 for _ in range(jump)]
            high = [rng.randint(80, 95) / 100.0 for _ in range(100 - jump)]
            curves.append(low + high)

        expected = [f"Curve {i}: Tm = {expected_tm(curve):.2f}" for i, curve in enumerate(curves)]
        actual = exchange(curves)
        assert actual == expected, f"Expected {expected!r}, got {actual!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
