#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import grp
import http.client
import os
import pwd
import socket
import stat
import subprocess
import tempfile
import time

USER = "user"
UID = pwd.getpwnam(USER).pw_uid
GID = grp.getgrnam(USER).gr_gid
SOCKET_PATH = "/home/user/run/health_monitor.sock"
ALERT_PATH = "/home/user/mail/alerts.mbox"


def stop_services():
    subprocess.run(["/usr/bin/pkill", "-u", str(UID), "-x", "monitor"], check=False)
    subprocess.run(["/usr/bin/pkill", "-u", str(UID), "-x", "nginx"], check=False)
    time.sleep(0.5)
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


def wait_for_socket(path, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(path).st_mode):
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    raise AssertionError(f"Unix socket was not created: {path}")


def unix_request(payload):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    client.connect(SOCKET_PATH)
    client.sendall(payload)
    chunks = []
    while True:
        data = client.recv(4096)
        if not data:
            break
        chunks.append(data)
    client.close()
    return b"".join(chunks)


def user_processes_named(name):
    result = subprocess.run(
        ["/usr/bin/pgrep", "-u", str(UID), "-x", name],
        text=True, capture_output=True, check=False
    )
    return [int(p) for p in result.stdout.split() if p.isdigit()]


def test_00_compile_source_and_execute_deployment():
    conf_path = "/home/user/nginx/nginx.conf"
    source_path = "/home/user/src/monitor.c"
    script_path = "/home/user/deploy.sh"

    assert os.path.isfile(conf_path), f"File missing: {conf_path}"
    assert os.path.isfile(source_path), f"File missing: {source_path}"
    assert os.path.isfile(script_path), f"Deploy script missing: {script_path}"
    assert os.stat(script_path).st_mode & stat.S_IXUSR, f"Deploy script {script_path} is not executable."

    with open(conf_path) as f:
        conf = f.read()
    assert "listen 8080;" in conf, "Nginx must continue listening on port 8080."
    assert "proxy_pass http://unix:/home/user/run/health_monitor.sock;" in conf

    # Compile monitor.c independently, then exercise the resulting service over
    # its Unix socket. This prevents pre-fabricated logs from satisfying the test.
    stop_services()
    build_dir = tempfile.mkdtemp(prefix="monitor-verifier-")
    os.chown(build_dir, UID, GID)
    test_binary = os.path.join(build_dir, "monitor")
    compile_result = subprocess.run(
        ["/usr/sbin/runuser", "-u", USER, "--", "/usr/bin/gcc", source_path, "-o", test_binary],
        text=True, capture_output=True, timeout=15
    )
    assert compile_result.returncode == 0, compile_result.stdout + compile_result.stderr
    with open(test_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor.c did not compile to an ELF executable."

    def demote():
        os.setgid(GID)
        os.setuid(UID)

    monitor = subprocess.Popen([test_binary], preexec_fn=demote)
    try:
        wait_for_socket(SOCKET_PATH)
        normal = unix_request(b"GET / HTTP/1.1\r\nHost: verifier\r\nConnection: close\r\n\r\n")
        assert normal == b"HTTP/1.1 200 OK\r\n\r\nSTATUS: UP\n", repr(normal)

        with open(ALERT_PATH, "wb") as f:
            f.truncate(0)
        alert = unix_request(b"GET /alert HTTP/1.1\r\nHost: verifier\r\nConnection: close\r\n\r\n")
        assert alert == b"HTTP/1.1 200 OK\r\n\r\nALERT SENT\n", repr(alert)
        with open(ALERT_PATH, "rb") as f:
            assert f.read() == b"ALERT: Service degraded\n"
    finally:
        monitor.terminate()
        try:
            monitor.wait(timeout=3)
        except subprocess.TimeoutExpired:
            monitor.kill()
            monitor.wait(timeout=3)
        stop_services()

    # Remove all outputs before running deploy.sh so it must recreate them and
    # bring up both real services itself.
    for path in [
        "/home/user/bin/monitor",
        "/home/user/logs/health_check.log",
        ALERT_PATH,
        SOCKET_PATH,
    ]:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    open(ALERT_PATH, "wb").close()
    os.chown(ALERT_PATH, UID, GID)

    deployed = subprocess.run(
        ["/usr/sbin/runuser", "-u", USER, "--", script_path],
        cwd="/home/user", text=True, capture_output=True, timeout=25
    )
    assert deployed.returncode == 0, deployed.stdout + deployed.stderr

    binary = "/home/user/bin/monitor"
    assert os.path.isfile(binary), "deploy.sh did not compile /home/user/bin/monitor."
    assert os.access(binary, os.X_OK), "Compiled monitor is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Deployed monitor is not a compiled executable."
    wait_for_socket(SOCKET_PATH)

    monitor_pids = user_processes_named("monitor")
    nginx_pids = user_processes_named("nginx")
    assert monitor_pids, "deploy.sh did not leave monitor running as user."
    assert nginx_pids, "deploy.sh did not leave nginx running as user."
    assert any(os.path.realpath(f"/proc/{pid}/exe") == binary for pid in monitor_pids), \
        "The running monitor is not /home/user/bin/monitor."

    # Exercise the public Nginx endpoint independently of deploy.sh's curl.
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
    conn.request("GET", "/")
    response = conn.getresponse()
    body = response.read()
    conn.close()
    assert response.status == 200
    assert body == b"STATUS: UP\n", repr(body)

    before = open(ALERT_PATH, "rb").read()
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
    conn.request("GET", "/alert")
    response = conn.getresponse()
    body = response.read()
    conn.close()
    assert response.status == 200
    assert body == b"ALERT SENT\n", repr(body)
    after = open(ALERT_PATH, "rb").read()
    assert after == before + b"ALERT: Service degraded\n"


def test_nginx_conf_updated():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"File missing: {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://unix:/home/user/run/health_monitor.sock;" in content, \
        "nginx.conf does not contain the corrected proxy_pass directive pointing to health_monitor.sock."


def test_health_check_log_contains_status():
    log_path = "/home/user/logs/health_check.log"
    assert os.path.isfile(log_path), f"Health check log missing: {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    assert "STATUS: UP" in content, \
        f"{log_path} does not contain 'STATUS: UP'. The C service might not be returning the correct fixed HTTP response."


def test_alerts_mbox_contains_alert():
    assert os.path.isfile(ALERT_PATH), f"Alerts mbox missing: {ALERT_PATH}"
    with open(ALERT_PATH, "r") as f:
        content = f.read()
    assert "ALERT: Service degraded" in content, \
        f"{ALERT_PATH} does not contain 'ALERT: Service degraded'. The C service alert logic or curl command might be failing."


def test_deploy_script_exists_and_executable():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deploy script missing: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deploy script {script_path} is not executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
