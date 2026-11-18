#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request

ORIGINAL_SOURCE = '''#include <stdio.h>

int main() {
    FILE *f = fopen("./metrics.json", "w");
    if (f == NULL) return 1;
    fprintf(f, "{\\"status\\": \\"ok\\", \\"active_users\\": 42}\\n");
    fclose(f);
    return 0;
}
'''


def test_backup_exists_and_content():
    backup_file = "/home/user/backup/collector.c.bak"
    assert os.path.isfile(backup_file), f"Backup file {backup_file} does not exist."
    with open(backup_file, 'r') as f:
        content = f.read()
    assert '"./metrics.json"' in content, f"Original path './metrics.json' not found in backup file {backup_file}."
    assert content == ORIGINAL_SOURCE, f"Backup file {backup_file} is not an unchanged copy of the original source."


def test_collector_c_updated_and_compiled():
    c_file = "/home/user/src/collector.c"
    assert os.path.isfile(c_file), f"File {c_file} does not exist."
    with open(c_file, 'r') as f:
        content = f.read()
    assert '"/home/user/dashboard/metrics.json"' in content, f"Updated path '/home/user/dashboard/metrics.json' not found in {c_file}."

    binary_file = "/home/user/bin/collector"
    assert os.path.isfile(binary_file), f"Binary {binary_file} does not exist."
    assert os.access(binary_file, os.X_OK), f"Binary {binary_file} is not executable."
    with open(binary_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Binary {binary_file} is not an ELF executable."

    # Check if binary was compiled after the source was updated
    c_mtime = os.path.getmtime(c_file)
    bin_mtime = os.path.getmtime(binary_file)
    assert bin_mtime >= c_mtime, f"Binary {binary_file} is older than source {c_file}. Did you recompile?"

    # Independently ensure the submitted source really compiles with gcc.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "collector")
        result = subprocess.run(
            ["gcc", c_file, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"Updated collector.c does not compile with gcc: {result.stderr}"


def test_submitted_collector_actually_generates_metrics():
    binary_file = "/home/user/bin/collector"
    metrics_file = "/home/user/dashboard/metrics.json"

    if os.path.exists(metrics_file):
        os.remove(metrics_file)

    with tempfile.TemporaryDirectory() as td:
        local_metrics = os.path.join(td, "metrics.json")
        with open(local_metrics, "w") as f:
            f.write("sentinel")

        result = subprocess.run(
            [binary_file],
            cwd=td,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode == 0, f"Collector exited with status {result.returncode}."
        assert os.path.isfile(metrics_file), "Executing the submitted collector did not create /home/user/dashboard/metrics.json."
        with open(local_metrics, "r") as f:
            assert f.read() == "sentinel", "Collector still wrote to ./metrics.json in its working directory."

    with open(metrics_file, "r") as f:
        data = json.load(f)
    assert data.get("status") == "ok", "Collector output is missing 'status': 'ok'."
    assert data.get("active_users") == 42, "Collector output is missing 'active_users': 42."


def test_metrics_json_generated():
    metrics_file = "/home/user/dashboard/metrics.json"
    assert os.path.isfile(metrics_file), f"Metrics file {metrics_file} does not exist. Did you run the recompiled binary?"
    with open(metrics_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Metrics file {metrics_file} does not contain valid JSON."
    assert data.get("status") == "ok", "Metrics JSON missing 'status': 'ok'."
    assert data.get("active_users") == 42, "Metrics JSON missing 'active_users': 42."


def _socket_inodes_for_pid(pid):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inodes.add(target[8:-1])
    return inodes


def _ipv4_listener_inodes(ip, port):
    packed_ip = socket.inet_aton(ip)[::-1].hex().upper()
    expected_local = f"{packed_ip}:{port:04X}"
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1] == expected_local and fields[3] == "0A":
                inodes.add(fields[9])
    return inodes


def test_socat_proxy_running():
    pid_file = "/home/user/proxy.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."
    with open(pid_file, 'r') as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer."

    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.basename(exe) == "socat", f"PID {pid} is not a socat process."
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        args = [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]
    lowered = [a.lower() for a in args]
    listen_args = [a for a in lowered if "tcp4-listen:9090" in a]
    assert listen_args, "socat is not configured with TCP4-LISTEN:9090."
    assert "bind=127.0.0.1" in listen_args[0], "socat listener is not bound to 127.0.0.1."
    assert "fork" in listen_args[0].split(","), "socat listener was not configured to fork."
    assert any("tcp4:127.0.0.1:8080" in a for a in lowered), "socat does not forward to 127.0.0.1:8080."

    owned = _socket_inodes_for_pid(pid)
    listeners = _ipv4_listener_inodes("127.0.0.1", 9090)
    assert owned & listeners, f"The socat process in {pid_file} does not own the listener on 127.0.0.1:9090."

    # Check if socat is listening on 9090
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(('127.0.0.1', 9090))
    sock.close()
    assert result == 0, "Nothing is listening on 127.0.0.1:9090. Is socat running correctly?"


def test_proxy_forwarding_works():
    # Test if we can fetch metrics.json via the proxy
    try:
        req = urllib.request.urlopen("http://127.0.0.1:9090/metrics.json", timeout=2)
        content = req.read().decode('utf-8')
        data = json.loads(content)
        assert data.get("active_users") == 42, "Fetched metrics JSON via proxy is incorrect."
    except urllib.error.URLError as e:
        assert False, f"Failed to fetch metrics via proxy on port 9090: {e}"
    except json.JSONDecodeError:
        assert False, "Data fetched via proxy is not valid JSON."


def test_proxy_forwards_fresh_dynamic_content():
    token = secrets.token_hex(24)
    filename = f"verifier-{secrets.token_hex(8)}.txt"
    path = os.path.join("/home/user/dashboard", filename)
    with open(path, "w") as f:
        f.write(token)
    try:
        direct = urllib.request.urlopen(f"http://127.0.0.1:8080/{filename}", timeout=3).read().decode()
        assert direct == token, "Dashboard service on port 8080 did not serve the challenge file."
        proxied = urllib.request.urlopen(f"http://127.0.0.1:9090/{filename}", timeout=3).read().decode()
        assert proxied == token, "Port 9090 did not forward fresh content from the dashboard on port 8080."
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
