#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import signal
import socket
import struct
import subprocess
import tempfile
import time
import pytest

HOME = "/home/user"
LIBDIR = "/app/libtcp-1.0"
PORT = 9000


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, **kwargs)


def expected_training(xs, ys):
    train_xs = xs[:80]
    train_ys = ys[:80]
    mn = min(train_xs)
    mx = max(train_xs)
    scaled = [(x - mn) / (mx - mn) for x in train_xs]
    w = 0.0
    b = 0.0
    for _ in range(1000):
        dw = 0.0
        db = 0.0
        for x, y in zip(scaled, train_ys):
            err = w * x + b - y
            dw += err * x
            db += err
        w -= 0.1 * dw / 80.0
        b -= 0.1 * db / 80.0
    return w, b, mn, mx


def read_weights(path):
    assert os.path.isfile(path), "model.weights is missing"
    with open(path, "r") as f:
        content = f.read().strip().split()
    assert len(content) >= 4, "model.weights should contain w, b, min, max"
    try:
        return tuple(float(v) for v in content[:4])
    except ValueError:
        pytest.fail("Could not parse floats from model.weights")


def run_training_case(train_binary, xs, ys, directory):
    with open(os.path.join(directory, "data.csv"), "w") as f:
        f.write("X,Y\n")
        for x, y in zip(xs, ys):
            f.write(f"{x},{y}\n")
    subprocess.run([train_binary], cwd=directory, check=True, timeout=15)
    actual = read_weights(os.path.join(directory, "model.weights"))
    expected = expected_training(xs, ys)
    assert abs(actual[2] - expected[2]) < 1e-4, (
        f"Data leakage or incorrect min. Expected {expected[2]}, got {actual[2]}")
    assert abs(actual[3] - expected[3]) < 1e-4, (
        f"Data leakage or incorrect max. Expected {expected[3]}, got {actual[3]}")
    assert abs(actual[0] - expected[0]) < 0.03, (
        f"w was not produced by the required gradient-descent training: "
        f"expected {expected[0]}, got {actual[0]}")
    assert abs(actual[1] - expected[1]) < 0.03, (
        f"b was not produced by the required gradient-descent training: "
        f"expected {expected[1]}, got {actual[1]}")
    return actual


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local = fields[1]
                        if int(local.rsplit(":", 1)[1], 16) == port:
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
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def clear_port(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def request(value):
    with socket.create_connection(("127.0.0.1", PORT), timeout=3.0) as s:
        s.settimeout(3.0)
        s.sendall(f"{value}\n".encode("utf-8"))
        chunks = []
        while True:
            part = s.recv(1024)
            if not part:
                break
            chunks.append(part)
            if b"\n" in part:
                break
    return b"".join(chunks).decode("utf-8")


def f32(value):
    return struct.unpack("f", struct.pack("f", value))[0]


def safe_dynamic_inputs(w, b, mn, mx):
    result = []
    rng = secrets.SystemRandom()
    while len(result) < 5:
        value = rng.uniform(mn - 30.0, mx + 40.0)
        double_pred = w * ((value - mn) / (mx - mn)) + b
        fw, fb, fmn, fmx, fv = map(f32, (w, b, mn, mx, value))
        scaled = f32(f32(fv - fmn) / f32(fmx - fmn))
        float_pred = f32(f32(fw * scaled) + fb)
        if f"{double_pred:.4f}\n" == f"{float_pred:.4f}\n":
            result.append(value)
    return result


def test_model_weights_and_server():
    # Build and execute the submitted training program.
    train_source = os.path.join(HOME, "train.c")
    assert os.path.isfile(train_source), "train.c is missing"
    train_binary = "/tmp/verified_train"
    run(["gcc", "-std=c11", "-Wall", "-Wextra", train_source, "-o", train_binary])

    # Exercise training on fresh inputs so fixed or fabricated weights do not pass.
    rng = secrets.SystemRandom()
    for _ in range(2):
        offset = rng.randint(-30, 30)
        step = rng.randint(2, 5)
        slope = rng.randint(2, 5)
        intercept = rng.randint(-15, 15)
        xs = [float(offset + step * i) for i in range(80)]
        xs += [float(offset - 500 - i) for i in range(10)]
        xs += [float(offset + step * 79 + 500 + i) for i in range(10)]
        ys = [float(slope * x + intercept) for x in xs]
        with tempfile.TemporaryDirectory() as td:
            run_training_case(train_binary, xs, ys, td)

    # Preserve the original checks against the supplied 100-row dataset, and
    # regenerate model.weights by actually running the submitted program.
    data_file = os.path.join(HOME, "data.csv")
    assert os.path.exists(data_file), "data.csv is missing"
    xs, ys = [], []
    with open(data_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            xs.append(float(row["X"]))
            ys.append(float(row["Y"]))
    assert len(xs) == 100, "data.csv should have 100 rows"

    subprocess.run([train_binary], cwd=HOME, check=True, timeout=15)
    w, b, actual_min, actual_max = read_weights(os.path.join(HOME, "model.weights"))
    expected_w, expected_b, expected_min, expected_max = expected_training(xs, ys)
    assert abs(actual_min - expected_min) < 1e-4, f"Data leakage or incorrect min. Expected {expected_min}, got {actual_min}"
    assert abs(actual_max - expected_max) < 1e-4, f"Data leakage or incorrect max. Expected {expected_max}, got {actual_max}"
    assert abs(w - expected_w) < 0.03, f"Incorrect gradient-descent w. Expected {expected_w}, got {w}"
    assert abs(b - expected_b) < 0.03, f"Incorrect gradient-descent b. Expected {expected_b}, got {b}"

    # The repaired vendored package must build through its own configuration.
    assert os.path.isfile(os.path.join(LIBDIR, "Makefile")), "vendored Makefile is missing"
    run(["make", "clean"], cwd=LIBDIR)
    run(["make"], cwd=LIBDIR)
    archive = os.path.join(LIBDIR, "libtcp.a")
    assert os.path.isfile(archive), "libtcp.a was not built"
    members = run(["ar", "t", archive]).stdout.splitlines()
    assert "tcp_server.o" in members, "libtcp.a does not contain tcp_server.o"
    lib_symbols = run(["nm", "-g", archive]).stdout
    assert re.search(r"\bT\s+start_server\b", lib_symbols), "libtcp.a does not define start_server"

    # Compile server.c separately and require an unresolved start_server API
    # reference before linking it against the newly built static library.
    server_source = os.path.join(HOME, "server.c")
    assert os.path.isfile(server_source), "server.c is missing"
    server_object = "/tmp/verified_server.o"
    server_binary = "/tmp/verified_server"
    run(["gcc", "-std=c11", "-Wall", "-Wextra", "-I", LIBDIR,
         "-c", server_source, "-o", server_object])
    object_symbols = run(["nm", "-u", server_object]).stdout
    assert re.search(r"\bU\s+start_server\b", object_symbols), (
        "server.c does not use the libtcp start_server API")
    run(["gcc", server_object, archive, "-o", server_binary])
    binary_symbols = run(["nm", "-g", server_binary]).stdout
    assert re.search(r"\bT\s+start_server\b", binary_symbols), (
        "server executable was not linked with libtcp.a")

    clear_port(PORT)
    proc = subprocess.Popen([server_binary], cwd=HOME,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 4.0
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail("compiled server exited before accepting connections")
            try:
                with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail("Failed to connect to server on port 9000")

        # Preserve the original fixed request assertion.
        test_x = 42.5
        expected_x_scaled = (test_x - actual_min) / (actual_max - actual_min)
        expected_y_pred = w * expected_x_scaled + b
        expected_response = f"{expected_y_pred:.4f}\n"
        response = request(test_x)
        assert response == expected_response, f"Server returned {response!r}, expected {expected_response!r}"

        # Also exercise independently generated requests to reject fixed listeners.
        for test_x in safe_dynamic_inputs(w, b, actual_min, actual_max):
            expected_x_scaled = (test_x - actual_min) / (actual_max - actual_min)
            expected_y_pred = w * expected_x_scaled + b
            expected_response = f"{expected_y_pred:.4f}\n"
            response = request(test_x)
            assert response == expected_response, f"Server returned {response!r}, expected {expected_response!r}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        clear_port(PORT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
