#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import signal
import socket
import string
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/"
COOKIE_NAME = "AuthToken"
COOKIE_VALUE = "DevSecOps_XYZ99"
REDACT_WORD = b"TITAN_PROJECT"
AES_KEY_STR = "5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d"
PORT = 8080


def decrypt_aes_256_cbc(b64_data: str, key_str: str) -> bytes:
    key_hex = key_str.encode("utf-8").hex()
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc",
        "-K", key_hex,
        "-iv", "00" * 16,
        "-base64", "-A",
    ]
    res = subprocess.run(
        cmd, input=b64_data.encode("ascii"), capture_output=True, timeout=5
    )
    if res.returncode != 0:
        raise ValueError(res.stderr.decode("utf-8", errors="ignore"))
    return res.stdout


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def kill_port_listeners(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = []
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
                    victims.append(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def launch_server(path):
    proc = subprocess.Popen(
        [path],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if listener_inodes(PORT):
            return proc
        if proc.poll() is not None:
            pytest.fail(f"{path} exited before listening on 127.0.0.1:8080 (status {proc.returncode})")
        time.sleep(0.05)
    proc.terminate()
    pytest.fail(f"{path} did not listen on 127.0.0.1:8080")


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)
    kill_port_listeners(PORT)


@pytest.fixture(scope="session", autouse=True)
def submitted_server():
    assert os.path.isfile("/home/user/middleware.cpp"), "Source file /home/user/middleware.cpp is missing"
    assert os.path.isfile("/home/user/middleware"), "Compiled binary /home/user/middleware is missing"
    assert os.access("/home/user/middleware", os.X_OK), "Compiled binary is not executable"
    with open("/home/user/middleware", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/middleware is not an ELF binary"

    kill_port_listeners(PORT)
    proc = launch_server("/home/user/middleware")
    state = {"proc": proc}
    yield state
    stop_server(state.get("proc"))


def assert_authorized_round_trip(payload: bytes):
    resp = requests.post(
        URL,
        data=payload,
        headers={"Cookie": f"other={secrets.token_hex(5)}; {COOKIE_NAME}={COOKIE_VALUE}; tail=yes"},
        timeout=5,
    )
    assert resp.status_code == 200, f"Expected 200 for authorized POST, got {resp.status_code}"
    encoded = resp.text.strip()
    assert encoded, "Authorized response body is empty"
    try:
        base64.b64decode(encoded, validate=True)
    except Exception as exc:
        pytest.fail(f"Response is not valid Base64: {exc}")
    try:
        plaintext = decrypt_aes_256_cbc(encoded, AES_KEY_STR)
    except Exception as exc:
        pytest.fail(f"Could not decrypt authorized response: {exc}")
    assert plaintext == payload.replace(REDACT_WORD, b"[REDACTED]")


def test_middleware_source_exists():
    assert os.path.isfile("/home/user/middleware.cpp"), "Source file /home/user/middleware.cpp is missing"


def test_middleware_binary_exists():
    assert os.path.isfile("/home/user/middleware"), "Compiled binary /home/user/middleware is missing"


def test_http_403_on_missing_or_invalid_cookie():
    try:
        resp = requests.post(URL, data="helloworld", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the middleware service: {exc}")
    assert resp.status_code == 403, f"Expected 403 Forbidden for missing cookie, got {resp.status_code}"

    resp = requests.post(URL, data="helloworld", cookies={COOKIE_NAME: "WrongToken"}, timeout=5)
    assert resp.status_code == 403, f"Expected 403 Forbidden for invalid cookie, got {resp.status_code}"


def test_http_200_and_encryption_on_valid_request():
    payload = "The new server for TITAN_PROJECT is deployed."
    expected_redacted = b"The new server for [REDACTED] is deployed."
    resp = requests.post(URL, data=payload, cookies={COOKIE_NAME: COOKIE_VALUE}, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK for valid request, got {resp.status_code}"
    b64_response = resp.text.strip()
    assert b64_response, "Response body is empty, expected base64 encoded encrypted data"
    try:
        decrypted_bytes = decrypt_aes_256_cbc(b64_response, AES_KEY_STR)
    except Exception as exc:
        pytest.fail(f"Could not decrypt the response: {exc}")
    assert decrypted_bytes == expected_redacted


def test_http_200_multiple_redactions():
    payload = "TITAN_PROJECT and TITAN_PROJECT"
    expected_redacted = b"[REDACTED] and [REDACTED]"
    resp = requests.post(URL, data=payload, cookies={COOKIE_NAME: COOKIE_VALUE}, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK for valid request, got {resp.status_code}"
    try:
        decrypted_bytes = decrypt_aes_256_cbc(resp.text.strip(), AES_KEY_STR)
    except Exception as exc:
        pytest.fail(f"Could not decrypt the response: {exc}")
    assert decrypted_bytes == expected_redacted


def test_randomized_authorization_redaction_and_encryption():
    alphabet = string.ascii_letters + string.digits + " _-.,:/"
    rng = secrets.SystemRandom()
    nonce = secrets.token_hex(12).encode()
    payloads = [
        nonce,
        b"prefix-" + nonce + b"-suffix",
        REDACT_WORD + nonce,
        nonce + REDACT_WORD,
        REDACT_WORD + nonce + REDACT_WORD,
        b"A" + REDACT_WORD * 3 + b"Z",
        b"line1\r\n" + nonce + b"\n" + REDACT_WORD + b"\r\nend",
    ]
    for _ in range(9):
        left = "".join(rng.choice(alphabet) for _ in range(rng.randrange(5, 90))).encode()
        right = "".join(rng.choice(alphabet) for _ in range(rng.randrange(5, 90))).encode()
        count = rng.randrange(0, 5)
        payloads.append(left + (REDACT_WORD + nonce) * count + right)
    for payload in payloads:
        assert_authorized_round_trip(payload)


def test_randomized_unauthorized_cookies_are_rejected():
    payload = b"unauthorized-" + secrets.token_bytes(18) + REDACT_WORD
    bad_headers = [
        {},
        {"Cookie": f"{COOKIE_NAME}={secrets.token_hex(16)}"},
        {"Cookie": f"X{COOKIE_NAME}={COOKIE_VALUE}"},
        {"Cookie": f"{COOKIE_NAME}={COOKIE_VALUE}{secrets.token_hex(4)}"},
        {"Cookie": f"other={COOKIE_VALUE}; unrelated={secrets.token_hex(4)}"},
    ]
    for headers in bad_headers:
        resp = requests.post(URL, data=payload, headers=headers, timeout=5)
        assert resp.status_code == 403, f"Unauthorized Cookie header was accepted: {headers!r}"


def test_fragmented_http_request_body_is_fully_read():
    nonce = secrets.token_hex(20).encode()
    payload = b"begin-" + nonce + REDACT_WORD + b"-middle-" + REDACT_WORD + b"-end"
    header = (
        b"POST / HTTP/1.1\r\n"
        b"Host: 127.0.0.1:8080\r\n"
        + f"Cookie: {COOKIE_NAME}={COOKIE_VALUE}\r\n".encode()
        + f"Content-Length: {len(payload)}\r\n".encode()
        + b"Connection: close\r\n\r\n"
    )
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as sock:
        sock.sendall(header[:17])
        time.sleep(0.01)
        sock.sendall(header[17:])
        for pos in range(0, len(payload), 7):
            sock.sendall(payload[pos:pos + 7])
            time.sleep(0.002)
        sock.settimeout(2)
        chunks = []
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
    response = b"".join(chunks)
    head, separator, body = response.partition(b"\r\n\r\n")
    assert separator, f"Malformed HTTP response: {response!r}"
    assert head.split(b"\r\n", 1)[0].startswith(b"HTTP/1.1 200") or head.split(b"\r\n", 1)[0].startswith(b"HTTP/1.0 200")
    decrypted = decrypt_aes_256_cbc(body.strip().decode("ascii"), AES_KEY_STR)
    assert decrypted == payload.replace(REDACT_WORD, b"[REDACTED]")


def test_z_source_builds_and_implements_service(submitted_server):
    compiled = "/tmp/middleware_compiled_from_source"
    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", "/home/user/middleware.cpp", "-o", compiled, "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"middleware.cpp failed to compile:\n{build.stderr}"

    stop_server(submitted_server["proc"])
    submitted_server["proc"] = launch_server(compiled)

    for i in range(7):
        nonce = secrets.token_hex(10 + i).encode()
        payload = nonce + (b"::" + REDACT_WORD) * i + b"::tail"
        assert_authorized_round_trip(payload)

    wrong = secrets.token_hex(15)
    resp = requests.post(URL, data=secrets.token_hex(18), headers={"Cookie": f"{COOKIE_NAME}={wrong}"}, timeout=5)
    assert resp.status_code == 403
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
