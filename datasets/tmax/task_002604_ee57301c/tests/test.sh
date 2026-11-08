#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import time
import urllib.request
import urllib.error
from decimal import Decimal

import pytest
import redis

SCRIPT = "/home/user/filter.sh"


def valid_row(line):
    fields = line.split(",")
    if len(fields) != 4:
        return False
    transaction_id, user_id, amount, description = fields
    if re.fullmatch(r"[0-9]+", transaction_id) is None:
        return False
    if re.fullmatch(r"[0-9]+", user_id) is None:
        return False
    if re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", amount) is None:
        return False
    if Decimal(amount) <= 0:
        return False
    return re.fullmatch(r"[A-Za-z0-9 ]+", description) is not None


def random_digits(minimum=1, maximum=16):
    return "".join(secrets.choice(string.digits) for _ in range(secrets.randbelow(maximum - minimum + 1) + minimum))


def random_description():
    words = []
    alphabet = string.ascii_letters + string.digits
    for _ in range(2 + secrets.randbelow(4)):
        words.append("".join(secrets.choice(alphabet) for _ in range(2 + secrets.randbelow(10))))
    return " ".join(words)


def generated_rows():
    rows = []
    for _ in range(24):
        transaction_id = random_digits()
        user_id = random_digits()
        if secrets.randbelow(2):
            amount = str(1 + secrets.randbelow(1000000))
        else:
            amount = f"{secrets.randbelow(100000)}.{1 + secrets.randbelow(999999):06d}"
        description = random_description()
        clean = f"{transaction_id},{user_id},{amount},{description}"
        rows.append(clean)
        mutation = secrets.randbelow(8)
        if mutation == 0:
            rows.append(f"x{transaction_id},{user_id},{amount},{description}")
        elif mutation == 1:
            rows.append(f"{transaction_id},{user_id}x,{amount},{description}")
        elif mutation == 2:
            rows.append(f"{transaction_id},{user_id},0,{description}")
        elif mutation == 3:
            rows.append(f"{transaction_id},{user_id},-{amount},{description}")
        elif mutation == 4:
            rows.append(f"{transaction_id},{user_id},1.2.3,{description}")
        elif mutation == 5:
            rows.append(f"{transaction_id},{user_id},{amount},{description}@")
        elif mutation == 6:
            rows.append(f"{transaction_id},{user_id},{amount}")
        else:
            rows.append(f"{transaction_id},{user_id},{amount},{description},extra")

    rows.extend([
        f"{random_digits()},{random_digits()},0.0000,{random_description()}",
        f"{random_digits()},{random_digits()},abc,{random_description()}",
        f"{random_digits()},{random_digits()},.5,{random_description()}",
        f"{random_digits()},{random_digits()},5.,{random_description()}",
        f" {random_digits()},{random_digits()},2,{random_description()}",
        f"{random_digits()}, {random_digits()},2,{random_description()}",
        f"{random_digits()},{random_digits()},2,bad_description",
        f"{random_digits()},{random_digits()},2,bad\tdescription",
    ])
    secrets.SystemRandom().shuffle(rows)
    return rows


def test_nginx_config_updated():
    nginx_conf_path = "/home/user/app/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"File {nginx_conf_path} does not exist."
    with open(nginx_conf_path, "r") as f:
        content = f.read()
    assert "http://127.0.0.1:5000" in content, "Nginx config does not proxy to http://127.0.0.1:5000"


def test_settings_env_updated():
    settings_env_path = "/home/user/app/settings.env"
    assert os.path.isfile(settings_env_path), f"File {settings_env_path} does not exist."
    with open(settings_env_path, "r") as f:
        content = f.read()
    assert re.search(r"^REDIS_PORT=6379$", content, re.MULTILINE), "REDIS_PORT is not set to 6379 in settings.env"
    assert re.search(r"^FILTER_SCRIPT=/home/user/filter\.sh$", content, re.MULTILINE), "FILTER_SCRIPT is not set correctly in settings.env"


def test_filter_script_executable():
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path), f"Filter script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Filter script {script_path} is not executable."


