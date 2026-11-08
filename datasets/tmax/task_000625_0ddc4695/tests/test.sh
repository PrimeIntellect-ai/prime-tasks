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
import os
import re
import shlex
import subprocess
import uuid

import configparser
import pytest
import requests

CONF = "/home/user/supervisor/supervisord.conf"


def supervisorctl(*args):
    return subprocess.run(
        ["supervisorctl", "-c", CONF, *args],
        capture_output=True,
        text=True,
    )


def supervisor_pid(name):
    result = supervisorctl("pid", name)
    assert result.returncode == 0, f"Could not obtain PID for {name}: {result.stdout} {result.stderr}"
    value = result.stdout.strip()
    assert value.isdigit() and int(value) > 0, f"Invalid supervisor PID for {name}: {value!r}"
    return int(value)


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except OSError as exc:
        pytest.fail(f"Could not inspect process {pid}: {exc}")


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/status", encoding="utf-8") as f:
                match = re.search(r"^PPid:\s*(\d+)", f.read(), re.MULTILINE)
        except OSError:
            return False
        if not match:
            return False
        pid = int(match.group(1))
    return pid == ancestor


def listening_socket_inodes(port, required_ipv4=None):
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_hex, state, inode = fields[1], fields[3], fields[9]
            address_hex, port_hex = local_hex.split(":")
            if state != "0A" or int(port_hex, 16) != port:
                continue
            if required_ipv4 is not None:
                octets = bytes.fromhex(address_hex)[::-1]
                address = ".".join(str(x) for x in octets)
                if address != required_ipv4:
                    continue
            inodes.add(inode)
    return inodes


