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
import hashlib
import json
import os
import random
import shutil
import socket
import stat
import subprocess
import uuid

import requests


def test_log_analysis_script():
    script_path = "/home/user/analyze_logs.sh"
    output_path = "/home/user/offline_nodes.txt"

    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert os.path.isfile(output_path), f"Missing output file: {output_path}"

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_content = "10.0.0.6 2023-10-12T10:00:00Z\n172.16.0.4 2023-10-12T10:10:00Z"
    assert content == expected_content, f"Output file content mismatch. Expected:\n{expected_content}\nGot:\n{content}"


def test_log_analysis_on_generated_input():
    log_path = "/home/user/system_health.log"
    output_path = "/home/user/offline_nodes.txt"
    original = open(log_path, "rb").read()
    nonce = uuid.uuid4().hex[:8]
    rows = [
        (f"2026-09-11T12:00:0{i}Z", f"10.{random.randint(20, 240)}.{i}.{random.randint(1, 254)}", status)
        for i, status in enumerate(["ONLINE", "OFFLINE", "ONLINE", "OFFLINE", "OFFLINE"])
    ]
    generated = "".join(
        f"[{ts}] NODE=node-{nonce}-{i} IP={ip} STATUS={status} RESPONSE_TIME={'TIMEOUT' if status == 'OFFLINE' else str(10+i)+'ms'}\n"
        for i, (ts, ip, status) in enumerate(rows)
    )
    expected = "\n".join(f"{ip} {ts}" for ts, ip, status in rows if status == "OFFLINE")

    try:
        with open(log_path, "w") as f:
            f.write(generated)
        result = subprocess.run(["/home/user/analyze_logs.sh"], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on generated log: {result.stderr}"
        assert os.path.isfile(output_path), f"Missing output file: {output_path}"
        with open(output_path) as f:
            actual = f.read().strip()
        assert actual == expected, f"Generated-log output mismatch. Expected:\n{expected}\nGot:\n{actual}"
    finally:
        with open(log_path, "wb") as f:
            f.write(original)


def listening_socket_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_is_gateway(port):
    inodes = listening_socket_inodes(port)
    if not inodes:
        return False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        owns_socket = False
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owns_socket = True
                break
        if owns_socket:
            try:
                if os.path.samefile(f"/proc/{pid}/exe", "/home/user/gateway"):
                    return True
            except OSError:
                pass
    return False


def test_gateway_artifacts_and_running_binary():
    source = "/home/user/gateway.c"
    binary = "/home/user/gateway"
    assert os.path.isfile(source), f"Missing C source: {source}"
    assert os.path.isfile(binary), f"Missing gateway executable: {binary}"
    assert os.access(binary, os.X_OK), f"Gateway is not executable: {binary}"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Gateway executable is not an ELF binary"
    compile_check = subprocess.run(["gcc", "-fsyntax-only", source], capture_output=True, text=True)
    assert compile_check.returncode == 0, f"gateway.c is not valid compilable C: {compile_check.stderr}"
    assert listener_is_gateway(8080), "Port 8080 is not owned by /home/user/gateway"
    assert listener_is_gateway(8081), "Port 8081 is not owned by /home/user/gateway"


def test_http_gateway():
    ip = "10.1.1.1"
    time = "999999"
    url = f"http://127.0.0.1:8080/sign?ip={ip}&time={time}"
    expected_hash = hashlib.md5(f"{ip}_SECRET-SRE-KEY_{time}".encode()).hexdigest()

    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as e:
        assert False, f"HTTP request to {url} failed: {e}"

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        assert False, f"Response is not valid JSON: {response.text}"

    assert data.get("ip") == ip, f"JSON 'ip' mismatch. Expected {ip}, got {data.get('ip')}"
    assert data.get("time") == time, f"JSON 'time' mismatch. Expected {time}, got {data.get('time')}"
    assert data.get("signature") == expected_hash, f"JSON 'signature' mismatch. Expected {expected_hash}, got {data.get('signature')}"


def test_tcp_gateway():
    ip = "192.168.2.2"
    time = "888888"
    payload = f"CHECK {ip} {time}\n".encode()
    expected_hash = hashlib.md5(f"{ip}_SECRET-SRE-KEY_{time}".encode()).hexdigest()
    expected_response = f"OK {expected_hash}\n".encode()

    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=2) as s:
            s.sendall(payload)
            response = s.recv(1024)
    except Exception as e:
        assert False, f"TCP connection/communication to 127.0.0.1:8081 failed: {e}"

    assert response == expected_response, f"TCP response mismatch. Expected {expected_response}, got {response}"


def signer_output(path, ip, timestamp):
    result = subprocess.run([path, ip, timestamp], capture_output=True, text=True, timeout=2)
    assert result.returncode == 0, f"Signer failed for {ip} {timestamp}: {result.stderr}"
    return result.stdout.rstrip("\r\n")


def receive_all(sock):
    chunks = []
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


def test_generated_requests_invoke_and_relay_signer_output():
    signer = "/app/health_signer"
    real_signer = "/app/health_signer.verifier-real"
    marker = f"/tmp/signer-calls-{uuid.uuid4().hex}"
    salt = uuid.uuid4().hex

    os.replace(signer, real_signer)
    with open(marker, "w"):
        pass
    os.chmod(marker, 0o666)
    wrapper = f'''#!/bin/sh
printf '%s\\t%s\\n' "$1" "$2" >> '{marker}'
base=$("{real_signer}" "$1" "$2") || exit $?
printf '%s|%s' "$base" '{salt}' | sha256sum | awk '{{print $1}}'
'''
    with open(signer, "w") as f:
        f.write(wrapper)
    os.chmod(signer, 0o755)

    requests_made = []
    try:
        for i in range(3):
            ip = f"10.{random.randint(20, 240)}.{random.randint(1, 254)}.{random.randint(1, 254)}"
            timestamp = f"2026-09-11T12:{random.randint(10, 59):02d}:{random.randint(10, 59):02d}Z-{uuid.uuid4().hex[:6]}"
            base = signer_output(real_signer, ip, timestamp)
            expected = hashlib.sha256(f"{base}|{salt}".encode()).hexdigest()
            response = requests.get("http://127.0.0.1:8080/sign", params={"ip": ip, "time": timestamp}, timeout=2)
            assert response.status_code == 200
            data = response.json()
            assert data == {"ip": ip, "time": timestamp, "signature": expected}
            requests_made.append(f"{ip}\t{timestamp}")

        for i in range(3):
            ip = f"192.168.{random.randint(3, 240)}.{random.randint(1, 254)}"
            timestamp = str(random.randint(100000000, 999999999))
            base = signer_output(real_signer, ip, timestamp)
            expected = hashlib.sha256(f"{base}|{salt}".encode()).hexdigest()
            with socket.create_connection(("127.0.0.1", 8081), timeout=2) as s:
                s.settimeout(2)
                s.sendall(f"CHECK {ip} {timestamp}\n".encode())
                response = receive_all(s)
            assert response == f"OK {expected}\n".encode()
            requests_made.append(f"{ip}\t{timestamp}")

        with open(marker) as f:
            calls = [line.rstrip("\n") for line in f]
        assert calls == requests_made, f"Gateway did not invoke /app/health_signer once with each request; calls were {calls}"
    finally:
        try:
            os.remove(signer)
        except FileNotFoundError:
            pass
        os.replace(real_signer, signer)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
