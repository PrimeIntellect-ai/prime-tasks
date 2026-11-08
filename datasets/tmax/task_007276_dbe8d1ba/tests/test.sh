#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

EXPECTED = '{"vms_running": 3, "qemu_cpu_usage": "45%", "qemu_mem_usage": "2GB"}'
SOCKET_PATH = "/tmp/qemu_stats.sock"
SCRIPT_PATH = "/home/user/check_capacity.sh"
REPORT_PATH = "/home/user/capacity_report.txt"


def listener_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].rsplit(":", 1)[1].upper() == wanted and fields[3] == "0A":
                    result.add(fields[9])
    return result


def unix_socket_inode(path):
    with open("/proc/net/unix") as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == path:
                return fields[6]
    return None


def owners_of_inodes(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(int(entry))
                break
    return owners


def cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode("utf-8", "replace")


def http_get(url, timeout=2):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8").strip(), response.headers


def unix_http_get(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect(path)
    s.sendall(b"GET /stats HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
    chunks = []
    while True:
        data = s.recv(65536)
        if not data:
            break
        chunks.append(data)
    s.close()
    raw = b"".join(chunks)
    head, body = raw.split(b"\r\n\r\n", 1)
    assert head.startswith(b"HTTP/1.1 200") or head.startswith(b"HTTP/1.0 200"), head
    return body.decode("utf-8").strip()


def wait_for(predicate, timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for service: {last_error}")


def run_capacity_script():
    result = subprocess.run(
        ["bash", SCRIPT_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f"Capacity script failed: {result.stderr}"


def test_nginx_config_fixed():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://unix:/tmp/qemu_stats.sock;" in content, "The nginx.conf file does not contain the corrected proxy_pass directive."
    assert "qemu-stats.sock" not in content, "The typo in nginx.conf was not completely removed."


def test_check_capacity_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "curl" in content, "The script does not use curl."
    assert "8080" in content, "The script does not target port 8080."
    assert "capacity_report.txt" in content, "The script does not seem to save to capacity_report.txt."
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    run_capacity_script()
    assert os.path.isfile(REPORT_PATH), "Executing the script did not create capacity_report.txt."


def test_capacity_report_content():
    assert os.path.isfile(REPORT_PATH), f"File {REPORT_PATH} does not exist. Did you run the script?"
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, f"The content of {REPORT_PATH} does not match the expected JSON payload."


def test_services_running_and_reachable():
    url = "http://127.0.0.1:8080/stats"
    try:
        status, body, headers = http_get(url)
    except urllib.error.URLError as e:
        assert False, f"Failed to reach the Nginx endpoint at {url}. Is Nginx running? Error: {e}"
    assert status == 200, f"Expected HTTP 200 OK, got {status}."
    assert body == EXPECTED, "The endpoint did not return the expected JSON payload. Is the Go API running and proxy configured correctly?"

    tcp_inodes = listener_inodes(8080)
    assert tcp_inodes, "No process is listening on TCP port 8080."
    tcp_owners = owners_of_inodes(tcp_inodes)
    assert tcp_owners, "Could not identify the process listening on port 8080."
    nginx_path = os.path.realpath(subprocess.check_output(["sh", "-c", "command -v nginx"], text=True).strip())
    for pid in tcp_owners:
        assert os.path.realpath(f"/proc/{pid}/exe") == nginx_path, f"Port 8080 is owned by PID {pid}, not the installed Nginx executable."
    nginx_cmds = [cmdline(pid) for pid in tcp_owners]
    assert any("/home/user/nginx/nginx.conf" in c and "/home/user/nginx" in c for c in nginx_cmds), "The running Nginx was not started with the required configuration and prefix."
    assert "nginx" in headers.get("Server", "").lower(), "The HTTP response was not served by Nginx."

    inode = unix_socket_inode(SOCKET_PATH)
    assert inode, f"The Go API is not listening on {SOCKET_PATH}."
    api_owners = owners_of_inodes({inode})
    assert api_owners, "Could not identify the process owning the API UNIX socket."
    go_owner_found = False
    for pid in api_owners:
        result = subprocess.run(["go", "version", "-m", f"/proc/{pid}/exe"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode == 0 and "go1." in result.stdout:
            go_owner_found = True
            break
    assert go_owner_found, "The qemu_stats UNIX socket is not owned by a running Go executable."
    assert unix_http_get(SOCKET_PATH) == EXPECTED, "The API listening on the UNIX socket returned the wrong payload."


def test_proxy_and_script_are_functionally_used():
    inode = unix_socket_inode(SOCKET_PATH)
    assert inode, "API UNIX socket disappeared before the functional test."
    api_pids = owners_of_inodes({inode})
    assert api_pids, "Could not locate the API process for the functional test."

    nonce = '{"verifier_probe":"%s"}' % os.urandom(12).hex()
    probe_source = r'''import os, socket
path = "/tmp/qemu_stats.sock"
try:
    os.unlink(path)
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(20)
body = os.environ["PROBE_BODY"].encode()
while True:
    c, _ = s.accept()
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            part = c.recv(4096)
            if not part:
                break
            data += part
        response = (b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " +
                    str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
        c.sendall(response)
    finally:
        c.close()
'''
    with open("/tmp/verifier_probe_backend.py", "w") as f:
        f.write(probe_source)

    probe = None
    restarted = None
    try:
        for pid in api_pids:
            os.kill(pid, signal.SIGTERM)
        wait_for(lambda: not owners_of_inodes({inode}), timeout=5)
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env["PROBE_BODY"] = nonce
        probe = subprocess.Popen(["python3", "/tmp/verifier_probe_backend.py"], env=env,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for(lambda: unix_socket_inode(SOCKET_PATH) is not None, timeout=5)
        wait_for(lambda: http_get("http://127.0.0.1:8080/stats")[1] == nonce, timeout=5)

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_capacity_script()
        assert os.path.isfile(REPORT_PATH), "The capacity script did not create its report during the live probe."
        with open(REPORT_PATH) as f:
            generated = f.read().strip()
        assert generated == nonce, "The script did not save the live response obtained through Nginx and the UNIX-socket API."
    finally:
        if probe is not None and probe.poll() is None:
            probe.terminate()
            try:
                probe.wait(timeout=3)
            except subprocess.TimeoutExpired:
                probe.kill()
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass

        restarted = subprocess.Popen(
            ["runuser", "-u", "user", "--", "bash", "-lc", "cd /home/user/app && exec go run api.go"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_for(lambda: unix_socket_inode(SOCKET_PATH) is not None, timeout=15)
        wait_for(lambda: http_get("http://127.0.0.1:8080/stats")[1] == EXPECTED, timeout=15)
        run_capacity_script()
        with open(REPORT_PATH) as f:
            assert f.read().strip() == EXPECTED, "The restored final capacity report is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