def socket_owner_pids(inodes):
    owners = set()
    targets = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        fd_dir = os.path.join(entry.path, "fd")
        try:
            for fd in os.scandir(fd_dir):
                try:
                    if os.readlink(fd.path) in targets:
                        owners.add(int(entry.name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def assert_supervised_listener(name, port, required_ipv4=None):
    managed_pid = supervisor_pid(name)
    inodes = listening_socket_inodes(port, required_ipv4)
    assert inodes, f"No process is listening on the required address/port for {name}: {required_ipv4 or '*'}:{port}"
    owners = socket_owner_pids(inodes)
    assert owners, f"Could not identify the owner of the listener on port {port}"
    assert any(is_descendant(pid, managed_pid) for pid in owners), (
        f"Port {port} is not owned by {name} or one of its descendants; "
        f"supervisor PID={managed_pid}, listener owners={sorted(owners)}"
    )


def test_app_data_size():
    app_data_dir = "/home/user/app_data"
    assert os.path.isdir(app_data_dir), f"Directory missing: {app_data_dir}"

    total_size = 0
    for dirpath, _, filenames in os.walk(app_data_dir):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)

    size_mb = total_size / (1024 * 1024)
    assert size_mb < 5.0, f"Total size of {app_data_dir} is {size_mb:.2f}MB, which is not strictly less than 5MB. The junk file may not have been removed."


def test_supervisord_conf():
    conf_path = CONF
    assert os.path.isfile(conf_path), f"Missing configuration file: {conf_path}"

    config = configparser.ConfigParser()
    config.read(conf_path)

    assert "program:api-service" in config.sections(), "Missing [program:api-service] section in supervisord.conf"

    autorestart = config.get("program:api-service", "autorestart", fallback="").lower()
    assert autorestart == "true", f"Expected autorestart=true in [program:api-service], got '{autorestart}'"

    startretries = config.get("program:api-service", "startretries", fallback="")
    assert startretries == "5", f"Expected startretries=5 in [program:api-service], got '{startretries}'"


def test_all_program_definitions():
    config = configparser.ConfigParser()
    config.read(CONF)
    expected = {
        "program:api-service": ["python3", "/home/user/api-service.py"],
        "program:storage-monitor": ["/home/user/storage-monitor.sh"],
        "program:nginx": ["nginx", "-c", "/home/user/nginx/nginx.conf"],
    }
    for section, expected_command in expected.items():
        assert section in config.sections(), f"Missing [{section}] section in supervisord.conf"
        command = config.get(section, "command", fallback="")
        assert shlex.split(command) == expected_command, (
            f"Unexpected command for [{section}]: {command!r}; expected {' '.join(expected_command)!r}"
        )


def test_supervisor_status():
    result = supervisorctl("status", "api-service")
    assert result.returncode == 0, f"supervisorctl command failed: {result.stderr}"
    assert "RUNNING" in result.stdout, f"api-service is not RUNNING. Output: {result.stdout}"


def test_all_supervisor_services_running():
    for name in ("api-service", "storage-monitor", "nginx"):
        result = supervisorctl("status", name)
        assert result.returncode == 0, f"supervisorctl status failed for {name}: {result.stdout} {result.stderr}"
        fields = result.stdout.split()
        assert len(fields) >= 2 and fields[0] == name and fields[1] == "RUNNING", (
            f"{name} is not RUNNING under supervisord. Output: {result.stdout}"
        )

    api_cmd = process_cmdline(supervisor_pid("api-service"))
    assert "/home/user/api-service.py" in api_cmd, f"Supervised api-service is not the requested API: {api_cmd}"

    monitor_cmd = process_cmdline(supervisor_pid("storage-monitor"))
    assert any(arg == "/home/user/storage-monitor.sh" for arg in monitor_cmd), (
        f"Supervised storage-monitor is not the requested daemon: {monitor_cmd}"
    )

    nginx_cmd = process_cmdline(supervisor_pid("nginx"))
    assert "nginx" in os.path.basename(nginx_cmd[0]) and "/home/user/nginx/nginx.conf" in nginx_cmd, (
        f"Supervised nginx is not using the requested configuration: {nginx_cmd}"
    )


def test_nginx_configuration():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Missing Nginx configuration: {conf_path}"
    result = subprocess.run(["nginx", "-t", "-c", conf_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Nginx configuration is invalid: {result.stdout} {result.stderr}"

    with open(conf_path, encoding="utf-8") as f:
        text = re.sub(r"#.*", "", f.read())
    assert re.search(r"\blisten\s+8080(?:\s+[^;]*)?;", text), "Nginx is not configured to listen on port 8080"
    location = re.search(r"location\s+/\s*\{([^{}]*)\}", text, re.DOTALL)
    assert location, "Nginx configuration is missing a location / block"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", location.group(1)), (
        "Nginx location / does not proxy to http://127.0.0.1:5000"
    )


def test_required_ports_belong_to_supervised_services():
    assert_supervised_listener("api-service", 5000, "127.0.0.1")
    assert_supervised_listener("nginx", 8080)


def test_nginx_ping():
    try:
        response = requests.get("http://127.0.0.1:8080/ping", timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200 OK for /ping, got {response.status_code}. Response: {response.text}"
        assert response.text.strip() == "pong", f"Expected response body 'pong', got '{response.text}'"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 for /ping: {e}")


def test_nginx_data_post():
    try:
        response = requests.post("http://127.0.0.1:8080/data", timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200 OK for POST /data, got {response.status_code}. Response: {response.text}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 for POST /data: {e}")


def test_proxy_forwards_nonfixed_request():
    path = "/verifier-not-found-" + uuid.uuid4().hex
    direct = requests.get("http://127.0.0.1:5000" + path, timeout=5)
    proxied = requests.get("http://127.0.0.1:8080" + path, timeout=5)
    assert direct.status_code == 404, f"Unexpected API result for generated path {path}: {direct.status_code}"
    assert proxied.status_code == direct.status_code, (
        f"Nginx did not preserve the API status for generated path {path}: API={direct.status_code}, proxy={proxied.status_code}"
    )
    assert proxied.content == direct.content, "Nginx response for a generated path did not match the API response"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
