#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import signal
import socket
import ssl
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def terminate_listeners(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_listener(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids(port):
            return
        time.sleep(0.1)
    pytest.fail(f"No service began listening on port {port}")


def process_description(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            comm = f.read().strip()
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
        return comm + " " + cmd
    except (FileNotFoundError, ProcessLookupError):
        return ""


def https_get(path="/status", timeout=5):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://127.0.0.1:8443" + path)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8"), response.headers
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace"), exc.headers


def test_nginx_config_fixed():
    nginx_conf = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf), f"Nginx config {nginx_conf} is missing."
    with open(nginx_conf, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:9000;" in content, "Nginx config was not updated to proxy to port 9000."

    config_check = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf], capture_output=True, text=True
    )
    assert config_check.returncode == 0, (
        f"Nginx rejected the submitted configuration:\n{config_check.stdout}\n{config_check.stderr}"
    )


def test_tls_certificates_exist_and_valid():
    cert_file = "/home/user/nginx/certs/server.crt"
    key_file = "/home/user/nginx/certs/server.key"
    assert os.path.isfile(cert_file), f"Certificate file {cert_file} is missing."
    assert os.path.isfile(key_file), f"Key file {key_file} is missing."

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-text", "-noout"], capture_output=True
    )
    assert cert_check.returncode == 0, f"Certificate {cert_file} is not a valid X509 certificate."

    key_check = subprocess.run(
        ["openssl", "rsa", "-in", key_file, "-check", "-noout"], capture_output=True
    )
    assert key_check.returncode == 0, f"Key {key_file} is not a valid RSA key."
    with open(key_file, "rb") as f:
        assert b"ENCRYPTED" not in f.read(), "The RSA private key must be unencrypted."

    cert_info = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-startdate", "-enddate", "-subject", "-issuer"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    values = dict(line.split("=", 1) for line in cert_info if "=" in line)
    assert values.get("subject") == values.get("issuer"), "The certificate is not self-signed."

    date_format = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], date_format).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values["notAfter"], date_format).replace(tzinfo=datetime.timezone.utc)
    lifetime = (not_after - not_before).total_seconds()
    assert abs(lifetime - 365 * 24 * 60 * 60) <= 300, "Certificate validity period is not 365 days."
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."

    self_verify = subprocess.run(
        ["openssl", "verify", "-CAfile", cert_file, cert_file], capture_output=True, text=True
    )
    assert self_verify.returncode == 0, f"Certificate self-signature is invalid: {self_verify.stderr}"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-pubkey", "-noout"], capture_output=True, check=True
    ).stdout
    cert_der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub, capture_output=True, check=True
    ).stdout
    key_der = subprocess.run(
        ["openssl", "pkey", "-in", key_file, "-pubout", "-outform", "DER"],
        capture_output=True,
        check=True,
    ).stdout
    assert cert_der == key_der, "Certificate and private key do not match."


class MockSMTP(threading.Thread):
    def __init__(self, bad_stage=None):
        super().__init__(daemon=True)
        self.bad_stage = bad_stage
        self.ready = threading.Event()
        self.commands = []
        self.error = None

    @staticmethod
    def recv_command(conn):
        data = bytearray()
        while len(data) < 4096:
            part = conn.recv(1)
            if not part:
                break
            if part in (b"\r", b"\n"):
                if data:
                    break
                continue
            data.extend(part)
        return data.decode(errors="replace").strip()

    def run(self):
        try:
            with socket.socket() as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 2525))
                server.listen(1)
                server.settimeout(8)
                self.ready.set()
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(6)
                    conn.sendall(b"554 wrong greeting\r\n" if self.bad_stage == 220 else b"220 mock relay ready\r\n")
                    if self.bad_stage == 220:
                        time.sleep(1)
                        return
                    helo = self.recv_command(conn)
                    self.commands.append(helo)
                    conn.sendall(b"550 HELO rejected\r\n" if self.bad_stage == 250 else b"250 hello localhost\r\n")
                    if self.bad_stage == 250:
                        time.sleep(1)
                        return
                    quit_command = self.recv_command(conn)
                    self.commands.append(quit_command)
                    conn.sendall(b"500 QUIT rejected\r\n" if self.bad_stage == 221 else b"221 goodbye\r\n")
        except Exception as exc:
            self.error = exc
            self.ready.set()


