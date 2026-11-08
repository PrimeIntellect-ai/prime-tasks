#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import re
import shutil
import signal
import socket
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

HOME = "/home/user"
CONF = f"{HOME}/supervisord.conf"
CERT = f"{HOME}/cert.pem"
KEY = f"{HOME}/key.pem"
EXPORTER = f"{HOME}/exporter.py"
URL = "https://127.0.0.1:8443"


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return ""


def proc_ppid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
    return 0


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = proc_ppid(pid)
    return False


def supervisor_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        cmd = proc_cmdline(int(name))
        if "supervisord" in cmd and CONF in cmd:
            found.append(int(name))
    return found


def listener_rows():
    output = subprocess.check_output(
        ["ss", "-H", "-ltnp", "sport = :8443"], text=True
    )
    rows = []
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 5:
            continue
        local = parts[3]
        pids = {int(x) for x in re.findall(r"pid=(\d+)", line)}
        rows.append((local, pids, line))
    return rows


def supervised_listener(supervisord_pid):
    rows = listener_rows()
    assert rows, "Nothing is listening on TCP port 8443"
    for local, _, line in rows:
        assert local == "127.0.0.1:8443", (
            f"Port 8443 must be bound exclusively to 127.0.0.1; found: {line}"
        )
    pids = set().union(*(pids for _, pids, _ in rows))
    assert pids, "Could not identify the process listening on port 8443"
    supervised = [pid for pid in pids if is_descendant(pid, supervisord_pid)]
    assert supervised, "The port 8443 listener is not supervised by the required supervisord"
    for pid in supervised:
        assert EXPORTER in proc_cmdline(pid), (
            f"Supervised listener PID {pid} is not running {EXPORTER}"
        )
    return supervised[0]


def served_certificate_der():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="127.0.0.1") as tls:
            return tls.getpeercert(binary_form=True)


def certificate_file_der(path):
    with open(path) as f:
        pem = f.read()
    return ssl.PEM_cert_to_DER_cert(pem)


def assert_https_payload():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(URL, method="GET")
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        status_code = response.getcode()
        assert status_code == 200, f"Expected HTTP 200, got {status_code}"
        content_type = response.headers.get("Content-Type", "")
        assert "application/json" in content_type, (
            f"Expected Content-Type: application/json, got {content_type}"
        )
        body = response.read().decode("utf-8")
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            assert False, f"Response body is not valid JSON: {body}"
        expected_data = {"cpu": 50, "mem": 1024}
        assert data == expected_data, f"Expected JSON payload {expected_data}, got {data}"


def test_files_created():
    expected_files = [EXPORTER, CERT, KEY, CONF]
    for filepath in expected_files:
        assert os.path.exists(filepath), f"Expected file {filepath} is missing."


def test_supervisord_config():
    assert os.path.exists(CONF), f"{CONF} does not exist."
    with open(CONF, "r") as f:
        content = f.read()

    assert "autorestart=true" in content.replace(" ", ""), "supervisord.conf must contain autorestart=true"
    assert "exporter.py" in content, "supervisord.conf must execute exporter.py"
    assert "exporter.log" in content, "supervisord.conf must route logs to exporter.log"

    parser = configparser.RawConfigParser()
    parser.read(CONF)
    section = "program:metric_exporter"
    assert parser.has_section(section), "supervisord.conf must define [program:metric_exporter]"
    command = parser.get(section, "command", fallback="")
    assert EXPORTER in command, f"metric_exporter must execute {EXPORTER}"
    assert parser.get(section, "autorestart", fallback="").strip().lower() == "true", (
        "metric_exporter must set autorestart=true"
    )
    assert parser.get(section, "stdout_logfile", fallback="").strip() == f"{HOME}/exporter.log", (
        "metric_exporter stdout must go to /home/user/exporter.log"
    )
    assert parser.get(section, "stderr_logfile", fallback="").strip() == f"{HOME}/exporter.log", (
        "metric_exporter stderr must go to /home/user/exporter.log"
    )


def test_processes_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "supervisord.*/home/user/supervisord.conf"]).decode()
        assert output.strip(), "supervisord is not running with /home/user/supervisord.conf"
    except subprocess.CalledProcessError:
        assert False, "supervisord process not found"

    try:
        output = subprocess.check_output(["pgrep", "-f", "exporter.py"]).decode()
        assert output.strip(), "exporter.py is not running"
    except subprocess.CalledProcessError:
        assert False, "exporter.py process not found"


def test_https_server_response():
    time.sleep(1)
    try:
        assert_https_payload()
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to {URL}: {e}"


def test_exclusive_binding_supervision_and_tls_files():
    supervisors = supervisor_pids()
    assert supervisors, f"No running supervisord uses {CONF}"
    assert len(supervisors) == 1, f"Expected one matching supervisord, found {supervisors}"
    supervisor = supervisors[0]
    listener = supervised_listener(supervisor)

    assert served_certificate_der() == certificate_file_der(CERT), (
        "The HTTPS server is not presenting /home/user/cert.pem"
    )
    cert_pub = subprocess.check_output(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", KEY, "-pubout"])
    assert cert_pub == key_pub, "/home/user/key.pem does not match /home/user/cert.pem"

    cert_stat = os.stat(CERT)
    key_stat = os.stat(KEY)
    with tempfile.TemporaryDirectory() as tmp:
        new_cert = os.path.join(tmp, "cert.pem")
        new_key = os.path.join(tmp, "key.pem")
        subprocess.check_call([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", new_key, "-out", new_cert, "-days", "1",
            "-subj", "/CN=127.0.0.1"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.chown(new_cert, cert_stat.st_uid, cert_stat.st_gid)
        os.chown(new_key, key_stat.st_uid, key_stat.st_gid)
        os.chmod(new_cert, cert_stat.st_mode & 0o777)
        os.chmod(new_key, key_stat.st_mode & 0o777)
        shutil.copyfile(new_cert, CERT)
        shutil.copyfile(new_key, KEY)
        expected_der = certificate_file_der(CERT)

    os.kill(listener, signal.SIGKILL)
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            new_listener = supervised_listener(supervisor)
            if new_listener == listener:
                time.sleep(0.2)
                continue
            if served_certificate_der() != expected_der:
                raise AssertionError("Restarted server did not load the replaced cert.pem")
            assert_https_payload()
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.3)
    assert False, (
        "metric_exporter was not automatically restarted by supervisord using "
        f"the required cert.pem and key.pem files: {last_error}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
