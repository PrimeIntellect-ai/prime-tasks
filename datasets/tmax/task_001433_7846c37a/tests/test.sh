#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import asyncio
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import time

APP = Path('/home/user/app')
VENV_PYTHON = APP / 'venv/bin/python'
DIAGNOSTICS = APP / 'diagnostics.json'
SERVICE = APP / 'service.py'
CLIENT = APP / 'client.py'
EXPECTED_CLIENT = '''import asyncio
import aiohttp
import time

async def main():
    async with aiohttp.ClientSession() as session:
        # 1. Send 5 valid requests
        values = [10, 20, 50, 80, 100]
        for v in values:
            async with session.post('http://127.0.0.1:8080/ingest', json={"value": v}) as resp:
                await resp.read()

        # 2. Send malformed request
        try:
            async with session.post('http://127.0.0.1:8080/ingest', data="{bad_json: True}") as resp:
                assert resp.status == 400, "Service did not return 400 for bad JSON"
        except aiohttp.ClientConnectionError:
            print("Connection dropped! Service crashed on bad JSON.")
            return

        # 3. Send 3 requests that are cancelled immediately (triggers CancelledError in handler)
        for i in range(3):
            try:
                task = asyncio.create_task(session.post('http://127.0.0.1:8080/ingest', json={"value": 999}))
                await asyncio.sleep(0.01) # let it connect
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            except Exception as e:
                pass

        # wait a bit for cancelled tasks to settle
        await asyncio.sleep(0.5)
        print("Client finished workload.")

if __name__ == '__main__':
    asyncio.run(main())
'''


def expected_ema(values):
    result = 0.0
    alpha = 0.5
    for value in values:
        result = (value * alpha) + (result * (1 - alpha))
    return result


def check_diagnostics(values):
    assert DIAGNOSTICS.is_file(), (
        'The diagnostics.json file was not generated. Did you send the SIGUSR1 signal to the service?'
    )
    try:
        with DIAGNOSTICS.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError('diagnostics.json does not contain valid JSON.') from exc

    assert 'active_tasks' in data, "diagnostics.json is missing the 'active_tasks' key."
    assert data['active_tasks'] == 0, (
        f"Task leak detected: {data['active_tasks']} active tasks remaining. Expected 0."
    )
    assert 'ema' in data, "diagnostics.json is missing the 'ema' key."
    wanted = expected_ema(values)
    assert abs(data['ema'] - wanted) < 0.001, (
        f'Incorrect EMA calculation. Expected around {wanted}, but got {data["ema"]}.'
    )