def test_filter_script_against_clean_corpus():
    script_path = "/home/user/filter.sh"
    clean_corpus_path = "/home/user/corpora/clean/transactions.csv"
    assert os.path.isfile(clean_corpus_path), f"Clean corpus {clean_corpus_path} missing."

    with open(clean_corpus_path, "r") as f:
        clean_lines = f.read().splitlines()

    failed_lines = []
    for line in clean_lines:
        if not line.strip():
            continue
        process = subprocess.run(
            [script_path],
            input=(line + "\n").encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        output = process.stdout.decode("utf-8").strip()
        if output != line:
            failed_lines.append(line)

    if failed_lines:
        pytest.fail(f"{len(failed_lines)} of {len(clean_lines)} clean rows modified/rejected. Offending rows: {failed_lines[:5]}")


def test_filter_script_against_evil_corpus():
    script_path = "/home/user/filter.sh"
    evil_corpus_path = "/home/user/corpora/evil/anomalies.csv"
    assert os.path.isfile(evil_corpus_path), f"Evil corpus {evil_corpus_path} missing."

    with open(evil_corpus_path, "r") as f:
        evil_lines = f.read().splitlines()

    failed_lines = []
    for line in evil_lines:
        if not line.strip():
            continue
        process = subprocess.run(
            [script_path],
            input=(line + "\n").encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        output = process.stdout.decode("utf-8").strip()
        if output != "":
            failed_lines.append(line)

    if failed_lines:
        pytest.fail(f"{len(failed_lines)} of {len(evil_lines)} evil rows bypassed. Offending rows: {failed_lines[:5]}")


def test_filter_script_generated_stream():
    rows = generated_rows()
    expected = [row for row in rows if valid_row(row)]
    process = subprocess.run(
        [SCRIPT],
        input=("\n".join(rows) + "\n").encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert process.returncode == 0, process.stderr.decode("utf-8", errors="replace")
    actual = process.stdout.decode("utf-8").splitlines()
    assert actual == expected, "Filter did not correctly process a generated multi-row stream"


def process_commands():
    commands = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                commands.append(f.read().replace(b"\0", b" ").decode("utf-8", errors="ignore"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return commands


def test_service_processes_and_nginx_syntax():
    checked = subprocess.run(
        ["nginx", "-t", "-c", "/home/user/app/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert checked.returncode == 0, checked.stderr
    commands = process_commands()
    assert any("nginx: master process" in command and "/home/user/app/nginx.conf" in command for command in commands), "Configured Nginx service is not running"
    assert any("redis-server" in command and "6379" in command for command in commands), "Redis is not running on the configured port"
    assert any("python" in command and "/home/user/app/app.py" in command for command in commands), "Flask ingestion API is not running"


def test_end_to_end_upload_flow():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True, socket_timeout=2)
    last_error = None
    for _ in range(20):
        try:
            assert client.ping() is True
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    else:
        pytest.fail(f"Redis on port 6379 is unavailable: {last_error}")

    client.delete("transactions")
    rows = generated_rows()[:20]
    expected = [row for row in rows if valid_row(row)]
    assert expected and len(expected) < len(rows)
    payload = ("\n".join(rows) + "\n").encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:8080/upload",
        data=payload,
        method="POST",
        headers={"Content-Type": "text/csv"},
    )

    response = None
    for _ in range(20):
        try:
            response = urllib.request.urlopen(request, timeout=3)
            break
        except urllib.error.URLError as exc:
            last_error = exc
            time.sleep(0.25)
    assert response is not None, f"Upload through Nginx failed: {last_error}"
    with response:
        body = response.read().decode("utf-8")
        status = response.status
        server = response.headers.get("Server", "")
    assert status == 200
    assert body == "OK"
    assert "nginx" in server.lower(), "Port 8080 response was not served through Nginx"

    deadline = time.time() + 3
    stored = []
    while time.time() < deadline:
        stored = client.lrange("transactions", 0, -1)
        if stored == expected:
            break
        time.sleep(0.1)
    assert stored == expected, "End-to-end upload did not store exactly the sanitised rows in Redis"


def test_services_running():
    # Check if Nginx is listening on 8080
    try:
        req = urllib.request.Request("http://localhost:8080/")
        urllib.request.urlopen(req, timeout=2)
    except urllib.error.URLError as e:
        if isinstance(e.reason, ConnectionRefusedError):
            pytest.fail("Nginx is not listening on port 8080. Did you run start_services.sh?")
    except Exception:
        pass # Ignore other errors like 404, we just want to know if it's listening
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
