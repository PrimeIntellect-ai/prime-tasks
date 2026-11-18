#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import socket
import stat
import subprocess
import time
from decimal import Decimal

import requests

BASE_URL = "http://127.0.0.1:8080"
API_PATH = "/home/user/app/api.py"
NGINX_CONF = "/home/user/nginx/nginx.conf"
FSTAB_PATH = "/home/user/vfs/fstab"


def get_json(path):
    try:
        response = requests.get(BASE_URL + path, timeout=5)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to Nginx on port 8080 or upstream is down: {exc}"
    assert response.status_code == 200, (
        f"Expected status code 200 from {path}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        assert False, f"Expected JSON response from {path}, got: {response.text}"


def process_cmdlines():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                cmd = handle.read().replace(b"\0", b" ").decode(errors="replace")
        except (OSError, PermissionError):
            continue
        result[int(entry)] = cmd
    return result


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
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
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(int(entry))
                break
    return pids


def test_health_endpoint():
    data = get_json("/health")
    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"


def test_original_metrics_endpoint():
    data = get_json("/metrics")
    expected_costs = {"EC2": 15.50, "S3": 4.00, "RDS": 15.00}
    for service, expected_val in expected_costs.items():
        assert service in data, f"Missing service '{service}' in JSON response. Got: {data}"
        actual_val = float(data[service])
        assert abs(actual_val - expected_val) < 0.01, (
            f"Expected {expected_val} for {service}, got {actual_val}"
        )


def test_nginx_gunicorn_and_unix_socket():
    assert os.path.exists(NGINX_CONF), f"{NGINX_CONF} is missing"
    check = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert check.returncode == 0, f"Invalid Nginx configuration:\n{check.stdout}"

    with open(NGINX_CONF) as handle:
        config = handle.read()
    assert re.search(r"\blisten\s+8080\b", config), "Nginx config does not listen on port 8080"
    assert re.search(r"\bproxy_pass\b", config), "Nginx config has no proxy_pass directive"
    assert "/tmp/wrong_path.sock" not in config, "Nginx still references the broken socket"

    socket_paths = set(re.findall(r"unix:(/[^\s:;]+)", config))
    assert socket_paths, "Nginx configuration does not reference a Unix socket"
    live_sockets = [p for p in socket_paths if os.path.exists(p) and stat.S_ISSOCK(os.stat(p).st_mode)]
    assert live_sockets, f"None of the configured Unix sockets is live: {sorted(socket_paths)}"

    cmdlines = process_cmdlines()
    gunicorn_commands = [cmd for cmd in cmdlines.values() if "gunicorn" in cmd.lower()]
    assert gunicorn_commands, "The Flask backend is not running under Gunicorn"
    assert any(path in cmd for cmd in gunicorn_commands for path in live_sockets), (
        "Gunicorn is not bound to the Unix socket referenced by Nginx"
    )

    owners = listening_pids(8080)
    assert owners, "No process is listening on TCP port 8080"
    assert any("nginx" in cmdlines.get(pid, "").lower() for pid in owners), (
        "TCP port 8080 is not being served by Nginx"
    )

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.connect(live_sockets[0])
        sock.sendall(b"GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n")
        response = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
    finally:
        sock.close()
    assert b"200" in response.split(b"\r\n", 1)[0], (
        f"Gunicorn socket did not return a successful health response: {response[:200]!r}"
    )


def test_api_py_uses_subprocess():
    assert os.path.exists(API_PATH), f"{API_PATH} is missing"
    with open(API_PATH) as handle:
        content = handle.read()
    assert "subprocess" in content, "api.py does not appear to use subprocess to calculate the costs."

    tree = ast.parse(content, filename=API_PATH)
    module_aliases = {"subprocess"}
    imported_functions = set()
    subprocess_functions = {
        "run", "Popen", "call", "check_call", "check_output",
        "getoutput", "getstatusoutput"
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "subprocess":
                    module_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == "subprocess":
            for alias in node.names:
                if alias.name in subprocess_functions:
                    imported_functions.add(alias.asname or alias.name)

    calls_subprocess = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if (isinstance(node.func.value, ast.Name)
                    and node.func.value.id in module_aliases
                    and node.func.attr in subprocess_functions):
                calls_subprocess = True
        elif isinstance(node.func, ast.Name) and node.func.id in imported_functions:
            calls_subprocess = True
    assert calls_subprocess, "api.py imports subprocess but never calls it"


def test_dynamic_fstab_discovery_and_aggregation():
    token = secrets.token_hex(6)
    selected_dir = f"/home/user/data/verifier_finops_{token}"
    decoy_dir = f"/home/user/data/verifier_decoy_{token}"
    os.makedirs(selected_dir, mode=0o755, exist_ok=True)
    os.makedirs(decoy_dir, mode=0o755, exist_ok=True)

    services = [f"Compute_{token}", f"Storage_{token}", f"Database_{token}"]
    records = [
        (services[0], Decimal(secrets.randbelow(8000) + 101) / 100),
        (services[1], Decimal(secrets.randbelow(8000) + 101) / 100),
        (services[0], Decimal(secrets.randbelow(8000) + 101) / 100),
        (services[2], Decimal(secrets.randbelow(8000) + 101) / 100),
        (services[1], Decimal(secrets.randbelow(8000) + 101) / 100),
    ]
    billing_path = os.path.join(selected_dir, "billing.log")
    with open(billing_path, "w") as handle:
        for index, (service, cost) in enumerate(records):
            handle.write(f"2026-01-01T00:00:{index:02d}Z|{service}|instance-{index}|{cost:.2f}\n")
    os.chmod(billing_path, 0o644)

    with open(os.path.join(decoy_dir, "billing.log"), "w") as handle:
        handle.write("2026-01-01T00:00:00Z|WRONG_VOLUME|x|999999.99\n")

    expected = {}
    with open(billing_path) as handle:
        for line in handle:
            fields = line.rstrip("\n").split("|")
            expected[fields[1]] = expected.get(fields[1], Decimal("0")) + Decimal(fields[3])

    with open(FSTAB_PATH, "rb") as handle:
        original_fstab = handle.read()
    replacement = (
        f"UUID=decoy {decoy_dir} ext4 defaults,rw 0 2\n"
        f"UUID=wrongtype {decoy_dir} xfs defaults,finops=true,rw 0 0\n"
        f"UUID=selected {selected_dir} ext4 defaults,finops=true,rw 0 2\n"
    )

    try:
        temporary = FSTAB_PATH + ".verifier"
        with open(temporary, "w") as handle:
            handle.write(replacement)
        os.replace(temporary, FSTAB_PATH)

        data = None
        last_error = None
        for _ in range(10):
            try:
                data = get_json("/metrics")
                if set(data) == set(expected):
                    break
            except AssertionError as exc:
                last_error = exc
            time.sleep(0.2)
        assert data is not None, f"No metrics response after fstab update: {last_error}"
        assert set(data) == set(expected), (
            f"Metrics did not follow the ext4 finops=true mount. Expected keys "
            f"{set(expected)}, got {data}"
        )
        for service, expected_value in expected.items():
            actual = float(data[service])
            assert abs(actual - float(expected_value)) < 0.000001, (
                f"Incorrect dynamically aggregated value for {service}: "
                f"expected {expected_value}, got {actual}"
            )
    finally:
        temporary = FSTAB_PATH + ".restore"
        with open(temporary, "wb") as handle:
            handle.write(original_fstab)
        os.replace(temporary, FSTAB_PATH)
        for path in (billing_path, os.path.join(decoy_dir, "billing.log")):
            try:
                os.unlink(path)
            except OSError:
                pass
        for directory in (selected_dir, decoy_dir):
            try:
                os.rmdir(directory)
            except OSError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
