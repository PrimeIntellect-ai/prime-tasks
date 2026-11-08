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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import time
from urllib.parse import quote

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
LOGIN_URL = f"{BASE_URL}/login"
CSP = "default-src 'self';"


def wait_for_server():
    max_retries = 10
    for _ in range(max_retries):
        try:
            requests.get(BASE_URL, timeout=1)
            return
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)
        except requests.exceptions.Timeout:
            pass
    pytest.fail("Server is not listening on 127.0.0.1:8080")


def listening_pids():
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            address, port = local_address.split(":")
            if address == "0100007F" and port.upper() == "1F90" and state == "0A":
                inodes.add(fields[9])

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
                    break
        except OSError:
            continue
    return owners


def make_token(password):
    output = subprocess.check_output(
        ["/app/legacy_crypto", password], text=True, timeout=2
    ).strip()
    assert len(output) == 8
    int(output, 16)
    return output


def random_password():
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(4))


def assert_success(response, password):
    assert response.status_code == 200, (
        f"Expected status 200, got {response.status_code}. Response: {response.text!r}"
    )
    assert response.headers.get("Content-Security-Policy") == CSP, (
        "Missing or incorrect CSP header. Got: "
        f"{response.headers.get('Content-Security-Policy', '')!r}"
    )
    assert response.text == password, (
        f"Expected exact body {password!r}, got {response.text!r}"
    )


@pytest.fixture(scope="module", autouse=True)
def setup():
    wait_for_server()


def test_server_is_native_executable():
    pids = listening_pids()
    assert pids, "No process owns a listening IPv4 socket on 127.0.0.1:8080"

    interpreter_names = {
        "python", "python3", "pypy", "pypy3", "bash", "sh", "dash", "zsh",
        "node", "nodejs", "perl", "ruby", "php", "java"
    }
    for pid in pids:
        exe_link = f"/proc/{pid}/exe"
        try:
            exe_name = os.path.basename(os.readlink(exe_link)).split(" ")[0].lower()
            with open(exe_link, "rb") as f:
                magic = f.read(4)
        except OSError as exc:
            pytest.fail(f"Cannot inspect listening process {pid}: {exc}")
        assert magic == b"\x7fELF", f"Listening process {pid} is not a native ELF executable"
        assert exe_name not in interpreter_names, (
            f"Listening service is running under interpreter {exe_name!r}, not as a compiled server"
        )


def test_valid_login_test():
    data = {"token": "46554746", "redirect": "/home"}
    try:
        response = requests.post(LOGIN_URL, data=data, timeout=2)
    except Exception as e:
        pytest.fail(f"Failed to connect or send request: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    csp_header = response.headers.get("Content-Security-Policy", "")
    assert "default-src 'self';" in csp_header, f"Missing or incorrect CSP header. Got: {csp_header}"
    assert response.text.strip() == "test", f"Expected body 'test', got '{response.text}'"


def test_invalid_redirect_http():
    data = {"token": "46554746", "redirect": "http://evil.com"}
    try:
        response = requests.post(LOGIN_URL, data=data, timeout=2)
    except Exception as e:
        pytest.fail(f"Failed to connect or send request: {e}")
    assert response.status_code == 400, f"Expected status 400 for absolute redirect, got {response.status_code}. Response: {response.text}"


def test_invalid_redirect_protocol_relative():
    data = {"token": "445b5b46", "redirect": "//attacker.com"}
    try:
        response = requests.post(LOGIN_URL, data=data, timeout=2)
    except Exception as e:
        pytest.fail(f"Failed to connect or send request: {e}")
    assert response.status_code == 400, f"Expected status 400 for protocol-relative redirect, got {response.status_code}. Response: {response.text}"


def test_valid_login_root():
    data = {"token": "445b5b46", "redirect": "/settings"}
    try:
        response = requests.post(LOGIN_URL, data=data, timeout=2)
    except Exception as e:
        pytest.fail(f"Failed to connect or send request: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    csp_header = response.headers.get("Content-Security-Policy", "")
    assert "default-src 'self';" in csp_header, f"Missing or incorrect CSP header. Got: {csp_header}"
    assert response.text.strip() == "root", f"Expected body 'root', got '{response.text}'"


def test_random_tokens_and_local_redirects():
    seen = set()
    while len(seen) < 6:
        seen.add(random_password())

    for index, password in enumerate(seen):
        token = make_token(password)
        redirect = f"/local/{secrets.token_hex(6)}/{index}"
        response = requests.post(
            LOGIN_URL,
            data={"redirect": redirect, "token": token, "extra": "ignored"},
            timeout=2,
        )
        assert_success(response, password)


def percent_encode_all(value):
    return "".join(f"%{byte:02X}" for byte in value.encode("ascii"))


def test_url_form_decoding_with_random_token():
    password = random_password()
    token = make_token(password)
    redirect = f"/encoded path/{secrets.token_hex(5)}"
    body = (
        f"%74%6F%6B%65%6E={percent_encode_all(token)}"
        f"&%72%65%64%69%72%65%63%74={percent_encode_all(redirect)}"
    )
    response = requests.post(
        LOGIN_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=2,
    )
    assert_success(response, password)


def test_encoded_random_absolute_redirects_are_rejected():
    password = random_password()
    token = make_token(password)
    host = f"{secrets.token_hex(8)}.invalid"
    redirects = [f"https://{host}/login", f"//{host}/next", f"http://{host}/"]

    for redirect in redirects:
        body = f"token={quote(token)}&redirect={quote(redirect, safe='')}"
        response = requests.post(
            LOGIN_URL,
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=2,
        )
        assert response.status_code == 400, (
            f"Expected 400 for decoded absolute redirect {redirect!r}, "
            f"got {response.status_code}: {response.text!r}"
        )


def test_non_local_redirect_is_rejected():
    password = random_password()
    response = requests.post(
        LOGIN_URL,
        data={"token": make_token(password), "redirect": f"relative-{secrets.token_hex(6)}"},
        timeout=2,
    )
    assert response.status_code == 400, (
        f"Expected 400 for redirect not starting with '/', got {response.status_code}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
