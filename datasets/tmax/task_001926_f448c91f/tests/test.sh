#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import signal
import socket
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import numpy as np
import pytest
import requests
from PIL import Image

ENGINE = "/app/engine/compute"
SOURCE = "/app/engine/compute.cpp"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[3] == "0A" and int(fields[1].split(":")[1], 16) == port:
                inodes.add(fields[9])
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
        except OSError:
            pass
    return pids


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.15)


def wait_http(url, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=0.5)
        except requests.RequestException as exc:
            last = exc
            time.sleep(0.1)
    raise AssertionError(f"Service at {url} did not become ready: {last}")


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submitted_engine():
    assert os.path.isfile(SOURCE), f"Missing required source {SOURCE}"
    assert os.path.isfile(ENGINE), "The compute engine was not compiled"
    assert os.access(ENGINE, os.X_OK), "The compute engine is not executable"
    assert os.path.getmtime(ENGINE) >= os.path.getmtime(SOURCE), \
        "compute.cpp is newer than the executable; the edited engine was not recompiled"

    src = open(SOURCE, encoding="utf-8").read()
    assert "determinant(" in src, "compute.cpp does not calculate the determinant"
    assert "std::abs" in src or "fabs" in src or "abs(" in src, \
        "compute.cpp does not take the absolute determinant"
    assert re.search(r"1(?:\.0*)?[eE]-0*5|0\.00001", src), \
        "compute.cpp is missing the 1e-5 determinant threshold"
    assert re.search(r"1(?:\.0*)?[eE]-0*6|0\.000001", src), \
        "compute.cpp is missing the 1e-6 regularization value"
    assert "diagonal" in src or "Identity" in src, \
        "compute.cpp does not add regularization to the main diagonal"
    assert "colPivHouseholderQr" in src, \
        "compute.cpp does not use Eigen colPivHouseholderQr()"

    stop_port(8080)
    try:
        os.remove(ENGINE)
    except FileNotFoundError:
        pass
    build = subprocess.run(["make", "-B"], cwd="/app/engine", text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=60)
    assert build.returncode == 0, f"compute.cpp failed to compile:\n{build.stdout}"
    assert os.path.isfile(ENGINE) and os.access(ENGINE, os.X_OK), \
        "Makefile did not produce an executable compute engine"
    with open(ENGINE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The produced compute artifact is not a compiled ELF binary"

    proc = subprocess.Popen([ENGINE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 8
    while time.time() < deadline and proc.poll() is None and not listener_pids(8080):
        time.sleep(0.1)
    assert proc.poll() is None, "The submitted compute engine exited during startup"
    owners = listener_pids(8080)
    assert proc.pid in owners, "Port 8080 is not served by the compiled /app/engine/compute artifact"
    yield
    # Deliberately leave the engine running, as required by the task.


def post_solve(A, b):
    url = "http://127.0.0.1:8080/solve"
    try:
        response = requests.post(url, json={"A": np.asarray(A).tolist(),
                                            "b": np.asarray(b).tolist()}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to compute engine at {url}: {e}")
    assert response.status_code == 200, \
        f"Expected HTTP 200 from compute engine, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Compute engine did not return valid JSON. Response: {response.text}")
    assert "x" in data, f"Response from compute engine missing 'x' key. Response: {data}"
    return data["x"]


def test_redis_running():
    """Verify Redis is listening on port 6379 and is actually Redis."""
    with socket.create_connection(("127.0.0.1", 6379), timeout=3) as s:
        s.sendall(b"*1\r\n$4\r\nPING\r\n")
        assert s.recv(64).startswith(b"+PONG"), "Port 6379 did not answer Redis PING"


def test_compute_engine_solve():
    """Retain the original fixed near-singular check."""
    x = post_solve([[1.0, 1.0], [1.0, 1.0]], [2.0, 2.0])
    assert isinstance(x, list), f"Expected 'x' to be a list, got {type(x)}"
    assert len(x) == 2, f"Expected 2 elements in 'x', got {len(x)}"
    for i, val in enumerate(x):
        assert isinstance(val, (int, float)), f"Element {i} is not a number: {val}"
        assert math.isclose(val, 1.0, rel_tol=1e-3, abs_tol=1e-3), \
            f"Element {i} of 'x' is {val}, expected approx 1.0"


def test_compute_engine_dynamic_systems():
    """Exercise varying dimensions, values, determinant branches, and right-hand sides."""
    rng = np.random.default_rng(secrets.randbits(64))
    cases = []
    for n in (2, 3, 4, 5):
        q, _ = np.linalg.qr(rng.normal(size=(n, n)))
        eig = rng.uniform(0.7, 2.5, size=n)
        A_regular = q @ np.diag(eig) @ q.T
        cases.append(A_regular)

        q, _ = np.linalg.qr(rng.normal(size=(n, n)))
        eig = rng.uniform(0.8, 1.8, size=n)
        eig[-1] = rng.uniform(1e-10, 5e-8)
        A_near = q @ np.diag(eig) @ q.T
        cases.append(A_near)

    for A in cases:
        b = rng.normal(size=A.shape[0])
        det = abs(float(np.linalg.det(A)))
        adjusted = A + (1e-6 * np.eye(A.shape[0]) if det < 1e-5 else 0.0)
        expected = np.linalg.solve(adjusted, b)
        actual = post_solve(A, b)
        assert isinstance(actual, list) and len(actual) == A.shape[0]
        actual = np.asarray(actual, dtype=float)
        assert np.all(np.isfinite(actual)), f"Non-finite solution for determinant {det}: {actual}"
        assert np.allclose(actual, expected, rtol=2e-6, atol=2e-6), \
            f"Incorrect solution for generated {A.shape[0]}x{A.shape[0]} system (|det|={det})"


def test_flask_app_health():
    url = "http://127.0.0.1:5000/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Flask app at {url}: {e}")
    assert response.status_code == 200, \
        f"Expected HTTP 200 from Flask app /health, got {response.status_code}"


def expected_simulation(size, anisotropy):
    n = size * size
    A = np.zeros((n, n), dtype=float)
    b = np.ones(n)
    for i in range(n):
        A[i, i] = 4.0
        if i % size != 0:
            A[i, i - 1] = -1.0
        if (i + 1) % size != 0:
            A[i, i + 1] = -1.0
        if i >= size:
            A[i, i - size] = -anisotropy
        if i < n - size:
            A[i, i + size] = -anisotropy
    if anisotropy > 0.99:
        for i in range(n):
            A[i, i] = 2.0 * anisotropy
            if i % size != 0:
                A[i, i - 1] = -anisotropy
            if (i + 1) % size != 0:
                A[i, i + 1] = -anisotropy
    if abs(float(np.linalg.det(A))) < 1e-5:
        A = A + 1e-6 * np.eye(n)
    return np.linalg.solve(A, b)


def test_flask_app_simulate():
    """Retain the original 10x10 simulation assertions."""
    url = "http://127.0.0.1:5000/simulate"
    payload = {"size": 10, "anisotropy": 0.99999}
    try:
        response = requests.post(url, json=payload, timeout=15)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Flask app at {url}: {e}")
    assert response.status_code == 200, \
        f"Expected HTTP 200 from Flask app /simulate, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Flask app did not return valid JSON. Response: {response.text}")
    assert "state" in data, f"Response missing 'state' key. Response: {data}"
    state = data["state"]
    assert isinstance(state, list), f"Expected 'state' to be a list, got {type(state)}"
    assert len(state) == 100, f"Expected 100 elements in state array, got {len(state)}"
    for i, val in enumerate(state):
        assert isinstance(val, (int, float)), f"Element {i} in state is not a number: {val}"
        assert not math.isnan(val), f"Found NaN at index {i} in state array"
        assert not math.isinf(val), f"Found Infinity at index {i} in state array"
    expected = expected_simulation(10, 0.99999)
    assert np.allclose(np.asarray(state), expected, rtol=3e-6, atol=3e-6), \
        "The 10x10 simulation state does not match the requested PDE system"


def test_flask_dynamic_simulations():
    rng = np.random.default_rng(secrets.randbits(64))
    for size, anisotropy in ((3, float(rng.uniform(0.2, 0.8))),
                             (4, float(rng.uniform(0.991, 0.9999))),
                             (5, float(rng.uniform(0.4, 0.9)))):
        response = requests.post("http://127.0.0.1:5000/simulate",
                                 json={"size": size, "anisotropy": anisotropy}, timeout=10)
        assert response.status_code == 200
        state = response.json().get("state")
        assert isinstance(state, list) and len(state) == size * size
        expected = expected_simulation(size, anisotropy)
        assert np.allclose(np.asarray(state, dtype=float), expected, rtol=3e-6, atol=3e-6), \
            f"Incorrect /simulate result for size={size}, anisotropy={anisotropy}"


def test_startup_script_configuration():
    path = "/app/start_services.sh"
    assert os.path.isfile(path) and os.access(path, os.X_OK)
    text = open(path, encoding="utf-8").read()
    assert "redis-server" in text, "Startup script does not start Redis"
    assert "/app/engine/compute" in text or "./compute" in text, \
        "Startup script does not start the compiled compute engine"
    assert "COMPUTE_URL=http://127.0.0.1:8080" in text, \
        "Startup script does not configure COMPUTE_URL"
    assert "app.py" in text or "gunicorn" in text, "Startup script does not start the Flask app"


def test_visualize_script_exists():
    path = "/home/user/visualize.py"
    assert os.path.isfile(path), f"Visualize script {path} does not exist"


def test_visualization_pipeline_executes():
    path = "/home/user/visualize.py"
    source = open(path, encoding="utf-8").read()
    assert "http://127.0.0.1:5000/simulate" in source
    assert "reshape" in source and "10" in source, "Visualization does not reshape the 10x10 state"
    assert "matplotlib" in source, "Visualization does not use matplotlib"
    assert "heatmap.png" in source, "Visualization does not save the required heatmap path"

    stop_port(5000)
    received = []
    phase = secrets.randbelow(1000000)
    returned = [float(((i + phase) % 10) + 10 * ((i // 10) % 2)) for i in range(100)]

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
            except Exception:
                body = None
            received.append((self.path, body))
            payload = json.dumps({"state": returned}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 5000), Handler)
    import threading
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    png = "/home/user/heatmap.png"
    try:
        if os.path.exists(png):
            os.remove(png)
        run = subprocess.run(["python3", path], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=30)
        assert run.returncode == 0, f"visualize.py failed when executed:\n{run.stdout}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert received, "visualize.py did not POST to the simulation service"
    assert received == [("/simulate", {"size": 10, "anisotropy": 0.99999})], \
        f"visualize.py sent the wrong endpoint or payload: {received}"
    assert os.path.isfile(png), f"Heatmap file {png} does not exist"
    with open(png, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"File {png} is not a valid PNG image"
    with Image.open(png) as image:
        image.verify()
    with Image.open(png).convert("RGB") as image:
        assert image.width >= 100 and image.height >= 100, "Generated heatmap is implausibly small"
        colors = image.resize((100, 100)).getcolors(maxcolors=10001)
        assert colors is not None and len(colors) > 20, "Generated PNG does not contain a plotted heatmap"

    env = os.environ.copy()
    env["COMPUTE_URL"] = "http://127.0.0.1:8080"
    subprocess.Popen(["python3", "/app/frontend/app.py"], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    response = wait_http("http://127.0.0.1:5000/health")
    assert response.status_code == 200


def test_heatmap_png_exists_and_valid():
    """Retain the original final PNG assertions."""
    path = "/home/user/heatmap.png"
    assert os.path.isfile(path), f"Heatmap file {path} does not exist"
    with open(path, "rb") as f:
        header = f.read(8)
        assert header == b'\x89PNG\r\n\x1a\n', f"File {path} is not a valid PNG image"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
