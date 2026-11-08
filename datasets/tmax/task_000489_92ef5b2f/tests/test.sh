#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

APP = "/home/user/app"
PARSER = APP + "/build/url_parser"
GATEWAY = APP + "/build/gateway"
ORACLE = "/home/user/oracle/url_parser_oracle"


def run_parser(value):
    return subprocess.run(
        [PARSER], input=value.encode("utf-8"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2
    )


def expected_parser_output(service, method, bench, retry):
    return (
        '{"service":"%s","method":"%s","bench":%d,"retry":%d}\n'
        % (service, method, bench, retry)
    ).encode("utf-8")


def test_fuzz_parser():
    assert os.path.isfile(PARSER), "Agent parser binary was not built."
    assert os.access(PARSER, os.X_OK), "Agent parser binary is not executable."
    with open(PARSER, "rb") as f:
        assert f.read(4) == bytes([0x7f]) + b"ELF", "url_parser must be a compiled executable."
    if os.path.exists(ORACLE):
        assert not filecmp.cmp(PARSER, ORACLE, shallow=False), "Submission must not copy the shipped oracle."

    rng = random.Random(secrets.randbits(64))
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    cases = [
        ("auth", "login", 50, 3),
        ("checkout", "process", 25, 1),
        ("a", "z", 0, 0),
        ("service-with-dashes", "method-9", 9999, 99),
    ]
    for _ in range(696):
        service = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 20)))
        method = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 20)))
        cases.append((service, method, rng.randint(0, 9999), rng.randint(0, 99)))

    outputs = set()
    for service, method, bench, retry in cases:
        value = f"test-env://{service}/{method}?bench={bench}&retry={retry}"
        proc = run_parser(value)
        assert proc.returncode == 0, f"Parser failed for valid input {value!r}: {proc.stderr!r}"
        expected = expected_parser_output(service, method, bench, retry)
        assert proc.stdout == expected, (
            f"Incorrect parser output for {value!r}\n"
            f"Expected: {expected!r}\nGot: {proc.stdout!r}"
        )
        outputs.add(proc.stdout)
    assert len(outputs) > 100, "Parser output does not vary with the supplied URL."

    malformed = [
        "", "junk", "test-env:/auth/login?bench=1&retry=2",
        "test-env://auth/login&bench=1&retry=2",
        "test-env://auth/login?bench=abc&retry=2",
        "test-env://auth/login?bench=1&retry=abc",
        "test-env:///login?bench=1&retry=2",
        "test-env://auth/?bench=1&retry=2",
    ]
    junk_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-/:?=&"
    malformed.extend(
        "".join(rng.choice(junk_chars) for _ in range(rng.randint(10, 150)))
        for _ in range(292)
    )
    for value in malformed:
        proc = run_parser(value)
        assert proc.returncode >= 0, f"Parser crashed on malformed input {value!r}."
        assert len(proc.stdout) < 4096 and len(proc.stderr) < 4096
        if proc.stdout.strip():
            try:
                json.loads(proc.stdout.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                pytest.fail(f"Parser emitted non-JSON output for malformed input {value!r}: {proc.stdout!r}")


def listening_pids(port):
    inodes = set()
    wanted = format(port, "04X")
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def redis_cli(*args):
    proc = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "--raw", *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=3
    )
    assert proc.returncode == 0, proc.stderr
    return proc.stdout.strip()


def post(payload, timeout=5):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/benchmark",
        data=payload.encode("utf-8"), method="POST"
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return response.status, json.loads(body)


def assert_report(data, service, method, bench):
    assert data.get("status") == "success"
    assert data.get("service") == service
    assert data.get("method") == method
    assert data.get("bench_simulated_ms") == bench
    assert isinstance(data.get("redis_count"), int) and data["redis_count"] > 0


def test_services_running_and_integrated():
    with open(APP + "/config/gateway.json") as f:
        config = json.load(f)
    assert config.get("redis_port") == 6379
    assert config.get("grpc_backend_port") == 50051

    redis_pids = listening_pids(6379)
    backend_pids = listening_pids(50051)
    gateway_pids = listening_pids(8080)
    assert redis_pids, "Redis server is not listening on port 6379."
    assert backend_pids, "Python mock backend is not listening on port 50051."
    assert gateway_pids, "Gateway is not listening on port 8080."
    assert any("redis-server" in cmdline(pid) for pid in redis_pids), "Port 6379 is not owned by Redis."
    assert any("mock_grpc_server.py" in cmdline(pid) and "python" in cmdline(pid).lower() for pid in backend_pids), (
        "Port 50051 is not owned by the requested Python mock backend."
    )
    assert os.path.isfile(GATEWAY) and os.access(GATEWAY, os.X_OK)
    gateway_real = os.path.realpath(GATEWAY)
    gateway_owners = []
    for pid in gateway_pids:
        try:
            if os.path.realpath(os.readlink(f"/proc/{pid}/exe")) == gateway_real:
                gateway_owners.append(pid)
        except OSError:
            pass
    assert gateway_owners, "Port 8080 must be served by /home/user/app/build/gateway."
    symbols = subprocess.run(["nm", GATEWAY], stdout=subprocess.PIPE, text=True, timeout=3).stdout
    assert "parse_url" in symbols, "Gateway was not built with the URL parser."
    assert redis_cli("PING") == "PONG"

    assert redis_cli("FLUSHDB") == "OK"

    status, fixed = post("test-env://checkout/process?bench=25&retry=1")
    assert status == 200
    assert_report(fixed, "checkout", "process", 25)

    token = secrets.token_hex(8)
    service = "svc-" + token
    method = "method-" + secrets.token_hex(5)
    payload = f"test-env://{service}/{method}?bench=2&retry=4"
    status, first = post(payload)
    assert status == 200
    assert_report(first, service, method, 2)
    status, second = post(payload)
    assert status == 200
    assert_report(second, service, method, 2)
    assert second["redis_count"] > first["redis_count"], "Repeated requests must update Redis state."
    assert int(redis_cli("DBSIZE")) > 0, "Gateway requests did not create any Redis state."

    stopped = list(backend_pids)
    for pid in stopped:
        os.kill(pid, signal.SIGSTOP)
    try:
        dependency_payload = (
            f"test-env://dependency-{secrets.token_hex(8)}/probe?bench=1&retry=0"
        )
        succeeded = False
        try:
            dep_status, dep_data = post(dependency_payload, timeout=1.0)
            succeeded = dep_status == 200 and dep_data.get("status") == "success"
        except (urllib.error.URLError, TimeoutError, socket.timeout, json.JSONDecodeError):
            pass
        assert not succeeded, "Gateway returned success while the configured backend was suspended."
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        time.sleep(0.2)

    assert listening_pids(50051), "Backend was not left running after verification."
    assert listening_pids(6379), "Redis was not left running after verification."
    assert listening_pids(8080), "Gateway was not left running after verification."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
