#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import re
import signal
import socket
import subprocess
import time

OBSERVABILITY_DIR = "/home/user/observability"
BACKUPS_DIR = os.path.join(OBSERVABILITY_DIR, "backups")
BACKUP_FILE = os.path.join(BACKUPS_DIR, "service_b.conf.bak")
SERVICE_B_CONF = os.path.join(OBSERVABILITY_DIR, "service_b.conf")
ALERT_CONF = os.path.join(OBSERVABILITY_DIR, "alert.conf")
MONITOR_SCRIPT = os.path.join(OBSERVABILITY_DIR, "monitor.sh")
DASHBOARD_LOG = os.path.join(OBSERVABILITY_DIR, "dashboard.log")
CRON_FILE = os.path.join(OBSERVABILITY_DIR, "cron_schedule.txt")
START_SCRIPT = os.path.join(OBSERVABILITY_DIR, "start_service_b.sh")
PID_FILE = os.path.join(OBSERVABILITY_DIR, "service_b.pid")

ORIGINAL_SERVICE_CONF = "BIND_IP=127.0.0.1\nBIND_PORT=8083\nMETRICS_PATH=/metrics\n"


def read_text(path):
    with open(path, "r") as f:
        return f.read()


def active_value(path, key):
    values = []
    pattern = re.compile(r"^(?:export[ \t]+)?" + re.escape(key) + r"[ \t]*=[ \t]*(.*)$")
    for line in read_text(path).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = pattern.fullmatch(stripped)
        if match:
            value = match.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            values.append(value)
    assert len(values) == 1, f"Expected exactly one active {key} assignment in {path}; got {values!r}."
    return values[0]


def port_open():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", 8082)) == 0


