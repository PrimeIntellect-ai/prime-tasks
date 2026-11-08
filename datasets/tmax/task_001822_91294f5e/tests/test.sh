#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import re
import socket
import ssl
import stat
import subprocess
import time
import urllib.error
import urllib.request
import uuid


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def test_makefile_fixed():
    makefile_path = "/app/legacy-tls-server-1.0/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "python3 " in content, "The typo 'pyton3' in the Makefile was not fixed to 'python3'."
    assert "pyton3 " not in content, "The typo 'pyton3' is still present in the Makefile."

    dry_run = run([
        "make", "-n", "start", "CERT=/tmp/test.crt", "KEY=/tmp/test.key", "PASS=test"
    ], cwd="/app/legacy-tls-server-1.0")
    assert dry_run.returncode == 0, dry_run.stderr
    assert re.search(r"\bpython3\s+(?:src/)?server\.py\b", dry_run.stdout), \
        f"The start target does not launch server.py with python3: {dry_run.stdout!r}"


def test_credentials_exist_and_secure():
    passphrase_file = "/home/user/passphrase.key"
    cert_file = "/home/user/certs/server.crt"
    key_file = "/home/user/certs/server.key"

    assert os.path.isfile(passphrase_file), f"Passphrase file missing at {passphrase_file}"
    st = os.stat(passphrase_file)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Passphrase file permissions are {oct(permissions)}, expected 0o400."

    assert os.path.isfile(cert_file), f"Certificate missing at {cert_file}"
    assert os.path.isfile(key_file), f"Private key missing at {key_file}"

    with open(key_file, "r") as f:
        key_content = f.read()
    assert "ENCRYPTED" in key_content, "The private key does not appear to be encrypted."

    passphrase = open(passphrase_file, "rb").read().strip()
    assert len(passphrase) >= 32, "The generated passphrase is too short to be strong."
    assert b"\x00" not in passphrase and b"\n" not in passphrase and b"\r" not in passphrase
    counts = {b: passphrase.count(b) for b in set(passphrase)}
    entropy = -sum((n / len(passphrase)) * math.log2(n / len(passphrase)) for n in counts.values())
    assert len(counts) >= 12 and entropy >= 3.5, "The passphrase lacks sufficient apparent randomness."

    encrypted_without_password = run([
        "openssl", "pkey", "-in", key_file, "-noout", "-passin", "pass:"
    ])
    assert encrypted_without_password.returncode != 0, "The private key can be opened without its passphrase."

    key_info = run([
        "openssl", "pkey", "-in", key_file, "-passin", f"file:{passphrase_file}",
        "-text", "-noout"
    ])
    assert key_info.returncode == 0, f"The passphrase does not decrypt the private key: {key_info.stderr}"
    assert re.search(r"(?:Private-Key|RSA Private-Key): \(4096 bit", key_info.stdout), \
        "The private key is not RSA 4096-bit."

    encryption_description = key_content
    asn1 = run(["openssl", "asn1parse", "-in", key_file, "-inform", "PEM"])
    encryption_description += "\n" + asn1.stdout + "\n" + asn1.stderr
    assert "AES-256-CBC" in encryption_description.upper(), \
        "The private key is not encrypted with AES-256-CBC."

    cert_info = run(["openssl", "x509", "-in", cert_file, "-noout", "-subject", "-issuer"])
    assert cert_info.returncode == 0, f"Invalid X.509 certificate: {cert_info.stderr}"
    fields = dict(line.split("=", 1) for line in cert_info.stdout.splitlines() if "=" in line)
    assert fields.get("subject", "").strip() == fields.get("issuer", "").strip(), \
        "The certificate is not self-signed."

    valid_now = run(["openssl", "x509", "-in", cert_file, "-noout", "-checkend", "0"])
    assert valid_now.returncode == 0, "The certificate is expired or not currently valid."
    verified = run(["openssl", "verify", "-CAfile", cert_file, cert_file])
    assert verified.returncode == 0, f"The self-signed certificate signature is invalid: {verified.stderr}"

    key_pub = run([
        "openssl", "pkey", "-in", key_file, "-passin", f"file:{passphrase_file}", "-pubout"
    ])
    cert_pub = run(["openssl", "x509", "-in", cert_file, "-pubkey", "-noout"])
    assert key_pub.returncode == 0 and cert_pub.returncode == 0
    assert key_pub.stdout == cert_pub.stdout, "The certificate does not match the generated private key."