def wait_for_service(proc):
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f'service.py exited before accepting requests (status {proc.returncode})')
        try:
            with socket.create_connection(('127.0.0.1', 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError('service.py did not start listening on port 8080')


def start_service():
    log = tempfile.TemporaryFile(mode='w+b')
    proc = subprocess.Popen(
        [str(VENV_PYTHON), str(SERVICE)],
        cwd=str(APP),
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    try:
        wait_for_service(proc)
    except Exception:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        log.seek(0)
        output = log.read().decode(errors='replace')
        log.close()
        raise AssertionError(f'Failed to start service.py:\n{output}')
    return proc, log


def stop_service(proc, log, dump=True):
    try:
        if proc.poll() is None:
            if dump:
                proc.send_signal(signal.SIGUSR1)
                proc.wait(timeout=10)
            else:
                proc.terminate()
                proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise AssertionError('service.py did not terminate after SIGUSR1')
    finally:
        log.close()


def run_random_live_test(values):
    helper = r'''
import asyncio, aiohttp, json, sys

async def main():
    values = json.loads(sys.argv[1])
    ema = 0.0
    async with aiohttp.ClientSession() as session:
        for value in values:
            async with session.post('http://127.0.0.1:8080/ingest', json={'value': value}) as response:
                body = await response.text()
                assert response.status == 200, (response.status, body)
                data = json.loads(body)
                ema = value * 0.5 + ema * 0.5
                assert abs(data['ema'] - ema) < 0.001, (data, ema)
        async with session.post('http://127.0.0.1:8080/ingest', data='{not valid json') as response:
            body = await response.text()
            assert response.status == 400, (response.status, body)
            assert body == 'Invalid JSON', repr(body)

asyncio.run(main())
'''
    if DIAGNOSTICS.exists():
        DIAGNOSTICS.unlink()
    proc, log = start_service()
    try:
        result = subprocess.run(
            [str(VENV_PYTHON), '-c', helper, json.dumps(values)],
            cwd=str(APP), text=True, capture_output=True, timeout=30
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert proc.poll() is None, 'service.py crashed while handling requests'
        stop_service(proc, log, dump=True)
        log = None
        check_diagnostics(values)
    finally:
        if proc.poll() is None:
            stop_service(proc, log, dump=False)


def run_required_client():
    if DIAGNOSTICS.exists():
        DIAGNOSTICS.unlink()
    proc, log = start_service()
    try:
        result = subprocess.run(
            [str(VENV_PYTHON), str(CLIENT)],
            cwd=str(APP), text=True, capture_output=True, timeout=45
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert 'Client finished workload.' in result.stdout, (
            'client.py did not successfully finish the required workload:\n' + result.stdout + result.stderr
        )
        assert proc.poll() is None, 'service.py crashed during the required client workload'
        stop_service(proc, log, dump=True)
        log = None
        check_diagnostics([10, 20, 50, 80, 100])
    finally:
        if proc.poll() is None:
            stop_service(proc, log, dump=False)


# Preserve the original verifier's assertions against the agent's submitted report.
check_diagnostics([10, 20, 50, 80, 100])

assert SERVICE.is_file(), 'service.py is missing'
assert CLIENT.is_file(), 'client.py is missing'
assert CLIENT.read_text() == EXPECTED_CLIENT, 'client.py was modified'
assert VENV_PYTHON.exists(), 'The virtual environment at /home/user/app/venv is missing'
assert (APP / 'venv/pyvenv.cfg').is_file(), 'venv is not a Python virtual environment'

venv_check = subprocess.run(
    [str(VENV_PYTHON), '-c',
     "import sys,aiohttp,pandas,numpy; assert sys.prefix == '/home/user/app/venv'"],
    text=True, capture_output=True, timeout=30
)
assert venv_check.returncode == 0, 'Required dependencies are not installed in the venv:\n' + venv_check.stderr
pip_check = subprocess.run(
    [str(VENV_PYTHON), '-m', 'pip', 'check'], text=True, capture_output=True, timeout=30
)
assert pip_check.returncode == 0, 'The installed dependencies still conflict:\n' + pip_check.stdout + pip_check.stderr

# Exercise cancellation directly and verify both task cancellation and set cleanup.
cancel_test = r'''
import asyncio, importlib.util
spec = importlib.util.spec_from_file_location('submitted_service', '/home/user/app/service.py')
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)
class Request:
    async def text(self):
        return '{"value": 321}'
async def main():
    service.active_tasks.clear()
    service.ema_state = 0.0
    handler = asyncio.create_task(service.handle_request(Request()))
    await asyncio.sleep(0.02)
    assert len(service.active_tasks) == 1
    inner = next(iter(service.active_tasks))
    handler.cancel()
    try:
        await handler
    except asyncio.CancelledError:
        pass
    await asyncio.sleep(0)
    assert inner.done() and inner.cancelled(), 'processing task continued after handler cancellation'
    assert len(service.active_tasks) == 0, 'cancelled task remains in active_tasks'
asyncio.run(main())
'''
cancel_result = subprocess.run(
    [str(VENV_PYTHON), '-c', cancel_test], cwd=str(APP), text=True,
    capture_output=True, timeout=20
)
assert cancel_result.returncode == 0, cancel_result.stdout + cancel_result.stderr

# Use unpredictable values so a prewritten diagnostics file or hardcoded workload cannot pass.
random_values = [secrets.randbelow(181) - 80 for _ in range(6)]
run_random_live_test(random_values)

# Finally execute the required shipped workload and leave its fresh signal-generated report in place.
run_required_client()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
