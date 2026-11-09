#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import json
import os
import re
import signal
import ssl
import subprocess
import time
import urllib.request
import uuid
from zoneinfo import ZoneInfo

import pytest

HOME = "/home/user"
APP = HOME + "/app"
CERTS = HOME + "/certs"
CONFIG = HOME + "/config/settings.json"
MAIL = HOME + "/mailbox/alert.eml"
DEPLOY = HOME + "/deploy.sh"
SOURCE = APP + "/server.go"
SERVER = APP + "/server"
STARTUP = APP + "/startup.log"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
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
                    result.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return result


def stop_port(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    assert not listener_pids(port), f"Could not free TCP port {port} before deployment"


def request(path):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://127.0.0.1:9443" + path)
    with urllib.request.urlopen(req, context=context, timeout=5) as response:
        return response.getcode(), response.read().decode("utf-8")


def wait_for_server():
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            return request("/health")
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Failed to connect to the Go web server: {last_error}")


def write_config(address):
    with open(CONFIG, "w") as f:
        json.dump({"admin_email": address}, f, separators=(",", ":"))


def expected_mail(address):
    return f"To: {address}\nSubject: Alert\n\nService notification triggered.\n"


def test_complete_deployment():
    # Preserve the original directory and exact initial configuration assertions.
    for directory in (APP, CERTS, HOME + "/config", HOME + "/mailbox"):
        assert os.path.isdir(directory), f"Directory {directory} does not exist"
    assert os.path.isfile(CONFIG), f"Configuration file {CONFIG} does not exist"
    with open(CONFIG) as f:
        config = json.load(f)
    assert config == {"admin_email": "sysadmin@local.domain"}, "settings.json does not have the exact required content"

    # The requested source and deployment artifacts must really exist.
    assert os.path.isfile(SOURCE), f"Go source file {SOURCE} does not exist"
    assert os.path.getsize(SOURCE) > 0, f"Go source file {SOURCE} is empty"
    assert os.path.isfile(DEPLOY), f"Script {DEPLOY} does not exist"
    assert os.access(DEPLOY, os.X_OK), f"Script {DEPLOY} is not executable"
    with open(DEPLOY, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!.*(?:bash|/bin/sh)(?:\s|$)", first_line), "deploy.sh is not a shell script"

    # Independently require server.go to be compilable Go source before deploy.sh runs.
    source_build = "/tmp/submitted-server-build"
    subprocess.run(["go", "build", "-o", source_build, SOURCE], cwd=APP,
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=45)
    assert os.path.isfile(source_build) and os.access(source_build, os.X_OK)

    # Remove all products and any pre-existing listener, then exercise deploy.sh itself.
    stop_port(9443)
    for path in (SERVER, STARTUP, MAIL, CERTS + "/cert.pem", CERTS + "/key.pem"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    dynamic_email = f"audit-{uuid.uuid4().hex}@local.domain"
    write_config(dynamic_email)
    trace_path = "/tmp/deploy-trace.log"
    started = time.time()
    with open(trace_path, "w") as trace:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "bash", "-x", DEPLOY],
            stdout=trace, stderr=subprocess.STDOUT, timeout=60
        )
    assert result.returncode == 0, "deploy.sh failed when executed as the unprivileged user"
    with open(trace_path, errors="replace") as f:
        trace = f.read()

    # Confirm the required deployment operations were performed, not merely pre-created.
    assert re.search(r"(?m)^\+ (?:export )?TZ=Europe/Copenhagen\s*$", trace), "deploy.sh did not export TZ=Europe/Copenhagen"
    assert re.search(r"(?m)^\+ sleep 2(?:\.0*)?\s*$", trace), "deploy.sh did not wait for 2 seconds"
    curl_lines = [line for line in trace.splitlines() if re.match(r"^\+ .*\bcurl\b", line)]
    assert any("https://127.0.0.1:9443/notify" in line and re.search(r"(?:\s-k(?:\s|$)|--insecure)", line) for line in curl_lines), \
        "deploy.sh did not use insecure curl to request the /notify endpoint"
    assert re.search(r"(?m)^\+ .*\bopenssl\b", trace), "deploy.sh did not generate the TLS material with openssl"
    build_lines = [line for line in trace.splitlines() if re.match(r"^\+ .*\bgo\s+build\b", line)]
    assert any("server.go" in line and ("/home/user/app/server" in line or "-o server" in line) for line in build_lines), \
        "deploy.sh did not compile server.go into the requested server executable"

    # Fresh, valid, matching, self-signed TLS material must have been generated.
    cert = CERTS + "/cert.pem"
    key = CERTS + "/key.pem"
    assert os.path.isfile(cert), "cert.pem does not exist"
    assert os.path.isfile(key), "key.pem does not exist"
    assert os.path.getmtime(cert) >= started - 1 and os.path.getmtime(key) >= started - 1, "TLS files were not freshly generated"
    subprocess.run(["openssl", "x509", "-in", cert, "-noout", "-checkip", "127.0.0.1"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    subprocess.run(["openssl", "verify", "-CAfile", cert, cert], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert, "-pubkey", "-noout"], timeout=10)
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", key, "-pubout"], stderr=subprocess.PIPE, timeout=10)
    assert hashlib.sha256(cert_pub).digest() == hashlib.sha256(key_pub).digest(), "cert.pem and key.pem do not match"

    assert os.path.isfile(SERVER) and os.access(SERVER, os.X_OK), "Compiled server executable does not exist"
    subprocess.run(["go", "version", "-m", SERVER], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)

    status, body = wait_for_server()
    assert status == 200, f"Expected HTTP 200 from /health, got {status}"
    data = json.loads(body)
    assert data.get("status") == "ok", "Expected JSON {'status': 'ok'}"

    pids = listener_pids(9443)
    assert pids, "No process is listening on port 9443"
    assert any(os.path.realpath(f"/proc/{pid}/exe") == SERVER for pid in pids), \
        "The listener on port 9443 is not /home/user/app/server"

    # deploy.sh's own /notify request must have generated this fresh dynamic result.
    assert os.path.isfile(MAIL), "deploy.sh did not generate alert.eml"
    with open(MAIL) as f:
        assert f.read() == expected_mail(dynamic_email), "deploy.sh did not trigger /notify using the current configuration"

    # Exercise /notify independently with a verifier-derived value to prevent a fixed response.
    second_email = f"second-{uuid.uuid4().hex}@local.domain"
    write_config(second_email)
    os.remove(MAIL)
    status, _ = request("/notify")
    assert status == 200, f"Expected HTTP 200 from /notify, got {status}"
    with open(MAIL) as f:
        assert f.read() == expected_mail(second_email), "/notify did not reread admin_email or write the exact email"

    # The startup timestamp must be newly generated, valid RFC3339, current, and Copenhagen-local.
    assert os.path.isfile(STARTUP), f"Log file {STARTUP} does not exist"
    with open(STARTUP) as f:
        lines = f.read().strip().splitlines()
    assert lines, f"Log file {STARTUP} is empty"
    timestamp = lines[-1].strip()
    pattern = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?\+(01:00|02:00)$"
    assert re.match(pattern, timestamp), f"Timestamp '{timestamp}' is not valid Copenhagen RFC3339"
    parsed = datetime.datetime.fromisoformat(timestamp)
    now = datetime.datetime.now(datetime.timezone.utc)
    assert abs((parsed.astimezone(datetime.timezone.utc) - now).total_seconds()) < 90, "Startup timestamp is not current"
    copenhagen = parsed.astimezone(ZoneInfo("Europe/Copenhagen"))
    assert parsed.utcoffset() == copenhagen.utcoffset(), "Startup timestamp does not use Europe/Copenhagen's current offset"
    assert os.path.getmtime(STARTUP) >= started - 1, "startup.log was not freshly created by this deployment"

    # Restore and verify the exact requested final state while leaving the deployed server running.
    write_config("sysadmin@local.domain")
    status, _ = request("/notify")
    assert status == 200
    with open(MAIL) as f:
        assert f.read() == expected_mail("sysadmin@local.domain"), "Final alert.eml contents are incorrect"
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
