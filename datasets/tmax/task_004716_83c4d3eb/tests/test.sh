#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import socket
import subprocess
import time

import pytest
import redis
import requests

REPO = "/app/telemetry_ingester"
BINARY = "/app/telemetry_ingester/target/release/telemetry_ingester"


def listener_pid(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    return int(pid)
        except (FileNotFoundError, PermissionError):
            continue
    return None


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode(errors="replace")


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def test_bisection_result():
    bisection_file = "/home/user/bisection_result.txt"
    assert os.path.exists(bisection_file), f"{bisection_file} does not exist"

    result = subprocess.run(
        ["git", "log", "--grep=Optimize parsing with zero-copy slice indexing", "--format=%H"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the expected commit in the git repository."

    with open(bisection_file) as f:
        actual_hash = f.read().strip()

    assert len(actual_hash) == 40 and all(c in "0123456789abcdef" for c in actual_hash.lower())
    assert actual_hash == expected_hash, f"Bisection result is incorrect. Expected {expected_hash}, got {actual_hash}"

    parent_parser = subprocess.run(
        ["git", "show", f"{expected_hash}^:src/parser.rs"], cwd=REPO,
        capture_output=True, text=True, check=True
    ).stdout
    bad_parser = subprocess.run(
        ["git", "show", f"{expected_hash}:src/parser.rs"], cwd=REPO,
        capture_output=True, text=True, check=True
    ).stdout
    assert "buffer.len() < 2 + len" in parent_parser
    assert "buffer.len() < 2 + len" not in bad_parser


def test_services_running_and_are_required_programs():
    ports = {6379: "Redis", 8080: "Telemetry Ingester (Rust)", 9090: "Telemetry API (Python)"}
    for port, service in ports.items():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            assert s.connect_ex(("127.0.0.1", port)) == 0, f"{service} is not listening on port {port}"

    redis_pid = listener_pid(6379)
    ingester_pid = listener_pid(8080)
    api_pid = listener_pid(9090)
    assert redis_pid and ingester_pid and api_pid
    assert "redis-server" in proc_cmdline(redis_pid)
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    assert file_hash(f"/proc/{ingester_pid}/exe") == file_hash(BINARY), \
        "Port 8080 is not served by the deployed release ingester binary"
    assert "/app/api/main.py" in proc_cmdline(api_pid), \
        "Port 9090 is not served by the required Python API"

    r = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    assert r.ping() is True


def test_parser_source_and_release_build_match_running_binary():
    parser = os.path.join(REPO, "src/parser.rs")
    harness = r'''
#[path = "/app/telemetry_ingester/src/parser.rs"]
mod parser;
fn main() {
    let cases: Vec<Vec<u8>> = vec![
        vec![], vec![0], vec![0, 1], vec![0, 2, b'x'],
        vec![0, 17, b'a', b'b'], vec![3, 32, b'z']
    ];
    for input in cases {
        let result = std::panic::catch_unwind(|| parser::parse(&input));
        assert!(result.is_ok(), "parser panicked on truncated input");
        match result.unwrap() {
            Err(parser::ParseError::Truncated) if input.len() >= 2 => {},
            Err(parser::ParseError::Invalid) if input.len() < 2 => {},
            other => panic!("wrong result for truncated input: {:?}", other),
        }
    }
    assert_eq!(parser::parse(&[0, 3, b'a', b'b', b'c']).unwrap(), "abc");
}
'''
    with open("/tmp/parser_harness.rs", "w") as f:
        f.write(harness)
    subprocess.run(["rustc", "/tmp/parser_harness.rs", "-o", "/tmp/parser_harness"], check=True)
    subprocess.run(["/tmp/parser_harness"], check=True)

    pid = listener_pid(8080)
    assert pid is not None
    running_hash = file_hash(f"/proc/{pid}/exe")
    os.utime(parser, None)
    build = subprocess.run(
        ["cargo", "build", "--release"], cwd=REPO,
        capture_output=True, text=True, timeout=180
    )
    assert build.returncode == 0, f"Release build failed:\n{build.stdout}\n{build.stderr}"
    assert file_hash(BINARY) == running_hash, \
        "The running ingester was not built from the current fixed source"


def send_packet(packet, expect_error=False):
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as s:
        s.settimeout(2)
        s.sendall(packet)
        s.shutdown(socket.SHUT_WR)
        if expect_error:
            assert s.recv(1) == b"\xff", "Malformed packet was not rejected by the ingester"


def api_events():
    resp = requests.get("http://127.0.0.1:9090/metrics", timeout=2)
    assert resp.status_code == 200, f"API returned status code {resp.status_code}"
    data = resp.json()
    assert isinstance(data, dict) and isinstance(data.get("recent_events"), list)
    return data["recent_events"]


def test_ingester_resilience_and_functionality():
    r = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    r.delete("telemetry_events")

    malformed = []
    for actual in (0, 1, 3, 11, 37):
        declared = actual + secrets.randbelow(200) + 1
        body = secrets.token_bytes(actual)
        malformed.append(declared.to_bytes(2, "big") + body)

    for packet in malformed:
        send_packet(packet, expect_error=True)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            assert s.connect_ex(("127.0.0.1", 8080)) == 0, \
                "Telemetry Ingester crashed after receiving a malformed packet"

    assert r.llen("telemetry_events") == 0, "Malformed payload was inserted into Redis"
    assert api_events() == [], "API returned events after only malformed packets were sent"

    tokens = ["verify_" + secrets.token_hex(12) for _ in range(4)]
    for token in tokens:
        payload = token.encode()
        send_packet(len(payload).to_bytes(2, "big") + payload)

    deadline = time.time() + 5
    events = []
    while time.time() < deadline:
        events = api_events()
        if all(token in events for token in tokens):
            break
        time.sleep(0.1)

    for token in tokens:
        assert token in events, f"Fresh valid payload {token!r} was not returned by the API: {events}"

    assert listener_pid(8080) is not None, "Telemetry Ingester is no longer running"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
