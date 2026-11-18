#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import importlib.util
import json
import os
import random
import re
import socket
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP_DIR = "/home/user/app"


def create_valid_token(payload, secret="secret_key_123"):
    header = base64.urlsafe_b64encode(b'{"alg":"HS256","typ":"JWT"}').decode().rstrip('=')
    payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')
    message = f"{header}.{payload_b64}"
    signature = hmac.new(secret.encode(), message.encode(), hashlib.sha256).digest()
    signature_b64 = base64.urlsafe_b64encode(signature).decode().rstrip('=')
    return f"{message}.{signature_b64}"


def create_none_token(payload):
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').decode().rstrip('=')
    payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')
    return f"{header}.{payload_b64}."


def random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits + "-_.", k=length))


def generate_fuzz_inputs(n=1000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        choice = random.random()
        if choice < 0.1:
            inputs.append(create_valid_token({"user": "admin", "rand": random.randint(1, 10000)}))
        elif choice < 0.2:
            inputs.append(create_none_token({"user": "admin", "rand": random.randint(1, 10000)}))
        elif choice < 0.3:
            inputs.append(create_valid_token({"user": "admin"}).rsplit('.', 1)[0])
        elif choice < 0.5:
            inputs.append(random_string(random.randint(10, 500)))
        else:
            parts = [random_string(random.randint(10, 50)) for _ in range(random.randint(1, 4))]
            inputs.append('.'.join(parts))
    return inputs


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"port {port} did not become available")


