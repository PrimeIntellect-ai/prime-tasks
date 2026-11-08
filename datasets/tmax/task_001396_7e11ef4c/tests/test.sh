#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import signal
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request


def run_filter(script, content):
    fd, path = tempfile.mkstemp(prefix="tz_case_", dir="/tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content)
        return subprocess.run([script, path], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=5).returncode
    finally:
        os.unlink(path)


def find_filter():
    scripts = glob.glob("/home/user/filter_tz.*")
    assert scripts, "No filter_tz script found in /home/user/."
    for path in scripts:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    path = scripts[0]
    os.chmod(path, 0o755)
    return path


def system_timezones():
    zones = []
    for table in ("/usr/share/zoneinfo/zone1970.tab", "/usr/share/zoneinfo/zone.tab"):
        if os.path.isfile(table):
            with open(table, encoding="utf-8") as f:
                for line in f:
                    if line and not line.startswith("#"):
                        fields = line.rstrip("\n").split("\t")
                        if len(fields) >= 3 and re.fullmatch(r"[A-Za-z0-9_/-]+", fields[2]):
                            zones.append(fields[2])
    assert zones, "System IANA timezone database is unavailable"
    return sorted(set(zones))


def test_filter_tz_script():
    script = find_filter()
    zones = system_timezones()
    chosen = random.SystemRandom().sample(zones, min(12, len(zones)))
    for zone in chosen:
        suffix = b"\n" if secrets.randbits(1) else b""
        assert run_filter(script, zone.encode() + suffix) == 0, f"Rejected valid IANA timezone {zone!r}"

    token = secrets.token_hex(8).encode()
    evil = [
        b"../../../etc/" + token + b"\n",
        b"America/New_York;echo " + token + b"\n",
        b"Europe/London\nUTC\n",
        b"Europe/London && id\n",
        b"America\\New_York\n",
        b"America/New York\n",
        b"/etc/passwd\n",
        b"../UTC\n",
        b"\n",
        b"Europe/London\x00" + token + b"\n",
    ]
    for payload in evil:
        assert run_filter(script, payload) == 1, f"Accepted malformed or malicious payload {payload!r}"


def test_fstab_setup():
    path = "/home/user/app_fstab"
    assert os.path.isfile(path), f"fstab file {path} is missing."
    with open(path, encoding="utf-8") as f:
        content = f.read()
    assert "/home/user/data_source" in content, "data_source not found in app_fstab."
    assert "/home/user/app/data" in content, "app/data not found in app_fstab."
    assert "bind" in content, "bind option not found in app_fstab."
    lines = content.splitlines()
    assert len(lines) == 1 and lines[0].strip(), "app_fstab must contain exactly one line"
    fields = lines[0].split()
    assert len(fields) == 6, "fstab entry must have six fields"
    assert fields[0] == "/home/user/data_source"
    assert fields[1] == "/home/user/app/data"
    assert fields[2] == "none"
    assert "bind" in fields[3].split(",")
    assert fields[4:] == ["0", "0"]


def parse_env(path):
    values = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            assert "=" in line, f"Invalid environment line: {raw!r}"
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("'\"")
    return values


def test_backend_env_configured():
    path = "/home/user/app/config/backend.env"
    assert os.path.isfile(path), f"Environment file {path} is missing."
    with open(path, encoding="utf-8") as f:
        content = f.read()
    assert "REDIS_HOST=localhost" in content or "REDIS_HOST=127.0.0.1" in content, "REDIS_HOST not set correctly."
    assert "REDIS_PORT=6379" in content, "REDIS_PORT not set correctly."
    assert "LANG=en_US.UTF-8" in content, "LANG not set correctly."
    assert "TZ=UTC" in content, "TZ not set correctly."
    env = parse_env(path)
    assert env.get("REDIS_HOST") in ("localhost", "127.0.0.1")
    assert env.get("REDIS_PORT") == "6379"
    assert env.get("LANG") == "en_US.UTF-8"
    assert env.get("TZ") == "UTC"


def test_nginx_conf_configured():
    path = "/home/user/app/config/nginx.conf"
    assert os.path.isfile(path), f"NGINX config {path} is missing."
    with open(path, encoding="utf-8") as f:
        content = f.read()
    assert "5000" in content, "NGINX config does not seem to proxy to port 5000."
    active = re.sub(r"#.*", "", content)
    assert re.search(r"\blisten\s+(?:[^;\n]*:)?8080\b[^;]*;", active), "NGINX must listen on port 8080"
    assert re.search(r"\blocation\s+(?:\^~\s+)?/api/\s*\{", active), "Missing /api/ location"
    assert re.search(r"\bproxy_pass\s+[^;]+;", active), "Missing proxy_pass in NGINX configuration"
    checked = subprocess.run(["nginx", "-t", "-c", path], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True)
    assert checked.returncode == 0, "Invalid NGINX configuration:\n" + checked.stdout


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(pid)
    return pids


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def wait_port(port, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.3):
                return
        except OSError:
            time.sleep(.15)
    raise AssertionError(f"Port {port} did not become ready")


def stop_existing_services():
    pids = set()
    for port in (8080, 5000, 6379):
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def fetch(url, timeout=3):
    req = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return response.status, dict(response.headers.items()), json.loads(body)


def process_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    return dict(item.decode(errors="replace").split("=", 1) for item in entries if b"=" in item)


def test_deployment_and_end_to_end_health():
    deploy = "/home/user/deploy.sh"
    starter = "/home/user/app/start_services.sh"
    assert os.path.isfile(deploy), f"Deployment script {deploy} is missing."
    assert os.access(deploy, os.X_OK), "Deployment script is not executable"
    assert os.path.isfile(starter) and os.access(starter, os.X_OK), "start_services.sh is missing or not executable"

    stop_existing_services()
    launch = subprocess.Popen([starter], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              start_new_session=True)
    try:
        for port in (6379, 5000, 8080):
            wait_port(port)

        status, headers, data = fetch("http://127.0.0.1:8080/api/health")
        assert status == 200
        assert data.get("status") == "ok"
        assert data.get("redis") == "connected"

        failures = []
        stop_probe = threading.Event()
        def probe():
            while not stop_probe.is_set():
                try:
                    code, _, body = fetch("http://127.0.0.1:8080/api/health", timeout=1)
                    if code != 200 or body.get("status") != "ok":
                        failures.append("unhealthy response")
                except Exception as exc:
                    failures.append(type(exc).__name__)
                time.sleep(.05)

        thread = threading.Thread(target=probe, daemon=True)
        thread.start()
        time.sleep(.2)
        deployed = subprocess.run([deploy], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, timeout=30)
        time.sleep(.3)
        stop_probe.set()
        thread.join(timeout=2)
        assert deployed.returncode == 0, "deploy.sh failed:\n" + deployed.stdout
        assert not failures, "Deployment dropped or failed requests: " + ", ".join(failures[:5])

        for port in (6379, 5000, 8080):
            wait_port(port)

        redis_pids = listener_pids(6379)
        backend_pids = listener_pids(5000)
        nginx_pids = listener_pids(8080)
        assert redis_pids and any("redis-server" in cmdline(p) for p in redis_pids), "Port 6379 is not served by Redis"
        assert nginx_pids and any("nginx" in cmdline(p).lower() for p in nginx_pids), "Port 8080 is not served by NGINX"
        assert backend_pids and any(re.search(r"python|flask|gunicorn|uwsgi", cmdline(p), re.I) for p in backend_pids), "Port 5000 is not served by a Python/Flask backend"

        backend_envs = [process_environment(p) for p in backend_pids]
        assert any(e.get("REDIS_HOST") in ("localhost", "127.0.0.1") and
                   e.get("REDIS_PORT") == "6379" and e.get("LANG") == "en_US.UTF-8" and
                   e.get("TZ") == "UTC" for e in backend_envs), "Backend process did not load backend.env"

        monitor = subprocess.Popen(["redis-cli", "-p", "6379", "MONITOR"],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(.3)
        nonce = secrets.token_hex(12)
        direct = fetch("http://127.0.0.1:5000/api/health?nonce=" + nonce)
        proxied = fetch("http://127.0.0.1:8080/api/health?nonce=" + nonce)
        time.sleep(.4)
        monitor.terminate()
        output, _ = monitor.communicate(timeout=3)

        for status, _, body in (direct, proxied):
            assert status == 200
            assert body.get("status") == "ok"
            assert body.get("redis") == "connected"
        assert "nginx" in proxied[1].get("Server", "").lower(), "Port 8080 response did not pass through NGINX"
        assert re.search(r'\bPING\b', output, re.I), "Backend health requests did not contact Redis"
    finally:
        if launch.poll() is None:
            try:
                os.killpg(launch.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
