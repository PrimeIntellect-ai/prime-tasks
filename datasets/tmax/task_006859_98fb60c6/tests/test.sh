#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid

HOME = "/home/user"
SERVER = "/home/user/bin/server"
LIB = "/home/user/lib/libfilter.so"
FILTER_C = "/home/user/c_src/filter.c"
URL = "http://127.0.0.1:8080/api/action"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def send(data, headers=None):
    req = urllib.request.Request(URL, data=data, headers=headers or {}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def start_server():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/lib" + (
        ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
    )
    process = subprocess.Popen(
        [SERVER], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if process.poll() is not None:
            out, err = process.communicate()
            raise AssertionError(
                "Server exited before listening:\n"
                + out.decode(errors="replace")
                + err.decode(errors="replace")
            )
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return process
        except OSError:
            time.sleep(0.1)
    process.terminate()
    process.wait(timeout=3)
    raise AssertionError("Server did not listen on 127.0.0.1:8080")


def stop_server(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=4)


def load_reference():
    spec = importlib.util.spec_from_file_location(
        "limiter_reference_" + uuid.uuid4().hex, "/home/user/legacy/limiter.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.request_counts.clear()
    return module


def test_files_build_and_submitted_tests():
    require(os.path.isfile("/home/user/test_success.log"),
            "/home/user/test_success.log was not created. Did the Go tests pass?")
    require(os.path.isfile("/home/user/src/main.go"), "/home/user/src/main.go is missing.")
    require(os.path.isfile("/home/user/src/main_test.go"), "/home/user/src/main_test.go is missing.")
    require(os.path.isfile("/home/user/Makefile"), "/home/user/Makefile is missing.")

    run(["make", "clean"], cwd=HOME, check=False)
    require(not os.path.exists(SERVER), "'make clean' did not remove /home/user/bin/server")
    require(not os.path.exists(LIB), "'make clean' did not remove /home/user/lib/libfilter.so")

    result = run(["make", "build"], cwd=HOME, capture_output=True, text=True)
    require(result.returncode == 0,
            "'make build' failed:\n" + result.stderr + "\n" + result.stdout)
    require(os.path.isfile(SERVER), "Server executable was not created at /home/user/bin/server")
    require(os.path.isfile(LIB), "Shared library was not created at /home/user/lib/libfilter.so")

    linked = run(["ldd", SERVER], capture_output=True, text=True)
    require(linked.returncode == 0 and "libfilter.so" in linked.stdout,
            "The server is not dynamically linked to libfilter.so")

    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    env["CGO_ENABLED"] = "1"
    env["LD_LIBRARY_PATH"] = "/home/user/lib" + (
        ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
    )
    result = run(
        ["go", "test", "-json", "."], cwd="/home/user/src", env=env,
        capture_output=True, text=True, timeout=120
    )
    require(result.returncode == 0,
            "Submitted Go tests failed:\n" + result.stdout + "\n" + result.stderr)
    executed = set()
    for line in result.stdout.splitlines():
        try:
            event = json.loads(line)
        except Exception:
            continue
        if event.get("Test") and event.get("Action") in ("run", "pass", "fail"):
            executed.add(event["Test"].split("/")[0])
    require(executed, "main_test.go did not execute any Go tests")


def test_original_and_randomized_behavior():
    process = start_server()
    try:
        headers = {"Content-Type": "application/json"}

        # Preserve the original fixed assertions.
        blocked = json.dumps({"user_id": "u1", "action": "jump"}).encode()
        require(send(blocked, {**headers, "X-Forwarded-For": "198.51.100.55"}) == 403,
                "Expected 403 Forbidden for blocked IP")
        require(send(json.dumps({"action": "jump"}).encode(), headers) == 400,
                "Expected 400 Bad Request for missing user_id")
        require(send(b"not a json", headers) == 400,
                "Expected 400 Bad Request for invalid JSON")
        fixed = json.dumps({"user_id": "u2", "action": "jump"}).encode()
        for index in range(3):
            require(send(fixed, headers) == 200,
                    f"Expected 200 OK for u2 request {index + 1}")
        require(send(fixed, headers) == 429,
                "Expected 429 Too Many Requests for fourth u2 request")

        # Exercise unpredictable users and payloads, deriving all answers from limiter.py.
        reference = load_reference()
        token = uuid.uuid4().hex
        cases = [
            b'{"user_id":"' + token.encode() + b'",',
            json.dumps({"action": "act-" + token}).encode(),
            json.dumps({"user_id": "missing-action-" + token}).encode(),
        ]
        for payload in cases:
            expected = reference.handle_request(payload.decode())
            require(send(payload, headers) == expected,
                    f"Server disagreed with limiter.py for payload {payload!r}")

        users = ["user-" + uuid.uuid4().hex for _ in range(random.randint(3, 6))]
        requests = []
        for user in users:
            payload = json.dumps({
                "user_id": user,
                "action": "action-" + uuid.uuid4().hex
            }, separators=(",", ":")).encode()
            for _ in range(random.randint(4, 6)):
                requests.append((payload, reference.handle_request(payload.decode())))
        random.shuffle(requests)
        for payload, expected in requests:
            actual = send(payload, headers)
            require(actual == expected,
                    f"Server returned {actual}, limiter.py returned {expected} for {payload!r}")
    finally:
        stop_server(process)


def test_server_really_uses_c_function():
    with open(FILTER_C, "r", encoding="utf-8") as handle:
        original = handle.read()

    dynamic_ip = f"203.0.113.{random.randint(1, 254)}"
    replacement = '''#include "filter.h"
#include <string.h>
int is_blocked(const char* ip) {
    if (ip == NULL) return 0;
    return strcmp(ip, "DYNAMIC_IP") == 0 ? 1 : 0;
}
'''.replace("DYNAMIC_IP", dynamic_ip)

    process = None
    try:
        with open(FILTER_C, "w", encoding="utf-8") as handle:
            handle.write(replacement)
        # Rebuild only the shared library. The already-built Go executable must
        # observe the changed C behavior through its dynamic CGO linkage.
        result = run(["make", "-B", "lib"], cwd=HOME, capture_output=True, text=True)
        require(result.returncode == 0,
                "Rebuilding lib target failed:\n" + result.stdout + result.stderr)

        process = start_server()
        headers = {"Content-Type": "application/json"}
        payload = json.dumps({
            "user_id": "c-check-" + uuid.uuid4().hex,
            "action": "jump"
        }).encode()
        require(send(payload, {**headers, "X-Forwarded-For": dynamic_ip}) == 403,
                "Server did not use is_blocked from the rebuilt C shared library")

        second = json.dumps({
            "user_id": "old-ip-check-" + uuid.uuid4().hex,
            "action": "jump"
        }).encode()
        require(send(second, {**headers, "X-Forwarded-For": "198.51.100.55"}) == 200,
                "Server appears to hardcode the original blocked IP instead of using is_blocked")
    finally:
        if process is not None:
            stop_server(process)
        with open(FILTER_C, "w", encoding="utf-8") as handle:
            handle.write(original)
        run(["make", "-B", "lib"], cwd=HOME, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, check=False)


def main():
    test_files_build_and_submitted_tests()
    test_original_and_randomized_behavior()
    test_server_really_uses_c_function()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
