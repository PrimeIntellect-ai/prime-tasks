#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import ssl
import socket
import subprocess
import time
import urllib.request
import uuid

import pytest

PORTS = (9001, 9002, 9003)
GATEWAY = "/home/user/gateway.py"
LOG = "/home/user/gateway.log"


def fetch_https(path="/data.txt"):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://localhost:8443" + path)
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        assert response.status == 200
        return response.read().decode("utf-8")


def fetch_http(port, path="/health.txt"):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=3) as response:
        return response.status, response.read().decode("utf-8")


def listening_pids(port):
    result = subprocess.run(
        ["lsof", "-nP", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return {int(line) for line in result.stdout.splitlines() if line.strip().isdigit()}


def only_listener(port):
    pids = listening_pids(port)
    assert len(pids) == 1, f"Expected exactly one listener on port {port}, found {pids}"
    return next(iter(pids))


def cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]


def parent_pid(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("PPid:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine parent of PID {pid}")


def assert_backend_process(port, gateway_pid, pid=None):
    pid = only_listener(port) if pid is None else pid
    assert parent_pid(pid) == gateway_pid, f"Backend {port} is not a child of gateway.py"
    args = cmdline(pid)
    assert "http.server" in args, f"Backend {port} is not Python's built-in HTTP server: {args}"
    assert str(port) in args, f"Backend process command does not specify port {port}: {args}"
    return pid


def gateway_pid():
    pid = only_listener(8443)
    args = cmdline(pid)
    assert any(os.path.abspath(arg) == GATEWAY for arg in args), \
        f"Port 8443 listener is not /home/user/gateway.py: {args}"
    return pid


def wait_until(predicate, timeout=12, interval=0.1, message="condition was not met"):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"{message}; last error: {last_error}")
    raise AssertionError(message)


def test_certs_exist_and_are_correct():
    cert = "/home/user/certs/cert.pem"
    key = "/home/user/certs/key.pem"
    assert os.path.isfile(cert), "cert.pem is missing"
    assert os.path.isfile(key), "key.pem is missing"

    text = subprocess.check_output(["openssl", "x509", "-in", cert, "-noout", "-text"], text=True)
    subject = subprocess.check_output(
        ["openssl", "x509", "-in", cert, "-noout", "-subject", "-nameopt", "RFC2253"], text=True
    )
    issuer = subprocess.check_output(
        ["openssl", "x509", "-in", cert, "-noout", "-issuer", "-nameopt", "RFC2253"], text=True
    )
    assert "Public Key Algorithm: rsaEncryption" in text, "Certificate key is not RSA"
    assert "Public-Key: (2048 bit)" in text, "Certificate does not use a 2048-bit RSA key"
    assert "CN=Migration Gateway" in subject, "Certificate CN is not Migration Gateway"
    assert subject.split("=", 1)[1].strip() == issuer.split("=", 1)[1].strip(), "Certificate is not self-signed"
    subprocess.run(["openssl", "pkey", "-in", key, "-noout"], check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["openssl", "verify", "-CAfile", cert, cert], check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", key, "-pubout"], stderr=subprocess.DEVNULL)
    assert cert_pub == key_pub, "cert.pem and key.pem do not match"

    expected_der = subprocess.check_output(["openssl", "x509", "-in", cert, "-outform", "DER"])
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls:
            served_der = tls.getpeercert(binary_form=True)
    assert served_der == expected_der, "The TLS listener is not serving cert.pem"


def test_backends_setup():
    assert os.path.isfile(GATEWAY), "gateway.py is missing"
    assert os.path.getsize(GATEWAY) > 0, "gateway.py is empty"
    for port in PORTS:
        health_file = f"/home/user/backend_{port}/health.txt"
        data_file = f"/home/user/backend_{port}/data.txt"
        assert os.path.isfile(health_file), f"Missing {health_file}"
        with open(health_file, "r") as f:
            assert "OK" in f.read(), f"health.txt for {port} does not contain OK"
        assert os.path.isfile(data_file), f"Missing {data_file}"
        with open(data_file, "r") as f:
            assert f"DATA FROM {port}" in f.read(), f"data.txt for {port} does not contain expected string"

    gp = gateway_pid()
    backend_pids = {assert_backend_process(port, gp) for port in PORTS}
    assert len(backend_pids) == 3, "The gateway does not manage three distinct backend children"
    for port in PORTS:
        status, body = fetch_http(port)
        assert status == 200 and "OK" in body, f"Backend {port} is not serving its health file"


def test_proxy_round_robin_and_backend_origin():
    time.sleep(2.5)
    token = uuid.uuid4().hex
    originals = {}
    expected = {}
    try:
        for port in PORTS:
            path = f"/home/user/backend_{port}/data.txt"
            with open(path, "rb") as f:
                originals[path] = f.read()
            expected_value = f"DATA FROM {port} {token}-{port}\n"
            with open(path, "w") as f:
                f.write(expected_value)
            expected[port] = expected_value

        responses = [fetch_https("/data.txt") for _ in range(6)]
        assert len(set(responses)) > 0, "Proxy failed to return valid data from backends"
        assert set(responses[:3]) == set(expected.values()), \
            f"First round did not visit every healthy backend exactly once: {responses[:3]}"
        assert responses[3:] == responses[:3], f"Responses are not round-robin: {responses}"
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)


def test_health_check_and_restart():
    gp = gateway_pid()
    old_pid = assert_backend_process(9002, gp)
    assert os.path.isfile(LOG), "gateway.log is missing"
    log_stat = os.stat(LOG)
    log_offset = log_stat.st_size

    health = "/home/user/backend_9002/health.txt"
    hidden = f"{health}.verifier-{uuid.uuid4().hex}"
    os.replace(health, hidden)
    try:
        def old_backend_was_killed():
            return not os.path.exists(f"/proc/{old_pid}") or old_pid not in listening_pids(9002)
        wait_until(old_backend_was_killed, timeout=8,
                   message="Gateway did not kill backend 9002 after its health check returned non-200")
    finally:
        if os.path.exists(hidden):
            os.replace(hidden, health)

    def replacement_ready():
        pids = listening_pids(9002)
        if len(pids) != 1:
            return False
        pid = next(iter(pids))
        if pid == old_pid:
            return False
        assert_backend_process(9002, gp, pid)
        status, body = fetch_http(9002)
        return pid if status == 200 and "OK" in body else False

    new_pid = wait_until(replacement_ready, timeout=12,
                         message="Gateway did not spawn a healthy replacement for backend 9002")
    assert new_pid != old_pid

    down_msg = "[HEALTH] Backend 9002 is DOWN. Restarting..."
    up_msg = "[HEALTH] Backend 9002 is UP."

    def new_log_messages():
        current = os.stat(LOG)
        assert current.st_ino == log_stat.st_ino, "gateway.log was replaced instead of appended"
        assert current.st_size >= log_offset, "gateway.log was truncated"
        with open(LOG, "r", errors="replace") as f:
            f.seek(log_offset)
            suffix = f.read()
        if down_msg in suffix and up_msg in suffix and suffix.index(down_msg) < suffix.index(up_msg):
            return suffix
        return False

    wait_until(new_log_messages, timeout=8,
               message="Fresh ordered DOWN and UP messages were not appended after the induced failure")

    res = fetch_https("/data.txt")
    assert "DATA FROM" in res, "Proxy failed to return valid data after backend restart"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
