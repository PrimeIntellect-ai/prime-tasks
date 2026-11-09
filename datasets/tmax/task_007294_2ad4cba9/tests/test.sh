#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import signal
import subprocess
import time
import urllib.error
import urllib.request
import pytest

USER = pwd.getpwnam("user")
C_SOURCE = "/home/user/quota_server.c"
C_BINARY = "/home/user/quota_server"
NGINX_CONFIG = "/home/user/nginx.conf"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def process_uid(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("Uid:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine uid for pid {pid}")


def wait_for_listener(port, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.05)
    return set()


def request(url):
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.read().decode("utf-8").strip()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8").strip()


def test_fallback_file():
    fallback_path = "/home/user/fallback.html"
    assert os.path.isfile(fallback_path), f"Fallback file not found: {fallback_path}"
    with open(fallback_path, "r") as f:
        content = f.read().strip()
    assert content == "Routed to cheap storage", f"Incorrect fallback file content: {content}"


def test_monitor_script_exists_and_executable():
    script_path = "/home/user/monitor_storage.sh"
    assert os.path.isfile(script_path), f"Monitor script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Monitor script is not executable: {script_path}"


def test_monitor_script_logic():
    script_path = "/home/user/monitor_storage.sh"
    fstab_path = "/home/user/cost_fstab"
    usage_path = "/home/user/expensive_usage.txt"

    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Monitor script failed to execute: {result.stderr}"

    assert os.path.isfile(usage_path), f"Usage file not created: {usage_path}"
    with open(usage_path, "r") as f:
        usage_str = f.read().strip()
    assert usage_str.isdigit(), f"Usage file does not contain a valid integer: {usage_str}"
    actual_usage = int(usage_str)

    expected_usage = 0
    with open(fstab_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 4 and "tier=expensive" in parts[3]:
                path = parts[0]
                if os.path.isdir(path):
                    du_res = subprocess.run(["du", "-sb", path], capture_output=True, text=True)
                    if du_res.returncode == 0:
                        expected_usage += int(du_res.stdout.split()[0])

    assert actual_usage == expected_usage, f"Monitor script calculated {actual_usage}, expected {expected_usage}"


def test_required_c_and_nginx_architecture():
    assert os.path.isfile(C_SOURCE), f"C source not found: {C_SOURCE}"
    assert os.path.isfile(C_BINARY), f"Compiled quota server not found: {C_BINARY}"
    assert os.access(C_BINARY, os.X_OK), f"Quota server is not executable: {C_BINARY}"
    with open(C_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "quota_server is not an ELF executable"

    c_pids = listener_pids(9000)
    assert c_pids, "No process is listening on port 9000"
    assert any(os.path.samefile(f"/proc/{pid}/exe", C_BINARY) for pid in c_pids), \
        "Port 9000 is not served by /home/user/quota_server"
    assert all(process_uid(pid) == USER.pw_uid for pid in c_pids), \
        "Quota server is not running as the non-root user"

    assert os.path.isfile(NGINX_CONFIG), f"Nginx config not found: {NGINX_CONFIG}"
    config_test = subprocess.run(
        ["nginx", "-T", "-p", "/home/user/nginx_run/", "-c", NGINX_CONFIG],
        capture_output=True,
        text=True,
    )
    assert config_test.returncode == 0, f"Invalid Nginx configuration: {config_test.stderr}"
    rendered = config_test.stdout
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", rendered), "Missing localhost:8080 listener"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9000/?\s*;", rendered), "Missing proxy to port 9000"
    assert re.search(r"\bproxy_intercept_errors\s+on\s*;", rendered), "proxy_intercept_errors is not enabled"
    assert re.search(r"\berror_page\s+503\s+(?:=\s*)?/[^;]+;", rendered), "Missing internal 503 error-page routing"

    for directive in ("pid", "error_log", "access_log", "client_body_temp_path", "proxy_temp_path"):
        match = re.search(rf"\b{directive}\s+([^\s;]+)", rendered)
        assert match, f"Missing required Nginx directive: {directive}"
        path = match.group(1).strip("'\"")
        assert path.startswith("/home/user/nginx_run/"), \
            f"{directive} must point inside /home/user/nginx_run/, got {path}"

    nginx_pids = listener_pids(8080)
    assert nginx_pids, "No process is listening on port 8080"
    nginx_processes = [pid for pid in nginx_pids if os.path.basename(process_exe(pid)) == "nginx"]
    assert nginx_processes, "Port 8080 is not served by Nginx"
    assert all(process_uid(pid) == USER.pw_uid for pid in nginx_pids), \
        "Nginx listener is not running entirely as the non-root user"
    loaded_custom_config = False
    for pid in nginx_processes:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            if NGINX_CONFIG in cmdline:
                loaded_custom_config = True
        except OSError:
            pass
    assert loaded_custom_config, "Running Nginx master was not started with /home/user/nginx.conf"

    # Rebuild the submitted source into the required artifact, then execute that
    # artifact so subsequent behavioral checks exercise the C implementation.
    for pid in c_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids(9000) and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(9000), "Could not stop the submitted quota server for rebuild"

    build = subprocess.run(["gcc", C_SOURCE, "-o", C_BINARY], capture_output=True, text=True)
    assert build.returncode == 0, f"quota_server.c does not compile with gcc: {build.stderr}"
    os.chown(C_BINARY, USER.pw_uid, USER.pw_gid)
    os.chmod(C_BINARY, 0o755)

    def demote():
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    log = open("/home/user/nginx_run/verifier_quota_server.log", "ab", buffering=0)
    subprocess.Popen([C_BINARY], stdout=log, stderr=log, preexec_fn=demote, start_new_session=True)
    rebuilt_pids = wait_for_listener(9000)
    assert rebuilt_pids, "Recompiled quota_server did not listen on port 9000"
    assert any(os.path.samefile(f"/proc/{pid}/exe", C_BINARY) for pid in rebuilt_pids), \
        "Recompiled /home/user/quota_server is not the port 9000 listener"


def test_dynamic_quota_behavior_and_static_fallback():
    usage_path = "/home/user/expensive_usage.txt"
    fallback_path = "/home/user/fallback.html"
    nonce = random.SystemRandom().randrange(1_000_000, 9_999_999)

    for value in (
        random.SystemRandom().randrange(0, 102401),
        random.SystemRandom().randrange(0, 102401),
        random.SystemRandom().randrange(102401, 2_000_000),
        random.SystemRandom().randrange(102401, 2_000_000),
    ):
        with open(usage_path, "w") as f:
            f.write(f"{value}\n")
        expected_status = 503 if value > 102400 else 200
        expected_body = "Quota Exceeded" if value > 102400 else "Traffic Allowed"
        status, body = request(f"http://127.0.0.1:9000/dynamic-{nonce}-{value}")
        assert status == expected_status, f"For usage {value}, C server returned {status}"
        assert body == expected_body, f"For usage {value}, C server returned body {body!r}"

        proxy_status, proxy_body = request(f"http://127.0.0.1:8080/dynamic-{nonce}-{value}")
        assert proxy_status == 200, f"For usage {value}, Nginx returned {proxy_status}"
        expected_proxy_body = "Routed to cheap storage" if value > 102400 else "Traffic Allowed"
        assert proxy_body == expected_proxy_body, \
            f"For usage {value}, Nginx returned body {proxy_body!r}"

    marker = f"fallback-verifier-{nonce}"
    try:
        with open(fallback_path, "w") as f:
            f.write(marker)
        with open(usage_path, "w") as f:
            f.write(f"{102401 + nonce}\n")
        status, body = request(f"http://127.0.0.1:8080/fallback-{nonce}")
        assert status == 200, f"Nginx fallback returned status {status}"
        assert body == marker, "Nginx is not serving the current /home/user/fallback.html file"
    finally:
        with open(fallback_path, "w") as f:
            f.write("Routed to cheap storage")


def test_quota_server_and_nginx_over_quota():
    usage_path = "/home/user/expensive_usage.txt"

    with open(usage_path, "w") as f:
        f.write("150000\n")

    try:
        req = urllib.request.Request("http://127.0.0.1:9000")
        with urllib.request.urlopen(req, timeout=2) as response:
            pytest.fail("Expected 503 error from quota server, but got 200 OK")
    except urllib.error.HTTPError as e:
        assert e.code == 503, f"Expected 503 from quota server, got {e.code}"
        body = e.read().decode("utf-8").strip()
        assert "Quota Exceeded" in body, f"Expected 'Quota Exceeded' in body, got: {body}"
    except Exception as e:
        pytest.fail(f"Could not connect to quota server on port 9000: {e}")

    try:
        req = urllib.request.Request("http://127.0.0.1:8080")
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode("utf-8").strip()
            assert "Routed to cheap storage" in body, f"Expected fallback content, got: {body}"
    except urllib.error.HTTPError as e:
        if e.code == 503:
            pytest.fail("Nginx did not intercept the 503 error to serve fallback.html")
        else:
            pytest.fail(f"Nginx returned unexpected HTTP error: {e.code}")
    except Exception as e:
        pytest.fail(f"Could not connect to Nginx on port 8080: {e}")


def test_quota_server_and_nginx_under_quota():
    usage_path = "/home/user/expensive_usage.txt"

    with open(usage_path, "w") as f:
        f.write("50000\n")

    try:
        req = urllib.request.Request("http://127.0.0.1:9000")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected 200 from quota server, got {response.status}"
            body = response.read().decode("utf-8").strip()
            assert "Traffic Allowed" in body, f"Expected 'Traffic Allowed' in body, got: {body}"
    except Exception as e:
        pytest.fail(f"Quota server request failed: {e}")

    try:
        req = urllib.request.Request("http://127.0.0.1:8080")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected 200 from Nginx, got {response.status}"
            body = response.read().decode("utf-8").strip()
            assert "Traffic Allowed" in body, f"Expected 'Traffic Allowed' via Nginx, got: {body}"
    except Exception as e:
        pytest.fail(f"Nginx request failed: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
