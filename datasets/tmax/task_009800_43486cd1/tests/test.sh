#!/bin/bash
mkdir -p /logs/verifier

cat << 'BEHAVIOR_EOF' > /tmp/test_provision_behavior.py
import hashlib
import json
import os
import signal
import socket
import ssl
import subprocess
import time
import urllib.request

HOME = "/home/user"
PROGRAM = os.path.join(HOME, "provision.go")
BINARY = "/tmp/provision-submission"
HEALTH = "https://127.0.0.1:8443/health"
COMPLETE = "Provisioning complete: server reachable"


def listener_pids(port=8443):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
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
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_listeners():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)
    assert not listener_pids(), "Could not stop the pre-existing service on port 8443"


def stop_process(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)
    stop_listeners()


def health_ok(timeout=0.15):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.Request(HEALTH, method="GET")
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as response:
            return response.status == 200 and response.read().decode("utf-8") == "OK"
    except Exception:
        return False


def configured():
    try:
        with open(os.path.join(HOME, "app-groups.conf")) as f:
            group_done = "deployer" in f.read()
        with open(os.path.join(HOME, "fw-rules.json")) as f:
            firewall_done = {"port": 8443, "action": "allow"} in json.load(f)
        with open(os.path.join(HOME, "provision.log")) as f:
            log_done = COMPLETE in f.read()
        return group_done or firewall_done or log_done
    except (OSError, ValueError):
        return False


def wait_for_run(proc, previous_log_count, check_order):
    saw_health = False
    deadline = time.time() + 25
    while time.time() < deadline:
        assert proc.poll() is None, "provision.go exited instead of remaining active with its server"
        if health_ok():
            saw_health = True
        if check_order and configured() and not saw_health:
            raise AssertionError("Configuration was updated before the HTTPS health endpoint was observed ready")
        try:
            with open(os.path.join(HOME, "provision.log")) as f:
                count = f.read().splitlines().count(COMPLETE)
        except OSError:
            count = 0
        if saw_health and count > previous_log_count:
            return
        time.sleep(0.01)
    raise AssertionError("Timed out waiting for provision.go to serve health and complete provisioning")


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def launch():
    return subprocess.Popen(
        [BINARY], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid
    )


