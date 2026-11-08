#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import ctypes
import http.client
import importlib
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import grpc

BASE = Path('/home/user/project')
SERVER_PROC = None
PROXY_PROC = None
PB_DIR = Path('/tmp/verifier_pb')


def test_project_structure():
    """Preserve the original required structure assertions."""
    base_dir = '/home/user/project'
    assert os.path.exists(base_dir), f'Directory {base_dir} is missing.'

    c_lib = os.path.join(base_dir, 'c_src', 'libtransform.so')
    assert os.path.exists(c_lib), f'C shared library {c_lib} is missing.'

    proto_dir = os.path.join(base_dir, 'proto')
    assert os.path.exists(proto_dir), f'Protobuf directory {proto_dir} is missing.'
    assert any(f.endswith('.proto') for f in os.listdir(proto_dir)), 'No .proto file found in proto directory.'

    go_server = os.path.join(base_dir, 'go_server', 'server')
    assert os.path.exists(go_server), f'Go server binary {go_server} is missing.'

    proxy_script = os.path.join(base_dir, 'proxy', 'proxy.py')
    assert os.path.exists(proxy_script), f'Python proxy script {proxy_script} is missing.'


def test_result_bin_content():
    """Preserve the original exact result assertion."""
    result_file = '/home/user/project/result.bin'
    assert os.path.exists(result_file), f'Result file {result_file} is missing.'

    with open(result_file, 'rb') as f:
        actual_bytes = f.read()

    input_str = b'ORBITAL_DATA_STREAM_XYZ'
    expected_bytes = bytes(c ^ 0x42 for c in input_str)
    assert actual_bytes == expected_bytes, (
        f'Content of {result_file} is incorrect.\n'
        f'Expected hex: {expected_bytes.hex()}\n'
        f'Actual hex:   {actual_bytes.hex()}'
    )


def xor_expected(data):
    return bytes(value ^ 0x42 for value in data)


def kill_existing_project_services():
    me = os.getpid()
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == me:
            continue
        try:
            exe = os.readlink(entry / 'exe')
            cmdline = (entry / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
            cwd = os.readlink(entry / 'cwd')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        is_server = exe == str(BASE / 'go_server' / 'server')
        is_proxy = str(BASE / 'proxy' / 'proxy.py') in cmdline and cwd.startswith(str(BASE))
        if is_server or is_proxy:
            try:
                os.kill(int(entry.name), signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.5)


def compile_and_import_proto():
    proto = BASE / 'proto' / 'transform.proto'
    assert proto.is_file(), 'Required proto/transform.proto is missing.'
    PB_DIR.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [sys.executable, '-m', 'grpc_tools.protoc',
         f'-I{proto.parent}', f'--python_out={PB_DIR}',
         f'--grpc_python_out={PB_DIR}', str(proto)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f'transform.proto does not compile: {result.stderr}'
    sys.path.insert(0, str(PB_DIR))
    importlib.invalidate_caches()
    pb2 = importlib.import_module('transform_pb2')
    pb2_grpc = importlib.import_module('transform_pb2_grpc')
    assert hasattr(pb2, 'TransformRequest') and hasattr(pb2, 'TransformResponse')
    assert hasattr(pb2_grpc, 'TransformerStub'), 'Transformer gRPC service is missing.'
    return pb2, pb2_grpc


def start_server(pb2, pb2_grpc):
    global SERVER_PROC
    server_path = BASE / 'go_server' / 'server'
    assert server_path.is_file(), 'go_server/server is not a regular file.'
    assert os.access(server_path, os.X_OK), 'go_server/server is not executable.'
    assert server_path.read_bytes()[:4] == b'\x7fELF', 'go_server/server is not a compiled binary.'

    env = os.environ.copy()
    old_ld = env.get('LD_LIBRARY_PATH', '')
    env['LD_LIBRARY_PATH'] = str(BASE / 'c_src') + (':' + old_ld if old_ld else '')
    SERVER_PROC = subprocess.Popen(
        [str(server_path)], cwd=str(BASE / 'go_server'), env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )

    channel = grpc.insecure_channel('127.0.0.1:50051')
    stub = pb2_grpc.TransformerStub(channel)
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if SERVER_PROC.poll() is not None:
            raise AssertionError(f'Go server exited with status {SERVER_PROC.returncode}')
        try:
            payload = os.urandom(23)
            response = stub.Apply(pb2.TransformRequest(payload=payload), timeout=1)
            assert response.result == xor_expected(payload)
            return channel, stub
        except grpc.RpcError as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f'Go gRPC server did not become ready: {last_error}')


def proxy_environment():
    env = os.environ.copy()
    module_dirs = {str(BASE / 'proxy'), str(BASE / 'proto'), str(PB_DIR)}
    for generated in BASE.rglob('*_pb2.py'):
        module_dirs.add(str(generated.parent))
    existing = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = os.pathsep.join(sorted(module_dirs)) + (os.pathsep + existing if existing else '')
    return env


def start_proxy():
    global PROXY_PROC
    script = BASE / 'proxy' / 'proxy.py'
    assert script.is_file(), 'proxy/proxy.py is not a regular file.'
    PROXY_PROC = subprocess.Popen(
        [sys.executable, str(script)], cwd=str(script.parent), env=proxy_environment(),
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )


def http_post(payload, timeout=3):
    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=timeout)
    try:
        conn.request('POST', '/', body=payload,
                     headers={'Content-Type': 'application/octet-stream',
                              'Content-Length': str(len(payload))})
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


