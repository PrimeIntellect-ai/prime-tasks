#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shutil
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest

HOST = '127.0.0.1'
PORT = 7070


def send_and_receive(payload: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to TCP server at {HOST}:{PORT}. Is it running?")

        s.sendall(payload.encode('utf-8'))
        s.shutdown(socket.SHUT_WR)

        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk

        return response.decode('utf-8')


def listener_pid():
    inodes = set()
    try:
        with open('/proc/net/tcp') as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                address, port_hex = local_address.split(':')
                if address == '0100007F' and int(port_hex, 16) == PORT and state == '0A':
                    inodes.add(fields[9])
    except OSError:
        return None

    for proc_entry in os.scandir('/proc'):
        if not proc_entry.name.isdigit():
            continue
        fd_dir = f'/proc/{proc_entry.name}/fd'
        try:
            for fd in os.scandir(fd_dir):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    return int(proc_entry.name)
        except OSError:
            continue
    return None


def wait_for_server(timeout=8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pid() is not None:
            return
        time.sleep(0.05)
    pytest.fail(f'The relaunched server did not listen on {HOST}:{PORT}')


def test_core_server_is_native_c_artifact():
    pid = listener_pid()
    assert pid is not None, f'No listener found on {HOST}:{PORT}'

    with open(f'/proc/{pid}/exe', 'rb') as executable:
        assert executable.read(4) == b'\x7fELF', 'The listening server process is not a native ELF executable'

    sources = []
    for root in ('/app', '/home/user', '/tmp'):
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {'.git', '__pycache__'}]
            for name in files:
                if name.endswith('.c'):
                    path = os.path.join(directory, name)
                    try:
                        if os.path.getsize(path) <= 2_000_000:
                            sources.append(Path(path).read_text(errors='ignore'))
                    except OSError:
                        pass

    combined = '\n'.join(sources)
    assert combined, 'No C source file for the server was found'
    for function in ('socket', 'bind', 'listen', 'accept'):
        assert re.search(r'\b' + function + r'\s*\(', combined), (
            f'C source does not contain the required TCP server operation {function}()'
        )


def test_tcp_server_basic_aggregation():
    """Test the server with a standard payload containing matching and non-matching edges."""
    payload = (
        "A,B,PURCHASE,100\n"
        "C,D,REFUND,50\n"
        "A,E,REFUND,200\n"
        "C,F,REFUND,300\n"
        "B,G,PURCHASE,500\n"
    )
    expected_response = "MAX_SOURCE: C, AMOUNT: 350\n"

    actual_response = send_and_receive(payload)
    assert actual_response == expected_response, (
        f"Expected response {repr(expected_response)}, but got {repr(actual_response)}"
    )


def test_tcp_server_no_matching_edges():
    """Test the server when there are no matching edges in the payload."""
    payload = (
        "A,B,PURCHASE,100\n"
        "B,G,PURCHASE,500\n"
    )
    expected_response = "MAX_SOURCE: NONE, AMOUNT: 0\n"

    actual_response = send_and_receive(payload)
    assert actual_response == expected_response, (
        f"Expected response {repr(expected_response)} for no matching edges, but got {repr(actual_response)}"
    )


def test_tcp_server_empty_payload():
    """Test the server with an empty payload."""
    payload = ""
    expected_response = "MAX_SOURCE: NONE, AMOUNT: 0\n"

    actual_response = send_and_receive(payload)
    assert actual_response == expected_response, (
        f"Expected response {repr(expected_response)} for empty payload, but got {repr(actual_response)}"
    )


def test_randomized_aggregation_and_rule_image_dependency():
    pid = listener_pid()
    assert pid is not None

    exe_link = os.readlink(f'/proc/{pid}/exe')
    assert not exe_link.endswith(' (deleted)'), 'Listening executable was deleted and cannot be retested'
    argv_raw = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
    argv = [part.decode(errors='surrogateescape') for part in argv_raw if part]
    assert argv, 'Could not recover server command line'
    cwd = os.readlink(f'/proc/{pid}/cwd')
    env = os.environ.copy()
    try:
        entries = Path(f'/proc/{pid}/environ').read_bytes().split(b'\0')
        env.update(
            entry.split(b'=', 1)[0].decode(errors='surrogateescape'):
            entry.split(b'=', 1)[1].decode(errors='surrogateescape')
            for entry in entries if b'=' in entry
        )
    except OSError:
        pass

    original_image = Path('/app/rule.png').read_bytes()
    alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    dynamic_type = ''.join(secrets.choice(alphabet) for _ in range(6))

    try:
        subprocess.run([
            'convert', '-size', '300x100', 'xc:white', '-fill', 'black',
            '-pointsize', '24', '-gravity', 'center', '-draw',
            f"text 0,0 'FILTER_TYPE={dynamic_type}'", '/app/rule.png'
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # Stop the old instance and execute the same native server artifact again,
        # forcing a correct implementation to extract the newly supplied rule.
        for _ in range(40):
            current = listener_pid()
            if current is None:
                break
            try:
                os.kill(current, signal.SIGTERM)
            except ProcessLookupError:
                pass
            time.sleep(0.05)
        current = listener_pid()
        if current is not None:
            os.kill(current, signal.SIGKILL)
            time.sleep(0.1)

        subprocess.Popen(
            argv,
            executable=exe_link,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        wait_for_server()

        token = secrets.token_hex(4)
        nodes = [f'N{token}_{i}' for i in range(7)]
        totals = {}
        lines = []
        for i, node in enumerate(nodes):
            count = 2 + secrets.randbelow(5)
            weights = [10 + secrets.randbelow(200) for _ in range(count)]
            totals[node] = sum(weights)
            for j, weight in enumerate(weights):
                lines.append(f'{node},T{j},{dynamic_type},{weight}\n')
            lines.append(f'{node},IGNORED,REFUND,{5000 + i}\n')
            lines.append(f'{node},IGNORED,OTHER,{7000 + i}\n')

        # Make the winner unique while keeping the expected value derived here.
        winner = nodes[secrets.randbelow(len(nodes))]
        extra = max(totals.values()) - totals[winner] + 1000 + secrets.randbelow(1000)
        totals[winner] += extra
        lines.append(f'{winner},FINAL,{dynamic_type},{extra}\n')
        random.SystemRandom().shuffle(lines)

        expected = f'MAX_SOURCE: {winner}, AMOUNT: {totals[winner]}\n'
        actual = send_and_receive(''.join(lines))
        assert actual == expected, f'Expected randomized response {expected!r}, got {actual!r}'
    finally:
        Path('/app/rule.png').write_bytes(original_image)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