def test_secure_runner_exists_and_is_active_sandbox():
    runner = "/home/user/secure_runner.sh"
    assert os.path.isfile(runner), f"Sandbox runner missing at {runner}"
    assert os.access(runner, os.X_OK), "secure_runner.sh is not executable."
    content = open(runner).read()
    assert content.startswith("#!") and "bash" in content.splitlines()[0], \
        "secure_runner.sh must be a bash script."
    assert re.search(r"(^|[^A-Za-z0-9_])(?:/usr/bin/)?bwrap([^A-Za-z0-9_]|$)", content), \
        "secure_runner.sh does not invoke bwrap."
    syntax = run(["bash", "-n", runner])
    assert syntax.returncode == 0, f"secure_runner.sh has invalid bash syntax: {syntax.stderr}"

    listener_inode = None
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        for line in open(table).read().splitlines()[1:]:
            cols = line.split()
            if len(cols) >= 10 and cols[1].split(":")[-1].upper() == "20FB" and cols[3] == "0A":
                listener_inode = cols[9]
                break
        if listener_inode:
            break
    assert listener_inode, "No process is listening on TCP port 8443."

    server_pid = None
    for pid in filter(str.isdigit, os.listdir("/proc")):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == f"socket:[{listener_inode}]":
                        server_pid = int(pid)
                        break
                except OSError:
                    pass
        except OSError:
            pass
        if server_pid:
            break
    assert server_pid, "Could not identify the process listening on port 8443."

    cmdline = open(f"/proc/{server_pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    assert "python" in cmdline and "server.py" in cmdline, \
        f"The listener is not the requested Python legacy server: {cmdline!r}"
    assert os.stat(f"/proc/{server_pid}/ns/mnt").st_ino != os.stat("/proc/1/ns/mnt").st_ino, \
        "The server is running in the host mount namespace rather than a sandbox."

    ancestors = []
    pid = server_pid
    for _ in range(20):
        try:
            raw = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            ancestors.append(raw)
            status = open(f"/proc/{pid}/status").read()
            ppid = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
        except (OSError, AttributeError):
            break
        if ppid <= 0 or ppid == pid:
            break
        pid = ppid
    assert any(re.search(r"(^|[/ ])bwrap(?: |$)", cmd) for cmd in ancestors), \
        f"The live server was not launched through bwrap; ancestry was {ancestors!r}"


def get_url(path, ctx):
    try:
        with urllib.request.urlopen(f"https://127.0.0.1:8443{path}", context=ctx, timeout=2) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def test_deployment_done_log():
    log_file = "/home/user/deployment_done.log"
    assert os.path.isfile(log_file), f"Deployment log missing at {log_file}"
    with open(log_file, "r") as f:
        content = f.read().strip()
    assert content == "READY", f"Deployment log content is '{content}', expected 'READY'."


def test_isolation_score():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    attempts = ["/etc/passwd", "/home/user/secrets/flag.txt"]
    blocked = 0
    server_up = False
    for _ in range(10):
        try:
            urllib.request.urlopen("https://127.0.0.1:8443/", context=ctx, timeout=1)
            server_up = True
            break
        except Exception:
            time.sleep(0.5)
    assert server_up, "Server is not reachable on https://127.0.0.1:8443. Ensure secure_runner.sh starts the server."

    for filename in attempts:
        try:
            req = urllib.request.urlopen(
                f"https://127.0.0.1:8443/read?file={filename}", context=ctx, timeout=2
            )
            res = req.read()
            if b"Not Found" in res:
                blocked += 1
        except Exception:
            blocked += 1
    isolation_score = blocked / len(attempts)
    assert isolation_score >= 1.0, \
        f"isolation_score is {isolation_score}, expected >= 1.0. Some LFI attempts succeeded."

    token = uuid.uuid4().hex
    host_canaries = [
        f"/home/user/secrets/audit-{token}",
        f"/home/user/audit-{token}",
        f"/root/audit-{token}",
        f"/tmp/audit-{token}",
    ]
    app_canary = f"/app/legacy-tls-server-1.0/src/audit-{token}"
    secret = ("UNPREDICTABLE_" + uuid.uuid4().hex).encode()
    try:
        for path in host_canaries + [app_canary]:
            with open(path, "wb") as f:
                f.write(secret)
            os.chmod(path, 0o644)

        status, body = get_url(f"/read?file={app_canary}", ctx)
        assert status == 200 and body == secret, \
            "The running service is not exercising the legacy server's LFI against its bound application tree."

        for path in host_canaries:
            status, body = get_url(f"/read?file={path}", ctx)
            assert secret not in body and status != 200, \
                f"A verifier-generated host file was readable from inside the sandbox: {path}"

        status, body = get_url("/", ctx)
        assert status == 200 and b"Legacy Server OK" in body, "The service stopped responding during isolation tests."
    finally:
        for path in host_canaries + [app_canary]:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    with socket.create_connection(("127.0.0.1", 8443), timeout=2) as sock:
        with ctx.wrap_socket(sock, server_hostname="127.0.0.1") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    local_der = ssl.PEM_cert_to_DER_cert(open("/home/user/certs/server.crt").read())
    assert hashlib.sha256(served_der).digest() == hashlib.sha256(local_der).digest(), \
        "The live server is not using /home/user/certs/server.crt."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
