#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import calendar
import hashlib
import json
import os
import re
import shutil
import ssl
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime

import pytest

DEPLOY_SCRIPT = "/home/user/deploy.py"
DEPLOY_LOG = "/home/user/deploy.log"
BACKUP_ARCHIVE = "/home/user/backups/app_backup.tar.gz"
CERT_FILE = "/home/user/certs/cert.pem"
KEY_FILE = "/home/user/certs/key.pem"
SERVER_SCRIPT = "/home/user/app_v2/server.py"
FORWARD_SCRIPT = "/home/user/forward.sh"

STATE = {}


def file_fingerprint(path):
    st = os.stat(path)
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    return digest, st.st_mtime_ns, st.st_ino


def read_log():
    with open(DEPLOY_LOG, "r", encoding="utf-8") as f:
        return f.read().strip().splitlines()


def run_deploy(audit_dir, audit_log):
    open(audit_log, "w").close()
    os.chmod(audit_log, 0o666)
    env = os.environ.copy()
    env.update({
        "HOME": "/home/user",
        "USER": "user",
        "LOGNAME": "user",
        "PYTHONPATH": audit_dir,
        "DEPLOY_AUDIT_LOG": audit_log,
    })
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env"]
        + [f"{k}={v}" for k, v in env.items()]
        + [DEPLOY_SCRIPT],
        capture_output=True,
        text=True,
        timeout=60,
    )


def audit_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().lower()


def descendants_and_self(pid):
    found = {pid}
    changed = True
    while changed:
        changed = False
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            child = int(entry)
            try:
                with open(f"/proc/{child}/stat", "r") as f:
                    stat = f.read()
                rest = stat[stat.rfind(")") + 2:].split()
                ppid = int(rest[1])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in found and child not in found:
                found.add(child)
                changed = True
    return found


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
    except OSError:
        return []


def stop_process(proc):
    if proc is None:
        return
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


