#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
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

import pytest


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def generate_jwt(alg="HS256", payload_data="", secret=b"SECRET_KEY_9988776655", invalid_sig=False, missing_sig=False, omit_alg=False):
    header = {"typ": "JWT"}
    if not omit_alg:
        header["alg"] = alg
    payload = {"data": payload_data}

    h_b64 = b64url_encode(json.dumps(header, separators=(",", ":")).encode())
    p_b64 = b64url_encode(json.dumps(payload, separators=(",", ":")).encode())
    msg = f"{h_b64}.{p_b64}".encode()

    if omit_alg or alg.lower() == "none":
        sig = b""
    else:
        sig = hmac.new(secret, msg, hashlib.sha256).digest()

    if invalid_sig:
        sig = bytes([sig[0] ^ 1]) + sig[1:] if sig else b"invalid"

    s_b64 = "" if missing_sig else b64url_encode(sig)
    return f"{h_b64}.{p_b64}.{s_b64}"


def run_agent(token=None, timeout=2):
    cmd = ["python3", "/home/user/secure_auth.py"]
    if token is not None:
        cmd.append(token)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def http_status(url, authorization, timeout=2):
    req = urllib.request.Request(url, headers={"Authorization": authorization})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return ""


def matching_pids(needle):
    result = []
    for entry in os.listdir("/proc"):
        if entry.isdigit() and needle in process_cmdline(entry):
            result.append(int(entry))
    return result


def listening_addresses_for_pid(pid, port):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:["):
                inodes.add(target[8:-1])
    except (FileNotFoundError, PermissionError):
        return []

    addresses = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) < 10 or fields[9] not in inodes or fields[3] != "0A":
                continue
            host_hex, port_hex = fields[1].split(":")
            if int(port_hex, 16) == port:
                addresses.append((table.endswith("tcp6"), host_hex))
    return addresses


def test_secure_auth_exists():
    assert os.path.isfile("/home/user/secure_auth.py"), "secure_auth.py not found at /home/user/secure_auth.py"