def main():
    assert os.path.isfile(PROGRAM), "Missing required /home/user/provision.go"
    assert not os.path.islink(PROGRAM), "/home/user/provision.go must be a real Go source file"
    with open(PROGRAM, "rb") as f:
        source = f.read()
    assert b"package main" in source, "provision.go is not a Go main program"

    subprocess.run(["go", "build", "-o", BINARY, PROGRAM], check=True, timeout=60)
    stop_listeners()

    os.makedirs(os.path.join(HOME, "certs"), exist_ok=True)
    for name in ("cert.pem", "key.pem"):
        try:
            os.remove(os.path.join(HOME, "certs", name))
        except FileNotFoundError:
            pass

    group_fixture = (
        "sudo:x:27:alice\n"
        "qa-team:x:4172:random-user\n"
        "web-admin:x:7319:bob,carol\n"
        "ops-team:x:8341:dana\n"
    )
    firewall_fixture = [
        {"port": 80, "action": "allow"},
        {"port": 19091, "action": "deny", "tag": "verifier-fixture"}
    ]
    with open(os.path.join(HOME, "app-groups.conf"), "w") as f:
        f.write(group_fixture)
    with open(os.path.join(HOME, "fw-rules.json"), "w") as f:
        json.dump(firewall_fixture, f, indent=2)
        f.write("\n")
    with open(os.path.join(HOME, "provision.log"), "w") as f:
        f.write("verifier-start-marker\n")
    os.chmod(os.path.join(HOME, "app-groups.conf"), 0o666)
    os.chmod(os.path.join(HOME, "fw-rules.json"), 0o666)
    os.chmod(os.path.join(HOME, "provision.log"), 0o666)
    os.chmod(os.path.join(HOME, "certs"), 0o777)

    first = launch()
    try:
        wait_for_run(first, 0, True)

        with open(os.path.join(HOME, "app-groups.conf")) as f:
            lines = f.read().splitlines()
        assert lines[0] == "sudo:x:27:alice"
        assert lines[1] == "qa-team:x:4172:random-user"
        assert lines[3] == "ops-team:x:8341:dana"
        web = [line for line in lines if line.startswith("web-admin:")]
        assert len(web) == 1, "The web-admin group must not be duplicated"
        parts = web[0].split(":")
        assert parts[:3] == ["web-admin", "x", "7319"]
        users = [u.strip() for u in parts[3].split(",") if u.strip()]
        assert sorted(users) == sorted(["bob", "carol", "deployer"])
        assert users.count("deployer") == 1

        with open(os.path.join(HOME, "fw-rules.json")) as f:
            rules = json.load(f)
        expected_rule = {"port": 8443, "action": "allow"}
        assert rules == firewall_fixture + [expected_rule], "Firewall rule was not appended while preserving existing rules"

        cert = os.path.join(HOME, "certs", "cert.pem")
        key = os.path.join(HOME, "certs", "key.pem")
        assert os.path.isfile(cert) and os.path.isfile(key)
        cert_state = (sha256(cert), os.stat(cert).st_mtime_ns)
        key_state = (sha256(key), os.stat(key).st_mtime_ns)
        group_state = open(os.path.join(HOME, "app-groups.conf"), "rb").read()
        firewall_state = open(os.path.join(HOME, "fw-rules.json"), "rb").read()
    finally:
        stop_process(first)

    with open(os.path.join(HOME, "provision.log")) as f:
        previous_count = f.read().splitlines().count(COMPLETE)
    assert previous_count == 1, "The first run must append exactly one completion line"

    second = launch()
    try:
        wait_for_run(second, previous_count, False)
        assert second.poll() is None, "Second invocation did not remain running"
        assert health_ok(timeout=1), "Second invocation is not serving /health"
        assert (sha256(cert), os.stat(cert).st_mtime_ns) == cert_state, "Existing certificate was regenerated"
        assert (sha256(key), os.stat(key).st_mtime_ns) == key_state, "Existing private key was regenerated"
        assert open(os.path.join(HOME, "app-groups.conf"), "rb").read() == group_state, "Group update is not idempotent"
        assert open(os.path.join(HOME, "fw-rules.json"), "rb").read() == firewall_state, "Firewall update is not idempotent"
        with open(os.path.join(HOME, "provision.log")) as f:
            assert f.read().splitlines().count(COMPLETE) == previous_count + 1
    except Exception:
        stop_process(second)
        raise


if __name__ == "__main__":
    main()
BEHAVIOR_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import ssl
import urllib.request
import urllib.error

def test_tls_certs_exist():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing."
    assert os.path.isfile(key_path), f"Private key file {key_path} is missing."

def test_https_server_health_endpoint():
    url = "https://127.0.0.1:8443/health"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            status = response.status
            body = response.read().decode('utf-8').strip()
            assert status == 200, f"Expected HTTP 200, got {status}"
            assert body == "OK", f"Expected response body 'OK', got '{body}'"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to {url}: {e}"

def test_mock_group_file_updated():
    path = "/home/user/app-groups.conf"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = f.read().splitlines()

    web_admin_line = None
    for line in lines:
        if line.startswith("web-admin:"):
            web_admin_line = line
            break

    assert web_admin_line is not None, "Group 'web-admin' not found in app-groups.conf."

    parts = web_admin_line.split(":")
    assert len(parts) >= 4, "Invalid format for web-admin group line."

    users = [u.strip() for u in parts[3].split(",") if u.strip()]
    assert "deployer" in users, f"'deployer' not found in web-admin users list. Found: {users}"

def test_mock_firewall_file_updated():
    path = "/home/user/fw-rules.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} is not valid JSON."

    assert isinstance(data, list), f"Expected JSON array in {path}."

    expected_rule = {"port": 8443, "action": "allow"}
    assert expected_rule in data, f"Expected rule {expected_rule} not found in {path}."

def test_provision_log_updated():
    path = "/home/user/provision.log"
    assert os.path.isfile(path), f"File {path} does not exist."

    expected_line = "Provisioning complete: server reachable"
    with open(path, "r") as f:
        content = f.read()

    assert expected_line in content, f"Expected line '{expected_line}' not found in {path}."
TEST_EOF

if python3 /tmp/test_provision_behavior.py 2>&1 && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