@pytest.fixture(scope="module", autouse=True)
def execute_deployment():
    assert os.path.isfile(DEPLOY_SCRIPT), f"Deployment script {DEPLOY_SCRIPT} not found."
    assert os.access(DEPLOY_SCRIPT, os.X_OK), f"Deployment script {DEPLOY_SCRIPT} is not executable."

    with open(DEPLOY_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=DEPLOY_SCRIPT)

    # Remove every artifact deploy.py is responsible for, so pre-created final
    # state cannot satisfy the tests. Also remove stale listeners from agent work.
    subprocess.run(["pkill", "-f", "/home/user/app_v2/server.py"], check=False)
    subprocess.run(["pkill", "-x", "socat"], check=False)
    for path in ("/home/user/backups", "/home/user/certs", "/home/user/app_v2"):
        shutil.rmtree(path, ignore_errors=True)
    for path in (FORWARD_SCRIPT,):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Supply content selected only at verification time and require that exact
    # directory content to be present in the resulting backup.
    shutil.rmtree("/home/user/app_v1", ignore_errors=True)
    os.makedirs("/home/user/app_v1/nested", exist_ok=True)
    token = os.urandom(24).hex()
    expected_files = {
        "data.txt": ("legacy data verification " + token + "\n").encode(),
        "nested/marker.bin": os.urandom(41),
    }
    for rel, data in expected_files.items():
        path = os.path.join("/home/user/app_v1", rel)
        with open(path, "wb") as f:
            f.write(data)
        os.chown(path, 1000, 1000)
    os.chown("/home/user/app_v1/nested", 1000, 1000)
    os.chown("/home/user/app_v1", 1000, 1000)
    with open(DEPLOY_LOG, "w"):
        pass
    os.chown(DEPLOY_LOG, 1000, 1000)
    os.chmod(DEPLOY_LOG, 0o666)
    STATE["expected_files"] = expected_files

    # Python audit hooks record actual subprocess creation by deploy.py.
    audit_dir = tempfile.mkdtemp(prefix="deploy_audit_")
    os.chmod(audit_dir, 0o755)
    audit_log = os.path.join(audit_dir, "events.log")
    with open(os.path.join(audit_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(r'''import os
import sys

def hook(event, args):
    if event == "subprocess.Popen":
        path = os.environ.get("DEPLOY_AUDIT_LOG")
        if path:
            try:
                with open(path, "a", encoding="utf-8") as out:
                    out.write(repr(args) + "\n")
            except Exception:
                pass
sys.addaudithook(hook)
''')

    first_start = time.time()
    result1 = run_deploy(audit_dir, audit_log)
    assert result1.returncode == 0, f"First execution of deploy.py failed:\n{result1.stderr}"
    first_audit = audit_text(audit_log)
    assert read_log() == ["BACKUP_CREATED", "CERTS_GENERATED"], \
        f"First run did not perform creation phases exactly once: {read_log()}"

    assert os.path.isfile(BACKUP_ARCHIVE)
    assert os.path.isfile(CERT_FILE)
    assert os.path.isfile(KEY_FILE)
    first_fingerprints = {
        p: file_fingerprint(p) for p in (BACKUP_ARCHIVE, CERT_FILE, KEY_FILE)
    }

    # The first run must really invoke openssl with arguments implementing RSA
    # 2048-bit, 365-day self-signed certificate generation.
    assert "openssl" in first_audit, "deploy.py did not invoke openssl through a subprocess"
    assert "2048" in first_audit, "openssl invocation did not request a 2048-bit key"
    assert "365" in first_audit, "openssl invocation did not request 365-day validity"
    assert ("-x509" in first_audit or "-signkey" in first_audit), \
        "openssl invocation did not request creation of a self-signed certificate"

    time.sleep(0.02)
    result2 = run_deploy(audit_dir, audit_log)
    assert result2.returncode == 0, f"Second execution of deploy.py failed:\n{result2.stderr}"
    second_audit = audit_text(audit_log)
    assert "openssl" not in second_audit, "Second run unnecessarily invoked openssl"

    for path, old in first_fingerprints.items():
        assert file_fingerprint(path) == old, f"Second run modified existing artifact {path}"

    STATE["first_start"] = first_start
    server_proc = None
    forward_proc = None
    try:
        assert os.path.isfile(SERVER_SCRIPT), f"Server script {SERVER_SCRIPT} not found."
        assert os.path.isfile(FORWARD_SCRIPT), f"Forward script {FORWARD_SCRIPT} not found."
        assert os.access(FORWARD_SCRIPT, os.X_OK), f"Forward script {FORWARD_SCRIPT} is not executable."

        server_proc = subprocess.Popen(
            ["runuser", "-u", "user", "--", "python3", SERVER_SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        forward_proc = subprocess.Popen(
            ["runuser", "-u", "user", "--", "bash", FORWARD_SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        STATE["forward_proc"] = forward_proc
        time.sleep(2)
        yield
    finally:
        stop_process(forward_proc)
        stop_process(server_proc)
        shutil.rmtree(audit_dir, ignore_errors=True)


def test_deploy_log_contents():
    assert os.path.isfile(DEPLOY_LOG), f"Log file {DEPLOY_LOG} not found."
    log_content = read_log()
    expected_logs = ["BACKUP_CREATED", "CERTS_GENERATED", "BACKUP_EXISTS", "CERTS_EXIST"]
    assert log_content == expected_logs, f"Log file contents do not match expected idempotency sequence. Got: {log_content}"


def test_backup_archive_exists_and_valid():
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} not found."
    assert tarfile.is_tarfile(BACKUP_ARCHIVE), f"{BACKUP_ARCHIVE} is not a valid tar archive."

    with tarfile.open(BACKUP_ARCHIVE, "r:gz") as tar:
        names = tar.getnames()
        has_data = any(name.endswith("data.txt") for name in names)
        assert has_data, f"Backup archive does not contain data.txt from app_v1. Contents: {names}"

        regular = {m.name: m for m in tar.getmembers() if m.isfile()}
        for rel, expected in STATE["expected_files"].items():
            matches = [m for name, m in regular.items()
                       if name == f"app_v1/{rel}" or name.endswith(f"/app_v1/{rel}")]
            assert len(matches) == 1, f"Backup does not contain exactly one app_v1/{rel}: {names}"
            extracted = tar.extractfile(matches[0])
            assert extracted is not None and extracted.read() == expected, \
                f"Backed-up content for app_v1/{rel} is incorrect"


def test_tls_certificates_exist_and_properties():
    assert os.path.isfile(CERT_FILE), f"Certificate file {CERT_FILE} not found."
    assert os.path.isfile(KEY_FILE), f"Key file {KEY_FILE} not found."

    decoded = ssl._ssl._test_decode_cert(CERT_FILE)
    assert decoded["subject"] == decoded["issuer"], "Certificate is not self-signed"
    not_before = calendar.timegm(time.strptime(decoded["notBefore"], "%b %d %H:%M:%S %Y %Z"))
    not_after = calendar.timegm(time.strptime(decoded["notAfter"], "%b %d %H:%M:%S %Y %Z"))
    assert abs((not_after - not_before) - 365 * 24 * 60 * 60) <= 2, \
        "Certificate validity is not 365 days"
    assert STATE["first_start"] - 600 <= not_before <= time.time() + 600, \
        "Certificate was not freshly generated by the first deployment"

    cert_text = subprocess.check_output(
        ["openssl", "x509", "-in", CERT_FILE, "-noout", "-text"], text=True
    )
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text), "Certificate key is not RSA-2048"
    assert "rsaEncryption" in cert_text, "Certificate does not contain an RSA public key"

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", CERT_FILE, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", KEY_FILE, "-pubout"])
    assert cert_pub == key_pub, "Certificate and private key do not match"


def request_status(port):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url = f"https://127.0.0.1:{port}/status"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        assert response.getheader("Content-Type") == "application/json", "Expected Content-Type: application/json"
        raw = response.read()
        assert raw == b'{"version": "v2", "status": "ok"}', f"Unexpected response body: {raw!r}"
        assert json.loads(raw.decode("utf-8")) == {"version": "v2", "status": "ok"}


def test_server_https_endpoint():
    try:
        request_status(8443)
    except Exception as e:
        pytest.fail(f"Failed to connect to or read from https://127.0.0.1:8443/status: {e}")


def test_forward_script_uses_socat():
    with open(FORWARD_SCRIPT, "r", encoding="utf-8") as f:
        script = f.read().lower()
    assert re.search(r"\bsocat\b", script), "forward.sh does not run socat"
    assert re.search(r"tcp(?:4)?-listen:8080\b", script), "socat does not listen on TCP port 8080"
    assert re.search(r"bind=127\.0\.0\.1\b", script), "socat listener is not bound to 127.0.0.1"
    assert re.search(r"tcp(?:4)?:127\.0\.0\.1:8443\b", script), \
        "socat does not forward to 127.0.0.1:8443"

    commands = [process_cmdline(pid) for pid in descendants_and_self(STATE["forward_proc"].pid)]
    socat_commands = [cmd for cmd in commands if cmd and os.path.basename(cmd[0]) == "socat"]
    assert socat_commands, f"Running forward.sh did not launch a socat process. Commands: {commands}"
    joined = " ".join(socat_commands[0]).lower()
    assert re.search(r"tcp(?:4)?-listen:8080\b", joined)
    assert re.search(r"bind=127\.0\.0\.1\b", joined)
    assert re.search(r"tcp(?:4)?:127\.0\.0\.1:8443\b", joined)


def test_forwarder_https_endpoint():
    try:
        request_status(8080)
    except Exception as e:
        pytest.fail(f"Failed to connect to or read from forwarded port https://127.0.0.1:8080/status: {e}")
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
