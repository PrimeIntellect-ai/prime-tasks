#!/bin/bash
set -e
export PATH="/opt/cargo/bin:${PATH}"
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

C_DIR = "/home/user/artifact/src"
SERVER_DIR = "/home/user/artifact-server"


def grpcurl(job_id):
    return subprocess.run(
        [
            "grpcurl", "-plaintext",
            "-import-path", os.path.join(SERVER_DIR, "proto"),
            "-proto", "build.proto",
            "-d", json.dumps({"job_id": job_id}),
            "localhost:50051",
            "build.BuildService/GetStatus",
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )


def stop_port_listeners(ports):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port in ports:
                            socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) in (1, os.getpid(), os.getppid()):
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(1)


def test_c_sources_build_cleanly():
    main_c = os.path.join(C_DIR, "main.c")
    makefile = os.path.join(C_DIR, "Makefile")
    assert os.path.isfile(main_c), "Expected main.c to exist."
    assert os.path.isfile(makefile), "Expected Makefile to exist."

    with tempfile.TemporaryDirectory() as tmp:
        compiled = os.path.join(tmp, "app")
        result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-o", compiled, main_c],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"main.c did not compile cleanly:\n{result.stdout}{result.stderr}"
        direct_run = subprocess.run([compiled], capture_output=True, text=True, timeout=10)
        assert direct_run.returncode == 0
        assert direct_run.stdout == "Artifact Built\n"

    app_path = os.path.join(C_DIR, "app")
    try:
        os.remove(app_path)
    except FileNotFoundError:
        pass
    result = subprocess.run(["make"], cwd=C_DIR, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"make failed:\n{result.stdout}{result.stderr}"
    assert os.path.isfile(app_path), "make did not produce app."
    with open(app_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "app must be a compiled native executable, not a script."


def test_c_app_built_and_runs():
    app_path = "/home/user/artifact/src/app"
    assert os.path.isfile(app_path), f"Expected {app_path} to exist. Did you run 'make' after fixing the code?"
    assert os.access(app_path, os.X_OK), f"Expected {app_path} to be executable."

    result = subprocess.run([app_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Expected app to exit with code 0, but got {result.returncode}."
    assert "Artifact Built" in result.stdout, "Expected app output to contain 'Artifact Built'."


def test_http_response_log():
    log_path = "/home/user/http_response.log"
    assert os.path.isfile(log_path), f"Expected {log_path} to exist. Did you save the curl output?"
    with open(log_path, "r") as f:
        content = f.read()
    assert "job123" in content, "Expected http_response.log to contain 'job123' indicating the job was processed."


def test_grpc_response_log():
    log_path = "/home/user/grpc_response.log"
    assert os.path.isfile(log_path), f"Expected {log_path} to exist. Did you save the grpcurl output?"
    with open(log_path, "r") as f:
        content = f.read()

    try:
        data = json.loads(content)
        assert data.get("status") == "COMPLETED", "Expected gRPC JSON response to have status 'COMPLETED'."
    except json.JSONDecodeError:
        assert '"status"' in content and '"COMPLETED"' in content, "Expected gRPC response to contain 'COMPLETED' status."


@pytest.fixture(scope="session")
def running_server():
    build = subprocess.run(
        ["cargo", "build"],
        cwd=SERVER_DIR,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert build.returncode == 0, f"Rust server failed to compile:\n{build.stdout}{build.stderr}"

    stop_port_listeners({8080, 50051})
    proc = subprocess.Popen(
        ["cargo", "run", "--quiet"],
        cwd=SERVER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    deadline = time.time() + 45
    last_error = "server did not become ready"
    while time.time() < deadline:
        if proc.poll() is not None:
            stdout, stderr = proc.communicate()
            pytest.fail(f"Rust server exited during startup:\n{stdout}{stderr}")
        try:
            req = urllib.request.Request(
                "http://localhost:8080/build/readiness",
                data=b"",
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status == 200:
                    probe = grpcurl("readiness")
                    if probe.returncode == 0:
                        break
                    last_error = probe.stderr
        except Exception as exc:
            last_error = str(exc)
        time.sleep(0.25)
    else:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=10)
        pytest.fail(f"Rust HTTP/gRPC server did not become ready: {last_error}")

    yield proc

    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)


def test_live_http_route_and_method(running_server):
    job_id = "verify" + uuid.uuid4().hex
    req = urllib.request.Request(
        f"http://localhost:8080/build/{job_id}",
        data=b"",
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        body = response.read().decode()
        assert response.status == 200
    assert body == f"Build started for {job_id}"

    try:
        urllib.request.urlopen(f"http://localhost:8080/build/{job_id}", timeout=10)
        pytest.fail("The build route incorrectly accepted GET; it must accept POST.")
    except urllib.error.HTTPError as exc:
        assert exc.code == 405


def test_live_grpc_status_for_arbitrary_job(running_server):
    job_id = "verify" + uuid.uuid4().hex
    result = grpcurl(job_id)
    assert result.returncode == 0, f"gRPC request failed: {result.stderr}"
    data = json.loads(result.stdout)
    assert data.get("status") == "COMPLETED"


def test_saved_logs_match_live_job123_responses(running_server):
    http = subprocess.run(
        ["curl", "-sS", "-X", "POST", "http://localhost:8080/build/job123"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert http.returncode == 0, http.stderr
    with open("/home/user/http_response.log") as f:
        assert f.read() == http.stdout

    grpc = grpcurl("job123")
    assert grpc.returncode == 0, grpc.stderr
    with open("/home/user/grpc_response.log") as f:
        assert f.read() == grpc.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
