#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import stat
import subprocess
import time
import secrets
from decimal import Decimal
from pathlib import Path

import pytest


def test_backend_socket_exists():
    sock_path = "/home/user/run/backend.sock"
    assert os.path.exists(sock_path), f"Backend socket not found at {sock_path}. Gunicorn not started correctly or configuration not fixed."

    mode = os.stat(sock_path).st_mode
    assert stat.S_ISSOCK(mode), f"{sock_path} exists but is not a Unix socket."

    config = Path("/app/api-server/gunicorn.conf.py").read_text()
    assert re.search(r"(?m)^\s*bind\s*=\s*['\"]unix:/home/user/run/backend\.sock['\"]\s*$", config), \
        "Gunicorn configuration does not bind to unix:/home/user/run/backend.sock."

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    try:
        client.connect(sock_path)
        client.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
        response = client.recv(4096)
    finally:
        client.close()

    assert response.startswith(b"HTTP/"), "The backend socket did not return an HTTP response."
    assert b"server: gunicorn" in response.lower(), "The backend listener is not Gunicorn."

    gunicorn_from_app_dir = False
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().replace(b"\x00", b" ").decode(errors="replace")
            cwd = os.readlink(entry / "cwd")
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
        if "gunicorn" in cmdline.lower() and os.path.realpath(cwd) == "/app/api-server":
            gunicorn_from_app_dir = True
            break
    assert gunicorn_from_app_dir, "No running Gunicorn process started from /app/api-server was found."


def test_fast_analyzer_exists_and_executable():
    agent_script = "/home/user/fast_analyzer.sh"
    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."


def test_fast_analyzer_correctness_and_speedup():
    agent_script = "/home/user/fast_analyzer.sh"
    baseline_script = "/app/slow_analyzer.sh"

    # Measure baseline
    t0 = time.time()
    try:
        base_out = subprocess.check_output(baseline_script, shell=True, text=True).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Baseline script {baseline_script} failed to run: {e}")
    base_time = time.time() - t0

    # Measure agent
    t0 = time.time()
    try:
        agent_out = subprocess.check_output(agent_script, shell=True, text=True).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Agent script {agent_script} failed to run: {e}")
    agent_time = time.time() - t0

    # Correctness check
    assert base_out == agent_out, f"Output mismatch. Baseline produced '{base_out}', Agent produced '{agent_out}'."

    # Speedup check
    speedup = base_time / agent_time if agent_time > 0 else float('inf')
    assert speedup >= 10.0, f"Speedup {speedup:.2f}x is below threshold 10.0x. Agent time: {agent_time:.4f}s, Baseline time: {base_time:.4f}s."


def test_fast_analyzer_reads_log_and_handles_unseen_inputs():
    agent_script = "/home/user/fast_analyzer.sh"
    log_path = Path("/home/user/data/large_access.log")
    original = log_path.read_bytes()
    original_stat = log_path.stat()

    try:
        for case in range(3):
            lines = []
            matching_cents = []
            count = 1200 + case * 173

            for i in range(count):
                is_502 = secrets.randbelow(5) == 0
                status = 502 if is_502 else [200, 201, 404, 503][secrets.randbelow(4)]
                cents = 1000 + secrets.randbelow(9001)
                latency = f"{cents // 100}.{cents % 100:02d}"
                if is_502:
                    matching_cents.append(cents)
                lines.append(
                    f'10.{case}.{i % 251}.{secrets.randbelow(254) + 1} - - '
                    f'[10/Oct/2023:13:55:36 -0700] "GET /case/{case}/{i} HTTP/1.1" '
                    f'{status} {latency}\n'
                )

            # Guarantee at least one match and avoid an exact half-cent rounding tie.
            if not matching_cents:
                lines[0] = '10.0.0.1 - - [10/Oct/2023:13:55:36 -0700] "GET /forced HTTP/1.1" 502 17.31\n'
                matching_cents.append(1731)
            while (sum(matching_cents) % len(matching_cents)) * 2 == len(matching_cents):
                matching_cents[-1] += 1
                old = lines[-1].rsplit(' ', 1)[0]
                cents = matching_cents[-1]
                lines[-1] = f"{old} {cents // 100}.{cents % 100:02d}\n"

            expected = format(
                Decimal(sum(matching_cents)) / Decimal(len(matching_cents)) / Decimal(100),
                ".2f",
            )
            log_path.write_text("".join(lines))

            try:
                output = subprocess.check_output(agent_script, shell=True, text=True).strip()
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Agent analyzer failed on generated input: {e}")

            assert re.fullmatch(r"\d+\.\d{2}", output), \
                f"Analyzer output is not one number with two decimal places: {output!r}"
            assert output == expected, \
                f"Generated-input mismatch. Expected '{expected}', Agent produced '{output}'."
    finally:
        log_path.write_bytes(original)
        os.chmod(log_path, stat.S_IMODE(original_stat.st_mode))
        os.chown(log_path, original_stat.st_uid, original_stat.st_gid)
        os.utime(log_path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
