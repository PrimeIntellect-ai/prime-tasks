#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import http.client
import json
import os
import random
import re
import socket
import stat
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest


def _regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except FileNotFoundError:
        return False


def _service_config(config, name, expected_port):
    entry = config.get(name)
    host = None
    port = None

    if isinstance(entry, dict):
        host = entry.get("host", entry.get("hostname", entry.get("address")))
        port = entry.get("port")
    elif isinstance(entry, str):
        host = entry

    host = config.get(f"{name}_host", host)
    port = config.get(f"{name}_port", port)

    assert port == expected_port, f"{name} port is not {expected_port}"
    assert host in ("127.0.0.1", "localhost"), f"{name} host must point to localhost"


def _wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    pytest.fail(f"Service did not start on port {port}")


def test_infrastructure_scripts_and_config():
    start_script = "/home/user/start_infrastructure.sh"
    config_file = "/home/user/bridge_config.json"

    assert _regular_file(start_script), f"Missing regular startup script: {start_script}"
    assert os.access(start_script, os.X_OK), f"Startup script is not executable: {start_script}"

    assert _regular_file(config_file), f"Missing config file: {config_file}"
    with open(config_file, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("bridge_config.json is not valid JSON")

    assert isinstance(config, dict), "bridge_config.json must contain a JSON object"
    _service_config(config, "sensor", 9001)
    _service_config(config, "cache", 6379)
    _service_config(config, "c2", 9002)

    # Ensure the requested script itself launches the services rather than relying
    # on processes that happened to be running before verification.
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "^python3 .*[/]app/services/sensor.py"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "^python3 .*[/]app/services/c2_server.py"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "redis-server"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    try:
        proc = subprocess.run([start_script], cwd="/home/user", timeout=15,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        pytest.fail("Startup script did not return after launching background services")
    assert proc.returncode == 0, f"Startup script failed: {proc.stderr.decode(errors='replace')}"

    for port in (6379, 9001, 9002):
        _wait_for_port(port)


def test_services_running():
    # Sensor protocol
    with socket.create_connection(("127.0.0.1", 9001), timeout=2) as sock:
        assert sock.recv(1024) == b"SENSITIVE_DATA\n"

    # Redis protocol
    with socket.create_connection(("127.0.0.1", 6379), timeout=2) as sock:
        sock.sendall(b"*1\r\n$4\r\nPING\r\n")
        assert sock.recv(1024).startswith(b"+PONG")

    # C2 HTTP protocol
    conn = http.client.HTTPConnection("127.0.0.1", 9002, timeout=2)
    conn.request("GET", "/")
    response = conn.getresponse()
    body = response.read()
    conn.close()
    assert response.status == 200
    assert body == b"OK"


def test_git_bisection_and_regression_script():
    bad_commit_file = "/home/user/bad_commit.txt"
    repo_dir = "/home/user/bot_repo"

    assert _regular_file(bad_commit_file), f"Missing bad commit file: {bad_commit_file}"
    with open(bad_commit_file, "r") as f:
        student_commit = f.read().strip()

    assert re.fullmatch(r"[0-9a-fA-F]{40}", student_commit), \
        "Commit hash should be exactly 40 hexadecimal characters"

    commits_output = subprocess.check_output(
        ["git", "log", "--reverse", "--format=%H"], cwd=repo_dir
    ).decode().strip().split("\n")

    actual_bad_commit = None
    for commit in commits_output:
        diff = subprocess.check_output(
            ["git", "show", commit], cwd=repo_dir, errors="ignore"
        )
        if ("rand" in diff or "segfault" in diff.lower() or "abort" in diff
                or "crash" in diff.lower()):
            actual_bad_commit = commit
            break

    if not actual_bad_commit and len(commits_output) >= 14:
        actual_bad_commit = commits_output[13]

    assert actual_bad_commit is not None, "Could not identify the introducing commit"
    assert student_commit == actual_bad_commit, \
        f"Incorrect bad commit identified. Expected {actual_bad_commit}, got {student_commit}"
    subprocess.check_call(["git", "cat-file", "-e", student_commit + "^{commit}"], cwd=repo_dir)

    # The instruction leaves the script's exact pathname open, so accept a
    # sensibly named regression/reproducer script in the repository or user home.
    candidates = []
    roots = [Path(repo_dir), Path("/home/user")]
    name_pattern = re.compile(r"(regression|test|repro|crash|bisect)", re.I)
    excluded = {
        Path("/home/user/start_infrastructure.sh"),
        Path("/home/user/decoder.cpp"),
        Path("/home/user/decoder.bin"),
    }
    seen = set()
    for root in roots:
        for path in root.rglob("*"):
            if ".git" in path.parts or path in excluded or path in seen:
                continue
            seen.add(path)
            try:
                mode = path.lstat().st_mode
            except OSError:
                continue
            if not stat.S_ISREG(mode) or not name_pattern.search(path.name):
                continue
            if path.suffix.lower() not in (".sh", ".py", ".bash", ""):
                continue
            if path.stat().st_size > 0:
                candidates.append(path)

    assert candidates, "No regression test/reproducer script was created"
    assert any(
        re.search(r"bot|g\+\+|make|cmake|segmentation|crash", p.read_text(errors="ignore"), re.I)
        for p in candidates
    ), "Regression script does not exercise or build the bot"


def _expected_decode(data):
    return bytes((((~byte) & 0xff) ^ (i & 0xff)) for i, byte in enumerate(data))


def _run_decoder(path, data):
    return subprocess.run([path], input=data, capture_output=True, timeout=15)


def test_decoder_fuzz_equivalence():
    oracle_path = "/app/oracle_decoder"
    agent_path = "/home/user/decoder.bin"
    source_path = "/home/user/decoder.cpp"

    assert _regular_file(source_path), f"Missing regular C++ source: {source_path}"
    assert _regular_file(agent_path), f"Missing regular agent decoder: {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent decoder is not executable: {agent_path}"
    assert _regular_file(oracle_path), f"Missing oracle decoder: {oracle_path}"
    assert not os.path.samefile(agent_path, oracle_path), "Agent decoder must not alias the oracle"

    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent decoder must not be a copy of the oracle binary"

    source = Path(source_path).read_text(errors="ignore")
    assert source.strip(), "decoder.cpp is empty"
    assert not re.search(r"\b(system|popen|execl|execlp|execle|execv|execvp|execve|fork)\s*\(", source), \
        "decoder.cpp must implement the transformation, not launch another program"

    compiled_path = os.path.join(tempfile.mkdtemp(prefix="decoder-build-"), "decoder")
    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", source_path, "-o", compiled_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"decoder.cpp does not compile: {build.stderr.decode(errors='replace')}"

    rng = random.Random(1337)

    # Preserve the original oracle-equivalence assertions.
    for i in range(50):
        length = rng.randint(1, 100000)
        input_data = os.urandom(length)
        oracle_proc = _run_decoder(oracle_path, input_data)
        agent_proc = _run_decoder(agent_path, input_data)
        assert oracle_proc.returncode == 0, "Oracle decoder failed"
        assert agent_proc.returncode == 0, "Agent decoder failed"
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(f"Mismatch detected on fuzz iteration {i} with input length {length} bytes")

    # Exercise the implementation compiled directly from decoder.cpp against
    # independently derived answers while the documented oracle pathname is absent.
    hidden_oracle = f"/app/.oracle_decoder.verifier-{uuid.uuid4().hex}"
    os.rename(oracle_path, hidden_oracle)
    try:
        cases = [
            b"",
            b"\x00",
            bytes(range(256)),
            b"\x00" * 4097,
            bytes((i * 73 + 19) & 0xff for i in range(65537)),
            os.urandom(1024 * 1024),
        ]
        for i in range(12):
            cases.append(os.urandom(rng.randint(1, 200000)))

        for i, input_data in enumerate(cases):
            proc = _run_decoder(compiled_path, input_data)
            assert proc.returncode == 0, f"Source-built decoder failed on case {i}"
            assert proc.stderr == b"", f"Source-built decoder wrote to stderr on case {i}"
            assert proc.stdout == _expected_decode(input_data), \
                f"Source-built decoder produced incorrect output on case {i}"
    finally:
        os.rename(hidden_oracle, oracle_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
