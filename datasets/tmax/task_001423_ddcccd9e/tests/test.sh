#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import re
import signal
import socket
import ssl
import subprocess
import time
import urllib.request

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

SERVICES = "/app/services"
START = SERVICES + "/start.sh"
CERT = SERVICES + "/nginx/certs/server.crt"
KEY = SERVICES + "/nginx/certs/server.key"
NGINX_CONF = SERVICES + "/nginx/nginx.conf"
REDIS_CONF = SERVICES + "/redis/redis.conf"
FLASK_APP = SERVICES + "/flask/app.py"
LOG = "/home/user/rotation_complete.log"
OLD_PASSWORD = "old_secret_pass"
EXPECTED_CSP = "default-src 'self'; script-src 'self' https://trusted.cdn.com; frame-ancestors 'none';"


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def get_password():
    content = read(LOG).strip()
    match = re.search(r"[A-Za-z0-9]{16}", content)
    assert match is not None
    return match.group(0), content


def tls_connect(minimum, maximum):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ctx.minimum_version = minimum
    ctx.maximum_version = maximum
    with socket.create_connection(("127.0.0.1", 8443), timeout=3) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as wrapped:
            return wrapped.version(), wrapped.getpeercert(binary_form=True)


def redis_ping(password):
    result = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "-a", password, "PING"],
        capture_output=True, text=True, timeout=5
    )
    return (result.stdout + result.stderr).strip()


def listening_pid(port):
    wanted = format(port, "04X")
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = read(table).splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    return int(name)
        except OSError:
            continue
    return None


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        try:
            status = read(f"/proc/{pid}/status")
        except OSError:
            return False
        match = re.search(r"^PPid:\s+(\d+)", status, re.M)
        if not match:
            return False
        pid = int(match.group(1))
    return pid == ancestor


def mount_options(pid, mountpoint):
    for line in read(f"/proc/{pid}/mountinfo").splitlines():
        fields = line.split()
        if len(fields) > 5 and fields[4] == mountpoint:
            return set(fields[5].split(","))
    return set()


def wait_for_stack(proc):
    deadline = time.time() + 25
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=2)
            pytest.fail(f"start.sh exited before the stack became ready\nSTDOUT:\n{out}\nSTDERR:\n{err}")
        try:
            version, _ = tls_connect(ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_2)
            if version == "TLSv1.2" and listening_pid(5000):
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.4)
    pytest.fail(f"Stack did not become ready: {last_error}")


