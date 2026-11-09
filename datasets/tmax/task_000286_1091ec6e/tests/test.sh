#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_final_state.py
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import uuid
from urllib.request import Request, urlopen

ROOT = "/app/tz-server-1.0"
BINARY = ROOT + "/tz-server"
MAKEFILE = ROOT + "/Makefile"
MONITOR = ROOT + "/monitor.sh"
CONF = "/home/user/nginx.conf"
HEALTH = "/home/user/data/health.status"


def http_get(url, timeout=2):
    req = Request(url, headers={"Connection": "close"})
    with urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8", "replace")


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
    except OSError:
        return []


def matching_pids(text):
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        if text in " ".join(proc_cmdline(int(entry))):
            result.append(int(entry))
    return result


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                result.add(fields[9])
    return result


def listener_pids(port):
    inodes = listener_inodes(port)
    assert inodes, f"Nothing is listening on port {port}"
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(int(entry))
                break
    assert owners, f"Could not identify the process listening on port {port}"
    return owners


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def proc_exe_hash(pid):
    return file_hash(f"/proc/{pid}/exe")


def proc_env(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            return set(f.read().split(b"\0"))
    except OSError:
        return set()


def io_syscr(pid):
    values = {}
    with open(f"/proc/{pid}/io") as f:
        for line in f:
            key, value = line.split(":", 1)
            values[key] = int(value.strip())
    return values["syscr"]


# Preserve the original artifact and health-file assertions.
assert os.path.isfile(HEALTH), f"Health status file {HEALTH} does not exist."
with open(HEALTH) as f:
    assert f.read().strip() == "OK", "Expected health.status to contain OK"
assert os.path.isfile(BINARY), f"tz-server binary not found at {BINARY}"
assert os.access(BINARY, os.X_OK), f"tz-server binary at {BINARY} is not executable"
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", "tz-server is not an ELF executable"

# Verify that the real compiled artifact, not a command-line lookalike, owns both ports.
binary_hash = file_hash(BINARY)
backend_pid = {}
for port in (8081, 8082):
    owners = listener_pids(port)
    valid = [pid for pid in owners if proc_exe_hash(pid) == binary_hash]
    assert valid, f"Port {port} is not owned by the submitted tz-server binary"
    valid_tz = [pid for pid in valid if b"TZ=Europe/Berlin" in proc_env(pid)]
    assert valid_tz, f"tz-server on port {port} is not running with TZ=Europe/Berlin"
    backend_pid[port] = valid_tz[0]
    status, body = http_get(f"http://127.0.0.1:{port}/time")
    assert status == 200, f"Backend {port} did not return HTTP 200"
    assert json.loads(body) == {"timezone": "Europe/Berlin"}, f"Bad backend response on {port}: {body}"

# The Makefile itself must contain the standard fix and successfully build the source.
assert os.path.isfile(MAKEFILE), "Makefile is missing"
make_text = open(MAKEFILE).read()
assert re.search(r"-std=(?:c\+\+|gnu\+\+)(?:11|14|17|20|23|2a|2b)", make_text), \
       "Makefile does not select a suitable C++ standard"
with tempfile.TemporaryDirectory() as build_dir:
    shutil.copy2(MAKEFILE, os.path.join(build_dir, "Makefile"))
    shutil.copy2(os.path.join(ROOT, "server.cpp"), os.path.join(build_dir, "server.cpp"))
    subprocess.run(["make", "clean", "all"], cwd=build_dir, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
    rebuilt = os.path.join(build_dir, "tz-server")
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK), "Corrected Makefile did not build tz-server"
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Makefile did not produce an ELF executable"

    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    probe_port = probe.getsockname()[1]
    probe.close()
    marker = "Verifier_" + uuid.uuid4().hex
    env = os.environ.copy()
    env["TZ"] = marker
    child = subprocess.Popen([rebuilt, str(probe_port)], cwd=build_dir, env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 3
        while True:
            try:
                status, body = http_get(f"http://127.0.0.1:{probe_port}/probe", timeout=.5)
                break
            except Exception:
                assert child.poll() is None, "Rebuilt tz-server exited during execution test"
                if time.time() >= deadline:
                    raise AssertionError("Rebuilt tz-server did not begin listening")
                time.sleep(.05)
        assert status == 200
        assert json.loads(body) == {"timezone": marker}, "Rebuilt binary returned a hardcoded response"
    finally:
        child.terminate()
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            child.kill()

# Inspect and validate the exact Nginx configuration requested by the instruction.
assert os.path.isfile(CONF), f"Nginx configuration not found at {CONF}"
check = subprocess.run(["nginx", "-t", "-c", CONF], stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True, timeout=10)
assert check.returncode == 0, "nginx -t failed:\n" + check.stdout
conf = re.sub(r"#.*", "", open(CONF).read())
assert re.search(r"\buser\s+user\s*;", conf), "Nginx is not configured for the non-root user"
assert re.search(r"\bpid\s+/home/user/nginx\.pid\s*;", conf), "Incorrect Nginx PID path"
for directive in ("error_log", "access_log"):
    match = re.search(rf"\b{directive}\s+([^;\s]+)", conf)
    assert match and (match.group(1) == "/dev/null" or match.group(1).startswith("/home/user/data/")), \
        f"{directive} is not under /home/user/data or /dev/null"
assert re.search(r"\blisten\s+127\.0\.0\.1:8080(?:\s|;)", conf), "Nginx does not listen on 127.0.0.1:8080"
assert re.search(r"\bclient_body_temp_path\s+/home/user/data/", conf), "client_body_temp_path is not under /home/user/data"

upstreams = re.findall(r"upstream\s+([A-Za-z0-9_]+)\s*\{([^}]*)\}", conf, re.S)
upstream_name = None
for name, body in upstreams:
    if re.search(r"server\s+127\.0\.0\.1:8081\s*;", body) and re.search(r"server\s+127\.0\.0\.1:8082\s*;", body):
        upstream_name = name
        break
assert upstream_name, "No upstream group contains both required backend servers"
time_location = re.search(r"location\s+(?:=\s*)?/time\s*\{([^}]*)\}", conf, re.S)
assert time_location, "Missing /time location"
assert re.search(rf"proxy_pass\s+http://{re.escape(upstream_name)}(?:/)?\s*;", time_location.group(1)), \
       "/time does not proxy to the two-server upstream"
health_location = re.search(r"location\s+(?:=\s*)?/health\s*\{([^}]*)\}", conf, re.S)
assert health_location, "Missing /health location"
hbody = health_location.group(1)
alias_ok = re.search(r"alias\s+/home/user/data/health\.status\s*;", hbody)
root_ok = re.search(r"root\s+/home/user/data(?:/)?\s*;", hbody) and re.search(r"try_files\b", hbody)
assert alias_ok or root_ok, "/health is not configured to serve the required health.status file"

# The live listener must really be Nginx started with this configuration, with a non-root worker.
nginx_owners = listener_pids(8080)
for pid in nginx_owners:
    assert os.path.basename(os.readlink(f"/proc/{pid}/exe")) == "nginx", "Port 8080 is owned by a non-Nginx process"
assert any(os.stat(f"/proc/{pid}").st_uid != 0 for pid in nginx_owners), "No non-root Nginx process owns the listener"
nginx_pids = matching_pids("nginx")
assert nginx_pids, "nginx is not running"
assert any(CONF in proc_cmdline(pid) or CONF in " ".join(proc_cmdline(pid)) for pid in nginx_pids), \
       "Running Nginx was not started with /home/user/nginx.conf"

# Preserve endpoint checks and prove traffic actually reaches both backend processes.
for _ in range(4):
    status, body = http_get("http://127.0.0.1:8080/time")
    assert status == 200
    assert "Europe/Berlin" in body
before = {port: io_syscr(pid) for port, pid in backend_pid.items()}
for _ in range(10):
    status, body = http_get("http://127.0.0.1:8080/time")
    assert status == 200 and json.loads(body) == {"timezone": "Europe/Berlin"}
after = {port: io_syscr(pid) for port, pid in backend_pid.items()}
for port in (8081, 8082):
    assert after[port] > before[port], f"Nginx did not send any tested requests to backend {port}"
status, body = http_get("http://127.0.0.1:8080/health")
assert status == 200 and body.strip() == "OK", "Expected OK from /health"

# Preserve the monitor-process assertion, then execute the submitted script from an unrelated cwd.
monitor_pids = matching_pids("monitor.sh")
assert monitor_pids, "monitor.sh is not running in the background"
assert os.path.isfile(MONITOR) and os.access(MONITOR, os.X_OK), "monitor.sh is missing or not executable"
monitor_text = open(MONITOR).read()
assert "/home/user/data/health.status" in monitor_text, "monitor.sh does not name the required absolute output path"
for pid in monitor_pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(.2)

# Demonstrate that /health serves the file rather than a hardcoded OK response.
health_marker = "health_" + uuid.uuid4().hex
with open(HEALTH, "w") as f:
    f.write(health_marker + "\n")
status, body = http_get("http://127.0.0.1:8080/health")
assert status == 200 and body.strip() == health_marker, "/health is not serving health.status"
os.unlink(HEALTH)

monitor_cwd = tempfile.mkdtemp(prefix="monitor-cwd-")
subprocess.Popen([MONITOR], cwd=monitor_cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 start_new_session=True)
deadline = time.time() + 3
while not os.path.isfile(HEALTH) and time.time() < deadline:
    time.sleep(.05)
assert os.path.isfile(HEALTH), "Executing monitor.sh did not create /home/user/data/health.status"
with open(HEALTH) as f:
    assert f.read().strip() == "OK", "monitor.sh did not write OK"
assert not os.path.exists(os.path.join(monitor_cwd, "health.status")), "monitor.sh still writes relative to its cwd"
assert matching_pids("monitor.sh"), "monitor.sh is not left running in the background"
PY_EOF

if python3 /tmp/verify_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