def wait_for_file_text(path, marker, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
            if marker in text:
                return text
        except FileNotFoundError:
            pass
        time.sleep(0.2)
    raise AssertionError(f"timed out waiting for {marker!r} in {path}")


def request(path, token, payload):
    data = json.dumps({"payload": payload, "message": payload, "log": payload}).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8080" + path,
        data=data,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def test_authentication():
    oracle = "/opt/oracle/token_verifier"
    agent = os.path.join(APP_DIR, "auth.py")
    assert os.path.isfile(oracle), "Oracle binary not found"
    assert os.path.isfile(agent), "auth.py not found"
    with open(oracle, "rb") as f:
        oracle_bytes = f.read()
    with open(agent, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "auth.py must be an implementation, not a byte-identical oracle copy"

    for token in generate_fuzz_inputs():
        expected = subprocess.run([oracle, token], capture_output=True, text=True, timeout=3)
        actual = subprocess.run([sys.executable, agent, token], capture_output=True, text=True, timeout=3)
        assert actual.returncode == expected.returncode
        assert actual.stdout.strip() == expected.stdout.strip(), (
            f"Mismatch on token {token!r}: expected {expected.stdout.strip()!r}, "
            f"got {actual.stdout.strip()!r}"
        )

    expected = subprocess.run([oracle], capture_output=True, text=True, timeout=3)
    actual = subprocess.run([sys.executable, agent], capture_output=True, text=True, timeout=3)
    assert actual.stdout.strip() == expected.stdout.strip() == "INVALID_FORMAT"


def test_config_text_and_values():
    nginx_path = os.path.join(APP_DIR, "nginx.conf")
    config_path = os.path.join(APP_DIR, "config.py")
    assert os.path.isfile(nginx_path), "nginx.conf not found"
    assert os.path.isfile(config_path), "config.py not found"

    with open(nginx_path, encoding="utf-8") as f:
        content = re.sub(r"#.*", "", f.read())
    assert re.search(r"listen\s+(?:127\.0\.0\.1:)?8080\s*;", content), "Nginx does not listen on port 8080"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000/?\s*;", content), "Nginx does not proxy to 127.0.0.1:5000"

    spec = importlib.util.spec_from_file_location("submitted_config", config_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.REDIS_HOST in ("127.0.0.1", "localhost"), "REDIS_HOST is not local"
    assert module.REDIS_PORT == 6379, "REDIS_PORT is not 6379"


def main():
    test_authentication()
    test_config_text_and_values()

    worker_path = os.path.join(APP_DIR, "worker.py")
    assert os.path.isfile(worker_path), "worker.py not found"

    processes = []
    redis_started = False
    try:
        redis_proc = subprocess.Popen(
            ["redis-server", "--bind", "127.0.0.1", "--port", "6379", "--save", "", "--appendonly", "no"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        processes.append(redis_proc)
        time.sleep(0.4)

        import redis
        client = redis.Redis(host="127.0.0.1", port=6379, socket_connect_timeout=1)
        deadline = time.time() + 8
        while True:
            try:
                assert client.ping()
                break
            except Exception:
                if time.time() >= deadline:
                    raise AssertionError("Redis did not start on 127.0.0.1:6379")
                time.sleep(0.1)
        redis_started = redis_proc.poll() is None
        client.flushdb()

        log_path = os.path.join(APP_DIR, "secure_logs.txt")
        try:
            os.remove(log_path)
        except FileNotFoundError:
            pass

        worker_proc = subprocess.Popen(
            [sys.executable, worker_path], cwd=APP_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        processes.append(worker_proc)
        time.sleep(0.3)
        assert worker_proc.poll() is None, "worker.py exited instead of running as a daemon"

        direct_marker = "DIRECT_REDACTION_CHECK"
        client.rpush("log_queue", direct_marker + " 123-45-6789 and 987-65-4321")
        text = wait_for_file_text(log_path, direct_marker)
        assert "***-**-6789" in text and "***-**-4321" in text, "worker did not redact all SSNs"
        assert "123-45-6789" not in text and "987-65-4321" not in text, "worker wrote an unredacted SSN"

        client.delete("log_queue")
        open(log_path, "w").close()

        launcher = "/tmp/launch_submitted_flask.py"
        with open(launcher, "w", encoding="utf-8") as f:
            f.write(r'''import glob, importlib.util, os, sys
from flask import Flask
app_dir = "/home/user/app"
sys.path.insert(0, app_dir)
found = None
for path in sorted(glob.glob(os.path.join(app_dir, "*.py"))):
    if os.path.basename(path) in ("auth.py", "worker.py", "config.py"):
        continue
    try:
        source = open(path, encoding="utf-8").read()
    except Exception:
        continue
    if "Flask" not in source and "create_app" not in source:
        continue
    name = "submitted_" + os.path.basename(path).replace(".py", "")
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for value in vars(mod).values():
        if isinstance(value, Flask):
            found = value
            break
    if found is None and callable(getattr(mod, "create_app", None)):
        candidate = mod.create_app()
        if isinstance(candidate, Flask):
            found = candidate
    if found is not None:
        break
if found is None:
    raise RuntimeError("No Flask application was found in /home/user/app")
found.run(host="127.0.0.1", port=5000, debug=False, use_reloader=False)
''')
        flask_proc = subprocess.Popen(
            [sys.executable, launcher], cwd=APP_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        processes.append(flask_proc)
        wait_for_port(5000)
        assert flask_proc.poll() is None, "Flask application exited"

        nginx_root = "/tmp/submitted_nginx"
        os.makedirs(nginx_root + "/logs", exist_ok=True)
        wrapper = nginx_root + "/nginx.conf"
        submitted_nginx = os.path.join(APP_DIR, "nginx.conf")
        direct_check = subprocess.run(
            ["nginx", "-t", "-c", submitted_nginx, "-p", nginx_root],
            capture_output=True, text=True,
        )
        if direct_check.returncode == 0:
            nginx_config = submitted_nginx
        else:
            with open(wrapper, "w", encoding="utf-8") as f:
                f.write("events {}\nhttp { include " + submitted_nginx + "; }\n")
            nginx_config = wrapper
            checked = subprocess.run(
                ["nginx", "-t", "-c", nginx_config, "-p", nginx_root],
                capture_output=True, text=True,
            )
            assert checked.returncode == 0, "Invalid nginx configuration: " + checked.stderr

        nginx_proc = subprocess.Popen(
            ["nginx", "-c", nginx_config, "-p", nginx_root, "-g", "daemon off;"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        processes.append(nginx_proc)
        wait_for_port(8080)
        assert nginx_proc.poll() is None, "Nginx exited"

        with open("/proc/net/tcp", encoding="ascii") as f:
            listeners = [line.split()[1] for line in f.readlines()[1:] if line.split()[3] == "0A"]
        port_hex = format(8080, "04X")
        assert f"0100007F:{port_hex}" in listeners, "Nginx is not bound to 127.0.0.1:8080"
        assert f"00000000:{port_hex}" not in listeners, "Nginx must not expose port 8080 on every interface"

        invalid_marker = "INVALID_TOKEN_MUST_NOT_BE_QUEUED"
        status = request("/submit", create_none_token({"user": "attacker"}), invalid_marker + " 111-22-3333")
        assert status in (401, 403), f"Flask accepted an unsupported alg=none token (HTTP {status})"
        time.sleep(1.5)
        with open(log_path, encoding="utf-8") as f:
            assert invalid_marker not in f.read(), "invalid authenticated payload reached the worker"

        valid_marker = "END_TO_END_VALID_PAYLOAD"
        status = request("/submit", create_valid_token({"user": "responder"}), valid_marker + " 321-54-9876")
        assert 200 <= status < 300, f"valid submission through Nginx failed with HTTP {status}"
        text = wait_for_file_text(log_path, valid_marker)
        assert "***-**-9876" in text, "end-to-end payload was not redacted"
        assert "321-54-9876" not in text, "end-to-end output contains the original SSN"
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                proc.terminate()
        for proc in reversed(processes):
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
        if not redis_started:
            try:
                import redis
                redis.Redis(host="127.0.0.1", port=6379).flushdb()
            except Exception:
                pass


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
