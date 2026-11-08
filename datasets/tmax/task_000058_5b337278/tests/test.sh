#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import signal
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest


def generate_input():
    num_lines = random.randint(0, 100)
    lines = []
    for _ in range(num_lines):
        id_len = random.randint(4, 8)
        id_str = ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(id_len))
        timestamp = random.randint(1600000000, 1700000000)
        num_vals = random.randint(1, 20)
        vals = [f"{random.uniform(-100.5, 100.5):.2f}" for _ in range(num_vals)]
        lines.append(f"{id_str}|{timestamp}|{','.join(vals)}")
    return "\n".join(lines) + ("\n" if num_lines > 0 else "")


def generate_unpredictable_input():
    rng = random.SystemRandom()
    lines = []
    for _ in range(rng.randint(2, 30)):
        ident = ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(rng.randint(5, 12)))
        timestamp = rng.randint(1500000000, 1800000000)
        vals = [f"{rng.randint(-500000, 500000) / 1000.0:.3f}" for _ in range(rng.randint(1, 25))]
        lines.append(f"{ident}|{timestamp}|{','.join(vals)}")
    return "\n".join(lines) + "\n"


def oracle_output(inp):
    proc = subprocess.run(
        ["python2", "/app/legacy/process_v2.py"],
        input=inp,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"Oracle failed:\n{proc.stderr}"
    return proc.stdout


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(':', 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = int(proc_dir.rsplit('/', 1)[1])
        try:
            for fd in os.scandir(proc_dir + "/fd"):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(pid)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def post_matches(url, inp, expected, timeout=5):
    req = urllib.request.Request(
        url,
        data=inp.encode("utf-8"),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status == 200 and response.read().decode("utf-8") == expected
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError):
        return False


def test_fuzz_equivalence():
    oracle_path = "/app/legacy/process_v2.py"
    agent_path = "/home/user/migrated/processor"

    assert os.path.isfile(agent_path), f"Agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

    random.seed(42)
    for i in range(500):
        inp = generate_input()

        oracle_proc = subprocess.run(
            ["python2", oracle_path],
            input=inp,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{inp}\nError:\n{oracle_proc.stderr}"

        agent_proc = subprocess.run(
            [agent_path],
            input=inp,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0 or agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input:\n{inp}\n\n"
                f"Oracle Output:\n{oracle_proc.stdout}\n\n"
                f"Agent Output:\n{agent_proc.stdout}\n\n"
                f"Agent Stderr:\n{agent_proc.stderr}"
            )


def test_e2e_service_composition():
    random.seed(999)
    inp = generate_input()

    oracle_proc = subprocess.run(
        ["python2", "/app/legacy/process_v2.py"],
        input=inp,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, "Oracle failed to generate expected output."
    expected_output = oracle_proc.stdout

    req = urllib.request.Request(
        "http://localhost:8080/api/process",
        data=inp.encode('utf-8'),
        headers={'Content-Type': 'text/plain'},
        method='POST'
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            resp_body = response.read().decode('utf-8')
            assert resp_body == expected_output, (
                f"E2E response mismatch.\nExpected:\n{expected_output}\nGot:\n{resp_body}"
            )
    except urllib.error.HTTPError as e:
        pytest.fail(f"HTTP request failed with status {e.code}: {e.read().decode('utf-8', errors='replace')}")
    except urllib.error.URLError as e:
        pytest.fail(f"HTTP request failed: {e.reason}")


def test_service_artifacts_and_processes():
    server_go = "/home/user/migrated/server.go"
    gateway_py = "/app/services/gateway/app.py"
    nginx_conf = "/app/services/nginx/nginx.conf"

    assert os.path.isfile(server_go), "Required Go gRPC source server.go is missing"
    assert os.path.getsize(server_go) > 0, "server.go is empty"
    source = open(server_go, encoding="utf-8").read()
    assert "package main" in source, "server.go is not a Go main-package source file"
    parsed = subprocess.run(["gofmt", server_go], capture_output=True, text=True)
    assert parsed.returncode == 0, f"server.go is not valid Go syntax: {parsed.stderr}"

    assert os.path.isfile(gateway_py), "Flask gateway app.py is missing"
    compiled = subprocess.run(["python3", "-m", "py_compile", gateway_py], capture_output=True, text=True)
    assert compiled.returncode == 0, f"Gateway is not valid Python 3: {compiled.stderr}"

    assert os.path.isfile(nginx_conf), "Required Nginx configuration is missing"
    checked = subprocess.run(["nginx", "-T", "-c", nginx_conf], capture_output=True, text=True)
    assert checked.returncode == 0, f"Nginx configuration is invalid: {checked.stderr}"
    effective = checked.stdout + checked.stderr
    assert "/api/process" in effective and "8080" in effective, "Nginx config does not expose the required route"
    assert "proxy_pass" in effective and "5000" in effective, "Nginx config does not proxy the route to the gateway"

    nginx_pids = listening_pids(8080)
    flask_pids = listening_pids(5000)
    grpc_pids = listening_pids(50051)
    assert nginx_pids, "Nothing is listening on Nginx port 8080"
    assert flask_pids, "Nothing is listening on Flask port 5000"
    assert grpc_pids, "Nothing is listening on gRPC port 50051"

    assert all("nginx" in os.path.basename(process_exe(pid)).lower() for pid in nginx_pids), \
        "Port 8080 is not owned by Nginx"
    assert all(os.path.basename(process_exe(pid)).lower().startswith("python3") for pid in flask_pids), \
        "Port 5000 is not owned by a Python 3 gateway"
    for pid in grpc_pids:
        info = subprocess.run(["go", "version", "-m", f"/proc/{pid}/exe"], capture_output=True, text=True)
        assert info.returncode == 0, "Port 50051 is not served by a compiled Go program"


def test_direct_grpc_backend():
    out_dir = "/tmp/grpc_probe"
    os.makedirs(out_dir, exist_ok=True)
    vpy = "/app/services/gateway/venv/bin/python"
    generated = subprocess.run([
        vpy, "-m", "grpc_tools.protoc",
        "-I/app/services/proto",
        f"--python_out={out_dir}",
        f"--grpc_python_out={out_dir}",
        "/app/services/proto/data.proto",
    ], capture_output=True, text=True)
    assert generated.returncode == 0, f"Could not build verifier gRPC client: {generated.stderr}"

    for site_dir in glob.glob("/app/services/gateway/venv/lib/python*/site-packages"):
        if site_dir not in sys.path:
            sys.path.insert(0, site_dir)
    sys.path.insert(0, out_dir)
    import grpc
    import data_pb2
    import data_pb2_grpc

    channel = grpc.insecure_channel("localhost:50051")
    stub = data_pb2_grpc.DataProcessorStub(channel)
    try:
        for _ in range(4):
            inp = generate_unpredictable_input()
            expected = oracle_output(inp)
            response = stub.ProcessData(data_pb2.DataRequest(raw_payload=inp), timeout=5)
            assert response.processed_payload == expected, "Direct gRPC backend response does not match the processor"
    finally:
        channel.close()


def test_multiple_unpredictable_e2e_requests():
    for _ in range(6):
        inp = generate_unpredictable_input()
        expected = oracle_output(inp)
        assert post_matches("http://localhost:8080/api/process", inp, expected), \
            "An unpredictable E2E request did not pass through the service correctly"


def test_layers_are_actual_dependencies():
    grpc_pids = listening_pids(50051)
    assert grpc_pids, "gRPC backend stopped before dependency test"
    inp = generate_unpredictable_input()
    expected = oracle_output(inp)
    try:
        for pid in grpc_pids:
            os.kill(pid, signal.SIGSTOP)
        time.sleep(0.2)
        assert not post_matches("http://localhost:5000/api/process", inp, expected, timeout=1.5), \
            "Flask returned the processed result while the Go gRPC backend was suspended"
    finally:
        for pid in grpc_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
    time.sleep(0.5)

    flask_pids = listening_pids(5000)
    assert flask_pids, "Flask gateway stopped before dependency test"
    inp = generate_unpredictable_input()
    expected = oracle_output(inp)
    try:
        for pid in flask_pids:
            os.kill(pid, signal.SIGSTOP)
        time.sleep(0.2)
        assert not post_matches("http://localhost:8080/api/process", inp, expected, timeout=1.5), \
            "Nginx returned the processed result while the Flask gateway was suspended"
    finally:
        for pid in flask_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
