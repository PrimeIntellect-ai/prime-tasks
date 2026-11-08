#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any copy left running by the agent so the rebuilt binary can bind port 8080.
pkill -f 'target/debug/polyglot-service' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import subprocess
import time

PROJECT = "/home/user/polyglot-service"
C_DIR = os.path.join(PROJECT, "c_src")
LIB_PATH = os.path.join(C_DIR, "libapi_processor.a")
BIN_PATH = os.path.join(PROJECT, "target/debug/polyglot-service")


def run_checked(args, cwd):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180)
    assert result.returncode == 0, f"Command {args!r} failed:\n{result.stdout}"
    return result.stdout


def test_00_rebuild_project_from_sources():
    # Force Make to produce a new archive rather than accepting a placeholder.
    for path in (LIB_PATH, os.path.join(C_DIR, "processor.o")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_checked(["make", "-B", "libapi_processor.a"], C_DIR)
    assert os.path.isfile(LIB_PATH), "Make did not create libapi_processor.a"
    with open(LIB_PATH, "rb") as f:
        assert f.read(8) == b"!<arch>\n", "libapi_processor.a is not an ar archive"

    members = run_checked(["ar", "t", LIB_PATH], C_DIR).splitlines()
    assert any(os.path.basename(member.strip()) == "processor.o" for member in members), \
        f"Archive does not contain processor.o: {members}"
    symbols = run_checked(["nm", "-g", "--defined-only", LIB_PATH], C_DIR)
    assert any(line.split()[-1] == "process_request" for line in symbols.splitlines() if line.split()), \
        "Static library does not define process_request"

    # A clean Cargo build proves the submitted C archive can really be linked via FFI.
    run_checked(["cargo", "clean"], PROJECT)
    run_checked(["cargo", "build"], PROJECT)


def test_static_library_compiled():
    lib_path = "/home/user/polyglot-service/c_src/libapi_processor.a"
    assert os.path.isfile(lib_path), f"Static library {lib_path} was not compiled or is missing."


def test_rust_binary_compiled():
    bin_path = "/home/user/polyglot-service/target/debug/polyglot-service"
    assert os.path.isfile(bin_path), f"Rust binary {bin_path} was not compiled or is missing."
    assert os.access(bin_path, os.X_OK), f"Rust binary {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Rust binary {bin_path} is not an ELF executable."


def test_results_log_content():
    log_path = "/home/user/results.log"
    assert os.path.isfile(log_path), f"Results log {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in {log_path}, found {len(lines)}."

    try:
        r1 = json.loads(lines[0])
        r2 = json.loads(lines[1])
    except json.JSONDecodeError as e:
        assert False, f"Failed to parse JSON from {log_path}: {e}"

    assert r1.get('result') == 45, f"Expected first result to be 45, got {r1.get('result')}"
    assert r2.get('result') == 42, f"Expected second result to be 42, got {r2.get('result')}"


def http_get(path):
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        request = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        sock.sendall(request.encode("ascii"))
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks)
    assert b"\r\n\r\n" in raw, f"Malformed HTTP response: {raw!r}"
    headers, body = raw.split(b"\r\n\r\n", 1)
    assert headers.startswith(b"HTTP/1.1 200"), f"Unexpected HTTP status: {headers!r}"
    return json.loads(body.decode("utf-8"))


def test_running_server_handles_derived_and_invalid_inputs():
    proc = subprocess.Popen([BIN_PATH], cwd=PROJECT, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode("utf-8", "replace")
                assert False, f"Server exited before accepting requests: {stderr}"
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            assert False, "Server did not bind to 127.0.0.1:8080"

        # Generate values at verification time so fixed canned responses cannot pass.
        sum_values = [secrets.randbelow(2001) - 1000 for _ in range(7)]
        max_values = [-(secrets.randbelow(9000) + 1) for _ in range(6)]

        sum_query = ",".join(map(str, sum_values))
        max_query = ",".join(map(str, max_values))
        assert http_get(f"/api/process?op=sum&values={sum_query}") == {"result": sum(sum_values)}
        assert http_get(f"/api/process?op=max&values={max_query}") == {"result": max(max_values)}

        assert http_get("/api/process?op=median&values=1,2,3") == {"error": "invalid"}
        assert http_get("/api/process?op=sum&values=1,not_an_integer,3") == {"error": "invalid"}
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