def wait_for_port(expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_open() == expected:
            return True
        time.sleep(0.1)
    return port_open() == expected


def read_pid():
    assert os.path.isfile(PID_FILE), "Service B PID file was not created by start_service_b.sh."
    raw = read_text(PID_FILE).strip()
    assert raw.isdigit(), f"Invalid Service B PID: {raw!r}"
    return int(raw)


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table, "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) < 10:
                    continue
                local_address = fields[1]
                state = fields[3]
                inode = fields[9]
                try:
                    local_port = int(local_address.rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port and state == "0A":
                    result.add(inode)
    return result


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    assert os.path.isdir(fd_dir), f"Service B process {pid} is not running."
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def stop_process(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline:
        if not os.path.exists(f"/proc/{pid}") or not port_open():
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    wait_for_port(False, 3)


def start_service():
    result = subprocess.run([START_SCRIPT], cwd=OBSERVABILITY_DIR, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"start_service_b.sh failed: {result.stderr}"
    assert wait_for_port(True, 5), "Service B did not restart on port 8082."


def test_backup_created():
    assert os.path.isdir(BACKUPS_DIR), f"Backup directory {BACKUPS_DIR} was not created."
    assert os.path.isfile(BACKUP_FILE), f"Backup file {BACKUP_FILE} does not exist."
    content = read_text(BACKUP_FILE)
    assert "BIND_PORT=8083" in content, "Backup file does not contain the original BIND_PORT=8083."
    assert content == ORIGINAL_SERVICE_CONF, "Backup is not an unchanged copy of the original service_b.conf."
    assert active_value(BACKUP_FILE, "BIND_PORT") == "8083"


def test_service_b_conf_updated():
    assert os.path.isfile(SERVICE_B_CONF), f"File {SERVICE_B_CONF} does not exist."
    content = read_text(SERVICE_B_CONF)
    assert "BIND_PORT=8082" in content, "BIND_PORT was not updated to 8082 in service_b.conf."
    assert active_value(SERVICE_B_CONF, "BIND_PORT") == "8082"
    assert active_value(SERVICE_B_CONF, "BIND_IP") == "127.0.0.1"
    assert active_value(SERVICE_B_CONF, "METRICS_PATH") == "/metrics"
    assert subprocess.run(["bash", "-n", SERVICE_B_CONF]).returncode == 0, "service_b.conf is not valid shell configuration."


def test_alert_conf_updated():
    assert os.path.isfile(ALERT_CONF), f"File {ALERT_CONF} does not exist."
    content = read_text(ALERT_CONF)
    assert "SMTP_PORT=1025" in content, "SMTP_PORT was not updated to 1025 in alert.conf."
    assert active_value(ALERT_CONF, "SMTP_PORT") == "1025"
    assert active_value(ALERT_CONF, "SMTP_HOST") == "127.0.0.1"
    assert active_value(ALERT_CONF, "ALERT_EMAIL") == "admin@local"
    assert subprocess.run(["bash", "-n", ALERT_CONF]).returncode == 0, "alert.conf is not valid shell configuration."


def test_service_b_running():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1)
        result = sock.connect_ex(("127.0.0.1", 8082))
        assert result == 0, "Service B is not listening on port 8082. Did you run start_service_b.sh?"

    pid = read_pid()
    cmdline_path = f"/proc/{pid}/cmdline"
    assert os.path.isfile(cmdline_path), f"PID {pid} from service_b.pid is not running."
    with open(cmdline_path, "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert re.search(r"(?:^|\s)-m\s+http\.server\s+8082(?:\s|$)", cmdline), \
        f"PID {pid} is not the configured Service B process: {cmdline!r}"

    listening = listener_inodes(8082)
    assert listening, "No listening socket exists on port 8082."
    assert listening & pid_socket_inodes(pid), "The PID recorded by Service B does not own the listener on port 8082."

    connection = http.client.HTTPConnection("127.0.0.1", 8082, timeout=2)
    try:
        connection.request("GET", "/metrics")
        response = connection.getresponse()
        response.read()
        assert response.getheader("Server", "").startswith("SimpleHTTP/"), \
            "Port 8082 is not serving responses from the requested Service B HTTP server."
    finally:
        connection.close()


def test_monitor_script_logic():
    assert os.path.isfile(MONITOR_SCRIPT), f"Monitor script {MONITOR_SCRIPT} does not exist."
    assert os.access(MONITOR_SCRIPT, os.X_OK), f"Monitor script {MONITOR_SCRIPT} is not executable."

    script_lines = [line for line in read_text(MONITOR_SCRIPT).splitlines()
                    if line.strip() and not line.lstrip().startswith("#")]
    active_script = "\n".join(script_lines)
    assert re.search(r"(?:^|[;&|() \t])(?:/[^ \t;|&()]+/)?curl[ \t]+-s[ \t]+(?:['\"])?http://127\.0\.0\.1:8082/metrics(?:['\"])?(?:[ \t;|&)]|$)", active_script), \
        "monitor.sh must contain an active 'curl -s http://127.0.0.1:8082/metrics' command."

    if os.path.exists(DASHBOARD_LOG):
        os.remove(DASHBOARD_LOG)
    result = subprocess.run([MONITOR_SCRIPT], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, "Monitor script execution failed."
    assert os.path.isfile(DASHBOARD_LOG), f"Dashboard log {DASHBOARD_LOG} was not created by the monitor script."
    content = read_text(DASHBOARD_LOG)
    assert "SERVICE_B_UP" in content, "Monitor script did not append 'SERVICE_B_UP' to the dashboard log when the service is up."
    assert content == "SERVICE_B_UP\n", f"Up check must append exactly SERVICE_B_UP once; got {content!r}."

    os.remove(DASHBOARD_LOG)
    traced = subprocess.run(["bash", "-x", MONITOR_SCRIPT], capture_output=True, text=True, timeout=10)
    assert traced.returncode == 0, "Monitor script failed under shell tracing."
    assert re.search(r"^\+ (?:/[^ ]+/)?curl -s http://127\.0\.0\.1:8082/metrics$", traced.stderr, re.MULTILINE), \
        "monitor.sh did not execute curl -s against the required metrics URL."
    assert read_text(DASHBOARD_LOG) == "SERVICE_B_UP\n"

    pid = read_pid()
    try:
        stop_process(pid)
        assert wait_for_port(False, 3), "Service B did not stop cleanly for the failure-path check."
        os.remove(DASHBOARD_LOG)
        failed = subprocess.run([MONITOR_SCRIPT], capture_output=True, text=True, timeout=10)
        assert failed.returncode == 0, "Monitor script failed while handling an unreachable service."
        assert os.path.isfile(DASHBOARD_LOG), "Monitor script did not create dashboard.log on failure."
        assert read_text(DASHBOARD_LOG) == "SERVICE_B_DOWN\n", \
            "Monitor script must append exactly SERVICE_B_DOWN when curl fails."
    finally:
        if not port_open():
            start_service()


def test_cron_schedule():
    assert os.path.isfile(CRON_FILE), f"Cron schedule file {CRON_FILE} does not exist."
    raw = read_text(CRON_FILE)
    content = raw.strip()
    expected = f"* * * * * {MONITOR_SCRIPT}"
    assert content == expected, f"Cron schedule file does not contain the exact expected expression. Got: '{content}', Expected: '{expected}'"
    assert raw.splitlines() == [expected], "Cron schedule must contain exactly one line and no extra blank lines."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
