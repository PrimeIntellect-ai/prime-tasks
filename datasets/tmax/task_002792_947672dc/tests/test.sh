#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import socket
import ssl
import subprocess
from pathlib import Path

import pytest

USER_UID = pwd.getpwnam("user").pw_uid
DATA_DIR = "/home/user/nginx_data/"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def listener_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port:
                    found.add(fields[9])
    return found


def processes_holding(inodes):
    holders = []
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            links = {os.readlink(fd) for fd in (proc / "fd").iterdir()}
            if not links.intersection(wanted):
                continue
            cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            status = (proc / "status").read_text()
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
            exe = os.path.realpath(proc / "exe")
            holders.append((int(proc.name), uid, exe, cmdline))
        except (OSError, ValueError, AttributeError):
            continue
    return holders


def directive_path(config, name):
    matches = re.findall(rf"(?m)^\s*{re.escape(name)}\s+([^;\s]+)(?:\s+[^;]*)?;", config)
    assert matches, f"Required directive {name} is missing"
    path = matches[0]
    assert os.path.isabs(path), f"{name} must use an absolute path"
    assert path.startswith(DATA_DIR), f"{name} must point inside {DATA_DIR}, got {path}"
    return path


def assert_user_writable_directory(path):
    assert os.path.isdir(path), f"Required directory does not exist: {path}"
    result = run(["runuser", "-u", "user", "--", "test", "-w", path])
    assert result.returncode == 0, f"Directory is not writable by user: {path}"


def test_required_artifacts_and_nginx_configuration():
    cert = "/home/user/cert.pem"
    key = "/home/user/key.pem"
    conf = "/home/user/nginx.conf"
    for path in (cert, key, conf):
        assert os.path.isfile(path), f"Required file missing: {path}"

    cert_text = run(["openssl", "x509", "-in", cert, "-noout", "-text"])
    assert cert_text.returncode == 0, cert_text.stderr
    assert "Public-Key: (2048 bit)" in cert_text.stdout, "Certificate must contain a 2048-bit RSA key"
    assert "Signature Algorithm: sha256WithRSAEncryption" in cert_text.stdout, "Certificate must use SHA256 with RSA"

    subject = run(["openssl", "x509", "-in", cert, "-noout", "-subject", "-nameopt", "RFC2253"])
    issuer = run(["openssl", "x509", "-in", cert, "-noout", "-issuer", "-nameopt", "RFC2253"])
    assert subject.returncode == issuer.returncode == 0
    assert subject.stdout.strip().split("=", 1)[-1] == issuer.stdout.strip().split("=", 1)[-1], "Certificate is not self-signed"
    verify = run(["openssl", "verify", "-CAfile", cert, cert])
    assert verify.returncode == 0, f"Self-signed certificate verification failed: {verify.stderr}"

    cert_pub = subprocess.run(["openssl", "x509", "-in", cert, "-pubkey", "-noout"], capture_output=True)
    key_pub = subprocess.run(["openssl", "pkey", "-in", key, "-pubout"], capture_output=True)
    assert cert_pub.returncode == key_pub.returncode == 0, "Unable to read certificate or private key"
    assert cert_pub.stdout == key_pub.stdout, "Private key does not match the certificate"

    tested = run(["runuser", "-u", "user", "--", "nginx", "-t", "-c", conf])
    assert tested.returncode == 0, f"nginx configuration is not valid for user: {tested.stdout}\n{tested.stderr}"
    dumped = run(["runuser", "-u", "user", "--", "nginx", "-T", "-c", conf])
    assert dumped.returncode == 0, f"Could not inspect nginx configuration: {dumped.stderr}"
    config = dumped.stdout + "\n" + dumped.stderr

    listens = re.findall(r"(?m)^\s*listen\s+([^;]+);", config)
    assert any(re.search(r"(?:^|\s)127\.0\.0\.1:8443(?:\s|$)", value) and re.search(r"(?:^|\s)ssl(?:\s|$)", value) for value in listens), "Nginx must listen with SSL on 127.0.0.1:8443"
    assert re.search(r"(?m)^\s*ssl_certificate\s+/home/user/cert\.pem\s*;", config)
    assert re.search(r"(?m)^\s*ssl_certificate_key\s+/home/user/key\.pem\s*;", config)
    assert re.search(r"location\s+/\s*\{[^{}]*\bproxy_pass\s+http://127\.0\.0\.1:8080\s*;", config, re.S), "location / must proxy to the specified backend"

    assert_user_writable_directory(DATA_DIR.rstrip("/"))
    file_directives = ("pid", "access_log", "error_log")
    temp_directives = ("client_body_temp_path", "proxy_temp_path", "fastcgi_temp_path", "uwsgi_temp_path", "scgi_temp_path")
    for name in file_directives:
        path = directive_path(config, name)
        assert_user_writable_directory(os.path.dirname(path))
    for name in temp_directives:
        path = directive_path(config, name)
        assert_user_writable_directory(path)


