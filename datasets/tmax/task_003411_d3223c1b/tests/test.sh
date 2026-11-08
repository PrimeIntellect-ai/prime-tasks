#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest


def uncomment(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def location_body(config, path):
    pattern = re.compile(r"\blocation\s+(?:(?:=|\^~)\s+)?" + re.escape(path) + r"\s*\{")
    match = pattern.search(config)
    assert match, f"Nginx config is missing location {path}."
    start = match.end()
    depth = 1
    i = start
    while i < len(config) and depth:
        if config[i] == "{":
            depth += 1
        elif config[i] == "}":
            depth -= 1
        i += 1
    assert depth == 0, f"Unclosed Nginx location block for {path}."
    return config[start:i - 1]


def request(url, method="GET", timeout=2):
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def wait_for_success(url, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = request(url)
            if status == 200:
                return status, body
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Timed out waiting for {url}: {last_error}")


def listening_socket_inodes(port):
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


def pids_holding(inodes):
    result = set()
    if not inodes:
        return result
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        result.add(int(name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return result


def clear_port(port):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = pids_holding(listening_socket_inodes(port))
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.5)
    assert not listening_socket_inodes(port), f"Could not clear TCP port {port}."


def test_nginx_config_fixed():
    nginx_conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"File {nginx_conf_path} does not exist."
    with open(nginx_conf_path) as f:
        content = f.read()
    assert "9090" in content, "Nginx config does not seem to be updated to port 9090."
    assert "proxy_pass" in content, "Nginx config is missing proxy_pass directive."

    active = uncomment(content)
    for path in ("/api/", "/health"):
        body = location_body(active, path)
        directives = re.findall(r"\bproxy_pass\s+([^;]+)\s*;", body)
        assert directives, f"Nginx location {path} has no active proxy_pass directive."
        assert all(value.strip().rstrip("/") == "http://127.0.0.1:9090" for value in directives), \
            f"Nginx location {path} does not proxy exclusively to 127.0.0.1:9090."

    checked = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert checked.returncode == 0, f"Nginx configuration is invalid:\n{checked.stdout}"


def test_go_app_fixed_and_compiles():
    go_app_path = "/home/user/app/main.go"
    assert os.path.isfile(go_app_path), f"File {go_app_path} does not exist."
    with open(go_app_path) as f:
        content = f.read()
    assert "9090" in content, "Go app does not seem to be updated to port 9090."

    built = subprocess.run(
        ["go", "build", "-o", "/tmp/verified-webhook-backend", go_app_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert built.returncode == 0, f"Go backend did not compile:\n{built.stdout}"
    assert os.path.isfile("/tmp/verified-webhook-backend")
    assert os.access("/tmp/verified-webhook-backend", os.X_OK)


def test_symlink_created():
    symlink_path = "/home/user/public_html/repos"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    resolved_target = os.path.realpath(symlink_path)
    expected_target = "/home/user/repos"
    assert resolved_target == expected_target, f"Symlink points to {resolved_target} instead of {expected_target}"


def test_logrotate_config():
    logrotate_path = "/home/user/logrotate.conf"
    assert os.path.isfile(logrotate_path), f"File {logrotate_path} does not exist."
    with open(logrotate_path) as f:
        content = f.read()

    assert "/home/user/logs/webhook.log" in content, "logrotate.conf does not target /home/user/logs/webhook.log"
    keywords = ["daily", "rotate 5", "compress", "missingok", "notifempty"]
    for kw in keywords:
        assert kw in content, f"logrotate.conf is missing '{kw}'"

    active = uncomment(content)
    stanza_match = re.search(
        r'(?:"/home/user/logs/webhook\.log"|/home/user/logs/webhook\.log)\s*\{(.*?)\}',
        active,
        re.DOTALL,
    )
    assert stanza_match, "No active logrotate stanza targets webhook.log."
    lines = [line.strip() for line in stanza_match.group(1).splitlines() if line.strip()]
    tokens = [line.split() for line in lines]
    assert ["daily"] in tokens, "webhook.log is not configured for daily rotation."
    assert ["rotate", "5"] in tokens, "webhook.log is not configured to keep exactly 5 backups."
    assert ["compress"] in tokens, "webhook.log is not configured for compression."
    assert ["missingok"] in tokens, "webhook.log is not configured with missingok."
    assert ["notifempty"] in tokens, "webhook.log is not configured with notifempty."

    checked = subprocess.run(
        ["logrotate", "-d", logrotate_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert checked.returncode == 0, f"logrotate rejected the configuration:\n{checked.stdout}"


def test_api_reachability_and_logging():
    url = "http://127.0.0.1:8080/api/hook"
    try:
        status, body = request(url, method="POST", timeout=5)
        assert status == 200, f"Expected status 200, got {status}"
        assert "Success" in body, "Expected 'Success' in response body"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to reach API at {url}: {e}. Ensure Nginx and the Go app are running.")

    log_path = "/home/user/logs/webhook.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Was it created by the webhook?"
    with open(log_path) as f:
        content = f.read()
    assert "WEBHOOK_RECEIVED" in content, "Log file does not contain 'WEBHOOK_RECEIVED'. The webhook logic might be failing."


def test_fresh_compiled_backend_is_reached_through_fresh_nginx():
    # Remove any substitute listeners, then execute the submitted artifacts themselves.
    clear_port(8080)
    clear_port(9090)
    try:
        os.unlink("/home/user/nginx_temp/nginx.pid")
    except FileNotFoundError:
        pass

    nginx_log = open("/tmp/verified-nginx.log", "w")
    nginx_proc = subprocess.Popen(
        ["nginx", "-c", "/home/user/nginx.conf"],
        stdout=nginx_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    # With no backend on 9090, the proxy must not manufacture a successful response.
    deadline = time.time() + 6
    saw_gateway_failure = False
    while time.time() < deadline:
        assert nginx_proc.poll() is None, "Nginx exited instead of serving the submitted configuration."
        try:
            request("http://127.0.0.1:8080/health")
            pytest.fail("Nginx returned success while the backend on port 9090 was stopped.")
        except urllib.error.HTTPError as exc:
            assert exc.code in (502, 503, 504), f"Expected a gateway failure without the backend, got {exc.code}."
            saw_gateway_failure = True
            break
        except urllib.error.URLError:
            time.sleep(0.15)
    assert saw_gateway_failure, "Fresh Nginx never became reachable on port 8080."

    backend_log = open("/tmp/verified-backend.log", "w")
    backend_proc = subprocess.Popen(
        ["/tmp/verified-webhook-backend"],
        stdout=backend_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_for_success("http://127.0.0.1:9090/health")
    status, health_body = wait_for_success("http://127.0.0.1:8080/health")
    assert status == 200
    assert "OK" in health_body
    assert backend_proc.poll() is None, "Compiled Go backend exited unexpectedly."

    log_path = "/home/user/logs/webhook.log"
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    before = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    status, body = request("http://127.0.0.1:8080/api/hook", method="POST", timeout=5)
    assert status == 200, f"Expected status 200, got {status}"
    assert "Success" in body, "Expected 'Success' in response body"
    assert os.path.getsize(log_path) > before, "The proxied webhook did not append to webhook.log."
    with open(log_path) as f:
        f.seek(before)
        appended = f.read()
    assert "WEBHOOK_RECEIVED" in appended, "The fresh proxied request did not write WEBHOOK_RECEIVED."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
