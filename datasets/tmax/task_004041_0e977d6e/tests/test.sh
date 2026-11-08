#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
import tarfile
import time
import urllib.error
import urllib.request

import pytest


def test_phase1_backup():
    backup_path = "/home/user/history_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup tarball {backup_path} is missing."

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            members = tar.getmembers()
            names = [m.name.strip("/").lstrip("./") for m in members]
            assert len(names) > 0, "Backup tarball is empty."

            anchors = [name for name in names if name == "history" or name.endswith("/history")]
            assert anchors, "Backup tarball does not contain the history directory."

            found_complete_history = False
            for anchor in anchors:
                by_name = {
                    m.name.strip("/").lstrip("./"): m
                    for m in members
                }
                directory = by_name.get(anchor)
                dummy = by_name.get(anchor + "/dummy.db")
                old_logs = by_name.get(anchor + "/old_logs.txt")
                if directory and directory.isdir() and dummy and dummy.isfile() and old_logs and old_logs.isfile():
                    found_complete_history = True
                    break

            assert found_complete_history, (
                "Backup tarball must contain the original /app/data/history directory "
                "and its dummy.db and old_logs.txt files."
            )
    except tarfile.ReadError:
        pytest.fail(f"File {backup_path} is not a valid gzip-compressed tarball.")


def test_phase2_api_binding():
    api_path = "/app/services/api/app.py"
    assert os.path.isfile(api_path), f"File {api_path} is missing."
    with open(api_path, "r") as f:
        content = f.read()
    assert "0.0.0.0" not in content, "The Capacity API is still binding to 0.0.0.0."
    assert "127.0.0.1" in content, "The Capacity API must bind to 127.0.0.1."


