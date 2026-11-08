#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import hashlib
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPORT = "/home/user/scan_report.json"
SOURCE = "/home/user/scanner.cpp"
BINARY = "/home/user/scanner"
CONF = "/app/nginx/nginx.conf"
DICT = "/app/dict.txt"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def get_json(url, token=None, timeout=3):
    headers = {}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        require(response.status == 200, f"Unexpected HTTP status {response.status} from {url}")
        return json.loads(response.read().decode("utf-8"))


def wait_json(url, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return get_json(url)
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Service at {url} did not become reachable: {last_error}")


def redis_ping():
    with socket.create_connection(("127.0.0.1", 6379), timeout=3) as sock:
        sock.sendall(b"*1\r\n$4\r\nPING\r\n")
        response = sock.recv(64)
    require(response.startswith(b"+PONG"), f"Redis did not answer PING: {response!r}")


def load_report():
    require(os.path.isfile(REPORT), f"Scan report not found at {REPORT}")
    try:
        with open(REPORT, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception as exc:
        raise AssertionError(f"Failed to read or parse {REPORT} as JSON: {exc}")
    require(isinstance(data, dict), "Scan report must be a JSON object")
    return data


def check_report(data, expected_token, expected_flag):
    score = 0.0
    if data.get("token") == expected_token:
        score += 0.5
    if data.get("flag") == expected_flag:
        score += 0.5
    require(score >= 0.95, f"Detection score is {score}, below 0.95")

    vulnerability_score = data.get("vulnerability_score", data.get("score"))
    require(
        isinstance(vulnerability_score, (int, float)) and not isinstance(vulnerability_score, bool),
        "Report must contain a numeric vulnerability score",
    )
    require(0.95 <= float(vulnerability_score) <= 1.0,
            f"Vulnerability score {vulnerability_score!r} is outside the required range")


def derive_original_answers():
    auth = get_json("http://127.0.0.1:8080/api/v1/auth")
    leaked_hash = auth.get("hash")
    require(isinstance(leaked_hash, str) and re.fullmatch(r"[0-9a-fA-F]{64}", leaked_hash),
            "Auth endpoint did not return a SHA-256 hash")

    with open(DICT, "r", encoding="utf-8") as handle:
        candidates = [line.rstrip("\r\n") for line in handle]
    matches = [word for word in candidates
               if hashlib.sha256(word.encode()).hexdigest().lower() == leaked_hash.lower()]
    require(len(matches) == 1, "The provided dictionary did not uniquely crack the leaked hash")
    token = matches[0]
    data = get_json("http://127.0.0.1:8080/api/v1/data", token)
    flag = data.get("flag")
    require(isinstance(flag, str) and flag, "Authenticated data endpoint returned no flag")
    return token, flag


def stop_processes():
    subprocess.run(["nginx", "-s", "stop", "-c", CONF], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "^python3 /app/api.py$"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.5)


def main():
    # Preserve the original report/configuration assertions and validate the live stack.
    require(os.path.isfile(CONF), f"Nginx config not found at {CONF}")
    with open(CONF, "r", encoding="utf-8") as handle:
        config = handle.read()
    require("5000" in config, "Nginx configuration does not mention Flask port 5000")
    require(re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000\s*;", config) is not None,
            "Nginx does not proxy to http://127.0.0.1:5000")
    subprocess.run(["nginx", "-t", "-c", CONF], check=True, timeout=10,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    redis_ping()
    require(get_json("http://127.0.0.1:5000/api/v1/status").get("status") == "ok",
            "Flask is not reachable directly on port 5000")
    require(get_json("http://127.0.0.1:8080/api/v1/status").get("status") == "ok",
            "The status endpoint is not reachable through Nginx on port 8080")

    original_token, original_flag = derive_original_answers()
    check_report(load_report(), original_token, original_flag)

    require(os.path.isfile(SOURCE) and os.path.getsize(SOURCE) > 0,
            f"C++ scanner source not found at {SOURCE}")
    require(os.path.isfile(BINARY) and os.access(BINARY, os.X_OK),
            f"Compiled scanner not found or not executable at {BINARY}")
    with open(BINARY, "rb") as handle:
        require(handle.read(4) == b"\x7fELF", "Scanner must be a compiled ELF executable")

    # Replace fixed answers with fresh answers so a prewritten report or hardcoded binary cannot pass.
    token = "tok_" + secrets.token_hex(12)
    flag = "FLAG{" + secrets.token_hex(12) + "}"
    proxy_nonce = secrets.token_hex(16)
    dictionary_backup = open(DICT, "rb").read()

    dynamic_api = r'''from flask import Flask, jsonify, request
import hashlib, os
app = Flask(__name__)
token = os.environ["VERIFY_TOKEN"]
flag = os.environ["VERIFY_FLAG"]
nonce = os.environ["VERIFY_NONCE"]
events = os.environ["VERIFY_EVENTS"]
def record(name):
    with open(events, "a") as f:
        f.write(name + "\n")
@app.get("/api/v1/auth")
def auth():
    if request.headers.get("X-Verification-Proxy") != nonce:
        return jsonify(error="proxy required"), 403
    record("auth")
    return jsonify(hash=hashlib.sha256(token.encode()).hexdigest())
@app.get("/api/v1/data")
def data():
    if request.headers.get("X-Verification-Proxy") != nonce:
        return jsonify(error="proxy required"), 403
    record("data")
    if request.headers.get("Authorization") == "Bearer " + token:
        return jsonify(flag=flag)
    return jsonify(error="Unauthorized"), 401
@app.get("/api/v1/status")
def status():
    record("status")
    return jsonify(status="ok")
app.run(host="127.0.0.1", port=5000)
'''

    verifier_nginx = f'''worker_processes 1;
pid /tmp/verifier-nginx.pid;
events {{ worker_connections 128; }}
http {{
    access_log /tmp/verifier-access.log;
    error_log /tmp/verifier-error.log;
    server {{
        listen 8080;
        location /api/ {{
            proxy_set_header X-Verification-Proxy {proxy_nonce};
            proxy_pass http://127.0.0.1:5000;
        }}
    }}
}}
'''

    api_process = None
    try:
        stop_processes()
        with open(DICT, "w", encoding="utf-8") as handle:
            handle.write("password\nadmin\n" + secrets.token_hex(10) + "\n" + token + "\nqwerty\n")
        with open("/tmp/verifier_api.py", "w", encoding="utf-8") as handle:
            handle.write(dynamic_api)
        with open("/tmp/verifier_nginx.conf", "w", encoding="utf-8") as handle:
            handle.write(verifier_nginx)
        open("/tmp/verifier_events.log", "w").close()

        env = os.environ.copy()
        env.update(VERIFY_TOKEN=token, VERIFY_FLAG=flag, VERIFY_NONCE=proxy_nonce,
                   VERIFY_EVENTS="/tmp/verifier_events.log")
        api_process = subprocess.Popen(
            ["python3", "/tmp/verifier_api.py"], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_json("http://127.0.0.1:5000/api/v1/status")
        subprocess.run(["nginx", "-c", "/tmp/verifier_nginx.conf"], check=True, timeout=10)
        wait_json("http://127.0.0.1:8080/api/v1/status")
        open("/tmp/verifier_events.log", "w").close()

        # Rebuild from the submitted source, then execute the demanded artifact.
        subprocess.run(
            ["g++", "-O3", SOURCE, "-o", BINARY, "-lcurl", "-lcrypto", "-pthread"],
            check=True, timeout=45, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(os.path.isfile(BINARY) and os.access(BINARY, os.X_OK),
                "Compilation did not produce /home/user/scanner")
        if os.path.exists(REPORT):
            os.remove(REPORT)
        completed = subprocess.run([BINARY], cwd="/home/user", timeout=30,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(completed.returncode == 0,
                f"Scanner exited with status {completed.returncode}: {completed.stderr.decode(errors='replace')}")
        check_report(load_report(), token, flag)

        with open("/tmp/verifier_events.log", "r", encoding="utf-8") as handle:
            events = set(handle.read().splitlines())
        require({"auth", "data", "status"}.issubset(events),
                f"Scanner did not request every required API endpoint; observed {sorted(events)}")
        redis_ping()
    finally:
        with open(DICT, "wb") as handle:
            handle.write(dictionary_backup)
        subprocess.run(["nginx", "-s", "stop", "-c", "/tmp/verifier_nginx.conf"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if api_process is not None:
            api_process.terminate()
            try:
                api_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                api_process.kill()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
