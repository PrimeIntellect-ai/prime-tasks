#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import signal
import socket
import subprocess
import time

import pytest

APP = "/home/user/app"
EVAL = APP + "/auth/auth_eval"
ORACLE = "/opt/oracle/evaluator"
PORTS = (8080, 50051, 50052)


def test_gateway_config():
    config_path = APP + "/gateway/config.yaml"
    assert os.path.isfile(config_path), f"{config_path} is missing"
    content = open(config_path, encoding="utf-8").read()

    # Preserve the original assertions.
    assert "50051" in content, "gateway config missing auth target port 50051"
    assert "50052" in content, "gateway config missing backend target port 50052"

    def target(name):
        match = re.search(rf"(?m)^\s*{name}\s*:\s*['\"]?([^'\"#\s]+)", content)
        assert match, f"gateway config is missing {name}"
        return match.group(1)

    auth_target = target("auth_target")
    backend_target = target("backend_target")
    assert re.fullmatch(r"(?:localhost|127\.0\.0\.1|auth):50051", auth_target), auth_target
    assert re.fullmatch(r"(?:localhost|127\.0\.0\.1|backend):50052", backend_target), backend_target


def test_proto_file_updated_and_generated():
    proto_path = APP + "/proto/auth.proto"
    assert os.path.isfile(proto_path), f"{proto_path} is missing"
    content = open(proto_path, encoding="utf-8").read()

    # Preserve the original assertion, then ensure it is real syntax in CheckRequest.
    assert "map<string, string> attributes = 3;" in content, (
        "auth.proto is missing the required attributes field in CheckRequest"
    )
    uncommented = re.sub(r"//.*", "", content)
    request = re.search(r"message\s+CheckRequest\s*\{(.*?)\}", uncommented, re.S)
    assert request, "CheckRequest message is missing"
    assert re.search(r"\bmap\s*<\s*string\s*,\s*string\s*>\s+attributes\s*=\s*3\s*;", request.group(1))

    subprocess.run(
        ["protoc", "--proto_path=" + APP + "/proto", "--descriptor_set_out=/tmp/auth.desc", proto_path],
        check=True, capture_output=True, text=True, timeout=15,
    )
    assert os.path.getsize("/tmp/auth.desc") > 0

    pb_files = glob.glob(APP + "/auth/**/*auth.pb.go", recursive=True)
    grpc_files = glob.glob(APP + "/auth/**/*auth_grpc.pb.go", recursive=True)
    assert pb_files, "regenerated Go protobuf stub auth.pb.go is missing"
    assert grpc_files, "regenerated Go gRPC stub auth_grpc.pb.go is missing"
    for path in pb_files + grpc_files:
        assert "Code generated" in open(path, encoding="utf-8").read(512), f"{path} is not generated code"


def test_go_module_resolved():
    assert os.path.isfile(APP + "/auth/go.mod")
    subprocess.run(["go", "mod", "verify"], cwd=APP + "/auth", check=True,
                   capture_output=True, text=True, timeout=60)
    subprocess.run(["go", "test", "./..."], cwd=APP + "/auth", check=True,
                   capture_output=True, text=True, timeout=120)


def run_eval(expr, attrs):
    proc = subprocess.run(
        [EVAL, expr, json.dumps(attrs, separators=(",", ":"))],
        capture_output=True, timeout=3,
    )
    assert proc.returncode == 0, f"auth_eval failed: {proc.stderr!r}"
    assert proc.stderr == b"", f"auth_eval wrote to stderr: {proc.stderr!r}"
    assert proc.stdout in (b"true", b"true\n", b"false", b"false\n"), (
        f"auth_eval output must be exactly true or false, got {proc.stdout!r}"
    )
    return proc.stdout.strip() == b"true"


def test_evaluator_binary_and_cli_contract():
    assert os.path.isfile(EVAL), f"Agent binary missing at {EVAL}"
    assert os.access(EVAL, os.X_OK), f"Agent binary at {EVAL} is not executable"
    with open(EVAL, "rb") as f:
        assert f.read(4) == b"\x7fELF", "auth_eval must be a compiled standalone binary"
    if os.path.isfile(ORACLE):
        assert open(EVAL, "rb").read() != open(ORACLE, "rb").read(), "submission is the reference artifact"

    for argv in ([EVAL], [EVAL, "x == 'x'"], [EVAL, "x == 'x'", "{}", "extra"]):
        proc = subprocess.run(argv, capture_output=True, timeout=3)
        assert proc.returncode != 0, "auth_eval must reject any argument count other than exactly two"

    fixed = [
        ("role == 'admin'", {"role": "admin"}, True),
        ("role == 'admin'", {"role": "administrator"}, False),
        ("role != 'admin'", {"role": "user"}, True),
        ("role != 'admin'", {"role": "admin"}, False),
        ("role == 'admin' && method == 'POST'", {"role": "admin", "method": "POST"}, True),
        ("role == 'admin' || role == 'user' && method == 'POST'", {"role": "user", "method": "GET"}, False),
        ("role == 'admin' || role == 'user' && method == 'POST'", {"role": "user", "method": "POST"}, True),
        ("(role == 'admin' || role == 'user') && method == 'POST'", {"role": "admin", "method": "GET"}, False),
        ("a == 'one' && (b != 'two' || c == 'three')", {"a": "one", "b": "two", "c": "three"}, True),
    ]
    for expr, attrs, expected in fixed:
        assert run_eval(expr, attrs) is expected, f"wrong result for {expr!r} with {attrs!r}"