def test_required_processes_own_the_listening_ports():
    nginx_sockets = listener_inodes(8443)
    backend_sockets = listener_inodes(8080)
    assert nginx_sockets, "Nothing is listening on TCP port 8443"
    assert backend_sockets, "Nothing is listening on TCP port 8080"

    nginx_holders = processes_holding(nginx_sockets)
    backend_holders = processes_holding(backend_sockets)
    assert nginx_holders, "Could not identify the process listening on port 8443"
    assert backend_holders, "Could not identify the process listening on port 8080"
    assert all(os.path.basename(p[2]) == "nginx" for p in nginx_holders), f"Port 8443 is not owned exclusively by nginx: {nginx_holders}"
    assert all(p[1] == USER_UID for p in nginx_holders), "Nginx listening processes must run as user"
    assert any("/app/backend.py" in p[3] for p in backend_holders), f"Port 8080 is not served by /app/backend.py: {backend_holders}"
    assert all(p[1] == USER_UID for p in backend_holders), "Backend listening process must run as user"

    nginx_processes = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if os.path.basename(os.path.realpath(proc / "exe")) != "nginx":
                continue
            cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            status = (proc / "status").read_text()
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
            nginx_processes.append((uid, cmdline))
        except (OSError, ValueError, AttributeError):
            pass
    assert any(uid == USER_UID and "/home/user/nginx.conf" in cmd for uid, cmd in nginx_processes), "No user-owned nginx process was started with /home/user/nginx.conf"


def test_services_running_and_proxying():
    try:
        result = subprocess.run(
            ["curl", "-s", "-k", "https://127.0.0.1:8443/"],
            capture_output=True,
            text=True,
            timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Timeout while trying to connect to Nginx on https://127.0.0.1:8443/")
    except FileNotFoundError:
        pytest.fail("curl command not found")

    assert result.returncode == 0, f"curl failed to connect to the reverse proxy. Return code: {result.returncode}, Stderr: {result.stderr}"
    assert "BACKEND_OK" in result.stdout, f"Expected 'BACKEND_OK' from the backend, but got: {result.stdout}"

    random_path = "/verify-" + secrets.token_hex(12) + "?request=" + secrets.token_hex(8)
    dynamic = run(["curl", "-s", "-k", "https://127.0.0.1:8443" + random_path], timeout=5)
    assert dynamic.returncode == 0 and "BACKEND_OK" in dynamic.stdout, "A fresh path was not proxied to the backend"

    live_der = ssl.get_server_certificate(("127.0.0.1", 8443))
    live_der = ssl.PEM_cert_to_DER_cert(live_der)
    file_pem = Path("/home/user/cert.pem").read_text()
    file_der = ssl.PEM_cert_to_DER_cert(file_pem)
    assert live_der == file_der, "The HTTPS listener is not serving /home/user/cert.pem"


def invoke_filter(script, payload):
    return subprocess.run(["bash", script, payload], capture_output=True, timeout=3).returncode


def test_filter_script_adversarial_corpus():
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path), f"Filter script not found at {script_path}"

    clean_corpus_path = "/app/corpus/clean.txt"
    evil_corpus_path = "/app/corpus/evil.txt"

    assert os.path.isfile(clean_corpus_path), f"Clean corpus missing at {clean_corpus_path}"
    assert os.path.isfile(evil_corpus_path), f"Evil corpus missing at {evil_corpus_path}"

    with open(clean_corpus_path, "r") as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    with open(evil_corpus_path, "r") as f:
        evil_lines = [line.strip() for line in f if line.strip()]

    clean_failures = []
    for line in clean_lines:
        result = subprocess.run(["bash", script_path, line], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(line)

    evil_failures = []
    for line in evil_lines:
        result = subprocess.run(["bash", script_path, line], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(line)

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_lines)} clean modified/rejected: {clean_failures}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_lines)} evil bypassed/accepted: {evil_failures}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_filter_on_fresh_derived_cases():
    script = "/home/user/filter.sh"
    assert os.path.isfile(script)
    syntax = run(["bash", "-n", script])
    assert syntax.returncode == 0, f"filter.sh is not valid Bash: {syntax.stderr}"

    token = secrets.token_hex(10)
    other = secrets.token_hex(7)
    clean = [
        "/" + token,
        f"/images/{token}-{other}.png",
        f"/api/v2/{token}?user={other}&sort=desc",
        f"/login?redirect=/{token}",
        f"/profile_{token}?id=98765&mode=safe",
        f"/about-{token}.html",
    ]
    for i in range(8):
        fresh = secrets.token_hex(6)
        clean.append(f"/section_{fresh}/item-{i}.json?key={fresh}&value={i}")

    domain = token + ".example"
    evil = [
        f"/login?redirect=http://{domain}/{other}",
        f"/login?redirect=https://{domain}/{other}",
        f"/login?x={other}&redirect=//{domain}/{token}",
        f"/search?q={token};id",
        f"/search?q={token}|id",
        f"/search?q={token}<input",
        f"/search?q={token}>output",
        f"/search?q=`id`{token}",
        f"/search?q=$(id){token}",
        f"/notes?text={token}sudo{other}",
        f"/run/{token}/bin/bash/{other}",
        f"/view?file={token}/etc/shadow",
        f"/files/{token}/root/{other}",
    ]

    rejected_clean = [payload for payload in clean if invoke_filter(script, payload) != 0]
    accepted_evil = [payload for payload in evil if invoke_filter(script, payload) == 0]
    assert not rejected_clean, f"Fresh valid paths were rejected: {rejected_clean}"
    assert not accepted_evil, f"Fresh malicious paths were accepted: {accepted_evil}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
