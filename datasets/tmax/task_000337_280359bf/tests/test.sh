#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request


def stop_port_listeners(*ports):
    wanted = set(ports)
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        state = fields[3]
                        if port in wanted and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = os.path.join("/proc", entry, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def post(payload, timeout=3):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:8080/process",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def legacy_pids():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(os.readlink(f"/proc/{entry}/exe")) == "/app/legacy_auth_processor":
                found.append(int(entry))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return found


def test_setup_complete_log():
    log_path = "/home/user/setup_complete.log"
    assert os.path.isfile(log_path), f"Missing log file at {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    assert "READY" in content, f"Log file {log_path} does not contain 'READY'"


def test_mount_and_fstab():
    # Check mount
    with open("/proc/mounts", "r") as f:
        mounts = f.read()
    assert "/home/user/user_data_mnt" in mounts, "/app/user_data.img is not mounted at /home/user/user_data_mnt"

    # Check fstab
    fstab_path = "/home/user/local_fstab"
    assert os.path.isfile(fstab_path), f"Missing local fstab at {fstab_path}"
    with open(fstab_path, "r") as f:
        fstab_content = f.read()
    assert "/app/user_data.img" in fstab_content and "/home/user/user_data_mnt" in fstab_content, "local_fstab does not contain the correct mount entry"


def test_services_and_corpus():
    script_path = "/home/user/start_services.sh"
    assert os.path.isfile(script_path), f"Missing startup script at {script_path}"
    assert os.access(script_path, os.X_OK), f"Startup script {script_path} is not executable"
    assert os.path.isfile("/home/user/proxy.py"), "Missing proxy script at /home/user/proxy.py"

    # Ensure the submitted startup script, rather than a pre-existing listener, supplies both services.
    stop_port_listeners(8080, 9090)

    # Run the startup script
    subprocess.run(["bash", script_path], check=True, timeout=10)

    # Wait for health endpoint
    health_url = "http://127.0.0.1:8080/health"
    max_retries = 10
    health_ok = False
    for _ in range(max_retries):
        try:
            req = urllib.request.Request(health_url)
            with urllib.request.urlopen(req, timeout=1) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode())
                    if data.get("status") == "ok":
                        health_ok = True
                        break
        except Exception:
            pass
        time.sleep(1)

    assert health_ok, "Proxy health endpoint did not return 200 OK with {'status': 'ok'} within 10 seconds"
    assert legacy_pids(), "start_services.sh did not start /app/legacy_auth_processor"

    # Test evil corpus
    evil_dir = "/app/corpus/evil"
    evil_files = os.listdir(evil_dir)
    evil_bypassed = []
    for f in evil_files:
        path = os.path.join(evil_dir, f)
        with open(path, "rb") as file:
            payload = file.read()
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/process", data=payload, headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status != 403:
                    evil_bypassed.append(f)
        except urllib.error.HTTPError as e:
            if e.code != 403:
                evil_bypassed.append(f)
        except Exception:
            evil_bypassed.append(f)

    # Test clean corpus
    clean_dir = "/app/corpus/clean"
    clean_files = os.listdir(clean_dir)
    clean_modified = []
    for f in clean_files:
        path = os.path.join(clean_dir, f)
        with open(path, "rb") as file:
            payload = file.read()
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/process", data=payload, headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status != 200:
                    clean_modified.append(f)
        except Exception:
            clean_modified.append(f)

    assert not evil_bypassed, f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}"
    assert not clean_modified, f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}"


def test_dynamic_forwarding_and_sanitisation():
    mount = "/home/user/user_data_mnt"

    # Unpredictable clean requests must be forwarded: validate both the legacy response
    # and the filesystem side effect produced by the legacy processor.
    for _ in range(3):
        username = "verify_" + secrets.token_hex(12)
        data = "value_" + secrets.token_hex(24)
        output = os.path.join(mount, username + ".dat")
        assert not os.path.exists(output)

        status, body = post({"username": username, "data": data})
        assert status == 200, f"Clean generated payload returned HTTP {status}"
        assert json.loads(body.decode("utf-8")) == {"status": "processed"}, "Proxy did not return the legacy processor response"
        assert os.path.isfile(output), "Forwarded clean request did not create the legacy processor output file"
        with open(output, "rb") as f:
            assert f.read() == data.encode("utf-8"), "Legacy processor output did not contain the forwarded data"

    # Generate fresh malicious payloads so a proxy cannot special-case the shipped corpus.
    attacks = [
        "prefix../suffix",
        "prefix;suffix",
        "prefix&&suffix",
        "prefix|suffix",
        "prefix`id`suffix",
        "prefix$(id)suffix",
        "prefix>suffix",
        "prefix<suffix",
        "prefix\nsuffix",
        "L" * 257,
    ]
    for attack in attacks:
        username = "blocked_" + secrets.token_hex(12)
        output = os.path.join(mount, username + ".dat")
        status, _ = post({"username": username, "data": secrets.token_hex(5) + attack + secrets.token_hex(5)})
        assert status == 403, f"Generated malicious payload was not rejected: {attack[:30]!r}"
        assert not os.path.exists(output), "Rejected payload was forwarded to the legacy processor"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
