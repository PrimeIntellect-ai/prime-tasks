#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import struct
import subprocess
import time
import urllib.error
import urllib.request

import pytest
import redis


def generate_fuzz_input(valid_header=True):
    if valid_header:
        data = b"DOCW\x01"
    else:
        data = bytes(random.choices(range(256), k=5))
        if data == b"DOCW\x01":
            data = b"DOCW\x02"

    if valid_header:
        num_records = random.randint(1, 50)
        for _ in range(num_records):
            rtype = random.choice([0x01, 0x02, 0x03])
            length = random.randint(0, 1024)
            payload = bytes(random.choices(range(256), k=length))
            data += struct.pack("<BH", rtype, length) + payload
        data += b"\xFF"
    return data


def run_extractor(binary_path, input_data):
    try:
        proc = subprocess.run(
            [binary_path],
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return -1, b"", b"TIMEOUT"


def test_extractor_fuzz_equivalence():
    oracle_path = "/app/bin/oracle_extractor"
    agent_path = "/home/user/extractor"
    source_path = "/home/user/extractor.c"

    assert os.path.isfile(source_path), f"C source missing at {source_path}"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"
    with open(agent_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled extractor is not an ELF binary"
    with open(agent_path, "rb") as f, open(oracle_path, "rb") as g:
        assert f.read() != g.read(), "Agent extractor must not be a byte-identical copy of the oracle"

    random.seed(42)
    for i in range(1000):
        valid_header = i % 2 == 0
        input_data = generate_fuzz_input(valid_header)

        oracle_code, oracle_stdout, oracle_stderr = run_extractor(oracle_path, input_data)
        agent_code, agent_stdout, agent_stderr = run_extractor(agent_path, input_data)

        assert agent_code == oracle_code, f"Exit code mismatch on input {i}. Expected {oracle_code}, got {agent_code}"
        assert agent_stdout == oracle_stdout, f"Stdout mismatch on input {i}. Expected {oracle_stdout}, got {agent_stdout}"

        if not valid_header:
            assert b"INVALID" in agent_stderr, f"Expected 'INVALID' in stderr for bad header, got {agent_stderr}"


def test_nginx_config_updated():
    nginx_conf_path = "/home/user/doc_system/nginx.conf"
    with open(nginx_conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass" in content, "nginx.conf missing proxy_pass directive"
    assert "127.0.0.1:5000" in content or "localhost:5000" in content, "nginx.conf proxy_pass not pointing to Flask"

    checked = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path, "-p", "/home/user/doc_system/"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert checked.returncode == 0, f"Invalid Nginx configuration: {checked.stderr.decode(errors='replace')}"


def test_flask_app_updated():
    flask_app_path = "/home/user/doc_system/flask_app.py"
    with open(flask_app_path, "r") as f:
        content = f.read()
    assert "/home/user/extractor" in content, "flask_app.py not updated to use /home/user/extractor"
    assert "/app/bin/oracle_extractor" not in content, "flask_app.py still contains reference to old oracle"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                    inodes.add(fields[9])

    owners = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = int(proc_dir.rsplit("/", 1)[1])
        for fd in glob.glob(proc_dir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(pid)
                break
    return owners


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\x00", b" ").decode(errors="replace")
    except OSError:
        return ""


def all_processes():
    result = []
    for path in glob.glob("/proc/[0-9]*"):
        pid = int(path.rsplit("/", 1)[1])
        result.append((pid, proc_exe(pid), proc_cmdline(pid)))
    return result


def post_doc(data, retries=5):
    last_error = None
    for attempt in range(retries):
        req = urllib.request.Request(
            "http://127.0.0.1:8080/api/upload",
            data=data,
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.status, response.read()
        except urllib.error.URLError as exc:
            last_error = exc
            if attempt + 1 < retries:
                time.sleep(1)
    pytest.fail(f"E2E request failed: {last_error}")


def test_required_services_are_real_and_running():
    processes = all_processes()

    nginx_owners = listening_pids(8080)
    assert nginx_owners, "Nothing is listening on Nginx port 8080"
    assert any(proc_exe(pid) == "/usr/sbin/nginx" for pid in nginx_owners), "Port 8080 is not owned by Nginx"
    assert any(
        exe == "/usr/sbin/nginx"
        and "/home/user/doc_system/nginx.conf" in cmd
        and "/home/user/doc_system/" in cmd
        for _, exe, cmd in processes
    ), "Nginx was not started with the required configuration and prefix"

    flask_owners = listening_pids(5000)
    assert flask_owners, "Nothing is listening on Flask port 5000"
    assert any(
        "/home/user/doc_system/flask_app.py" in proc_cmdline(pid)
        and os.path.basename(proc_exe(pid)).startswith("python")
        for pid in flask_owners
    ), "Port 5000 is not owned by the required Flask application"

    redis_owners = listening_pids(6379)
    assert redis_owners, "Nothing is listening on Redis port 6379"
    assert any(os.path.basename(proc_exe(pid)).startswith("redis-server") for pid in redis_owners), "Port 6379 is not owned by Redis"

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    assert client.ping() is True, "Redis did not answer PING"


def test_pipeline_invokes_extractor_and_stores_in_redis():
    extractor = "/home/user/extractor"
    backup = f"{extractor}.verifier-backup-{os.getpid()}"
    capture = f"/tmp/extractor-capture-{os.getpid()}-{secrets.token_hex(8)}"
    marker = ("EXTRACTOR-PROBE-" + secrets.token_hex(24)).encode()
    input_data = b"DOCW\x01" + struct.pack("<BH", 1, 20) + os.urandom(20) + b"\xff"
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)

    os.replace(extractor, backup)
    try:
        script = (
            "#!/usr/bin/python3\n"
            "import sys\n"
            "data = sys.stdin.buffer.read()\n"
            f"open({capture!r}, 'wb').write(data)\n"
            f"sys.stdout.buffer.write({marker!r})\n"
        )
        with open(extractor, "w") as f:
            f.write(script)
        os.chmod(extractor, 0o755)
        client.delete("last_doc")

        status, body = post_doc(input_data)
        assert status == 200, f"Expected HTTP 200 from extractor probe, got {status}"
        assert body == marker, "The proxied Flask request did not execute /home/user/extractor"
        with open(capture, "rb") as f:
            assert f.read() == input_data, "Flask did not pass the request body to the extractor unchanged"
        assert client.get("last_doc") == marker, "Redis last_doc was not set to the extractor output"
    finally:
        try:
            os.unlink(extractor)
        except FileNotFoundError:
            pass
        os.replace(backup, extractor)
        try:
            os.unlink(capture)
        except FileNotFoundError:
            pass


def test_services_running_and_e2e():
    text_payload = b"Hello, DocWAL E2E Test!"
    docwal_data = b"DOCW\x01" + struct.pack("<BH", 0x01, len(text_payload)) + text_payload + b"\xFF"

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    client.delete("last_doc")
    status, body = post_doc(docwal_data)
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert body == text_payload, f"Expected response {text_payload}, got {body}"
    assert client.get("last_doc") == text_payload, "Redis last_doc does not contain the extracted document"

    for _ in range(3):
        first = os.urandom(37)
        ignored = os.urandom(29)
        second = os.urandom(41)
        randomized_doc = (
            b"DOCW\x01"
            + struct.pack("<BH", 0x01, len(first)) + first
            + struct.pack("<BH", 0x02, len(ignored)) + ignored
            + struct.pack("<BH", 0x01, len(second)) + second
            + b"\xFF"
        )
        expected = first + second
        client.delete("last_doc")
        status, body = post_doc(randomized_doc)
        assert status == 200
        assert body == expected, "Randomized proxied extraction returned the wrong output"
        assert client.get("last_doc") == expected, "Redis last_doc was not updated by the randomized request"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