def test_security_score():
    verifier_path = "/app/verifier/score.py"
    assert os.path.isfile(verifier_path), f"Verifier script missing at {verifier_path}"

    result = subprocess.run(["python3", verifier_path], capture_output=True, text=True)
    match = re.search(r"Score:\s*([0-9.]+)", result.stdout)
    assert match is not None, (
        f"Could not find 'Score: <value>' in verifier output.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    score = float(match.group(1))
    assert score >= 95, f"Security score is {score}, expected >= 95."


def test_rotation_complete_log():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    content = read(LOG).strip()
    match = re.search(r"[A-Za-z0-9]{16}", content)
    assert match is not None, (
        f"Could not find a 16-character alphanumeric password in {LOG}. "
        f"File content: {content}"
    )


def test_actual_hardened_stack():
    for path in (START, CERT, KEY, NGINX_CONF, REDIS_CONF, FLASK_APP, LOG):
        assert os.path.isfile(path), f"Required artifact missing: {path}"
    assert os.access(START, os.X_OK), "start.sh is not executable"

    password, log_content = get_password()
    assert re.fullmatch(r"[A-Za-z0-9]{16}", log_content), "The log must contain the new 16-character password"
    assert password != OLD_PASSWORD

    cert = x509.load_pem_x509_certificate(open(CERT, "rb").read())
    key = serialization.load_pem_private_key(open(KEY, "rb").read(), password=None)
    assert isinstance(key, rsa.RSAPrivateKey), "TLS key is not RSA"
    assert key.key_size == 4096, f"RSA key is {key.key_size} bits, expected 4096"
    assert cert.public_key().public_numbers() == key.public_key().public_numbers(), "Certificate and key do not match"
    assert cert.issuer == cert.subject, "Certificate is not self-signed"
    cert.public_key().verify(cert.signature, cert.tbs_certificate_bytes, padding.PKCS1v15(), cert.signature_hash_algorithm)
    not_before = getattr(cert, "not_valid_before_utc", cert.not_valid_before.replace(tzinfo=datetime.timezone.utc))
    not_after = getattr(cert, "not_valid_after_utc", cert.not_valid_after.replace(tzinfo=datetime.timezone.utc))
    assert not_after - not_before == datetime.timedelta(days=365), "Certificate validity is not exactly 365 days"
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid"

    nginx_text = read(NGINX_CONF)
    redis_text = read(REDIS_CONF)
    flask_text = read(FLASK_APP)
    start_text = read(START)
    assert OLD_PASSWORD not in redis_text
    assert OLD_PASSWORD not in flask_text
    assert OLD_PASSWORD not in start_text
    assert re.search(r"\bbwrap\b", start_text), "start.sh does not invoke bwrap"
    for pattern in (
        r"--unshare-pid\b",
        r"--share-net\b",
        r"--ro-bind\s+/\s+/",
        r"--bind\s+/tmp\s+/tmp",
    ):
        assert re.search(pattern, start_text), f"Missing required bwrap option: {pattern}"

    subprocess.run(["pkill", "-TERM", "-f", "/app/services/flask/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)

    proc = subprocess.Popen(
        [START], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True, env=os.environ.copy()
    )
    try:
        wait_for_stack(proc)

        assert redis_ping(password).splitlines()[-1:] == ["PONG"], "Redis rejects the logged new password"
        old_result = redis_ping(OLD_PASSWORD)
        assert not re.search(r"(^|\n)PONG($|\n)", old_result), "The old Redis password still works"

        version12, served_der = tls_connect(ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_2)
        assert version12 == "TLSv1.2"
        assert served_der == cert.public_bytes(serialization.Encoding.DER), "Nginx is not serving the submitted certificate"
        version13, _ = tls_connect(ssl.TLSVersion.TLSv1_3, ssl.TLSVersion.TLSv1_3)
        assert version13 == "TLSv1.3"
        for obsolete in (ssl.TLSVersion.TLSv1, ssl.TLSVersion.TLSv1_1):
            with pytest.raises(Exception):
                tls_connect(obsolete, obsolete)

        ctx = ssl._create_unverified_context()
        request = urllib.request.Request("https://127.0.0.1:8443/api/status")
        with urllib.request.urlopen(request, context=ctx, timeout=5) as response:
            body = json.loads(response.read().decode())
            csp = response.headers.get("Content-Security-Policy")
        assert csp == EXPECTED_CSP, f"Incorrect CSP header: {csp!r}"
        assert body.get("status") == "ok", f"End-to-end API failed: {body}"
        assert body.get("message") == "Connected to Redis"

        flask_pid = listening_pid(5000)
        assert flask_pid is not None, "No Flask process is listening on port 5000"
        assert is_descendant(flask_pid, proc.pid), "The listening Flask process was not launched by start.sh"
        flask_cmd = read(f"/proc/{flask_pid}/cmdline").replace("\0", " ")
        assert "app.py" in flask_cmd, f"Unexpected process on Flask port: {flask_cmd}"

        bwrap_pids = []
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                args = [x.decode(errors="replace") for x in open(f"/proc/{name}/cmdline", "rb").read().split(b"\0") if x]
            except OSError:
                continue
            if args and os.path.basename(args[0]) == "bwrap" and is_descendant(int(name), proc.pid):
                bwrap_pids.append((int(name), args))
        assert bwrap_pids, "No live bwrap process launched by start.sh was found"
        args = next((a for p, a in bwrap_pids if is_descendant(flask_pid, p)), None)
        assert args is not None, "The Flask listener is not a child of bwrap"
        assert "--unshare-pid" in args and "--share-net" in args
        assert any(args[i:i+3] == ["--ro-bind", "/", "/"] for i in range(len(args)-2))
        assert any(args[i:i+3] == ["--bind", "/tmp", "/tmp"] for i in range(len(args)-2))

        assert os.readlink(f"/proc/{flask_pid}/ns/pid") != os.readlink("/proc/self/ns/pid"), "Flask did not enter an unshared PID namespace"
        assert os.readlink(f"/proc/{flask_pid}/ns/net") == os.readlink("/proc/self/ns/net"), "Flask does not share the host network namespace"
        assert "ro" in mount_options(flask_pid, "/"), "Flask root filesystem is not read-only"
        assert "rw" in mount_options(flask_pid, "/tmp"), "Flask /tmp is not read-write"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
