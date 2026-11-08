#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib
import json
import os
import pathlib
import pwd
import socket
import subprocess
import sys
import tempfile
import time

import pytest

SERVICE_DIR = '/home/user/polyglot_service'


def test_protobuf_files_generated():
    pb2_path = os.path.join(SERVICE_DIR, 'math_ops_pb2.py')
    grpc_path = os.path.join(SERVICE_DIR, 'math_ops_pb2_grpc.py')

    assert os.path.isfile(pb2_path), f"Expected protobuf generated file is missing: {pb2_path}"
    assert os.path.isfile(grpc_path), f"Expected gRPC generated file is missing: {grpc_path}"

    sys.path.insert(0, SERVICE_DIR)
    try:
        pb2 = importlib.import_module('math_ops_pb2')
        pb2_grpc = importlib.import_module('math_ops_pb2_grpc')
        request = pb2.MagicRequest(x=7, y=9)
        assert request.x == 7 and request.y == 9
        assert hasattr(pb2_grpc, 'MagicServiceStub')
        assert hasattr(pb2_grpc, 'MagicServiceServicer')
        assert 'math_ops.MagicService' in pb2.DESCRIPTOR.services_by_name['MagicService'].full_name
    finally:
        sys.path.pop(0)


def test_shared_library_compiled():
    so_path = os.path.join(SERVICE_DIR, 'libmath.so')
    assert os.path.isfile(so_path), f"Shared library is missing: {so_path}"
    with open(so_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'libmath.so is not an ELF shared library.'

    lib = ctypes.CDLL(so_path)
    fn = lib.calculate_magic
    fn.argtypes = [ctypes.c_int, ctypes.c_int]
    fn.restype = ctypes.c_int
    for x, y in [(7, 9), (-11, 5), (13, 17)]:
        assert fn(x, y) == x * y, f'calculate_magic({x}, {y}) returned the wrong value.'


def test_memory_leak_fixed():
    c_path = os.path.join(SERVICE_DIR, 'libmath.c')
    assert os.path.isfile(c_path), f"C source file is missing: {c_path}"

    with open(c_path, 'r') as f:
        content = f.read()
    assert 'free(' in content, "The memory leak in libmath.c does not appear to be fixed (missing 'free(' statement)."

    harness = r'''
#include <stdio.h>
int calculate_magic(int, int);
int main(void) {
    for (int i = 1; i <= 20; ++i) {
        int x = i + 2;
        int y = i * 3 - 4;
        if (calculate_magic(x, y) != x * y) return 2;
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, 'harness.c')
        executable = os.path.join(td, 'leak_check')
        pathlib.Path(harness_path).write_text(harness)
        build = subprocess.run(
            ['gcc', '-O0', '-g', '-fno-omit-frame-pointer', '-fsanitize=address',
             harness_path, c_path, '-o', executable],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert build.returncode == 0, f'libmath.c could not be compiled with AddressSanitizer:\n{build.stderr}'
        env = os.environ.copy()
        env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1:exitcode=99'
        env['LSAN_OPTIONS'] = 'exitcode=99'
        run = subprocess.run([executable], env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, timeout=15)
        assert run.returncode == 0, f'AddressSanitizer detected a memory error or leak:\n{run.stderr}'


def test_client_performs_grpc_exchange_and_result_json():
    client_path = os.path.join(SERVICE_DIR, 'test_client.py')
    result_path = '/home/user/result.json'
    assert os.path.isfile(client_path), f'Expected test client is missing: {client_path}'

    # Remove any stale server and any result that could have been fabricated earlier.
    subprocess.run(['pkill', '-f', '/home/user/polyglot_service/server.py'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        os.unlink(result_path)
    except FileNotFoundError:
        pass

    private_dir = tempfile.mkdtemp(prefix='grpc_verifier_', dir='/tmp')
    os.chmod(private_dir, 0o700)
    marker = os.path.join(private_dir, 'observed.json')
    wrapper = os.path.join(private_dir, 'verified_server.py')
    pathlib.Path(wrapper).write_text(r'''
import json
import os
import sys
from concurrent import futures
import grpc
sys.path.insert(0, os.environ['SERVICE_DIR'])
import math_ops_pb2_grpc
import server as submitted_server

class ObservedService(submitted_server.MagicServiceServicer):
    def ComputeMagic(self, request, context):
        response = super().ComputeMagic(request, context)
        with open(os.environ['MARKER'], 'w') as f:
            json.dump({'x': request.x, 'y': request.y, 'result': response.result}, f)
        return response

srv = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
math_ops_pb2_grpc.add_MagicServiceServicer_to_server(ObservedService(), srv)
if srv.add_insecure_port('[::]:50051') == 0:
    raise RuntimeError('could not bind gRPC port 50051')
srv.start()
srv.wait_for_termination()
''')

    env = os.environ.copy()
    env['SERVICE_DIR'] = SERVICE_DIR
    env['MARKER'] = marker
    server_proc = subprocess.Popen(
        [sys.executable, wrapper], cwd=SERVICE_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.time() + 10
        while time.time() < deadline:
            if server_proc.poll() is not None:
                out, err = server_proc.communicate()
                pytest.fail(f'gRPC server failed to start:\n{out}\n{err}')
            try:
                with socket.create_connection(('127.0.0.1', 50051), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            pytest.fail('gRPC server did not become ready on port 50051.')

        user = pwd.getpwnam('user')
        def demote():
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        client = subprocess.run(
            [sys.executable, client_path], cwd=SERVICE_DIR, env=os.environ.copy(),
            preexec_fn=demote, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20)
        assert client.returncode == 0, f'test_client.py failed:\n{client.stdout}\n{client.stderr}'

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.isfile(marker):
            time.sleep(0.05)
        assert os.path.isfile(marker), 'test_client.py did not make a ComputeMagic RPC call.'

        with open(marker) as f:
            observed = json.load(f)
        solutions = [(x, 120 - x) for x in range(-10000, 10001)
                     if x > 120 - x and x * (120 - x) == 3456]
        assert len(solutions) == 1, 'Verifier could not derive a unique constraint solution.'
        expected_x, expected_y = solutions[0]
        assert observed == {'x': expected_x, 'y': expected_y,
                            'result': expected_x * expected_y}, \
            f'Unexpected RPC request or response: {observed}'
    finally:
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_proc.kill()
            server_proc.wait()

    assert os.path.isfile(result_path), f"Result file is missing: {result_path}"
    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} is not valid JSON.")

    assert 'x' in data, "Result JSON missing 'x' key."
    assert 'y' in data, "Result JSON missing 'y' key."
    assert 'result' in data, "Result JSON missing 'result' key."
    assert data['x'] == expected_x, f"Expected x={expected_x}, got {data['x']}."
    assert data['y'] == expected_y, f"Expected y={expected_y}, got {data['y']}."
    assert data['result'] == expected_x * expected_y, \
        f"Expected result={expected_x * expected_y}, got {data['result']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
