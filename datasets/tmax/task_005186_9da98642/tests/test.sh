#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import importlib
import json
import math
import os
import secrets
import signal
import subprocess
import sys
import time
from pathlib import Path

import grpc
import pytest
import websockets

RELEASE = Path('/home/user/release')
LOG = Path('/home/user/deploy_log.txt')


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except Exception:
            pass


def clear_existing_servers():
    subprocess.run(['pkill', '-f', 'grpc_server.py'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-f', 'ws_server.py'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def start_script(name, env=None):
    return subprocess.Popen(
        [sys.executable, str(RELEASE / name)],
        cwd=str(RELEASE), env=env, start_new_session=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def wait_for_grpc(proc, timeout=10):
    channel = grpc.insecure_channel('localhost:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=timeout)
    except Exception:
        status = proc.poll()
        pytest.fail(f'gRPC server did not become ready (exit status {status})')
    return channel


def wait_for_file(path, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if Path(path).exists():
            return
        time.sleep(0.05)
    pytest.fail(f'Timed out waiting for {path}')


def run_deploy_check():
    result = subprocess.run(
        [sys.executable, str(RELEASE / 'deploy_check.py')],
        cwd=str(RELEASE), text=True, capture_output=True, timeout=15,
    )
    assert result.returncode == 0, (
        f'deploy_check.py failed with status {result.returncode}:\n'
        f'{result.stdout}\n{result.stderr}'
    )


def test_complete_deployment_workflow():
    clear_existing_servers()

    # Preserve the original existence and source assertions.
    so_path = RELEASE / 'libprocessor.so'
    assert os.path.exists(so_path), f'File {so_path} does not exist. The C library was not compiled.'

    pb2_path = RELEASE / 'data_pb2.py'
    pb2_grpc_path = RELEASE / 'data_pb2_grpc.py'
    assert os.path.exists(pb2_path), f'File {pb2_path} does not exist. gRPC stubs were not generated.'
    assert os.path.exists(pb2_grpc_path), f'File {pb2_grpc_path} does not exist. gRPC stubs were not generated.'

    server_path = RELEASE / 'grpc_server.py'
    assert os.path.exists(server_path), f'File {server_path} is missing.'
    content = server_path.read_text()
    assert 'ctypes.c_double' in content, 'The ABI mismatch in grpc_server.py does not appear to be fixed to use ctypes.c_double.'

    # The library must be a real loadable ELF shared object and implement the C source behavior.
    assert so_path.is_file() and so_path.read_bytes()[:4] == b'\x7fELF', 'libprocessor.so is not an ELF shared library.'
    lib = ctypes.CDLL(str(so_path))
    lib.process_data.argtypes = [ctypes.c_double]
    lib.process_data.restype = ctypes.c_double
    rng = secrets.SystemRandom()
    direct_inputs = [rng.uniform(-30.0, -0.25), rng.uniform(0.25, 30.0), rng.randint(1, 100) + 0.375]
    for value in direct_inputs:
        assert math.isclose(lib.process_data(value), value * 2.5, rel_tol=1e-12, abs_tol=1e-12)

    # The generated modules must import and describe the requested protobuf service.
    sys.path.insert(0, str(RELEASE))
    os.chdir(RELEASE)
    data_pb2 = importlib.import_module('data_pb2')
    data_pb2_grpc = importlib.import_module('data_pb2_grpc')
    assert data_pb2.DESCRIPTOR.services_by_name['DataProcessor'].methods_by_name['Process']
    assert hasattr(data_pb2_grpc, 'DataProcessorStub')

    # Check the actual ctypes declarations, not merely the presence of a token in the source.
    grpc_server_module = importlib.import_module('grpc_server')
    assert grpc_server_module.lib.process_data.argtypes == [ctypes.c_double]
    assert grpc_server_module.lib.process_data.restype is ctypes.c_double

    # Launch the submitted gRPC server and exercise unpredictable fractional inputs end-to-end.
    grpc_proc = start_script('grpc_server.py')
    try:
        channel = wait_for_grpc(grpc_proc)
        stub = data_pb2_grpc.DataProcessorStub(channel)
        rpc_inputs = [rng.uniform(-20.0, -0.1), rng.uniform(0.1, 20.0), rng.randint(1, 40) + 0.625]
        for value in rpc_inputs:
            response = stub.Process(data_pb2.DataRequest(value=value), timeout=5)
            assert math.isclose(response.result, value * 2.5, rel_tol=1e-12, abs_tol=1e-12), (
                f'Process({value}) returned {response.result}, expected {value * 2.5}'
            )
        channel.close()
    finally:
        stop_process(grpc_proc)

    # Verify that the submitted WebSocket server itself creates the deployment log from a message.
    if LOG.exists():
        LOG.unlink()
    ws_proc = start_script('ws_server.py')
    ws_message = f'PROBE-{secrets.token_hex(12)}'

    async def send_probe():
        deadline = time.time() + 10
        while True:
            try:
                async with websockets.connect('ws://localhost:8765') as websocket:
                    await websocket.send(ws_message)
                    return
            except OSError:
                if time.time() >= deadline:
                    raise
                await asyncio.sleep(0.1)

    try:
        asyncio.run(send_probe())
        wait_for_file(LOG)
        assert LOG.read_text() == ws_message
    finally:
        stop_process(ws_proc)

    # Run deploy_check against verifier-controlled services. The result is chosen at
    # verification time, so a hardcoded SUCCESS message cannot pass.
    clear_existing_servers()
    capture = Path(f'/tmp/deploy_capture_{secrets.token_hex(8)}.json')
    ready = Path(f'/tmp/deploy_ready_{secrets.token_hex(8)}')
    returned_value = rng.randint(-150, 150) / 8.0
    if returned_value == 10.0:
        returned_value = 10.125

    mock_source = r'''
import asyncio
import json
import os
from concurrent import futures
import grpc
import websockets
import data_pb2
import data_pb2_grpc

capture = os.environ['CAPTURE']
ready = os.environ['READY']
returned = float(os.environ['RETURNED'])
request_values = []
done = None

class Servicer(data_pb2_grpc.DataProcessorServicer):
    def Process(self, request, context):
        request_values.append(request.value)
        return data_pb2.DataResponse(result=returned)

async def handler(websocket):
    message = await websocket.recv()
    with open(capture, 'w') as f:
        json.dump({'requests': request_values, 'message': message}, f)
    done.set()

async def main():
    global done
    done = asyncio.Event()
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
    data_pb2_grpc.add_DataProcessorServicer_to_server(Servicer(), server)
    assert server.add_insecure_port('[::]:50051') != 0
    server.start()
    try:
        async with websockets.serve(handler, 'localhost', 8765):
            open(ready, 'w').close()
            await asyncio.wait_for(done.wait(), timeout=20)
    finally:
        server.stop(0).wait()

asyncio.run(main())
'''
    mock_path = Path(f'/tmp/mock_endpoints_{secrets.token_hex(8)}.py')
    mock_path.write_text(mock_source)
    env = os.environ.copy()
    env.update({'CAPTURE': str(capture), 'READY': str(ready), 'RETURNED': repr(returned_value)})
    mock_proc = subprocess.Popen(
        [sys.executable, str(mock_path)], cwd=str(RELEASE), env=env,
        start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_file(ready)
        run_deploy_check()
        wait_for_file(capture)
        observed = json.loads(capture.read_text())
        assert observed['requests'] == [4.0], 'deploy_check.py did not call Process with exactly 4.0.'
        assert observed['message'] == f'SUCCESS: {returned_value}', (
            'deploy_check.py did not format and send the float returned by the gRPC service.'
        )
    finally:
        stop_process(mock_proc)
        mock_path.unlink(missing_ok=True)
        ready.unlink(missing_ok=True)
        capture.unlink(missing_ok=True)

    # Finally execute the requested submitted servers and deployment check together.
    clear_existing_servers()
    if LOG.exists():
        LOG.unlink()
    ws_proc = start_script('ws_server.py')
    grpc_proc = start_script('grpc_server.py')
    try:
        channel = wait_for_grpc(grpc_proc)
        channel.close()
        time.sleep(0.5)
        assert ws_proc.poll() is None, 'ws_server.py exited before deployment validation.'
        run_deploy_check()
        wait_for_file(LOG)

        # Preserve the original final-state assertion exactly in substance.
        log_path = '/home/user/deploy_log.txt'
        assert os.path.exists(log_path), f'File {log_path} does not exist. The deployment check was not completed successfully.'
        with open(log_path, 'r') as f:
            final_content = f.read().strip()
        assert final_content == 'SUCCESS: 10.0', f"Expected 'SUCCESS: 10.0' in {log_path}, but got '{final_content}'"
    finally:
        stop_process(grpc_proc)
        stop_process(ws_proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
