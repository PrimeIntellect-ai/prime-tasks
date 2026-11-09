#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib.util
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

SECRET = "SUPER_SECRET_KEY"
ROOT = "/app"


def expected_signature(resource_id, secret=SECRET):
    # JavaScript charCodeAt iterates UTF-16 code units, and bitwise operations
    # convert the accumulator to a signed 32-bit integer on every iteration.
    raw = (str(resource_id) + str(secret)).encode("utf-16-le", "surrogatepass")
    value = 0
    for i in range(0, len(raw), 2):
        code_unit = raw[i] | (raw[i + 1] << 8)
        value = ((value * 31) + code_unit) & 0xffffffff
        if value & 0x80000000:
            value -= 0x100000000
    return ("-" + format(-value, "x")) if value < 0 else format(value, "x")


def stop_services():
    commands = [
        ["pkill", "-x", "nginx"],
        ["pkill", "-x", "server"],
        ["pkill", "-f", "gunicorn.*app:app"],
        ["pkill", "-f", "python3 app.py"],
        ["pkill", "-f", "/app/start_services.sh"],
    ]
    for command in commands:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.4)


def wait_for_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def request(resource_id, signature, timeout=3):
    rid = urllib.parse.quote(str(resource_id), safe="")
    sig = urllib.parse.quote(str(signature), safe="")
    url = f"http://127.0.0.1:8080/api/v1/resource/{rid}?sig={sig}"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return response.getcode(), response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:
        return 0, str(exc)


