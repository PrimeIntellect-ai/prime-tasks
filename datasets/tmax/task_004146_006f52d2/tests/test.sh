#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shlex
import socket
import string
import subprocess
import time
import urllib.request

import pytest
import redis


def test_nginx_conf_fixed():
    path = "/home/user/nginx.conf"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass" in content and "5000" in content, "Nginx config missing proxy_pass to port 5000"


def test_flask_app_fixed():
    path = "/home/user/search_app.py"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "127.0.0.1" in content and "6379" in content, "Flask app not configured to connect to Redis on 127.0.0.1:6379"
    assert "dummy" not in content, "Flask app still contains dummy Redis configuration"


def wait_for_port(port, process, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            out, err = process.communicate()
            pytest.fail(f"Service for port {port} exited early. stdout={out!r} stderr={err!r}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Service did not listen on port {port}")


def stop_process(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def test_services_work_end_to_end():
    subprocess.run(
        ["nginx", "-t", "-c", "/home/user/nginx.conf"],
        capture_output=True,
        check=True,
        timeout=5,
    )

    redis_process = None
    flask_process = None
    nginx_process = None
    monitor_process = None

    client = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    try:
        try:
            client.ping()
        except Exception:
            redis_process = subprocess.Popen(
                ["redis-server", "--bind", "127.0.0.1", "--port", "6379", "--save", "", "--appendonly", "no"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            wait_for_port(6379, redis_process)

        client.flushdb()

        flask_process = subprocess.Popen(
            ["python3", "/home/user/search_app.py"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        wait_for_port(5000, flask_process)

        nginx_process = subprocess.Popen(
            ["nginx", "-c", "/home/user/nginx.conf", "-g", "daemon off; pid /tmp/verifier-nginx.pid;"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        wait_for_port(8080, nginx_process)

        monitor_process = subprocess.Popen(
            ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "MONITOR"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert monitor_process.stdout.readline().strip() == "OK", "Could not monitor Redis traffic"

        with urllib.request.urlopen("http://127.0.0.1:8080/search?q=test", timeout=5) as response:
            assert response.status == 200
            json.loads(response.read().decode("utf-8"))

        time.sleep(0.3)
        stop_process(monitor_process)
        monitor_output = monitor_process.stdout.read() if monitor_process.stdout else ""
        commands = []
        for line in monitor_output.splitlines():
            match = re.search(r"\]\s+(.*)$", line)
            if not match:
                continue
            try:
                parts = shlex.split(match.group(1))
            except ValueError:
                continue
            if parts:
                commands.append(parts)

        reads = [parts for parts in commands if parts[0].upper() in {"GET", "HGET", "HGETALL", "MGET", "LRANGE", "SMEMBERS", "ZRANGE"}]
        assert reads, f"Flask handled /search without reading search metadata from Redis. Commands: {commands}"

        token = "redis-verifier-payload-7f31c9"
        encoded_payload = json.dumps({"results": [token]})
        for parts in reads:
            command = parts[0].upper()
            if command == "GET" and len(parts) >= 2:
                client.set(parts[1], encoded_payload)
            elif command == "HGET" and len(parts) >= 3:
                client.delete(parts[1])
                client.hset(parts[1], parts[2], encoded_payload)
            elif command == "HGETALL" and len(parts) >= 2:
                client.delete(parts[1])
                client.hset(parts[1], token, encoded_payload)
            elif command == "MGET":
                for key in parts[1:]:
                    client.set(key, encoded_payload)
            elif command == "LRANGE" and len(parts) >= 2:
                client.delete(parts[1])
                client.rpush(parts[1], encoded_payload)
            elif command == "SMEMBERS" and len(parts) >= 2:
                client.delete(parts[1])
                client.sadd(parts[1], encoded_payload)
            elif command == "ZRANGE" and len(parts) >= 2:
                client.delete(parts[1])
                client.zadd(parts[1], {encoded_payload: 1})

        with urllib.request.urlopen("http://127.0.0.1:8080/search?q=test", timeout=5) as response:
            body = response.read().decode("utf-8")
            assert response.status == 200
            json.loads(body)
            assert token in body, "The JSON returned through Nginx did not contain the payload stored in Redis"
    finally:
        stop_process(monitor_process)
        stop_process(nginx_process)
        stop_process(flask_process)
        stop_process(redis_process)


def generate_fuzz_input(seed):
    random.seed(seed)
    num_entries = random.randint(10, 100)
    lines = []
    for _ in range(num_entries):
        req_id = random.randint(1, 10000)
        endpoint = "/"
        for _ in range(random.randint(2, 5)):
            char = random.choice(string.ascii_lowercase)
            endpoint += char * random.randint(1, 6)
        status = random.choice([200, 404, 500])
        lines.append(f"[REQ_START] id={req_id}")
        lines.append(json.dumps({"endpoint": endpoint, "status": status}))
        lines.append("[REQ_END]")
    return "\n".join(lines) + "\n"


def test_archiver_fuzz_equivalence():
    agent_script = "/home/user/archiver.py"
    oracle_bin = "/tests/doc_archiver_ref"

    assert os.path.isfile(agent_script), f"Missing agent script at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Missing verifier oracle at {oracle_bin}"
    with open(agent_script, "rb") as agent_file, open(oracle_bin, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent submission is byte-identical to the reference implementation"

    for i in range(50):
        input_data = generate_fuzz_input(seed=i)
        try:
            oracle_proc = subprocess.run(
                ["python3", oracle_bin],
                input=input_data.encode("utf-8"),
                capture_output=True,
                check=True,
                timeout=5,
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Oracle failed on input {i}: {exc.stderr.decode('utf-8', errors='ignore')}")

        try:
            agent_proc = subprocess.run(
                ["python3", agent_script],
                input=input_data.encode("utf-8"),
                capture_output=True,
                check=True,
                timeout=5,
            )
            agent_out = agent_proc.stdout
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Agent script failed on input {i}. Stderr: {exc.stderr.decode('utf-8', errors='ignore')}")

        assert agent_out == oracle_out, (
            f"Output mismatch on fuzz input {i}.\nInput:\n{input_data}\n"
            f"Oracle output (hex): {oracle_out.hex()}\nAgent output (hex): {agent_out.hex()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
