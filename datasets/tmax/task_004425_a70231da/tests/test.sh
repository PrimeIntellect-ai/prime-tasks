#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import subprocess
import time
import pytest

HOST = '127.0.0.1'
PORT = 9090


def listener_pids():
    """Find processes holding a listening socket on 127.0.0.1:9090."""
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != '0A':
                        continue
                    local = fields[1]
                    try:
                        port = int(local.rsplit(':', 1)[1], 16)
                    except (ValueError, IndexError):
                        continue
                    if port == PORT:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return result


def stop_listener():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), 'Could not stop the existing server on port 9090.'


def wait_for_server(proc=None):
    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail(f'Server exited early with status {proc.returncode}.')
        try:
            with socket.create_connection((HOST, PORT), timeout=0.25):
                return
        except OSError as exc:
            last_error = exc
            time.sleep(0.05)
    pytest.fail(f'Server did not listen on {HOST}:{PORT}: {last_error}')


def recv_line(sock):
    data = b''
    while not data.endswith(b'\n'):
        chunk = sock.recv(1)
        assert chunk, 'Connection closed before a complete response line was received.'
        data += chunk
        assert len(data) < 4096, 'Response line was unreasonably long.'
    return data.decode('utf-8')


def dump_lines():
    with socket.create_connection((HOST, PORT), timeout=5) as s:
        s.settimeout(5)
        s.sendall(b'DUMP\n')
        response = b''
        while b'END\n' not in response:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
    text = response.decode('utf-8')
    return [line.strip() for line in text.strip().split('\n') if line.strip()]


def exercise_randomized_server(executable):
    stop_listener()
    proc = subprocess.Popen([executable], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_server(proc)
        token = secrets.token_hex(8)
        keys = [f'audit_{token}_{i}' for i in range(7)]
        values = [secrets.randbelow(900000) + 1 for _ in keys]
        updated = secrets.randbelow(900000) + 1000001
        invalid = {
            f'audit_{token}_zero': '0',
            f'audit_{token}_negative': f'-{secrets.randbelow(9999) + 1}',
            f'audit_{token}_text': 'not_an_integer',
            f'audit_{token}_decimal': '3.5',
        }

        # Exercise line-by-line parsing with many commands over one connection.
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.settimeout(5)
            for i, (key, value) in enumerate(zip(keys, values)):
                admin = f'PrivateAdmin_{token}_{i}'
                s.sendall(f'ADD key={key} value={value} admin={admin}\n'.encode())
                assert recv_line(s) == 'ACK\n', 'Valid ADD did not return the exact ACK response.'

            # Overwrite a non-edge entry to verify true key-based deduplication.
            s.sendall(f'ADD key={keys[3]} value={updated} admin=Replacement_{token}\n'.encode())
            assert recv_line(s) == 'ACK\n', 'Deduplicating ADD did not return ACK.'

            for key, value in invalid.items():
                s.sendall(f'ADD key={key} value={value} admin=Invalid_{token}\n'.encode())
                assert recv_line(s) == 'ACK\n', 'Invalid ADD did not return the specified ACK response.'

        lines = dump_lines()
        assert lines and lines[-1] == 'END', 'DUMP did not terminate with END.'
        configs = lines[:-1]
        pattern = re.compile(r'^CONFIG: key=([^ ]+) value=([^ ]+) admin=\*\*\*$')
        parsed = []
        for line in configs:
            match = pattern.fullmatch(line)
            assert match, f'Malformed or unmasked DUMP line: {line!r}'
            parsed.append((match.group(1), match.group(2)))

        expected = dict(zip(keys, map(str, values)))
        expected[keys[3]] = str(updated)
        for key, value in expected.items():
            matches = [v for k, v in parsed if k == key]
            assert matches == [value], f'Expected exactly one current record for {key} with value {value}, got {matches}.'
        for key in invalid:
            assert all(k != key for k, _ in parsed), f'Invalid value was stored for key {key}.'
        assert token not in '\n'.join(configs).replace(f'audit_{token}', ''), 'An administrator name was leaked.'
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except (subprocess.TimeoutExpired, ProcessLookupError):
            try:
                proc.kill()
            except ProcessLookupError:
                pass
        stop_listener()


def test_server_source_and_binary_exist():
    """Test that the C source and compiled binary exist."""
    assert os.path.exists('/home/user/config_server.c'), "Source file /home/user/config_server.c is missing."
    assert os.path.exists('/home/user/config_server'), "Compiled binary /home/user/config_server is missing."
    assert os.access('/home/user/config_server', os.X_OK), "Binary /home/user/config_server is not executable."

    pids = listener_pids()
    assert pids, 'No process is listening on port 9090.'
    assert any(os.path.samefile(f'/proc/{pid}/exe', '/home/user/config_server') for pid in pids), \
        'The submitted /home/user/config_server binary is not the server listening on port 9090.'


def test_server_dump_output():
    """Test the DUMP command on the server to verify the final configuration state."""
    try:
        lines = dump_lines()
        assert lines, "Received empty response from DUMP command."
        assert lines[-1] == "END", "Response did not end with 'END'."
        config_lines = lines[:-1]
        expected_configs = {
            "CONFIG: key=timeout value=120 admin=***",
            "CONFIG: key=retries value=5 admin=***",
            "CONFIG: key=max_connections value=1000 admin=***"
        }
        actual_configs = set(config_lines)
        missing = expected_configs - actual_configs
        extra = actual_configs - expected_configs
        assert not missing, f"Missing expected configurations: {missing}"
        assert not extra, f"Unexpected configurations found: {extra}"
        assert len(config_lines) == len(expected_configs), "Duplicate configurations found in DUMP output."
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}. Is it running?")
    except socket.timeout:
        pytest.fail("Connection or read timed out.")


def test_server_add_validation():
    """Test that the server correctly validates and masks new ADD commands."""
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.sendall(b"ADD key=test_neg value=-5 admin=Alice\n")
            ack1 = s.recv(1024).decode('utf-8')
            s.sendall(b"ADD key=test_pos value=42 admin=Bob\n")
            ack2 = s.recv(1024).decode('utf-8')
            assert "ACK" in ack2, "Server did not acknowledge valid ADD command."

        response_str = '\n'.join(dump_lines())
        assert "CONFIG: key=test_pos value=42 admin=***" in response_str, "Valid config was not stored or masked correctly."
        assert "test_neg" not in response_str, "Invalid config (negative value) was incorrectly stored."
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}. Is it running?")
    except socket.timeout:
        pytest.fail("Connection or read timed out.")


def test_submitted_binary_general_behavior():
    exercise_randomized_server('/home/user/config_server')


def test_c_source_builds_and_implements_general_behavior():
    rebuilt = '/tmp/config_server_rebuilt'
    result = subprocess.run(
        ['gcc', '/home/user/config_server.c', '-o', rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'C source failed to compile:\n{result.stdout}'
    assert os.access(rebuilt, os.X_OK), 'Rebuilt C server is not executable.'
    exercise_randomized_server(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
