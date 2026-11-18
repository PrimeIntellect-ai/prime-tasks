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
import math
import os
import signal
import socket
import struct
import subprocess
import time
import wave

import pytest
import requests


def decode_dtmf(path):
    rows = [697, 770, 852, 941]
    cols = [1209, 1336, 1477, 1633]
    keypad = {
        (697, 1209): "1", (697, 1336): "2", (697, 1477): "3", (697, 1633): "A",
        (770, 1209): "4", (770, 1336): "5", (770, 1477): "6", (770, 1633): "B",
        (852, 1209): "7", (852, 1336): "8", (852, 1477): "9", (852, 1633): "C",
        (941, 1209): "*", (941, 1336): "0", (941, 1477): "#", (941, 1633): "D",
    }
    with wave.open(path, "rb") as wav:
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2
        rate = wav.getframerate()
        raw = wav.readframes(wav.getnframes())
    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
    window = max(1, rate // 10)
    observed = []
    for start in range(0, len(samples) - window + 1, window):
        chunk = samples[start:start + window]
        rms = math.sqrt(sum(x * x for x in chunk) / len(chunk))
        if rms < 1000:
            observed.append(None)
            continue

        def energy(freq):
            real = 0.0
            imag = 0.0
            for i, value in enumerate(chunk):
                angle = 2.0 * math.pi * freq * i / rate
                real += value * math.cos(angle)
                imag -= value * math.sin(angle)
            return real * real + imag * imag

        row = max(rows, key=energy)
        col = max(cols, key=energy)
        observed.append(keypad[(row, col)])

    digits = []
    previous = None
    for value in observed:
        if value is not None and value != previous:
            digits.append(value)
        previous = value
    return "".join(digits)


def socket_inodes_for_pid(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except (FileNotFoundError, PermissionError):
        return result
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            result.add(target[8:-1])
    return result


def pids_for_inode(inode):
    found = []
    for name in os.listdir("/proc"):
        if name.isdigit() and inode in socket_inodes_for_pid(int(name)):
            found.append(int(name))
    return found


def unix_socket_pids(path):
    inodes = set()
    with open("/proc/net/unix") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                inodes.add(fields[6])
    return sorted({pid for inode in inodes for pid in pids_for_inode(inode)})


def ipv4_listener_pids(host, port):
    packed = socket.inet_aton(host)
    address_hex = packed[::-1].hex().upper()
    wanted = f"{address_hex}:{port:04X}"
    inodes = set()
    with open("/proc/net/tcp") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            if fields[1] == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    return sorted({pid for inode in inodes for pid in pids_for_inode(inode)})


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            return handle.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def assert_compiled_go_process(pid):
    proc_exe = f"/proc/{pid}/exe"
    with open(proc_exe, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Backend process is not a compiled ELF executable."
    result = subprocess.run(["go", "version", "-m", proc_exe], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0 and "go1" in result.stdout, \
        f"Process serving backend.sock is not a compiled Go program: {result.stdout}"


def unix_http_get(path, target="/pin"):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    try:
        client.connect(path)
        client.sendall(f"GET {target} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".encode())
        chunks = []
        while True:
            block = client.recv(65536)
            if not block:
                break
            chunks.append(block)
    finally:
        client.close()
    response = b"".join(chunks)
    head, separator, body = response.partition(b"\r\n\r\n")
    assert separator, "Backend did not return a valid HTTP response."
    assert head.splitlines()[0].startswith(b"HTTP/1.1 200") or head.splitlines()[0].startswith(b"HTTP/1.0 200"), \
        f"Backend returned a non-200 response: {head.splitlines()[0]!r}"
    return body.decode().strip()


def get_with_retries(url):
    last_error = None
    for _ in range(5):
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                return response
            last_error = AssertionError(f"HTTP status was {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(1)
    pytest.fail(f"Failed to get a successful response from {url}: {last_error}")


def expected_pin():
    decoded = decode_dtmf("/app/voicemail.wav")
    assert decoded == "73925", f"DTMF decoder obtained unexpected fixture PIN {decoded!r}."
    return decoded


def test_keepalive_script_exists():
    path = "/home/user/keepalive.sh"
    assert os.path.isfile(path), f"Supervisor script {path} is missing."
    assert os.access(path, os.X_OK) or "bash" in open(path).read(), \
        f"Supervisor script {path} should be executable or a bash script."


def test_crontab_configured():
    try:
        output = subprocess.check_output(["crontab", "-l"], text=True, stderr=subprocess.STDOUT)
        assert "keepalive.sh" in output, "crontab does not contain the keepalive script."
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to read crontab: {exc.output}")


def test_backend_source_and_compiled_server():
    assert os.path.isfile("/home/user/app/backend.go"), "Go backend source is missing."
    pids = unix_socket_pids("/tmp/backend.sock")
    assert pids, "No process is listening on /tmp/backend.sock."
    assert_compiled_go_process(pids[0])
    body = unix_http_get("/tmp/backend.sock")
    assert body == '{"status": "ok", "pin": "%s"}' % expected_pin(), \
        f"Direct Go backend returned the wrong payload: {body!r}"


def test_keepalive_restarts_backend():
    old_pids = unix_socket_pids("/tmp/backend.sock")
    assert old_pids, "Backend was not running before supervisor test."
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in old_pids):
        time.sleep(0.1)
    for pid in old_pids:
        if os.path.exists(f"/proc/{pid}"):
            os.kill(pid, signal.SIGKILL)
    time.sleep(0.3)
    try:
        os.unlink("/tmp/backend.sock")
    except FileNotFoundError:
        pass

    supervisor = subprocess.Popen(["bash", "/home/user/keepalive.sh"], cwd="/home/user",
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
    try:
        supervisor.wait(timeout=5)
    except subprocess.TimeoutExpired:
        supervisor.terminate()

    deadline = time.time() + 10
    new_pids = []
    while time.time() < deadline:
        new_pids = unix_socket_pids("/tmp/backend.sock")
        if new_pids:
            break
        time.sleep(0.25)
    assert new_pids, "keepalive.sh did not restart the backend."
    assert not set(new_pids).intersection(old_pids), "Supervisor did not start a new backend process."
    assert_compiled_go_process(new_pids[0])
    assert expected_pin() in unix_http_get("/tmp/backend.sock")


def test_nginx_config_fixed():
    path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path) as handle:
        content = handle.read()
    assert "wrong_path.sock" not in content, "Nginx config still contains the broken proxy_pass directive."
    assert "backend.sock" in content, "Nginx config does not point to the new backend.sock."
    check = subprocess.run(["nginx", "-t", "-c", path], text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert check.returncode == 0, f"Nginx configuration is invalid: {check.stdout}"


def test_nginx_is_running_and_proxying():
    pids = ipv4_listener_pids("127.0.0.1", 8080)
    assert pids, "Nothing is listening on Nginx's 127.0.0.1:8080 endpoint."
    assert any(os.path.basename(process_exe(pid)) == "nginx" for pid in pids), \
        "Port 8080 is not owned by Nginx."
    assert any("nginx.conf" in process_cmdline(pid) for pid in pids), \
        "Running Nginx was not started with the user-mode nginx.conf."
    response = get_with_retries("http://127.0.0.1:8080/pin")
    assert response.json() == {"status": "ok", "pin": expected_pin()}, \
        f"Nginx did not proxy the backend payload: {response.text}"


def test_ssh_tunnel_active():
    pids = ipv4_listener_pids("0.0.0.0", 8888)
    assert pids, "No service is listening on 0.0.0.0:8888 (SSH tunnel missing)."
    ssh_pids = [pid for pid in pids if os.path.basename(process_exe(pid)) == "ssh"]
    assert ssh_pids, "Port 8888 is not owned by an SSH client tunnel."
    command = " ".join(process_cmdline(pid) for pid in ssh_pids)
    assert "-L" in command and "8888" in command and "8080" in command, \
        f"SSH process does not contain the required local-forward configuration: {command}"
    assert "localhost" in command or "127.0.0.1" in command, \
        "SSH tunnel is not configured through localhost."


def test_api_endpoint():
    url = "http://127.0.0.1:8888/pin"
    response = get_with_retries(url)
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
    assert data.get("pin") == "73925", f"Expected pin '73925', got {data.get('pin')}"
    assert data.get("pin") == expected_pin(), "Tunnel response does not contain the PIN decoded from the audio."

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
