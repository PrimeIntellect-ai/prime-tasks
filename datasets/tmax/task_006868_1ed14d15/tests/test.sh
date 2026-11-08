#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import signal
import socket
import subprocess
import sys
import textwrap
import time

import pytest

SERVER_PATH = '/home/user/monitor_service/server.py'
MRE_PATH = '/home/user/mre.py'
EXPECTED_PAYLOAD = 'metric=DISK|val=NaN_ERROR_99'
EXPECTED_PORT = 8888


def test_payload_txt():
    path = '/home/user/payload.txt'
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    expected = EXPECTED_PAYLOAD
    assert content == expected, f"payload.txt contains '{content}' instead of the expected payload '{expected}'."


def test_server_py_patched():
    path = SERVER_PATH
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, 'r') as f:
        code = f.read()

    try:
        tree = ast.parse(code)
    except SyntaxError as e:
        pytest.fail(f"server.py has a syntax error: {e}")

    safe_lock = False
    for node in ast.walk(tree):
        # Check for 'with lock:'
        if isinstance(node, ast.With):
            for item in node.items:
                if isinstance(item.context_expr, ast.Name) and item.context_expr.id == 'lock':
                    safe_lock = True
        # Check for 'try...finally' containing 'lock.release()'
        elif isinstance(node, ast.Try):
            for stmt in node.finalbody:
                if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Call):
                    func = stmt.value.func
                    if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
                        if func.value.id == 'lock' and func.attr == 'release':
                            safe_lock = True

    assert safe_lock, "server.py does not safely release the lock. You must use a 'with lock:' context manager or a 'try...finally' block calling 'lock.release()'."


def test_server_lock_is_released_behaviorally():
    helper = textwrap.dedent(f'''\
        import importlib.util
        import threading

        spec = importlib.util.spec_from_file_location("submitted_server", {SERVER_PATH!r})
        server = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(server)

        try:
            server.handle_client({EXPECTED_PAYLOAD.encode('utf-8')!r})
        except Exception:
            # Rejecting the malformed metric is permitted, but the lock must be free.
            pass

        assert server.lock.acquire(timeout=1.0), "malformed metric left the mutex locked"
        server.lock.release()

        worker = threading.Thread(target=server.handle_client, args=(b'metric=CPU|val=45',))
        worker.start()
        worker.join(1.0)
        assert not worker.is_alive(), "a subsequent metric deadlocked"
        assert server.metrics.get('CPU') == '45', "a subsequent valid metric was not processed"

        assert server.lock.acquire(timeout=1.0), "valid metric processing left the mutex locked"
        server.lock.release()
    ''')
    result = subprocess.run(
        [sys.executable, '-c', helper],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_server_starts_without_missing_environment_and_binds_pcap_port():
    # Ensure the expected port is free before attributing its later use to the server.
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.bind(('127.0.0.1', EXPECTED_PORT))
    except OSError as exc:
        probe.close()
        pytest.fail(f"UDP port {EXPECTED_PORT} was already occupied before starting server.py: {exc}")
    probe.close()

    env = os.environ.copy()
    env.pop('MONITOR_PORT', None)
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd='/home/user/monitor_service',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        preexec_fn=os.setsid,
    )
    try:
        deadline = time.time() + 3.0
        bound = False
        while time.time() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"server.py exited instead of starting with MONITOR_PORT unset:\n{out}{err}")
            check = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                check.bind(('127.0.0.1', EXPECTED_PORT))
            except OSError:
                bound = True
                break
            finally:
                check.close()
            time.sleep(0.05)

        assert bound, f"server.py did not bind UDP port {EXPECTED_PORT} with MONITOR_PORT unset"

        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sender.sendto(EXPECTED_PAYLOAD.encode('utf-8'), ('127.0.0.1', EXPECTED_PORT))
        sender.sendto(b'metric=NET|val=10', ('127.0.0.1', EXPECTED_PORT))
        sender.close()
        time.sleep(0.2)
        assert proc.poll() is None, "server.py terminated after receiving the malformed payload"
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=2)


def test_mre_py_exists_and_correct():
    path = MRE_PATH
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    expected_payload = EXPECTED_PAYLOAD
    assert expected_payload in content, f"mre.py does not contain the malicious payload: {expected_payload}"
    assert 'socket' in content or 'UDP' in content or 'scapy' in content, "mre.py does not appear to contain network code to send the payload."


def test_mre_actually_sends_exact_udp_payload():
    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.bind(('127.0.0.1', EXPECTED_PORT))
    receiver.settimeout(3.0)
    try:
        result = subprocess.run(
            [sys.executable, MRE_PATH],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=4,
        )
        assert result.returncode == 0, f"mre.py failed:\n{result.stdout}{result.stderr}"
        try:
            data, _ = receiver.recvfrom(65535)
        except socket.timeout:
            pytest.fail(f"mre.py did not send a UDP datagram to 127.0.0.1:{EXPECTED_PORT}")
        assert data == EXPECTED_PAYLOAD.encode('utf-8'), f"mre.py sent {data!r}, not the exact malicious payload"
    finally:
        receiver.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
