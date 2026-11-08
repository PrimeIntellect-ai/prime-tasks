#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import collections
import os
import secrets
import socket
import string
import subprocess
import time

import pytest
import websockets


def check_port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[-1] == wanted:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def socket_owners(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def descendants(pid):
    result = {pid}
    changed = True
    while changed:
        changed = False
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) in result:
                continue
            try:
                with open(f"/proc/{entry}/stat") as f:
                    data = f.read()
                rest = data[data.rfind(")") + 2:].split()
                ppid = int(rest[1])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in result:
                result.add(int(entry))
                changed = True
    return result


def established_8081_inodes():
    found = set()
    wanted = f"{8081:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = fields[1].split(":")[-1]
                    remote_port = fields[2].split(":")[-1]
                    if fields[3] == "01" and wanted in (local_port, remote_port):
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def read_proxy_pid():
    pid_file = "/home/user/proxy.pid"
    assert os.path.isfile(pid_file), f"{pid_file} does not exist"
    with open(pid_file) as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file {pid_file} does not contain a valid integer PID"
    return int(value)


def test_rust_server_running():
    assert check_port_open(8081), "Rust WebSocket server is not listening on port 8081"

    owners = socket_owners(listener_inodes(8081))
    assert owners, "Could not identify the process listening on port 8081"
    rust_owners = []
    for pid in owners:
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/exe", "rb") as f:
                is_elf = f.read(4) == b"\x7fELF"
        except OSError:
            continue
        if is_elf and os.path.basename(exe).replace(" (deleted)", "") == "py2_evaluator":
            rust_owners.append(pid)
    assert rust_owners, "Port 8081 is not owned by the compiled py2_evaluator executable"

    source = "/home/user/py2_evaluator/src/main.rs"
    manifest = "/home/user/py2_evaluator/Cargo.toml"
    assert os.path.isfile(source), "Rust source file is missing"
    assert os.path.isfile(manifest), "Cargo.toml is missing"
    with open(source) as f:
        text = f.read()
    assert text.strip() and text.strip() != "fn main() {}", "Rust server source was not implemented"


def test_proxy_running():
    assert check_port_open(8080), "Reverse proxy is not listening on port 8080"


def test_proxy_pid_file():
    pid = read_proxy_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running")

    owners = socket_owners(listener_inodes(8080))
    assert owners & descendants(pid), "The PID in proxy.pid does not own the port 8080 listener"


def test_proxy_really_forwards_to_8081():
    script = r'''
import asyncio
import websockets

async def main():
    async with websockets.connect("ws://127.0.0.1:8080") as ws:
        await ws.send('37 / 5')
        assert await ws.recv() == '7'
        print('READY', flush=True)
        await asyncio.sleep(4)
asyncio.run(main())
'''
    proc = subprocess.Popen(
        ["python3", "-c", script], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    try:
        assert proc.stdout.readline().strip() == "READY", "Could not establish a WebSocket through the proxy"
        time.sleep(0.2)
        proxy_family = descendants(read_proxy_pid())
        forwarding_owners = socket_owners(established_8081_inodes())
        assert proxy_family & forwarding_owners, "The port 8080 proxy has no forwarded TCP connection to port 8081"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_websocket_behavior():
    client_script = """
import asyncio
import websockets
import sys

async def test():
    uri = "ws://127.0.0.1:8080"
    tests = {
        'print "test"': 'test',
        '9 / 2': '4',
        'print 10 / 3': '3',
        'invalid syntax': 'ERROR'
    }
    try:
        async with websockets.connect(uri) as websocket:
            for req, expected in tests.items():
                await websocket.send(req)
                res = await websocket.recv()
                if res != expected:
                    print(f"Failed on {req}: expected {expected}, got {res}")
                    sys.exit(1)
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

asyncio.run(test())
"""
    with open("/tmp/test_ws.py", "w") as f:
        f.write(client_script)

    result = subprocess.run(["python3", "/tmp/test_ws.py"], capture_output=True, text=True)
    assert result.returncode == 0, f"WebSocket test failed: {result.stdout}\n{result.stderr}"


def test_randomized_python2_rules_on_server_and_proxy():
    cases = []
    for _ in range(20):
        a = secrets.randbelow(900000) + 1
        b = secrets.randbelow(999) + 1
        expression = f"{a} / {b}"
        answer = str(a // b)
        cases.append((expression, answer))
        cases.append((f"print {expression}", answer))

    alphabet = string.ascii_letters + string.digits + " "
    for _ in range(15):
        value = ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(20) + 1))
        cases.append((f'print "{value}"', value))

    token = secrets.token_hex(12)
    cases.extend([
        (f"print '{token}'", "ERROR"),
        (f' print "{token}"', "ERROR"),
        (f'print "{token}" ', "ERROR"),
        ("0 / 2", "ERROR"),
        ("2 / 0", "ERROR"),
        ("-9 / 2", "ERROR"),
        ("9/2", "ERROR"),
        ("print(9 / 2)", "ERROR"),
        (f'print "{token}" trailing', "ERROR"),
        (f"{secrets.randbelow(999)+1} + {secrets.randbelow(999)+1}", "ERROR"),
    ])
    secrets.SystemRandom().shuffle(cases)

    async def exercise(uri):
        async with websockets.connect(uri, open_timeout=3) as ws:
            for request, expected in cases:
                await ws.send(request)
                actual = await asyncio.wait_for(ws.recv(), timeout=3)
                assert actual == expected, f"{uri}: {request!r}: expected {expected!r}, got {actual!r}"

    asyncio.run(exercise("ws://127.0.0.1:8081"))
    asyncio.run(exercise("ws://127.0.0.1:8080"))


