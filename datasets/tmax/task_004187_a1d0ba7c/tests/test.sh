#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import secrets
import shlex
import signal
import subprocess
import time
import urllib.request


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_for_inodes(inodes):
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def listener_pids(port):
    return pids_for_inodes(listening_inodes(port))


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def exe_path(pid):
    try:
        return os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return ""


def wait_for_listener(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids(port):
            return
        time.sleep(0.1)
    raise AssertionError(f"No process began listening on port {port}")


def fetch(url, expected, timeout=2):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return response.status == 200 and response.read() == expected
    except Exception:
        return False


def test_fix_log_exists_and_content():
    log_path = "/home/user/fix.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "Service Restored", f"Expected 'Service Restored' in {log_path}, got '{content}'."


def test_tunnel_sh_exists_and_content():
    tunnel_path = "/home/user/tunnel.sh"
    assert os.path.isfile(tunnel_path), f"Tunnel script {tunnel_path} does not exist."
    with open(tunnel_path, "r") as f:
        content = f.read()
    assert "8080" in content and "9999" in content, f"Expected port forwarding command involving ports 8080 and 9999 in {tunnel_path}."

    commands = []
    for line in content.splitlines():
        try:
            tokens = shlex.split(line, comments=True)
        except ValueError:
            continue
        if tokens:
            commands.append(tokens)

    valid = False
    for tokens in commands:
        ssh_positions = [i for i, token in enumerate(tokens) if os.path.basename(token) == "ssh"]
        for pos in ssh_positions:
            args = tokens[pos + 1:]
            specs = []
            for i, arg in enumerate(args):
                if arg == "-L" and i + 1 < len(args):
                    specs.append(args[i + 1])
                elif arg.startswith("-L") and len(arg) > 2:
                    specs.append(arg[2:])
            for spec in specs:
                parts = spec.rsplit(":", 3)
                if len(parts) == 3:
                    local_port, host, remote_port = parts
                elif len(parts) == 4:
                    _, local_port, host, remote_port = parts
                else:
                    continue
                if local_port == "8080" and host in ("localhost", "127.0.0.1") and remote_port == "9999":
                    valid = True
    assert valid, "tunnel.sh must contain an ssh -L forwarding command from local port 8080 to localhost:9999"


def test_required_processes_and_configuration():
    source = "/app/go-fileserver/main.go"
    config = "/home/user/nginx.conf"
    assert os.path.isfile(source), f"Backend source {source} is missing"
    assert os.path.isfile(config), f"Nginx config {config} is missing"

    subprocess.run(["nginx", "-t", "-c", config], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    with open(config) as f:
        nginx_config = f.read()
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9000/?\s*;", nginx_config), "nginx.conf does not proxy to the Go backend on 127.0.0.1:9000"

    nginx_pids = listener_pids(8080)
    assert nginx_pids, "Nothing is listening on port 8080"
    assert any("nginx" in os.path.basename(exe_path(pid)) for pid in nginx_pids), "Port 8080 is not being served by Nginx"
    assert any("nginx" in cmdline(pid) and config in cmdline(pid) for pid in map(int, filter(str.isdigit, os.listdir('/proc')))), "Nginx was not started with /home/user/nginx.conf"

    backend_pids = listener_pids(9000)
    assert backend_pids, "Nothing is listening on backend port 9000"
    go_backends = []
    for pid in backend_pids:
        result = subprocess.run(["go", "version", "-m", f"/proc/{pid}/exe"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        if result.returncode == 0:
            go_backends.append(pid)
    assert go_backends, "Port 9000 is not served by a compiled Go program"


def test_nginx_load_success_rate():
    def fetch_url(url):
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status == 200 and response.read().decode('utf-8').strip() == "success":
                    return 1
        except Exception:
            pass
        return 0

    url = "http://127.0.0.1:8080/test.txt"
    successes = 0
    total = 100

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        results = [executor.submit(fetch_url, url) for _ in range(total)]
        for f in concurrent.futures.as_completed(results):
            successes += f.result()

    success_rate = successes / total
    assert success_rate >= 0.98, f"Metric threshold failed. Success rate {success_rate} < 0.98. The server is not responding correctly or is failing under load."


def test_current_source_builds_and_serves_via_backend_and_nginx():
    source = "/app/go-fileserver/main.go"
    rebuilt = f"/tmp/verified-go-fileserver-{os.getpid()}"
    subprocess.run(["go", "build", "-o", rebuilt, source], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK), "Go source did not produce an executable"

    old_pids = listener_pids(9000)
    assert old_pids, "Backend stopped before source verification"
    for pid in old_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while listener_pids(9000) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(9000):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 3
    while listener_pids(9000) and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(9000), "Could not stop the existing backend for source verification"

    backend = subprocess.Popen([rebuilt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_for_listener(9000, timeout=10)
    assert backend.poll() is None, "Backend compiled from main.go exited during startup"

    token = secrets.token_hex(12)
    relative = f"verifier-{token}/payload-{token}.bin"
    path = os.path.join("/home/user/data", relative)
    expected = secrets.token_bytes(4096)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(expected)

    direct_url = f"http://127.0.0.1:9000/{relative}"
    proxied_url = f"http://127.0.0.1:8080/{relative}"
    assert fetch(direct_url, expected), "Backend built from current main.go does not serve /home/user/data on port 9000"
    assert fetch(proxied_url, expected), "Nginx does not proxy dynamically generated content to the rebuilt Go backend"

    total = 40
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(lambda _: fetch(proxied_url, expected), range(total)))
    assert sum(results) >= 39, "Rebuilt backend and Nginx failed the dynamic concurrent load check"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
