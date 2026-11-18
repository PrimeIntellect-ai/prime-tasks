#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import os
import signal
import subprocess
import time

import pytest
import websockets

PROJECT = '/home/user/ws_proxy'
EXECUTABLE = os.path.join(PROJECT, 'proxy_server')
LOG_PATH = '/home/user/ws_response.log'
MESSAGE = '{"type": "chat", "msg": "<script>alert(1)</script>"}'
EXPECTED = '{"status": "blocked", "reason": "XSS detected"}'
RUNNING_PROCESS = None


def test_makefile_fixed():
    makefile_path = os.path.join(PROJECT, 'Makefile')
    assert os.path.isfile(makefile_path), f"The file {makefile_path} does not exist."

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert "-lws_v2" in content, "Makefile does not link against the correct libws version (-lws_v2)."
    assert "-lauth_v3" in content, "Makefile does not link against the correct libauth version (-lauth_v3)."
    assert "-lfilter_v2" in content, "Makefile does not link against the correct libfilter version (-lfilter_v2)."


def test_proxy_server_built():
    assert os.path.isfile(EXECUTABLE), f"The executable {EXECUTABLE} was not built."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."


def test_ws_response_log_content():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} does not exist."

    with open(LOG_PATH, 'r') as f:
        content = f.read().strip()

    assert content == EXPECTED, f"The log file content is incorrect. Expected '{EXPECTED}', got '{content}'."


def test_proxy_server_running():
    try:
        output = subprocess.check_output(['pgrep', '-f', 'proxy_server']).decode('utf-8').strip()
        assert output, "The proxy_server process is not running in the background."
    except subprocess.CalledProcessError:
        pytest.fail("The proxy_server process is not running in the background.")


def _kill_port_8080_owners():
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if owners:
        time.sleep(0.5)
    for pid in owners:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_clean_rebuild_uses_required_dependency_chain():
    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)

    result = subprocess.run(
        ['make'], cwd=PROJECT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"A clean build failed:\n{result.stdout}"
    assert os.path.isfile(EXECUTABLE), "make did not produce proxy_server."
    assert os.access(EXECUTABLE, os.X_OK), "The rebuilt proxy_server is not executable."

    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "proxy_server is not a compiled ELF executable."

    nm = subprocess.run(
        ['nm', '-g', EXECUTABLE], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert nm.returncode == 0, f"Could not inspect rebuilt executable: {nm.stderr}"
    for symbol in ('ws_init_secure', 'auth_check_v3', 'filter_strict'):
        assert symbol in nm.stdout, f"Rebuilt executable does not contain required symbol {symbol}."


def test_rebuilt_proxy_serves_message_and_log_is_actual_response():
    global RUNNING_PROCESS
    _kill_port_8080_owners()
    time.sleep(0.5)

    RUNNING_PROCESS = subprocess.Popen(
        [EXECUTABLE], cwd=PROJECT, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )

    async def exchange():
        last_error = None
        for _ in range(30):
            if RUNNING_PROCESS.poll() is not None:
                pytest.fail(f"Rebuilt proxy_server exited with status {RUNNING_PROCESS.returncode}.")
            try:
                async with websockets.connect('ws://127.0.0.1:8080', open_timeout=1) as websocket:
                    await websocket.send(MESSAGE)
                    return await asyncio.wait_for(websocket.recv(), timeout=3)
            except Exception as exc:
                last_error = exc
                await asyncio.sleep(0.2)
        pytest.fail(f"Could not exchange a WebSocket message with rebuilt proxy_server: {last_error}")

    response = asyncio.run(exchange())
    assert response == EXPECTED, f"Unexpected live WebSocket response: {response!r}"

    with open(LOG_PATH, 'r') as f:
        raw_log = f.read()
    assert raw_log == response, "ws_response.log is not exactly the payload returned by the live server."
    assert RUNNING_PROCESS.poll() is None, "proxy_server did not remain running after the test."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