def wait_for_proxy():
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if PROXY_PROC.poll() is not None:
            raise AssertionError(f'Python proxy exited with status {PROXY_PROC.returncode}')
        payload = os.urandom(19)
        try:
            status, body = http_post(payload, timeout=2)
            if status == 200 and body == xor_expected(payload):
                return
            last_error = AssertionError(f'HTTP status/body mismatch: {status}, {body.hex()}')
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f'Python proxy did not become ready: {last_error}')


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def test_runtime_c_grpc_and_proxy_pipeline():
    global SERVER_PROC, PROXY_PROC
    kill_existing_project_services()

    # Execute the submitted shared library on verifier-chosen binary inputs.
    c_dir = BASE / 'c_src'
    assert (c_dir / 'transform.c').is_file(), 'c_src/transform.c is missing.'
    assert (c_dir / 'transform.h').is_file(), 'c_src/transform.h is missing.'
    library = ctypes.CDLL(str(c_dir / 'libtransform.so'))
    transform = library.transform_data
    transform.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int]
    transform.restype = None
    for payload in [b'\x00\xff\x42\x80', os.urandom(1), os.urandom(257)]:
        array = (ctypes.c_ubyte * len(payload)).from_buffer_copy(payload)
        transform(array, len(payload))
        assert bytes(array) == xor_expected(payload), 'C transform_data returned incorrect bytes.'

    server_source = (BASE / 'go_server' / 'server.go')
    assert server_source.is_file(), 'go_server/server.go is missing.'
    source_text = server_source.read_text(errors='ignore')
    assert 'import "C"' in source_text or "import 'C'" in source_text, 'server.go does not use CGO.'
    assert 'transform_data' in source_text, 'server.go does not call the C transform_data function.'

    pb2, pb2_grpc = compile_and_import_proto()
    channel, stub = start_server(pb2, pb2_grpc)

    # Exercise concurrent direct gRPC calls with unpredictable binary payloads.
    payloads = [os.urandom(31 + i) for i in range(8)] + [b'\x00A\x00B\xff']
    def grpc_apply(payload):
        response = stub.Apply(pb2.TransformRequest(payload=payload), timeout=5)
        return response.result
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(grpc_apply, payloads))
    assert results == [xor_expected(p) for p in payloads]

    start_proxy()
    wait_for_proxy()
    for payload in [os.urandom(47), b'embedded\x00null\xffbytes', os.urandom(513)]:
        status, body = http_post(payload, timeout=5)
        assert status == 200, f'Proxy returned HTTP {status}.'
        assert body == xor_expected(payload), 'Proxy pipeline returned incorrect bytes.'

    # A real HTTP-to-gRPC proxy must not keep producing valid responses while
    # its Go gRPC backend is unavailable.
    channel.close()
    stop_process(SERVER_PROC)
    unavailable_payload = os.urandom(37)
    backend_was_required = False
    try:
        status, body = http_post(unavailable_payload, timeout=3)
        backend_was_required = not (status == 200 and body == xor_expected(unavailable_payload))
    except Exception:
        backend_was_required = True
    assert backend_was_required, 'Proxy produced the answer without the Go gRPC backend.'

    # Restore both required background services and verify the pipeline again.
    channel, stub = start_server(pb2, pb2_grpc)
    if PROXY_PROC.poll() is not None:
        start_proxy()
    wait_for_proxy()
    final_payload = os.urandom(61)
    status, body = http_post(final_payload, timeout=5)
    assert status == 200 and body == xor_expected(final_payload)
    channel.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