def test_sorted_results():
    raw_file = "/home/user/raw_results.txt"
    sorted_file = "/home/user/sorted_results.txt"

    assert os.path.isfile(raw_file), f"{raw_file} does not exist"
    assert os.path.isfile(sorted_file), f"{sorted_file} does not exist"

    with open(raw_file, "r") as f:
        raw_lines = [line.strip() for line in f if line.strip()]

    with open(sorted_file, "r") as f:
        sorted_lines = [line.strip() for line in f if line.strip()]

    assert len(raw_lines) == len(sorted_lines), "Sorted file does not have the same number of lines as raw file"

    def get_latency(line):
        parts = line.split()
        if not parts:
            return -1
        try:
            return int(parts[0])
        except ValueError:
            return -1

    expected_sorted = sorted(raw_lines, key=get_latency, reverse=True)
    assert sorted_lines == expected_sorted, "Results are not correctly sorted by latency in descending order"

    results_only = [" ".join(line.split()[1:]) for line in raw_lines]
    assert set(results_only) == {"hello", "2", "3", "ERROR"}, "Raw results don't contain the expected outputs"
    assert len(raw_lines) == 4, "Benchmark output must contain exactly four results"
    assert collections.Counter(results_only) == collections.Counter(["hello", "2", "3", "ERROR"])
    assert all(get_latency(line) >= 0 for line in raw_lines), "Every benchmark line must start with a nonnegative integer latency"
    assert os.path.getmtime(sorted_file) >= os.path.getmtime(raw_file), "Sorted results predate raw benchmark results"


def test_benchmark_script_executes_against_service():
    raw_file = "/home/user/raw_results.txt"
    with open(raw_file, "rb") as f:
        saved_raw = f.read()
    saved_stat = os.stat(raw_file)
    try:
        result = subprocess.run(
            ["/bin/bash", "/home/user/benchmark.sh"],
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, f"Benchmark failed: {result.stdout}\n{result.stderr}"
        with open(raw_file) as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 4, "The benchmark did not produce four results"
        parsed = []
        for line in lines:
            parts = line.split(maxsplit=1)
            assert len(parts) == 2 and parts[0].isdigit(), f"Malformed benchmark line: {line!r}"
            assert int(parts[0]) >= 0
            parsed.append(parts[1])
        assert parsed == ["hello", "2", "3", "ERROR"], "Benchmark responses are incorrect or out of order"
    finally:
        with open(raw_file, "wb") as f:
            f.write(saved_raw)
        os.utime(raw_file, ns=(saved_stat.st_atime_ns, saved_stat.st_mtime_ns))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
