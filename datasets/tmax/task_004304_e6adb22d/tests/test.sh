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
import base64
import os
import random
import shutil
import socket
import ssl
import string
import subprocess
import time

import pytest
import requests

requests.packages.urllib3.disable_warnings()


def test_c_source_binary_and_running_process():
    source = "/home/user/proxy.c"
    binary = "/home/user/proxy"

    assert os.path.isfile(source), f"C source {source} does not exist."
    assert os.path.isfile(binary), f"Compiled proxy {binary} does not exist."
    assert os.access(binary, os.X_OK), f"Compiled proxy {binary} is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not an ELF executable."

    rebuilt = "/tmp/proxy_verifier_build"
    result = subprocess.run(
        ["gcc", "-std=gnu11", "-O2", source, "-o", rebuilt,
         "-lssl", "-lcrypto", "-pthread"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"proxy.c does not compile as C:\n{result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    wanted_inodes = set()
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local_addr, state, inode = fields[1], fields[3], fields[9]
            address, port_hex = local_addr.split(":")
            port = int(port_hex, 16)
            if address == "0100007F" and state == "0A" and port in (8080, 8443):
                wanted_inodes.add((port, inode))

    assert {port for port, _ in wanted_inodes} == {8080, 8443}, \
        "Proxy is not listening on both required IPv4 loopback ports."

    binary_stat = os.stat(binary)
    owners = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:["):
                    inode = target[8:-1]
                    for port, wanted in wanted_inodes:
                        if inode == wanted:
                            owners[port] = pid
        except (FileNotFoundError, PermissionError):
            continue

    assert set(owners) == {8080, 8443}, "Could not identify the listener processes."
    for port, pid in owners.items():
        running_stat = os.stat(f"/proc/{pid}/exe")
        assert (running_stat.st_dev, running_stat.st_ino) == (binary_stat.st_dev, binary_stat.st_ino), \
            f"Port {port} is not served by /home/user/proxy."


def test_certificates_exist_and_valid():
    crt_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"

    assert os.path.exists(crt_path), f"Certificate file {crt_path} does not exist."
    assert os.path.exists(key_path), f"Key file {key_path} does not exist."

    try:
        result = subprocess.run(
            ["openssl", "x509", "-in", crt_path, "-noout", "-subject"],
            capture_output=True, text=True, check=True
        )
        assert "*.internal.corp" in result.stdout, "Certificate is not for *.internal.corp"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to parse certificate: {e.stderr}")


def test_proxy_listening():
    def is_port_open(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            return s.connect_ex(("127.0.0.1", port)) == 0

    assert is_port_open(8080), "Proxy is not listening on 127.0.0.1:8080"
    assert is_port_open(8443), "Proxy is not listening on 127.0.0.1:8443"


def test_benign_http_request():
    try:
        response = requests.get(
            "http://127.0.0.1:8080/login",
            headers={"Host": "test.internal.corp"},
            timeout=5
        )
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        assert "CLEAN" in response.text, "Response did not contain the expected output from the binary."
    except requests.RequestException as e:
        pytest.fail(f"Benign HTTP request failed: {e}")


def test_benign_https_request():
    try:
        response = requests.get(
            "https://127.0.0.1:8443/login",
            headers={"Host": "test.internal.corp"},
            verify=False,
            timeout=5
        )
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        assert "CLEAN" in response.text, "Response did not contain the expected output from the binary."
    except requests.RequestException as e:
        pytest.fail(f"Benign HTTPS request failed: {e}")


def test_malicious_http_request_dropped():
    malicious_headers = {
        "Host": "test.internal.corp",
        "Referer": "http://test.internal.corp//evil.com/%2e%2e"
    }
    try:
        response = requests.get(
            "http://127.0.0.1:8080/login",
            headers=malicious_headers,
            timeout=5
        )
        pytest.fail(f"Expected connection to be dropped, but received response: {response.status_code}")
    except requests.exceptions.ConnectionError:
        pass
    except requests.RequestException as e:
        pytest.fail(f"Unexpected exception during malicious HTTP request: {e}")


def test_malicious_https_request_dropped():
    malicious_headers = {
        "Host": "test.internal.corp",
        "Referer": "http://test.internal.corp//evil.com/%2e%2e"
    }
    try:
        response = requests.get(
            "https://127.0.0.1:8443/login",
            headers=malicious_headers,
            verify=False,
            timeout=5
        )
        pytest.fail(f"Expected connection to be dropped, but received response: {response.status_code}")
    except requests.exceptions.ConnectionError:
        pass
    except requests.RequestException as e:
        pytest.fail(f"Unexpected exception during malicious HTTPS request: {e}")


def test_security_drops_log():
    log_path = "/home/user/security_drops.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    expected_log_entry = "[DROP] IP=127.0.0.1 Payload=aHR0cDovL3Rlc3QuaW50ZXJuYWwuY29ycC8vZXZpbC5jb20vJTJlJTJl"
    with open(log_path, "r") as f:
        logs = f.read()
    assert expected_log_entry in logs, f"Expected log entry '{expected_log_entry}' not found in {log_path}."


def _random_text(prefix):
    alphabet = string.ascii_lowercase + string.digits
    return prefix + "".join(random.SystemRandom().choice(alphabet) for _ in range(18))


def _expect_raw_drop(port, referer, use_tls):
    raw = (
        f"GET /{_random_text('audit-')} HTTP/1.1\r\n"
        "Host: test.internal.corp\r\n"
        f"Referer: {referer}\r\n"
        "Connection: close\r\n\r\n"
    ).encode("ascii")

    sock = socket.create_connection(("127.0.0.1", port), timeout=4)
    if use_tls:
        context = ssl._create_unverified_context()
        sock = context.wrap_socket(sock, server_hostname="test.internal.corp")
    sock.settimeout(4)
    try:
        sock.sendall(raw)
        try:
            data = sock.recv(4096)
        except (ConnectionResetError, BrokenPipeError, ssl.SSLError):
            return
        assert data == b"", f"Expected connection drop on port {port}, received {data[:100]!r}"
    except socket.timeout:
        pytest.fail(f"Malicious connection on port {port} was not immediately dropped.")
    finally:
        sock.close()


def test_dynamic_inspector_invocation_and_randomized_crash_payloads():
    inspector = "/app/traffic_inspector"
    backup = "/tmp/traffic_inspector.verifier.backup"
    replacement = "/tmp/traffic_inspector.verifier.replacement"
    nonce_file = "/tmp/traffic_inspector.verifier.nonce"
    calls_file = "/tmp/traffic_inspector.verifier.calls"

    shutil.copy2(inspector, backup)
    wrapper = f'''#!/usr/bin/python3
import os, sys
data = sys.stdin.buffer.read()
with open({calls_file!r}, "ab") as f:
    f.write(data + b"\\0")
with open({nonce_file!r}, "rb") as f:
    token = f.read()
sys.stdout.buffer.write(token + b"\\n")
'''
    with open(replacement, "w") as f:
        f.write(wrapper)
    os.chmod(replacement, 0o755)

    try:
        os.replace(replacement, inspector)

        for port, scheme, verify in ((8080, "http", True), (8443, "https", False)):
            token = _random_text("INSPECTOR_PROOF_")
            header_value = _random_text("header-")
            cookie_value = _random_text("cookie-")
            with open(nonce_file, "w") as f:
                f.write(token)
            open(calls_file, "wb").close()

            response = requests.get(
                f"{scheme}://127.0.0.1:{port}/{_random_text('benign-')}",
                headers={
                    "Host": "test.internal.corp",
                    "X-Audit-Value": header_value,
                    "Cookie": f"audit={cookie_value}"
                },
                verify=verify,
                timeout=5
            )
            assert response.status_code == 200
            assert token in response.text, \
                f"Port {port} did not return dynamically generated inspector output."
            with open(calls_file, "rb") as f:
                passed = f.read()
            assert header_value.encode() in passed, "Benign headers were not passed to traffic_inspector."
            assert cookie_value.encode() in passed, "Benign cookies were not passed to traffic_inspector."

        log_path = "/home/user/security_drops.log"
        for port, use_tls in ((8080, False), (8443, True)):
            origin = _random_text("origin-") + ".internal.corp"
            target = _random_text("redirect-") + ".example"
            suffix = _random_text("q")
            referer = f"https://{origin}/login//{target}/%2e%2e?{suffix}"
            expected = "[DROP] IP=127.0.0.1 Payload=" + base64.b64encode(referer.encode()).decode()

            open(calls_file, "wb").close()
            start = os.path.getsize(log_path) if os.path.exists(log_path) else 0
            _expect_raw_drop(port, referer, use_tls)

            with open(calls_file, "rb") as f:
                assert f.read() == b"", \
                    f"Crash-triggering request on port {port} was sent to traffic_inspector."

            added = ""
            deadline = time.time() + 2
            while time.time() < deadline:
                if os.path.exists(log_path):
                    with open(log_path, "r", errors="replace") as f:
                        f.seek(start)
                        added = f.read()
                    if expected in added:
                        break
                time.sleep(0.05)
            assert expected in added, \
                f"Fresh randomized drop was not logged correctly on port {port}."
    finally:
        if os.path.exists(backup):
            os.replace(backup, inspector)
        for path in (replacement, nonce_file, calls_file):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