def run_expect(script, timeout=8):
    proc = subprocess.Popen(
        ["expect", script], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        return proc.returncode, stdout, stderr
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        return None, stdout, stderr


def test_expect_script_exists_and_works():
    expect_script = "/home/user/test_smtp.exp"
    assert os.path.isfile(expect_script), f"Expect script {expect_script} is missing."
    with open(expect_script) as f:
        script_text = f.read()

    assert re.search(r"(?im)^\s*spawn\s+.*\b(?:nc|netcat|telnet)\b.*127\.0\.0\.1.*2525", script_text), (
        "Expect script must spawn nc/netcat or telnet to 127.0.0.1 port 2525."
    )
    ordered = re.search(
        r"expect[\s\S]*?220[\s\S]*?send[\s\S]*?HELO\s+localhost[\s\S]*?expect[\s\S]*?250"
        r"[\s\S]*?send[\s\S]*?QUIT[\s\S]*?expect[\s\S]*?221",
        script_text,
        re.IGNORECASE,
    )
    assert ordered, "Expect script does not perform the required 220/HELO/250/QUIT/221 exchange."

    terminate_listeners(2525)
    smtp = MockSMTP()
    smtp.start()
    assert smtp.ready.wait(2) and smtp.error is None, f"Could not start mock SMTP server: {smtp.error}"
    result_code, stdout, stderr = run_expect(expect_script)
    smtp.join(timeout=2)
    assert result_code == 0, f"Expect script failed to execute properly. Output: {stdout}\n{stderr}"
    assert smtp.error is None, f"SMTP exchange failed: {smtp.error}"
    assert len(smtp.commands) == 2, f"Expected HELO and QUIT, received {smtp.commands!r}"
    assert smtp.commands[0].upper() == "HELO LOCALHOST", f"Wrong HELO command: {smtp.commands[0]!r}"
    assert smtp.commands[1].upper() == "QUIT", f"Wrong QUIT command: {smtp.commands[1]!r}"

    # A diagnostic script must not report success when any required SMTP reply is absent.
    for bad_stage in (220, 250, 221):
        terminate_listeners(2525)
        bad_server = MockSMTP(bad_stage)
        bad_server.start()
        assert bad_server.ready.wait(2) and bad_server.error is None
        code, _, _ = run_expect(expect_script, timeout=6)
        bad_server.join(timeout=2)
        assert code != 0, f"Expect script falsely succeeded without receiving SMTP {bad_stage}."


def test_start_script_and_endpoint_accessibility():
    start_script = "/home/user/start_all.sh"
    assert os.path.isfile(start_script), f"Startup script {start_script} is missing."

    terminate_listeners(8443)
    terminate_listeners(9000)
    result = subprocess.run(
        ["bash", start_script], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"start_all.sh did not exit cleanly:\n{result.stdout}\n{result.stderr}"
    )
    wait_for_listener(9000)
    wait_for_listener(8443)

    backend_pids = listener_pids(9000)
    assert any(
        "python" in process_description(pid).lower()
        and "/home/user/app/server.py" in process_description(pid)
        for pid in backend_pids
    ), "Port 9000 was not started by python3 /home/user/app/server.py."

    nginx_pids = listener_pids(8443)
    assert any("nginx" in process_description(pid).lower() for pid in nginx_pids), (
        "HTTPS port 8443 is not actually being served by Nginx."
    )

    status, body, headers = https_get()
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert body == "OK", f"Expected body 'OK', got '{body}'"
    assert headers.get("Server", "").lower().startswith("nginx"), (
        f"HTTPS response was not identified as Nginx: {headers.get('Server')!r}"
    )

    # Prove the Nginx response depends on the backend listening on the corrected port,
    # rather than being a static or unrelated HTTPS response.
    terminate_listeners(9000)
    down_status, down_body, _ = https_get(timeout=4)
    assert not (down_status == 200 and down_body == "OK"), (
        "Nginx still returned the backend response while port 9000 was offline."
    )

    subprocess.Popen(
        ["python3", "/home/user/app/server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_listener(9000)
    status, body, headers = https_get()
    assert status == 200, f"Expected HTTP 200 after backend restart, got {status}"
    assert body == "OK", f"Expected body 'OK' after backend restart, got '{body}'"
    assert headers.get("Server", "").lower().startswith("nginx")


def test_result_log():
    result_log = "/home/user/result.log"
    assert os.path.isfile(result_log), f"Result log {result_log} is missing."
    with open(result_log, "r") as f:
        content = f.read().strip()
    assert "200" in content, f"Expected '200' in {result_log}, got '{content}'"
    assert content == "200", f"{result_log} must contain the exact HTTP status code, got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