def test_phase2_nginx_proxy():
    nginx_path = "/app/services/nginx/nginx.conf"
    assert os.path.isfile(nginx_path), f"File {nginx_path} is missing."
    with open(nginx_path, "r") as f:
        content = f.read()
    assert "proxy_pass" in content, "nginx.conf is missing proxy_pass directive."
    assert "127.0.0.1:5000" in content or "localhost:5000" in content, "nginx.conf is not proxying to the API on port 5000."

    result = subprocess.run(
        ["nginx", "-t", "-c", nginx_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"nginx configuration is invalid: {result.stderr}"


def listening_ipv4_addresses(port):
    addresses = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address, local_port = fields[1].split(":")
                state = fields[3]
                if state == "0A" and int(local_port, 16) == port:
                    addresses.add(local_address.upper())
    except OSError:
        pass
    return addresses


def wait_for_ports(ports, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(listening_ipv4_addresses(port) for port in ports):
            return
        time.sleep(0.2)
    missing = [port for port in ports if not listening_ipv4_addresses(port)]
    pytest.fail(f"Services did not open required ports: {missing}")


def process_cmdlines():
    cmdlines = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                raw = f.read()
            if raw:
                cmdlines.append(raw.replace(b"\0", b" ").decode("utf-8", "replace"))
        except (OSError, PermissionError):
            pass
    return cmdlines


def post_json(url, payload):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.getcode() == 200, f"Expected HTTP 200, got {response.getcode()}"


def test_phase2_end_to_end_flow():
    subprocess.run(["pkill", "-f", "/app/services/api/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    start_script = "/app/services/start_all.sh"
    assert os.path.isfile(start_script), f"Start script {start_script} is missing."
    assert os.access(start_script, os.X_OK), f"Start script {start_script} is not executable."
    result = subprocess.run(
        [start_script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"start_all.sh failed: {result.stderr}"

    wait_for_ports([5000, 6379, 8080])

    api_addresses = listening_ipv4_addresses(5000)
    assert api_addresses == {"0100007F"}, (
        "The Capacity API must listen only on IPv4 127.0.0.1:5000; "
        f"observed addresses were {api_addresses}."
    )

    cmdlines = process_cmdlines()
    assert any("/app/services/api/app.py" in cmd for cmd in cmdlines), "start_all.sh did not start the Capacity API app.py."
    assert any("nginx" in cmd and "/app/services/nginx/nginx.conf" in cmd for cmd in cmdlines), "start_all.sh did not start nginx with the provided configuration."
    assert any("redis-server" in cmd for cmd in cmdlines), "start_all.sh did not start Redis."

    ping = subprocess.run(["redis-cli", "PING"], capture_output=True, text=True, timeout=5)
    assert ping.returncode == 0 and ping.stdout.strip() == "PONG", "Redis is not operational on port 6379."
    subprocess.run(["redis-cli", "DEL", "capacity_queue"], capture_output=True, timeout=5)

    payload = {"host": "web-01", "cpu_percent": 45.5, "mem_bytes": 1024}
    try:
        post_json("http://127.0.0.1:8080/ingest", payload)
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to reach the ingestion endpoint through Nginx: {e}")

    result = subprocess.run(["redis-cli", "LPOP", "capacity_queue"], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Failed to execute redis-cli."
    output = result.stdout.strip()
    assert "web-01" in output, "The payload was not found in the Redis capacity_queue."
    assert json.loads(output) == payload, "The Redis queue did not contain the exact submitted payload."

    nonce_payload = {
        "host": "node-" + secrets.token_hex(10),
        "cpu_percent": random.uniform(0.01, 99.99),
        "mem_bytes": secrets.randbelow(10**9) + 1,
    }
    post_json("http://127.0.0.1:8080/ingest", nonce_payload)
    result = subprocess.run(["redis-cli", "LPOP", "capacity_queue"], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Failed to read the dynamic payload from Redis."
    assert json.loads(result.stdout.strip()) == nonce_payload, "The dynamic request was not proxied intact into capacity_queue."


def run_sanitizer(input_data):
    script_path = "/home/user/sanitizer.py"
    assert os.path.isfile(script_path), f"Sanitizer script {script_path} is missing."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), "Sanitizer must be a regular Python file."
    try:
        return subprocess.run(
            ["python3", script_path],
            input=input_data,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Sanitizer did not terminate after reaching end of input.")


def test_phase3_sanitizer_evil_corpus():
    evil_corpus = "/app/corpora/evil/evil_logs.jsonl"
    assert os.path.isfile(evil_corpus), f"Evil corpus {evil_corpus} is missing."
    with open(evil_corpus, "r") as f:
        evil_data = f.read()

    result = run_sanitizer(evil_data)
    assert result.returncode == 0, f"Sanitizer script crashed on evil corpus: {result.stderr}"
    output_lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(output_lines) == 0, f"{len(output_lines)} evil logs bypassed the sanitizer."


def test_phase3_sanitizer_clean_corpus():
    clean_corpus = "/app/corpora/clean/clean_logs.jsonl"
    assert os.path.isfile(clean_corpus), f"Clean corpus {clean_corpus} is missing."
    with open(clean_corpus, "r") as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    result = run_sanitizer("\n".join(clean_lines) + "\n")
    assert result.returncode == 0, f"Sanitizer script crashed on clean corpus: {result.stderr}"
    output_lines = [line for line in result.stdout.splitlines() if line.strip()]
    missing_count = len(clean_lines) - len(output_lines)
    assert len(output_lines) == len(clean_lines), f"{missing_count} of {len(clean_lines)} clean logs modified or dropped."

    for i, out_line in enumerate(output_lines):
        try:
            parsed = json.loads(out_line)
            expected = json.loads(clean_lines[i])
            assert parsed == expected, f"Clean log modified. Expected {expected}, got {parsed}"
        except json.JSONDecodeError:
            pytest.fail("Sanitizer output is not valid JSON.")


def test_phase3_sanitizer_dynamic_adversarial_cases():
    token = secrets.token_hex(12)
    valid_objects = [
        {"host": "abc", "cpu_percent": 0, "mem_bytes": 1},
        {"host": "Z9-" + token, "cpu_percent": 100.0, "mem_bytes": 2**50 + 123},
        {"host": "node-" + secrets.token_hex(8), "cpu_percent": round(random.uniform(0.1, 99.9), 6), "mem_bytes": secrets.randbelow(10**8) + 1},
        {"host": "A" * 64, "cpu_percent": 37, "mem_bytes": 999},
    ]

    invalid_objects = [
        {"host": "ab", "cpu_percent": 50, "mem_bytes": 1},
        {"host": "A" * 65, "cpu_percent": 50, "mem_bytes": 1},
        {"host": "bad_host", "cpu_percent": 50, "mem_bytes": 1},
        {"host": "bad host", "cpu_percent": 50, "mem_bytes": 1},
        {"host": 123, "cpu_percent": 50, "mem_bytes": 1},
        {"host": "valid-host", "cpu_percent": -0.01, "mem_bytes": 1},
        {"host": "valid-host", "cpu_percent": 100.01, "mem_bytes": 1},
        {"host": "valid-host", "cpu_percent": "50", "mem_bytes": 1},
        {"host": "valid-host", "cpu_percent": True, "mem_bytes": 1},
        {"host": "valid-host", "cpu_percent": 50, "mem_bytes": 0},
        {"host": "valid-host", "cpu_percent": 50, "mem_bytes": -1},
        {"host": "valid-host", "cpu_percent": 50, "mem_bytes": 1.5},
        {"host": "valid-host", "cpu_percent": 50, "mem_bytes": True},
        {"host": "valid-host", "cpu_percent": 50},
        {"host": "valid-host", "cpu_percent": 50, "mem_bytes": 1, "extra": token},
    ]

    entries = [(json.dumps(obj), obj) for obj in valid_objects]
    entries += [(json.dumps(obj), None) for obj in invalid_objects]
    entries += [
        ("{malformed-" + token, None),
        (json.dumps(["not", "an", "object", token]), None),
        (json.dumps(token), None),
        ("null", None),
    ]
    random.SystemRandom().shuffle(entries)

    expected = [obj for _, obj in entries if obj is not None]
    input_data = "\n".join(line for line, _ in entries) + "\n"
    result = run_sanitizer(input_data)
    assert result.returncode == 0, f"Sanitizer crashed on dynamic corpus: {result.stderr}"

    output_lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(output_lines) == len(expected), (
        f"Expected exactly {len(expected)} valid dynamic lines, got {len(output_lines)}."
    )
    try:
        actual = [json.loads(line) for line in output_lines]
    except json.JSONDecodeError as e:
        pytest.fail(f"Sanitizer emitted invalid JSON: {e}")
    assert actual == expected, "Sanitizer did not apply all validation rules or changed valid-line order/content."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
