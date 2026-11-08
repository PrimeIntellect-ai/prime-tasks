#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request

import pytest


def numeric_output(text):
    stripped = text.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", stripped), \
        f"Expected only one numeric value, got {text!r}"
    return float(stripped)


def run_parser(path):
    result = subprocess.run(
        ["/bin/bash", "/home/user/parse.sh", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"parse.sh failed: {result.stderr}"
    return numeric_output(result.stdout)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].split(":")[1], 16)
                        if local_port == port:
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
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def fetch(url):
    with urllib.request.urlopen(url, timeout=2) as response:
        return response.read().decode()


def test_logrotate_conf():
    conf_file = "/home/user/logrotate.conf"
    assert os.path.exists(conf_file), f"Configuration file {conf_file} does not exist."
    with open(conf_file, "r") as f:
        content = f.read()

    assert "/home/user/logs/api.log" in content, "logrotate.conf does not target /home/user/logs/api.log"
    assert re.search(r"size\s+1k", content) or re.search(r"size\s*=\s*1k", content) or "1k" in content, "logrotate.conf must specify size 1k"
    assert re.search(r"rotate\s+2", content) or re.search(r"rotate\s*=\s*2", content), "logrotate.conf must keep 2 rotated logs"
    assert "compress" in content, "logrotate.conf must use compress"
    assert "delaycompress" in content, "logrotate.conf must use delaycompress"


def test_logrotate_state_and_rotation():
    state_file = "/home/user/logrotate.state"
    assert os.path.exists(state_file), f"State file {state_file} does not exist. Did you run logrotate with a custom state file?"

    rotated_log = "/home/user/logs/api.log.1"
    assert os.path.exists(rotated_log), f"Rotated log {rotated_log} does not exist. Ensure logrotate was executed successfully."


def test_parse_script_and_output():
    script_file = "/home/user/parse.sh"
    assert os.path.exists(script_file), f"Script file {script_file} does not exist."
    assert os.path.isfile(script_file), f"{script_file} must be a regular file."

    output_file = "/home/user/avg_error.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content in ["475", "475.0"], f"Expected average error response time to be 475, but got {content}"

    actual = run_parser("/home/user/logs/api.log.1")
    assert actual == pytest.approx(475.0), f"parse.sh returned {actual} for the rotated log"
    assert numeric_output(content) == pytest.approx(actual), "avg_error.txt does not match parse.sh output"

    for count in (2, 3):
        values = [secrets.randbelow(700) + 101 for _ in range(count)]
        expected = sum(values) / len(values)
        lines = [
            f"ERROR 2026-01-01T00:00:00 [DB] ignored 999ms",
            f"INFO 2026-01-01T00:00:01 [API] ignored 888ms",
            f"ERROR 2026-01-01T00:00:02 [APIISH] ignored 777ms",
        ]
        for i, value in enumerate(values):
            lines.append(f"prefix {1000+i} [API] text ERROR endpoint {value}ms")
        secrets.SystemRandom().shuffle(lines)
        with tempfile.NamedTemporaryFile("w", delete=False, prefix="parser-case-", suffix=".log") as f:
            f.write("\n".join(lines) + "\n")
            case_path = f.name
        try:
            assert run_parser(case_path) == pytest.approx(expected, rel=1e-5, abs=1e-5)
        finally:
            os.unlink(case_path)


def test_proxy_script_and_output():
    script_file = "/home/user/proxy.sh"
    assert os.path.exists(script_file), f"Proxy script {script_file} does not exist."
    assert os.path.isfile(script_file), f"{script_file} must be a regular file."

    with open(script_file, "r") as f:
        content = f.read()

    assert "socat" in content, "Proxy script does not contain a socat command."
    assert "9090" in content, "Proxy script does not reference port 9090."
    assert "8000" in content, "Proxy script does not reference port 8000."

    output_file = "/home/user/health_check.txt"
    assert os.path.exists(output_file), f"Health check output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == "OK", f"Expected health check output to be 'OK', but got '{content}'"

    nonce = secrets.token_hex(24)
    nonce_name = f"verify-{secrets.token_hex(8)}"
    nonce_path = f"/home/user/server/{nonce_name}"
    with open(nonce_path, "w") as f:
        f.write(nonce)

    try:
        assert fetch(f"http://127.0.0.1:8000/{nonce_name}") == nonce, "Metrics server is not running on port 8000."

        stop_listeners(9090)
        subprocess.Popen(
            ["/bin/bash", script_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.time() + 6
        forwarded = None
        while time.time() < deadline:
            try:
                forwarded = fetch(f"http://127.0.0.1:9090/{nonce_name}")
                break
            except Exception:
                time.sleep(0.1)
        assert forwarded == nonce, "Executing proxy.sh did not forward port 9090 to the server on port 8000."

        pids = listener_pids(9090)
        assert pids, "No process is listening on port 9090 after executing proxy.sh."
        commands = []
        for pid in pids:
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    commands.append(f.read().replace(b"\0", b" ").decode(errors="replace"))
            except (FileNotFoundError, ProcessLookupError):
                pass
        assert any("socat" in cmd and "9090" in cmd and "8000" in cmd for cmd in commands), \
            f"The port 9090 listener is not the required socat forwarder: {commands}"
    finally:
        try:
            os.unlink(nonce_path)
        except FileNotFoundError:
            pass


def test_port_9090_listening():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        result = s.connect_ex(('127.0.0.1', 9090))
        assert result == 0, "Port 9090 is not listening. Ensure the proxy script is running in the background."
    finally:
        s.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
