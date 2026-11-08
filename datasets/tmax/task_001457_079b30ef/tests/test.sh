#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import signal
import socket
import ssl
import subprocess
import time
import urllib.request
import pytest

CONF = "/home/user/nginx.conf"
URL = "https://127.0.0.1:8443/"
EXPECTED_BODY = '{"status": "ok"}'


def https_get(timeout=2):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(URL)
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def wait_for_https(timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = https_get()
            if status == 200 and EXPECTED_BODY in body:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"HTTPS service did not become ready: {last_error}")


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def wait_for_process_exit(pid, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_exists(pid):
            return True
        time.sleep(0.1)
    return not process_exists(pid)


def nginx_pid():
    with open("/home/user/nginx.pid", "r") as f:
        value = f.read().strip()
    assert value.isdigit(), "Nginx PID file does not contain a valid PID"
    return int(value)


def effective_nginx_config():
    result = subprocess.run(
        ["nginx", "-T", "-c", CONF],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"nginx configuration is invalid:\n{result.stdout}"
    return result.stdout


def listening_pids_ipv4(port):
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            address_hex, port_hex = local_address.split(":")
            if state == "0A" and int(port_hex, 16) == port and address_hex == "0100007F":
                inodes.add(fields[9])

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_backend(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listening_pids_ipv4(8080)
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def test_symlink_fixed():
    path = "/home/user/app/current"
    assert os.path.islink(path), f"{path} is not a symlink"
    target = os.readlink(path)
    assert target
    assert os.path.realpath(path) == "/home/user/app/releases/v1", \
        f"Symlink {path} does not resolve to /home/user/app/releases/v1"


def test_nginx_conf_proxy_pass():
    path = CONF
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8080;" in content, \
        "nginx.conf does not contain 'proxy_pass http://127.0.0.1:8080;'"

    rendered = effective_nginx_config()
    assert re.search(r"(?m)^\s*proxy_pass\s+http://127\.0\.0\.1:8080;\s*(?:#.*)?$", rendered), \
        "The parsed nginx configuration has no active IPv4 proxy_pass directive"
    assert re.search(r"(?m)^\s*listen\s+8443\s+ssl;\s*(?:#.*)?$", rendered), \
        "The parsed nginx configuration does not actively listen with TLS on port 8443"


def test_nginx_conf_ssl():
    path = CONF
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "ssl_certificate /home/user/cert.pem;" in content, \
        "nginx.conf missing 'ssl_certificate /home/user/cert.pem;'"
    assert "ssl_certificate_key /home/user/key.pem;" in content, \
        "nginx.conf missing 'ssl_certificate_key /home/user/key.pem;'"

    rendered = effective_nginx_config()
    assert re.search(r"(?m)^\s*ssl_certificate\s+/home/user/cert\.pem;\s*(?:#.*)?$", rendered)
    assert re.search(r"(?m)^\s*ssl_certificate_key\s+/home/user/key\.pem;\s*(?:#.*)?$", rendered)


def test_ssl_certificates_exist():
    cert = "/home/user/cert.pem"
    key = "/home/user/key.pem"
    assert os.path.isfile(cert), f"{cert} does not exist"
    assert os.path.isfile(key), f"{key} does not exist"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert, "-pubkey", "-noout"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key, "-pubout"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    ).stdout
    assert cert_pub == key_pub, "The certificate and private key do not match"


def test_nginx_running():
    pid_file = "/home/user/nginx.pid"
    assert os.path.isfile(pid_file), f"Nginx PID file {pid_file} does not exist. Nginx might not be running."
    pid = nginx_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Nginx process with PID {pid} is not running")

    executable = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.basename(executable).startswith("nginx"), \
        f"PID {pid} is not an nginx process: {executable}"
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
    assert "-c" in cmdline and CONF in cmdline, \
        f"Running nginx was not started with the required custom configuration: {cmdline}"

    subprocess.run(["nginx", "-t", "-c", CONF], check=True, timeout=10,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["nginx", "-s", "reload", "-c", CONF], check=True, timeout=10,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    wait_for_https()


def test_health_monitor_script_exists():
    path = "/home/user/health_monitor.py"
    assert os.path.isfile(path), f"File {path} does not exist"
    assert os.path.getsize(path) > 0, f"File {path} is empty"


def test_health_log_content():
    path = "/home/user/health.log"
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "STATUS: UP" in content, f"{path} does not contain 'STATUS: UP'"


def test_services_actually_working():
    status, body = https_get()
    assert status == 200, f"Expected HTTP 200 from Nginx, got {status}"
    assert EXPECTED_BODY in body, "Response body does not match expected backend output"

    backend_pids = wait_for_backend()
    assert backend_pids, "No process is listening on IPv4 127.0.0.1:8080"
    assert len(backend_pids) == 1, f"Expected one backend listener, found PIDs {backend_pids}"
    backend_pid = next(iter(backend_pids))
    with open(f"/proc/{backend_pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
    assert "python3" in cmdline and ("/home/user/app/current/app.py" in cmdline or
                                     "/home/user/app/releases/v1/app.py" in cmdline), \
        f"Port 8080 is not served by the requested Python application: {cmdline}"

    restarted = None
    try:
        os.kill(backend_pid, signal.SIGTERM)
        assert wait_for_process_exit(backend_pid), "Backend process did not stop"
        time.sleep(0.2)
        try:
            stopped_status, stopped_body = https_get()
            assert not (stopped_status == 200 and EXPECTED_BODY in stopped_body), \
                "HTTPS response is a fixed fake and does not depend on the backend"
        except Exception:
            pass
    finally:
        if not listening_pids_ipv4(8080):
            restarted = subprocess.Popen(
                ["python3", "/home/user/app/current/app.py"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        assert wait_for_backend(), "Backend failed to restart"
        wait_for_https()

    served_pem = ssl.get_server_certificate(("127.0.0.1", 8443))
    served_der = ssl.PEM_cert_to_DER_cert(served_pem)
    with open("/home/user/cert.pem", "r") as f:
        configured_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert hashlib.sha256(served_der).digest() == hashlib.sha256(configured_der).digest(), \
        "The TLS endpoint is not serving /home/user/cert.pem"


def test_health_monitor_behavior():
    script = "/home/user/health_monitor.py"
    log = "/home/user/health.log"

    with open(log, "rb") as f:
        before_up = f.read()
    result = subprocess.run(["python3", script], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, f"Health monitor failed against a healthy service: {result.stderr.decode(errors='replace')}"
    with open(log, "rb") as f:
        after_up = f.read()
    assert after_up[len(before_up):] == b"STATUS: UP\n", \
        "Running the health monitor against the live endpoint must append exactly 'STATUS: UP\\n'"

    old_pid = nginx_pid()
    try:
        subprocess.run(["nginx", "-s", "quit", "-c", CONF], check=True, timeout=10,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert wait_for_process_exit(old_pid), "Nginx did not stop for the failure-path check"
        with pytest.raises(Exception):
            https_get(timeout=1)

        with open(log, "rb") as f:
            before_down = f.read()
        result = subprocess.run(["python3", script], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f"Health monitor crashed when the request failed: {result.stderr.decode(errors='replace')}"
        with open(log, "rb") as f:
            after_down = f.read()
        assert after_down[len(before_down):] == b"STATUS: DOWN\n", \
            "Running the health monitor while the endpoint is unavailable must append exactly 'STATUS: DOWN\\n'"
    finally:
        if process_exists(old_pid):
            os.kill(old_pid, signal.SIGTERM)
            wait_for_process_exit(old_pid, timeout=3)
        subprocess.run(["nginx", "-c", CONF], check=True, timeout=10,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        wait_for_https()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