def test_nginx_config_updated_and_valid():
    with open("/app/nginx/nginx.conf") as f:
        content = f.read()
    assert "eyJhbGciOiJub25lIg" in content, "Nginx config does not contain the IDS regex for alg=none"
    result = subprocess.run(
        ["nginx", "-t", "-c", "/app/nginx/nginx.conf"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_start_services_updated():
    with open("/app/start_services.sh") as f:
        content = f.read()
    assert "bwrap" in content, "bwrap command not found in start_services.sh"
    assert "secure_auth.py" in content, "secure_auth.py not found in start_services.sh"
    assert "legacy_auth" not in content, "legacy_auth should be removed from start_services.sh"


def test_none_and_missing_algorithms_are_rejected_exactly():
    for token in (
        generate_jwt(alg="none", payload_data="lower"),
        generate_jwt(alg="None", payload_data="mixed"),
        generate_jwt(payload_data="missing", omit_alg=True),
    ):
        result = run_agent(token)
        assert result.returncode == 1
        assert result.stdout.strip() == '{"status": "error", "reason": "invalid_algorithm"}'


def test_fuzz_equivalence_for_valid_tokens_and_rejection_of_bad_signatures():
    random.seed(42)
    oracle_path = "/app/bin/legacy_auth"

    for _ in range(1000):
        length = random.randint(10, 50)
        payload_data = "".join(random.choices(string.ascii_letters + string.digits, k=length))
        choice = random.random()

        if choice < 0.2:
            alg = "none" if choice < 0.1 else "None"
            token = generate_jwt(alg=alg, payload_data=payload_data)
            result = run_agent(token)
            assert result.returncode == 1
            assert result.stdout.strip() == '{"status": "error", "reason": "invalid_algorithm"}'
        elif choice < 0.4:
            token = generate_jwt(payload_data=payload_data, invalid_sig=True)
            result = run_agent(token)
            assert result.returncode != 0, f"Invalid signature was accepted: {token}"
            assert '"status": "success"' not in result.stdout
        elif choice < 0.5:
            token = generate_jwt(payload_data=payload_data, missing_sig=True)
            result = run_agent(token)
            assert result.returncode != 0, f"Missing signature was accepted: {token}"
            assert '"status": "success"' not in result.stdout
        else:
            token = generate_jwt(payload_data=payload_data)
            agent = run_agent(token)
            oracle = subprocess.run([oracle_path, token], capture_output=True, text=True)
            assert agent.stdout == oracle.stdout, f"Mismatch on valid token {token}"
            assert agent.returncode == oracle.returncode


def test_malformed_tokens_are_rejected():
    for token in ("not-a-jwt", "a.b", "a.b.c", "..", ""):
        result = run_agent(token)
        assert result.returncode != 0
        assert '"status": "success"' not in result.stdout


@pytest.fixture(scope="module")
def running_services():
    subprocess.run(["nginx", "-s", "stop", "-c", "/app/nginx/nginx.conf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    proc = subprocess.Popen(
        ["/app/start_services.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid,
    )

    valid_token = generate_jwt(payload_data="service_probe")
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            status, body = http_status("http://127.0.0.1:8080/api/data", f"Bearer {valid_token}", timeout=1)
            if status == 200:
                yield proc, valid_token, body
                break
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    else:
        pytest.fail(f"Services did not become ready: {last_error}")

    if proc.poll() is not None:
        pytest.fail(f"start_services.sh exited before services became ready with code {proc.returncode}")

    subprocess.run(["nginx", "-s", "stop", "-c", "/app/nginx/nginx.conf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def test_services_execute_secure_auth_inside_bwrap(running_services):
    _, valid_token, body = running_services
    assert "success" in body

    python_pids = [
        pid for pid in matching_pids("/home/user/secure_auth.py")
        if "python" in process_cmdline(pid).lower()
    ]
    assert python_pids, "No persistent secure_auth.py Python service is running"
    assert matching_pids("bwrap"), "No running Bubblewrap supervisor was found"

    isolated = False
    local_listener = False
    for pid in python_pids:
        root = f"/proc/{pid}/root"
        if os.path.exists(root + "/home/user") and os.path.exists(root + "/usr") and not os.path.exists(root + "/app"):
            isolated = True
        for is_v6, host_hex in listening_addresses_for_pid(pid, 8081):
            if (not is_v6 and host_hex == "0100007F") or (is_v6 and host_hex == "00000000000000000000000001000000"):
                local_listener = True

    assert isolated, "secure_auth.py can still read /app or is not running in the required restricted filesystem"
    assert local_listener, "secure_auth.py is not listening only on loopback port 8081"

    status, _ = http_status("http://127.0.0.1:8080/api/data", f"Bearer {valid_token}")
    assert status == 200

    bad_token = generate_jwt(payload_data="bad_service_sig", invalid_sig=True)
    status, _ = http_status("http://127.0.0.1:8080/api/data", f"Bearer {bad_token}")
    assert status in (401, 403), "Nginx/auth service accepted an invalid signature"


def test_nginx_drops_none_tokens_without_contacting_auth_service(running_services):
    auth_pids = [
        pid for pid in matching_pids("/home/user/secure_auth.py")
        if "python" in process_cmdline(pid).lower()
    ]
    assert auth_pids
    for pid in auth_pids:
        os.kill(pid, signal.SIGSTOP)

    try:
        none_token = generate_jwt(alg="none", payload_data="ids_probe")
        started = time.monotonic()
        status, _ = http_status(
            "http://127.0.0.1:8080/api/data",
            f"Bearer {none_token}",
            timeout=2,
        )
        elapsed = time.monotonic() - started
        assert status == 403
        assert elapsed < 1.5, "Request reached the stopped auth service instead of being dropped by Nginx"
    finally:
        for pid in auth_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
