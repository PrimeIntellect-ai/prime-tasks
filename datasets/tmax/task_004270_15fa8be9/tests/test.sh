#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import tempfile
import time
import urllib.request

import pytest


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_health_checker"
    agent_path = "/home/user/new_health_checker.py"

    assert os.path.isfile(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing: {agent_path}"

    random.seed(42)
    N = 1000

    for _ in range(N):
        arg1 = random.randint(0, 1000000)
        arg2 = random.randint(arg1 + 1, 2000000)
        arg3 = random.randint(0, 128000)
        arg4 = random.randint(0, 2000)
        args = [str(arg1), str(arg2), str(arg3), str(arg4)]

        oracle_res = subprocess.run(
            [oracle_path] + args, capture_output=True, text=True
        )
        agent_res = subprocess.run(
            ["python3", agent_path] + args, capture_output=True, text=True
        )

        assert oracle_res.returncode == 0, f"Oracle failed on args {args}"
        assert agent_res.returncode == 0, f"Agent failed on args {args}"
        assert oracle_res.stdout == agent_res.stdout, \
            f"Output mismatch on args {args}.\nOracle: {oracle_res.stdout!r}\nAgent: {agent_res.stdout!r}"


def test_monitor_script_exists():
    monitor_path = "/home/user/monitor.sh"
    assert os.path.isfile(monitor_path), f"Monitor script missing: {monitor_path}"
    assert os.access(monitor_path, os.X_OK) or os.access(monitor_path, os.R_OK), \
        f"Monitor script {monitor_path} must be executable or readable."


def metric_snapshot():
    df = subprocess.run(
        ["df", "-Pm", "/"], capture_output=True, text=True, check=True
    ).stdout.strip().splitlines()[-1].split()
    disk_total = int(df[1])
    disk_used = int(df[2])

    free_lines = subprocess.run(
        ["free", "-m"], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    mem = next(line.split() for line in free_lines if line.startswith("Mem:"))
    ram_used = int(mem[2])

    with open("/proc/loadavg", "r", encoding="utf-8") as f:
        cpu_load = int(float(f.read().split()[0]) * 100)

    return disk_used, disk_total, ram_used, cpu_load


def test_monitor_gathers_metrics_and_invokes_checker():
    monitor_path = "/home/user/monitor.sh"
    checker_path = "/home/user/new_health_checker.py"
    nonce = secrets.token_hex(16)
    record_path = f"/tmp/monitor-args-{secrets.token_hex(12)}.jsonl"
    backup_path = f"/tmp/checker-backup-{secrets.token_hex(12)}"

    shutil.copy2(checker_path, backup_path)
    probe = f'''#!/usr/bin/env python3
import json
import sys
with open({record_path!r}, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
print({nonce!r})
'''

    before = metric_snapshot()
    try:
        with open(checker_path, "w", encoding="utf-8") as f:
            f.write(probe)
        os.chmod(checker_path, 0o755)

        result = subprocess.run(
            ["bash", monitor_path], capture_output=True, text=True, timeout=15
        )
        after = metric_snapshot()

        assert result.returncode == 0, \
            f"monitor.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert result.stdout.strip() == nonce, \
            "monitor.sh did not print the output produced by the checker"
        assert os.path.isfile(record_path), \
            "monitor.sh did not invoke /home/user/new_health_checker.py"

        with open(record_path, "r", encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert calls, "No checker invocation was recorded"
        assert len(calls[-1]) == 4, \
            f"Checker must receive exactly four metrics, got {calls[-1]!r}"
        try:
            disk_used, disk_total, ram_used, cpu_load = map(int, calls[-1])
        except ValueError as e:
            pytest.fail(f"Monitor passed non-integer metrics: {calls[-1]!r}: {e}")

        # Permit small changes while the monitor runs, but require values to
        # correspond to the live host rather than fixed placeholders.
        assert min(before[0], after[0]) - 16 <= disk_used <= max(before[0], after[0]) + 16, \
            f"Disk-used metric is not the live / filesystem value: {disk_used}"
        assert min(before[1], after[1]) - 16 <= disk_total <= max(before[1], after[1]) + 16, \
            f"Disk-total metric is not the live / filesystem value: {disk_total}"
        assert min(before[2], after[2]) - 256 <= ram_used <= max(before[2], after[2]) + 256, \
            f"RAM-used metric is not the live used-memory value: {ram_used}"
        assert min(before[3], after[3]) - 5 <= cpu_load <= max(before[3], after[3]) + 5, \
            f"CPU metric is not the live one-minute load multiplied by 100: {cpu_load}"
    finally:
        shutil.copy2(backup_path, checker_path)
        os.unlink(backup_path)
        if os.path.exists(record_path):
            os.unlink(record_path)


def test_tls_certs_exist():
    cert_path = "/home/user/cert.pem"
    key_path = "/home/user/key.pem"
    assert os.path.isfile(cert_path), f"TLS cert missing: {cert_path}"
    assert os.path.isfile(key_path), f"TLS key missing: {key_path}"

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"],
        capture_output=True, text=True
    )
    assert cert_check.returncode == 0, f"Invalid or expired TLS certificate: {cert_check.stderr}"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
        capture_output=True, text=True, check=True
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-pubout"],
        capture_output=True, text=True
    )
    assert key_pub.returncode == 0, f"Invalid TLS private key: {key_pub.stderr}"
    assert cert_pub.strip() == key_pub.stdout.strip(), \
        "cert.pem and key.pem do not form a matching TLS key pair"

    self_verify = subprocess.run(
        ["openssl", "verify", "-CAfile", cert_path, cert_path],
        capture_output=True, text=True
    )
    assert self_verify.returncode == 0, \
        f"cert.pem is not a usable self-signed certificate: {self_verify.stderr}"


def https_get(path):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(f"https://127.0.0.1:8443{path}")
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        return response.status, response.headers, response.read().decode("utf-8")


def test_web_server_listening_and_response():
    server_path = "/home/user/server.py"
    assert os.path.isfile(server_path), f"Web server script missing: {server_path}"

    port_open = False
    for _ in range(5):
        try:
            with socket.create_connection(("127.0.0.1", 8443), timeout=1):
                port_open = True
                break
        except OSError:
            time.sleep(1)
    assert port_open, "No process is listening on port 8443."

    # Require an IPv4 wildcard bind, as requested, rather than localhost only.
    wildcard_listener = False
    with open("/proc/net/tcp", "r", encoding="utf-8") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            address, port = fields[1].split(":")
            if address == "00000000" and int(port, 16) == 8443 and fields[3] == "0A":
                wildcard_listener = True
                break
    assert wildcard_listener, "The server is not listening on 0.0.0.0:8443"

    try:
        status, headers, body = https_get("/")
        assert status == 200, f"Expected HTTP 200, got {status}"
        body = body.strip()
    except Exception as e:
        pytest.fail(f"Failed to fetch from HTTPS server: {e}")

    pattern = r"^STATUS: (OK|WARN|CRIT) - Score: \d+$"
    assert re.match(pattern, body), f"Response format invalid. Got: {body!r}"

    # Confirm the live endpoint presents the certificate stored at the required path.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="127.0.0.1") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    with open("/home/user/cert.pem", "r", encoding="utf-8") as f:
        file_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert served_der == file_der, "HTTPS server is not using /home/user/cert.pem"


def test_web_server_executes_monitor_for_each_get():
    monitor_path = "/home/user/monitor.sh"
    backup_path = f"/tmp/monitor-backup-{secrets.token_hex(12)}"
    record_path = f"/tmp/server-monitor-{secrets.token_hex(12)}"
    score = random.SystemRandom().randint(100000000, 999999999)
    expected = f"STATUS: OK - Score: {score}"
    request_path = f"/probe-{secrets.token_hex(12)}?q={secrets.token_hex(8)}"

    shutil.copy2(monitor_path, backup_path)
    probe = f'''#!/bin/bash
printf '%s\\n' invoked >> {record_path!r}
printf '%s\\n' {expected!r}
'''

    try:
        with open(monitor_path, "w", encoding="utf-8") as f:
            f.write(probe)
        os.chmod(monitor_path, 0o755)

        status, headers, body = https_get(request_path)
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert headers.get_content_type() == "text/plain", \
            f"Expected text/plain response, got {headers.get('Content-Type')!r}"
        assert body.strip() == expected, \
            "HTTPS server did not return the current output of monitor.sh"
        assert os.path.isfile(record_path), \
            "GET request did not execute /home/user/monitor.sh"
        with open(record_path, "r", encoding="utf-8") as f:
            invocations = [line for line in f if line.strip()]
        assert len(invocations) >= 1, "No monitor invocation was recorded"
    finally:
        shutil.copy2(backup_path, monitor_path)
        os.unlink(backup_path)
        if os.path.exists(record_path):
            os.unlink(record_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
