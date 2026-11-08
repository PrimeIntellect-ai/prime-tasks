#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

URL = "http://localhost:8081/calculate"
SOURCE = "/home/user/fixed_server.go"
BINARY = "/tmp/verified_collatz_server"


def request(number, timeout=2):
    data = json.dumps({"number": number}).encode("utf-8")
    req = urllib.request.Request(URL, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def expected_collatz(number):
    sequence = []
    while number != 1:
        sequence.append(number)
        if number % 2 == 0:
            number //= 2
        else:
            number = 3 * number + 1
    sequence.append(1)
    return sequence


def listening_inodes(port):
    result = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted_port and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port_users(port):
    inodes = listening_inodes(port)
    if not inodes:
        return
    victims = set()
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
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_poison_input_identified():
    path = "/home/user/poison_input.txt"
    assert os.path.exists(path), f"File {path} does not exist. You must create it."
    with open(path, "r") as handle:
        content = handle.read().strip()
    assert content == "0", f"Expected poison input to be '0', but got '{content}'."


def test_fixed_server_code_exists():
    assert os.path.isfile(SOURCE), f"Fixed server code {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"Fixed server code {SOURCE} is empty."


def test_deployed_server_running_and_normal_request():
    try:
        status, _ = request(5)
    except urllib.error.URLError as error:
        pytest.fail(f"Failed to connect to the fixed server on port 8081. Is it running? Error: {error}")
    assert status == 200, f"Expected HTTP 200 for valid input, got {status}."


def test_deployed_server_handles_poison_input():
    try:
        status, _ = request(0)
    except urllib.error.URLError as error:
        if "timed out" in str(error.reason).lower() or isinstance(error.reason, TimeoutError):
            pytest.fail("Request timed out. The service is likely still stuck in an infinite loop allocating memory.")
        pytest.fail(f"Unexpected connection error when testing poison input: {error}")
    assert status == 400, f"Expected HTTP 400 Bad Request for poison input, but got HTTP {status}."


@pytest.fixture(scope="module")
def compiled_server():
    try:
        build = subprocess.run(
            ["go", "build", "-o", BINARY, SOURCE],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Compiling fixed_server.go timed out.")
    assert build.returncode == 0, f"fixed_server.go does not compile:\n{build.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Go build did not produce an executable."

    kill_port_users(8081)
    process = subprocess.Popen(
        [BINARY],
        cwd="/tmp",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            output = process.stdout.read() if process.stdout else ""
            pytest.fail(f"Compiled server exited before serving on port 8081:\n{output}")
        try:
            with socket.create_connection(("127.0.0.1", 8081), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        pytest.fail("Compiled fixed_server.go did not listen on port 8081.")

    yield process

    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    kill_port_users(8081)


def test_compiled_source_returns_collatz_sequences(compiled_server):
    values = [1, 2, 5, 6, 27]
    rng = secrets.SystemRandom()
    values.extend(rng.sample(range(3, 200), 5))
    for value in values:
        status, body = request(value)
        assert status == 200, f"Expected HTTP 200 for valid input {value}, got {status}."
        try:
            decoded = json.loads(body)
        except Exception as error:
            pytest.fail(f"Response for {value} was not valid JSON: {error}; body={body!r}")
        assert decoded == expected_collatz(value), (
            f"Incorrect Collatz response for {value}: expected {expected_collatz(value)}, got {decoded}."
        )
    assert compiled_server.poll() is None, "Compiled server stopped while handling valid requests."


def test_compiled_source_rejects_all_nonpositive_inputs(compiled_server):
    rng = secrets.SystemRandom()
    invalid_values = [0, -1, -2, -17, -rng.randint(20, 500)]
    for value in invalid_values:
        status, _ = request(value)
        assert status == 400, f"Expected HTTP 400 for invalid input {value}, got HTTP {status}."
        assert compiled_server.poll() is None, f"Compiled server crashed after invalid input {value}."

    status, body = request(11)
    assert status == 200, "Server did not remain usable after rejecting invalid inputs."
    assert json.loads(body) == expected_collatz(11), "Server returned an incorrect result after invalid requests."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