def test_derived_fuzz_evaluation():
    # Expected answers are computed from generated atoms, not obtained from the broken oracle.
    rng = random.Random(42)
    for case in range(500):
        attrs = {}
        groups = []
        group_values = []
        ident = 0
        for _ in range(rng.randint(1, 4)):
            atoms = []
            values = []
            for _ in range(rng.randint(1, 4)):
                name = f"attribute_{case}_{ident}"
                ident += 1
                wanted = f"value{rng.randrange(8)}"
                actual = wanted if rng.random() < 0.5 else f"other{rng.randrange(8)}"
                attrs[name] = actual
                op = rng.choice(("==", "!="))
                atoms.append(f"{name} {op} '{wanted}'")
                values.append((actual == wanted) if op == "==" else (actual != wanted))
            groups.append(" && ".join(atoms))
            group_values.append(all(values))

        # Deliberately omit outer parentheses to exercise && precedence over ||.
        expr = " || ".join(groups)
        expected = any(group_values)
        assert run_eval(expr, attrs) is expected, f"case {case}: {expr} / {attrs}"

        # Also exercise explicit grouping without changing the independently known result.
        parenthesized = " || ".join(f"({group})" for group in groups)
        assert run_eval(parenthesized, attrs) is expected, f"parenthesized case {case}"


def listening_pids(port):
    inodes = set()
    needle = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == needle and fields[3] == "0A":
                inodes.add(fields[9])
    result = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                link = os.readlink(fd)
            except OSError:
                continue
            if link.startswith("socket:[") and link[8:-1] in inodes:
                result.add(pid)
                break
    return result


def wait_for_ports(timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        owners = {port: listening_pids(port) for port in PORTS}
        if all(owners.values()):
            return owners
        time.sleep(0.2)
    pytest.fail(f"services did not listen on all required ports: {owners}")


def grpc_http2_probe(port):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + b"\x00\x00\x00\x04\x00\x00\x00\x00\x00")
        data = b""
        while len(data) < 9:
            chunk = sock.recv(64)
            assert chunk, f"port {port} closed without an HTTP/2 response"
            data += chunk
        assert data[3] == 4, f"port {port} is not serving gRPC/HTTP2 (first frame type {data[3]})"


def request_code(role="admin", action="read", timeout=5):
    proc = subprocess.run([
        "curl", "-sS", "--max-time", str(timeout), "-o", "/tmp/e2e-body", "-w", "%{http_code}",
        "-X", "POST", "http://localhost:8080/secure-data",
        "-H", f"X-Role: {role}", "-H", f"X-Action: {action}",
    ], capture_output=True, text=True)
    return proc.stdout.strip()[-3:] if proc.stdout.strip() else "000"


def terminate_existing():
    for port in PORTS:
        for pid in listening_pids(port):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.5)


def test_end_to_end_flow_and_service_dependencies():
    start_script = APP + "/start.sh"
    assert os.path.isfile(start_script), f"{start_script} is missing"
    assert os.access(start_script, os.X_OK), f"{start_script} is not executable"
    terminate_existing()
    proc = subprocess.Popen([start_script], cwd=APP, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    stopped = set()
    try:
        owners = wait_for_ports()
        assert owners[8080].isdisjoint(owners[50051])
        assert owners[8080].isdisjoint(owners[50052])
        assert owners[50051].isdisjoint(owners[50052]), "Auth and Backend must be distinct services"

        grpc_http2_probe(50051)
        grpc_http2_probe(50052)

        # Preserve the original successful end-to-end request assertion.
        assert request_code("admin", "read") == "200", "satisfying attributes did not return HTTP 200"
        assert not request_code("user", "read").startswith("2"), "invalid role was authorized"
        assert not request_code("admin", "write").startswith("2"), "invalid action was authorized"

        # A successful response must actually depend on both downstream services.
        for port, name in ((50051, "Auth"), (50052, "Backend")):
            pids = listening_pids(port)
            assert pids, f"{name} service disappeared"
            for pid in pids:
                os.kill(pid, signal.SIGSTOP)
                stopped.add(pid)
            try:
                assert request_code("admin", "read", timeout=3) != "200", (
                    f"Gateway still returned 200 while {name} service was stopped"
                )
            finally:
                for pid in pids:
                    try:
                        os.kill(pid, signal.SIGCONT)
                    except ProcessLookupError:
                        pass
                    stopped.discard(pid)
            deadline = time.time() + 5
            while time.time() < deadline and request_code("admin", "read", timeout=2) != "200":
                time.sleep(0.2)
            assert request_code("admin", "read", timeout=3) == "200", f"flow did not recover after {name} resumed"
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        terminate_existing()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
