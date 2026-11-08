#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import time


def server_pids():
    pids = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read()
            if b'build_server.py' in cmdline:
                pids.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def run_orchestrator():
    return subprocess.run(
        ['/home/user/polybuild/orchestrate.sh'],
        cwd='/home/user/polybuild',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=25,
    )


def wait_for_server_exit(timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not server_pids():
            return True
        time.sleep(0.1)
    return not server_pids()


def test_orchestrate_script_exists_and_executable():
    script_path = '/home/user/polybuild/orchestrate.sh'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} is not executable.'


def test_diff_report_exists_and_correct():
    report_path = '/home/user/polybuild/diff_report.txt'
    if os.path.exists(report_path):
        os.unlink(report_path)

    result = run_orchestrator()
    assert result.returncode == 0, (
        f'orchestrate.sh failed with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(report_path), f'Report file {report_path} does not exist.'

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected = 'T001,5\nT002,-5\nT003,0'
    assert content == expected, f'Content of {report_path} is incorrect.\nExpected:\n{expected}\nActual:\n{content}'


def test_build_server_not_running():
    # Retain the original cleanup assertion.
    try:
        output = subprocess.check_output(['pgrep', '-f', 'build_server.py'], text=True)
        assert not output.strip(), 'build_server.py is still running. It was not cleanly killed.'
    except subprocess.CalledProcessError:
        pass


def test_orchestrator_uses_websocket_data_and_merges_dynamic_input():
    base = '/home/user/polybuild'
    server_path = f'{base}/build_server.py'
    client_path = f'{base}/ws_client.py'
    legacy_path = f'{base}/legacy_results.txt'
    report_path = f'{base}/diff_report.txt'

    paths = [server_path, client_path, legacy_path, report_path]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                backups[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            backups[path] = None

    token = secrets.token_hex(8)
    server_log = f'/tmp/polybuild_server_{token}.log'
    client_log = f'/tmp/polybuild_client_{token}.log'

    task_z = f'Z{token[:8]}'
    task_a = f'A{token[:8]}'
    task_m = f'M{token[:8]}'

    x = secrets.randbelow(30) + 11
    y = (secrets.randbelow(30) + 10) * 2
    exponent = secrets.randbelow(4) + 5
    current = {
        task_z: x + 5 * 2,
        task_a: y // 2 - 3,
        task_m: 2 ** exponent,
    }
    legacy = {
        task_z: secrets.randbelow(40) + 1,
        task_a: secrets.randbelow(40) + 1,
        task_m: secrets.randbelow(40) + 1,
    }

    response = (
        f'{task_z};;{x}+5*2;;python\\n'
        f'{task_a};;{y}/2-3;;nodejs\\n'
        f'{task_m};;2^{exponent};;cpp'
    )

    server_source = f'''#!/usr/bin/env python3
import asyncio
import websockets

LOG = {server_log!r}
RESPONSE = {response!r}

async def handler(websocket, *args):
    with open(LOG, 'a') as log:
        log.write('STARTED\\n')
        log.flush()
    async for message in websocket:
        with open(LOG, 'a') as log:
            log.write('MESSAGE:' + message + '\\n')
            log.flush()
        if message == 'GET_TEST_TASKS':
            await websocket.send(RESPONSE)
        else:
            await websocket.send('INVALID_COMMAND')

start_server = websockets.serve(handler, 'localhost', 9090)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
'''

    client_source = f'''#!/usr/bin/env python3
import asyncio
import sys
import websockets

with open({client_log!r}, 'a') as log:
    log.write(sys.argv[1] + '\\n')

async def send_msg():
    async with websockets.connect('ws://localhost:9090') as websocket:
        await websocket.send(sys.argv[1])
        print(await websocket.recv())

asyncio.get_event_loop().run_until_complete(send_msg())
'''

    leaked_after_run = []
    try:
        with open(server_path, 'w') as f:
            f.write(server_source)
        with open(client_path, 'w') as f:
            f.write(client_source)
        os.chmod(server_path, 0o755)
        os.chmod(client_path, 0o755)

        with open(legacy_path, 'w') as f:
            f.write(f'{task_m},{legacy[task_m]}\n')
            f.write(f'{task_z},{legacy[task_z]}\n')
            f.write(f'{task_a},{legacy[task_a]}\n')

        if os.path.exists(report_path):
            os.unlink(report_path)

        result = run_orchestrator()
        server_stopped = wait_for_server_exit()
        leaked_after_run = server_pids()

        assert result.returncode == 0, (
            f'orchestrate.sh failed on dynamic inputs with status {result.returncode}.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert os.path.isfile(report_path), 'orchestrate.sh did not create diff_report.txt'

        expected_lines = [
            f'{task},{current[task] - legacy[task]}'
            for task in sorted(current)
        ]
        with open(report_path) as f:
            actual = f.read().strip()
        assert actual == '\n'.join(expected_lines), (
            f'Dynamic report was incorrect.\nExpected:\n{chr(10).join(expected_lines)}\nActual:\n{actual}'
        )

        assert os.path.isfile(client_log), 'ws_client.py was not invoked'
        with open(client_log) as f:
            client_messages = [line.rstrip('\n') for line in f]
        assert client_messages and all(m == 'GET_TEST_TASKS' for m in client_messages), (
            f'ws_client.py was not called with the exact required command: {client_messages}'
        )

        assert os.path.isfile(server_log), 'build_server.py was not started'
        with open(server_log) as f:
            server_events = [line.rstrip('\n') for line in f]
        assert 'STARTED' in server_events, 'build_server.py did not accept a WebSocket connection'
        assert 'MESSAGE:GET_TEST_TASKS' in server_events, (
            'The server did not receive the exact GET_TEST_TASKS command'
        )
        assert server_stopped and not leaked_after_run, (
            f'build_server.py was not cleanly killed after orchestrate.sh exited: {leaked_after_run}'
        )
    finally:
        for pid in server_pids():
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass
        for path, backup in backups.items():
            if backup is None:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            else:
                data, mode = backup
                with open(path, 'wb') as f:
                    f.write(data)
                os.chmod(path, mode)
        for path in (server_log, client_log):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
