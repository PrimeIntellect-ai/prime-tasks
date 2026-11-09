#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import hashlib
import os
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import time
import urllib.request


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(proc + "/fd"):
                try:
                    target = os.readlink(proc + "/fd/" + fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.rsplit("/", 1)[1]))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode(errors="replace")


def request_raw(port, tls=False):
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    if tls:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        sock = ctx.wrap_socket(sock, server_hostname="localhost")
    try:
        sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
        return data
    finally:
        sock.close()


def test_compiled_server_and_listener_identity():
    server_path = "/home/user/server"
    assert os.path.isfile(server_path), f"Compiled executable {server_path} is missing."
    assert os.access(server_path, os.X_OK), f"File {server_path} is not executable."
    with open(server_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server is not an ELF executable produced by the compilation step"

    pids = listening_pids(8080)
    assert pids, "No process is listening on TCP port 8080"
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", server_path):
                matching.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert matching, "The process listening on port 8080 is not /home/user/server"

    response = request_raw(8080)
    assert response.startswith(b"HTTP/1.1 200 OK\r\n"), response
    assert response.endswith(b"\r\n\r\nOK"), response

    # The source uses the C++ standard library; confirm the running artifact is
    # the C++ executable and exhibits the source's distinctive response/logging.
    maps = ""
    for pid in matching:
        try:
            maps += open(f"/proc/{pid}/maps").read()
        except OSError:
            pass
    assert "libstdc++" in maps, "Running server is not linked as the supplied C++ program"


def test_certificates():
    cert_path = "/home/user/cert.pem"
    key_path = "/home/user/key.pem"
    assert os.path.isfile(cert_path), f"Certificate {cert_path} is missing."
    assert os.path.isfile(key_path), f"Private key {key_path} is missing."

    try:
        output = subprocess.check_output(
            ["openssl", "x509", "-in", cert_path, "-text", "-noout"],
            stderr=subprocess.STDOUT,
        ).decode()
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to parse certificate with openssl: {e.output.decode()}"

    assert "CN = localhost" in output or "CN=localhost" in output, "Certificate does not have Common Name (CN) set to localhost."
    assert re.search(r"Public-Key:\s*\(2048 bit\)", output), "Certificate does not contain a 2048-bit key"
    assert "rsaEncryption" in output, "Certificate public key is not RSA"

    run(["openssl", "pkey", "-in", key_path, "-check", "-noout"])
    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", key_path, "-pubout"])
    cert_der = subprocess.check_output(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub)
    key_der = subprocess.check_output(["openssl", "pkey", "-pubin", "-outform", "DER"], input=key_pub)
    assert cert_der == key_der, "key.pem does not match cert.pem"

    subject = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"]).stdout.split("=", 1)[1].strip()
    issuer = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"]).stdout.split("=", 1)[1].strip()
    assert subject == issuer, "Certificate is not self-signed"
    run(["openssl", "verify", "-CAfile", cert_path, cert_path])


def test_socat_tls_termination_and_log():
    pids = listening_pids(8443)
    assert pids, "No process is listening on TCP port 8443"
    socat_pids = []
    for pid in pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            command = cmdline(pid)
        except OSError:
            continue
        if os.path.basename(exe) == "socat":
            socat_pids.append((pid, command))
    assert socat_pids, "The TLS listener on port 8443 is not socat"

    valid = False
    for _, command in socat_pids:
        compact = command.replace(" ", "")
        if ("OPENSSL-LISTEN:8443" in command.upper()
                and "verify=0" in compact.lower()
                and re.search(r"cert=/home/user/cert\.pem(?:,|\s|$)", command)
                and re.search(r"key=/home/user/key\.pem(?:,|\s|$)", command)
                and re.search(r"(?:TCP|TCP4|TCP6|TCP-CONNECT):[^\s]*8080", command, re.I)):
            valid = True
    assert valid, "socat is not configured with cert.pem, key.pem, verify=0, and forwarding to port 8080"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    file_der = ssl.PEM_cert_to_DER_cert(open("/home/user/cert.pem").read())
    assert served_der == bytes.fromhex(file_der), "Port 8443 is not serving /home/user/cert.pem"

    url = "https://127.0.0.1:8443"
    with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
        body = response.read().decode()
        assert body == "OK", f"Expected response 'OK', got '{body}'"

    time.sleep(0.5)
    log_path = "/home/user/app.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path) as f:
        log_content = f.read()
    assert "Connection received" in log_content, f"Log file {log_path} does not contain 'Connection received'."


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"Logrotate config {conf_path} is missing."
    with open(conf_path) as f:
        content = f.read()

    lines = [line.split('#')[0].strip() for line in content.splitlines()]
    text = " ".join(lines)
    assert "size 1k" in text or "size=1k" in text.replace(" ", ""), "Logrotate config missing 'size 1k'."
    assert "rotate 3" in text or "rotate=3" in text.replace(" ", ""), "Logrotate config missing 'rotate 3'."
    assert "compress" in text.split(), "Logrotate config missing 'compress'."
    assert "missingok" in text.split(), "Logrotate config missing 'missingok'."
    assert "/home/user/app.log" in content, "Configuration does not manage /home/user/app.log"

    # Exercise the submitted configuration against an isolated copy, rather
    # than trusting directive-like text or rotating the live server's open log.
    work = tempfile.mkdtemp(prefix="logrotate-test-")
    os.chmod(work, 0o777)
    test_log = os.path.join(work, "app.log")
    test_conf = os.path.join(work, "logrotate.conf")
    state = os.path.join(work, "state")
    transformed = content.replace("/home/user/app.log", test_log)
    with open(test_conf, "w") as f:
        f.write(transformed)
    os.chmod(test_conf, 0o644)

    with open(test_log, "wb") as f:
        f.write(b"x" * 512)
    run(["logrotate", "-s", state, test_conf])
    assert not glob.glob(test_log + "*.*"), "Log rotated before reaching 1k"

    with open(test_log, "wb") as f:
        f.write(b"x" * 2048)
    run(["logrotate", "-s", state, test_conf])
    assert glob.glob(test_log + "*.*"), "A log larger than 1k was not rotated"

    for i in range(5):
        with open(test_log, "wb") as f:
            f.write((f"rotation-{i}\n" * 200).encode())
        run(["logrotate", "-f", "-s", state, test_conf])

    backups = [p for p in glob.glob(test_log + "*") if p != test_log]
    assert len(backups) == 3, f"Expected exactly 3 rotated backups, found {backups}"
    for backup in backups:
        with open(backup, "rb") as f:
            assert f.read(2) == b"\x1f\x8b", f"Rotated log is not gzip-compressed: {backup}"
        with gzip.open(backup, "rb") as f:
            f.read(1)

    if os.path.exists(test_log):
        os.unlink(test_log)
    run(["logrotate", "-s", state, test_conf])


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
