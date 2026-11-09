#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import time
import urllib.error
import urllib.request


def http_get(url, timeout=2):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8")


def test_success_log_content():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
        assert data.get("status") == "online", "success.log does not contain the correct status."
        assert data.get("version") == "1.0.3", "success.log does not contain the correct version."
    except json.JSONDecodeError:
        assert False, "success.log does not contain valid JSON."


def assert_storage_symlink(link_path):
    assert os.path.islink(link_path), f"{link_path} is not a symbolic link."
    target = os.readlink(link_path)
    target_abs = os.path.abspath(os.path.join(os.path.dirname(link_path), target))
    assert target_abs == "/home/user/storage", f"Symlink {link_path} does not point to /home/user/storage."


def test_symlink_exists():
    assert_storage_symlink("/home/user/deploy/current/mnt")


def test_source_symlink_exists():
    assert_storage_symlink("/home/user/app/mnt")


def test_nginx_config_fixed():
    config_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config missing at {config_path}."

    with open(config_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:9000" in content, "Nginx config was not updated to proxy to port 9000."
    assert "127.0.0.1:9001" not in content, "Nginx config still contains the incorrect port 9001."
    assert "proxy_pass" in content, "Nginx config does not contain a proxy_pass directive."


def test_python_backend_deployed_and_fixed():
    server_path = "/home/user/deploy/current/server.py"
    assert os.path.isfile(server_path), f"Backend not deployed to {server_path}."

    with open(server_path, "r") as f:
        content = f.read()

    assert "PORT = 9000" in content or "9000" in content, "Deployed Python backend does not seem to bind to port 9000."


def find_ipv4_listener_pids(ip_hex, port):
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if address == ip_hex and int(port_hex, 16) == port and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def test_backend_listener_is_deployed_unprivileged_process():
    pids = find_ipv4_listener_pids("0100007F", 9000)
    assert pids, "No process is listening on 127.0.0.1:9000."

    matching = []
    for pid in pids:
        try:
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
            uid = os.stat(f"/proc/{pid}").st_uid
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if cwd == os.path.realpath("/home/user/deploy/current") and "server.py" in cmdline and uid != 0:
            matching.append(pid)

    assert matching, (
        "The listener on 127.0.0.1:9000 is not an unprivileged server.py process "
        "running from /home/user/deploy/current."
    )


def test_live_nginx_request():
    url = "http://127.0.0.1:8080/api/status"
    try:
        status, body = http_get(url)
        assert status == 200, f"Expected HTTP 200, got {status}"
        data = json.loads(body)
        assert data.get("status") == "online", "Live API did not return the correct status."
    except urllib.error.HTTPError as e:
        assert False, f"HTTP request failed with status code {e.code}. Is the backend running and Nginx reloaded?"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Nginx: {e.reason}"
    except Exception as e:
        assert False, f"Unexpected error making request to Nginx: {e}"


def test_nginx_really_proxies_deployed_dynamic_backend():
    data_path = "/home/user/storage/data.json"
    with open(data_path, "rb") as f:
        original = f.read()

    nonce = secrets.token_hex(24)
    expected = {
        "status": "probe-" + nonce,
        "version": "verify-" + nonce,
        "verifier_nonce": nonce,
    }

    try:
        with open(data_path, "w") as f:
            json.dump(expected, f)
            f.flush()
            os.fsync(f.fileno())

        time.sleep(0.05)

        direct_status, direct_body = http_get("http://127.0.0.1:9000/api/status")
        assert direct_status == 200, f"Direct backend returned HTTP {direct_status}."
        assert json.loads(direct_body) == expected, (
            "The process on port 9000 did not serve the verifier-generated application data."
        )

        nginx_status, nginx_body = http_get("http://127.0.0.1:8080/api/status")
        assert nginx_status == 200, f"Nginx returned HTTP {nginx_status}."
        assert json.loads(nginx_body) == expected, (
            "Nginx did not proxy the verifier-generated response from the backend on port 9000."
        )
    finally:
        with open(data_path, "wb") as f:
            f.write(original)
            f.flush()
            os.fsync(f.fileno())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