def test_c_backend_optimized_fixed_and_executable():
    makefile_path = "/app/c_backend/Makefile"
    assert os.path.exists(makefile_path), "Makefile is missing."
    with open(makefile_path, "r") as handle:
        content = handle.read()
    assert "-O3" in content, "Makefile does not contain the -O3 optimization flag."

    validator_path = "/app/c_backend/validator.c"
    assert os.path.exists(validator_path), "validator.c is missing."
    with open(validator_path, "r") as handle:
        val_content = handle.read()
    assert "10000000" not in val_content, "The artificial delay loop was not removed from validator.c"

    stop_services()
    server_path = "/app/c_backend/server"
    if os.path.exists(server_path):
        os.remove(server_path)
    built = subprocess.run(
        ["make", "-B"], cwd="/app/c_backend", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert built.returncode == 0, f"Makefile failed to compile:\n{built.stdout}"
    assert "-O3" in built.stdout, f"The actual compiler invocation did not use -O3:\n{built.stdout}"
    assert os.path.isfile(server_path) and os.access(server_path, os.X_OK), "make did not create an executable server"
    with open(server_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "The built C backend is not an ELF executable"

    backend = subprocess.Popen([server_path], cwd="/app/c_backend", start_new_session=True)
    try:
        wait_for_port(9000, 5)
        for resource_id in ["12345", "0", "abcXYZ", "987654321"]:
            with socket.create_connection(("127.0.0.1", 9000), timeout=1) as sock:
                sock.sendall((resource_id + "\n").encode())
                reply = sock.recv(1024).decode().strip()
            assert reply == "VALIDATED", f"Unexpected C backend response: {reply!r}"
    finally:
        try:
            os.killpg(backend.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        backend.wait(timeout=5)


def test_python_translation_matches_legacy_algorithm():
    path = "/app/flask_app/crypto_utils.py"
    assert os.path.isfile(path), "crypto_utils.py is missing"
    spec = importlib.util.spec_from_file_location("submitted_crypto_utils", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "validate_signature"), "validate_signature is missing"

    cases = ["12345", "0", "abcXYZ", "987654321", "resource-with-dashes", "café", "emoji-😀"]
    for resource_id in cases:
        actual = module.validate_signature(resource_id, SECRET)
        assert not isinstance(actual, bool), "validate_signature must return the signature string, not a boolean"
        assert actual == expected_signature(resource_id), (
            f"Incorrect translated signature for {resource_id!r}: expected "
            f"{expected_signature(resource_id)!r}, got {actual!r}"
        )


def test_full_started_system_security_correctness_and_throughput():
    stop_services()
    assert os.path.isfile("/app/start_services.sh") and os.access("/app/start_services.sh", os.X_OK)
    subprocess.Popen(
        ["/app/start_services.sh"], cwd="/app", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_for_port(8080, 15)

    resource_ids = ["12345", "0", "abcXYZ", "987654321", "resource-with-dashes"]
    for resource_id in resource_ids:
        status, body = request(resource_id, expected_signature(resource_id))
        assert status == 200, f"Valid request for {resource_id!r} returned HTTP {status}: {body[:200]}"
        assert json.loads(body) == {"data": "VALIDATED"}, f"Wrong response for {resource_id!r}: {body!r}"

        valid = expected_signature(resource_id)
        invalid = valid + "0"
        status, _ = request(resource_id, invalid)
        assert status == 403, f"Invalid signature for {resource_id!r} was not rejected with 403"

    status, _ = request("12345", "")
    assert status == 403, "Missing/empty signature was not rejected with 403"

    work = [resource_ids[i % len(resource_ids)] for i in range(1000)]

    def fetch(resource_id):
        return request(resource_id, expected_signature(resource_id), timeout=3)

    start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=100) as executor:
        results = list(executor.map(fetch, work))
    elapsed = time.time() - start

    failures = []
    successful = 0
    for status, body in results:
        if status != 200:
            failures.append(f"HTTP {status}: {body[:100]}")
            continue
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            failures.append(f"Invalid JSON: {body[:100]}")
            continue
        if payload != {"data": "VALIDATED"}:
            failures.append(f"Wrong payload: {payload!r}")
            continue
        successful += 1

    throughput = successful / elapsed if elapsed else 0.0
    assert successful == 1000, f"Only {successful}/1000 requests succeeded. Samples: {failures[:3]}"
    assert throughput >= 200.0, f"Throughput too low: {throughput:.2f} RPS (threshold: 200 RPS)"


def test_flask_route_really_uses_and_relays_tcp_backend():
    stop_services()
    log_path = "/tmp/mock_backend_received.log"
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass

    mock_source = r'''
import socket
import threading

log_path = "/tmp/mock_backend_received.log"
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 9000))
server.listen(100)

def serve(conn):
    try:
        data = b""
        while b"\n" not in data:
            part = conn.recv(1024)
            if not part:
                break
            data += part
        rid = data.decode("utf-8", "replace").strip()
        with open(log_path, "a") as out:
            out.write(rid + "\n")
        conn.sendall(("MOCK[" + rid + "]\n").encode())
    finally:
        conn.close()

while True:
    conn, _ = server.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
'''
    with open("/tmp/mock_backend.py", "w") as handle:
        handle.write(mock_source)

    mock = subprocess.Popen([sys.executable, "/tmp/mock_backend.py"], start_new_session=True)
    flask = None
    nginx = None
    try:
        wait_for_port(9000, 5)
        flask = subprocess.Popen(
            [sys.executable, "-m", "gunicorn", "-w", "2", "-b", "127.0.0.1:5000", "app:app"],
            cwd="/app/flask_app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        wait_for_port(5000, 10)
        nginx = subprocess.Popen(
            ["nginx", "-c", "/app/nginx.conf"], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )
        wait_for_port(8080, 10)

        resource_ids = ["backend-proof-17", "backend-proof-29", "7654321"]
        for resource_id in resource_ids:
            status, body = request(resource_id, expected_signature(resource_id))
            assert status == 200, f"Valid request returned HTTP {status}: {body[:200]}"
            assert json.loads(body) == {"data": f"MOCK[{resource_id}]"}, (
                "Flask did not relay the response supplied by the TCP backend"
            )

        with open(log_path, "r") as handle:
            received = handle.read().splitlines()
        for resource_id in resource_ids:
            assert resource_id in received, f"C backend did not receive resource ID {resource_id!r}"
    finally:
        for process in [nginx, flask, mock]:
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        stop_services()
        # Leave the submitted system running, as required by the task.
        subprocess.Popen(
            ["/app/start_services.sh"], cwd="/app", stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
