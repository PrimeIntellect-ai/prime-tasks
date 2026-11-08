#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import ctypes
import json
import os
import random
import signal
import socket
import string
import subprocess
import time
import urllib.error
import urllib.request

SO_PATH = "/home/user/fast_process/libfasthash.so"
URL = "http://localhost:8080/process"


def request_raw(data, content_type="application/json"):
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": content_type}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            body = response.read().decode("utf-8")
            try:
                parsed = json.loads(body)
            except Exception:
                parsed = None
            return response.status, parsed
    except urllib.error.HTTPError as exc:
        exc.read()
        return exc.code, None
    except Exception:
        return None, None


def post_request(payload_dict):
    return request_raw(json.dumps(payload_dict).encode("utf-8"))


def wait_for_fresh_window():
    time.sleep(1.1)


def expected_original_hash(value):
    return len(value) * 100 + ord(value[0]) if value else 0


def listening_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def read_process_launch(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as handle:
        argv = [part.decode("utf-8", "surrogateescape") for part in handle.read().split(b"\0") if part]
    assert argv, "Could not determine the server command line."
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as handle:
        for item in handle.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return argv, cwd, env


def stop_all_listeners():
    deadline = time.time() + 5
    while time.time() < deadline:
        pids = listening_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    assert not listening_pids(), "The original server could not be stopped for the FFI test."


def wait_for_listener(process, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Restarted server exited with status {process.returncode}.")
        if listening_pids():
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                    return
            except OSError:
                pass
        time.sleep(0.1)
    raise AssertionError("Restarted server did not listen on port 8080.")


def test_libfasthash_compiled():
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not found. Did you fix the Makefile and run make?"

    result = subprocess.run(
        ["make", "-B"], cwd="/home/user/fast_process", stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=20
    )
    assert result.returncode == 0, f"Running make failed:\n{result.stdout}"
    assert os.path.isfile(SO_PATH), "make did not produce libfasthash.so."

    try:
        library = ctypes.CDLL(SO_PATH)
        compute_hash = library.compute_hash
    except Exception as exc:
        raise AssertionError(f"libfasthash.so is not a loadable shared library exporting compute_hash: {exc}")
    compute_hash.argtypes = [ctypes.c_char_p]
    compute_hash.restype = ctypes.c_int
    for value in (b"Test", b"A7z9", b"LongPayload123"):
        expected = len(value) * 100 + value[0]
        assert compute_hash(value) == expected, f"compute_hash returned the wrong value for {value!r}."


def test_server_ready_file():
    ready_file = "/home/user/server_ready.txt"
    assert os.path.isfile(ready_file), f"Ready file {ready_file} was not found."
    with open(ready_file, "r") as handle:
        content = handle.read().strip()
    assert content == "READY", f"Expected ready file to contain exactly 'READY', but got '{content}'."


def test_server_valid_request():
    wait_for_fresh_window()
    status, data = post_request({"payload": "Test"})
    assert status == 200, f"Expected HTTP 200 for valid payload, got {status}."
    assert isinstance(data, dict), "Expected a JSON object response."
    assert data.get("hash") == 484, f"Expected hash 484 for 'Test', got {data.get('hash')}."

    alphabet = string.ascii_letters + string.digits
    rng = random.SystemRandom()
    values = [
        "".join(rng.choice(alphabet) for _ in range(rng.randint(2, 18)))
        for _ in range(4)
    ]
    for value in values:
        status, body = post_request({"payload": value})
        assert status == 200, f"Expected HTTP 200 for valid payload {value!r}, got {status}."
        assert isinstance(body, dict), f"Expected a JSON object for {value!r}."
        actual = body.get("hash")
        assert type(actual) is int, f"Expected an integer hash for {value!r}, got {actual!r}."
        assert actual == expected_original_hash(value), f"Wrong hash for randomized payload {value!r}: {actual}."


def test_server_invalid_payload_format():
    wait_for_fresh_window()
    status, _ = post_request({"wrong_key": "Test"})
    assert status == 400, f"Expected HTTP 400 for missing 'payload' key, got {status}."

    malformed_documents = [b"{", b'{"payload":', b"not-json", b""]
    for document in malformed_documents:
        status, _ = request_raw(document)
        assert status == 400, f"Expected HTTP 400 for malformed JSON {document!r}, got {status}."

    wait_for_fresh_window()
    for value in (None, 123, True, ["Test"], {"nested": "Test"}):
        status, _ = post_request({"payload": value})
        assert status == 400, f"Expected HTTP 400 for non-string payload {value!r}, got {status}."


def test_server_invalid_payload_content():
    wait_for_fresh_window()
    status, _ = post_request({"payload": "Test!"})
    assert status == 400, f"Expected HTTP 400 for non-alphanumeric payload, got {status}."

    for value in ("with space", "under_score", "dash-value", "é", "中文"):
        status, _ = post_request({"payload": value})
        assert status == 400, f"Expected HTTP 400 for payload outside ASCII alphanumerics: {value!r}; got {status}."


def test_server_rate_limiting():
    wait_for_fresh_window()

    def make_req(index):
        return post_request({"payload": f"Rate{index}"})[0]

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        results = list(executor.map(make_req, range(6)))

    status_200_count = results.count(200)
    status_429_count = results.count(429)
    assert status_200_count == 5, f"Expected exactly 5 successful requests, got {status_200_count}. Results: {results}"
    assert status_429_count >= 1, f"Expected at least 1 rate-limited request (HTTP 429), got {status_429_count}. Results: {results}"


def test_server_actually_calls_shared_library():
    wait_for_fresh_window()
    pids = listening_pids()
    assert pids, "No process is listening on port 8080."
    pid = min(pids)
    argv, cwd, env = read_process_launch(pid)

    secret = random.SystemRandom().randint(200000, 900000)
    probe_source = f'''#include <string.h>\nint compute_hash(const char *input) {{\n    if (!input) return -1;\n    int n = (int)strlen(input);\n    if (n == 0) return {secret};\n    return {secret} + n * 37 + ((unsigned char)input[0]) * 3 + (unsigned char)input[n-1];\n}}\n'''
    probe_c = "/tmp/fasthash_probe.c"
    probe_so = "/tmp/libfasthash_probe.so"
    with open(probe_c, "w") as handle:
        handle.write(probe_source)
    build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20
    )
    assert build.returncode == 0, f"Could not build verifier probe library:\n{build.stdout}"
    os.replace(probe_so, SO_PATH)

    stop_all_listeners()
    process = subprocess.Popen(
        argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )
    try:
        wait_for_listener(process)
        alphabet = string.ascii_letters + string.digits
        rng = random.SystemRandom()
        values = ["".join(rng.choice(alphabet) for _ in range(rng.randint(3, 16))) for _ in range(4)]
        for value in values:
            status, body = post_request({"payload": value})
            expected = secret + len(value) * 37 + ord(value[0]) * 3 + ord(value[-1])
            assert status == 200, f"Restarted server rejected valid probe payload {value!r} with status {status}."
            assert isinstance(body, dict) and body.get("hash") == expected, (
                "The server did not return the result from the replacement compute_hash implementation; "
                "it appears not to call libfasthash.so through FFI."
            )
    finally:
        try:
            process.kill()
            process.wait(timeout=2)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
