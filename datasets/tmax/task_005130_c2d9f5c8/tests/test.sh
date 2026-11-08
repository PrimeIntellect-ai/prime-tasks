#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import signal
import subprocess
import sys
import time
import uuid

import pytest


def _stop_existing_servers():
    targets = []
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ')
            if b'/app/server.py' in cmdline:
                targets.append(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    for pid in targets:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in targets:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _server_processes():
    result = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ')
            if b'/app/server.py' in cmdline:
                result.append(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


@pytest.fixture(scope='session', autouse=True)
def run_submitted_service():
    script = '/app/run_service.sh'
    assert os.path.isfile(script), f'Expected script {script} to exist.'
    assert os.access(script, os.X_OK), f'Expected script {script} to be executable.'

    _stop_existing_servers()
    for path in (
        '/app/dep_resolver/resolve.o',
        '/app/dep_resolver/libresolver.so',
        '/app/resolver_pb2.py',
        '/app/resolver_pb2_grpc.py',
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        completed = subprocess.run(
            [script],
            cwd='/app',
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('/app/run_service.sh did not finish orchestration within 30 seconds.')
    except OSError as exc:
        pytest.fail(f'Could not execute /app/run_service.sh: {exc}')

    assert completed.returncode == 0, f'/app/run_service.sh exited with {completed.returncode}.'
    assert os.path.isfile('/app/dep_resolver/libresolver.so'), 'The script did not build libresolver.so.'
    assert os.path.isfile('/app/resolver_pb2.py'), 'The script did not generate resolver_pb2.py.'
    assert os.path.isfile('/app/resolver_pb2_grpc.py'), 'The script did not generate resolver_pb2_grpc.py.'

    import grpc
    channel = grpc.insecure_channel('127.0.0.1:50505')
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
    except grpc.FutureTimeoutError:
        pytest.fail('The service started by /app/run_service.sh did not listen on port 50505.')

    assert _server_processes(), '/app/run_service.sh did not leave /app/server.py running.'
    yield


def test_c_library_built():
    path = '/app/dep_resolver/libresolver.so'
    assert os.path.isfile(path), f'Expected shared library {path} to be built.'
    lib = ctypes.CDLL(path)
    lib.validate_graph.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.validate_graph.restype = ctypes.c_int
    assert lib.validate_graph(b'lib-core', b'1.2.0') == 1
    assert lib.validate_graph(b'not-lib-core', b'1.2.0') == 0


def test_proto_file_exists():
    path = '/app/proto/resolver.proto'
    assert os.path.isfile(path), f'Expected protobuf file {path} to exist.'
    with open(path, 'r') as f:
        content = f.read()
    assert 'syntax' in content and 'proto3' in content, 'Proto file should use proto3 syntax.'
    assert 'package ci;' in content, "Proto file should have package 'ci'."
    assert 'service DependencyResolver' in content, "Proto file should define 'DependencyResolver' service."
    assert re.search(r'rpc\s+ResolveGraph\s*\(\s*ResolveRequest\s*\)\s*returns\s*\(\s*ResolveResponse\s*\)\s*;', content)

    sys.path.insert(0, '/app')
    import resolver_pb2

    descriptor = resolver_pb2.DESCRIPTOR
    assert descriptor.package == 'ci'
    assert set(descriptor.services_by_name) == {'DependencyResolver'}
    service = descriptor.services_by_name['DependencyResolver']
    assert len(service.methods) == 1
    method = service.methods[0]
    assert method.name == 'ResolveGraph'
    assert method.input_type.full_name == 'ci.ResolveRequest'
    assert method.output_type.full_name == 'ci.ResolveResponse'

    request = descriptor.message_types_by_name['ResolveRequest']
    assert [(f.name, f.number, f.type) for f in request.fields] == [
        ('package_name', 1, f.TYPE_STRING),
        ('current_version', 2, f.TYPE_STRING),
    ]
    response = descriptor.message_types_by_name['ResolveResponse']
    assert [(f.name, f.number, f.type) for f in response.fields] == [
        ('is_valid', 1, f.TYPE_BOOL),
        ('resolved_tree', 2, f.TYPE_STRING),
    ]


def test_run_service_script():
    path = '/app/run_service.sh'
    assert os.path.isfile(path), f'Expected script {path} to exist.'
    assert os.access(path, os.X_OK), f'Expected script {path} to be executable.'


def _extract_token():
    text = subprocess.check_output(['tesseract', '/app/pipeline_specs.png', 'stdout'], text=True)
    match = re.search(r'TOKEN:\s*([^\s]+)', text)
    assert match, 'Could not derive the authentication token from pipeline_specs.png.'
    return match.group(1)


def _stub():
    sys.path.insert(0, '/app')
    import grpc
    import resolver_pb2_grpc
    channel = grpc.insecure_channel('127.0.0.1:50505')
    return grpc, resolver_pb2_grpc.DependencyResolverStub(channel)


def test_grpc_service():
    sys.path.insert(0, '/app')
    try:
        import grpc
    except ImportError:
        pytest.fail('grpcio is not installed.')
    try:
        import resolver_pb2
        import resolver_pb2_grpc
    except ImportError as e:
        pytest.fail(f'Could not import generated protobuf modules from /app: {e}')

    channel = grpc.insecure_channel('127.0.0.1:50505')
    stub = resolver_pb2_grpc.DependencyResolverStub(channel)
    request = resolver_pb2.ResolveRequest(package_name='lib-core', current_version='1.2.0')
    metadata = (('authorization', f'Bearer {_extract_token()}'),)
    try:
        response = stub.ResolveGraph(request, metadata=metadata, timeout=5)
    except grpc.RpcError as e:
        pytest.fail(f'gRPC call failed. Is the server running and accepting the auth token? Error: {e}')
    assert response.is_valid is True, 'Expected is_valid to be True in the response.'
    assert response.resolved_tree == 'lib-core@1.2.0->deps@ok', f'Unexpected resolved_tree in the response: {response.resolved_tree}'


def test_grpc_authentication_and_dynamic_resolution():
    import grpc
    import resolver_pb2
    import resolver_pb2_grpc

    channel = grpc.insecure_channel('127.0.0.1:50505')
    stub = resolver_pb2_grpc.DependencyResolverStub(channel)
    token = _extract_token()

    with pytest.raises(grpc.RpcError) as exc:
        stub.ResolveGraph(
            resolver_pb2.ResolveRequest(package_name='lib-core', current_version='1.2.0'),
            metadata=(('authorization', 'Bearer definitely-wrong-token'),),
            timeout=5,
        )
    assert exc.value.code() == grpc.StatusCode.UNAUTHENTICATED

    lib = ctypes.CDLL('/app/dep_resolver/libresolver.so')
    lib.validate_graph.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.validate_graph.restype = ctypes.c_int

    cases = []
    for _ in range(4):
        cases.append(('lib-core', str(uuid.uuid4())))
        cases.append((f'pkg-{uuid.uuid4().hex}', str(uuid.uuid4())))

    for package_name, version in cases:
        expected_valid = bool(lib.validate_graph(package_name.encode(), version.encode()))
        expected_tree = f'{package_name}@{version}->deps@ok' if expected_valid else 'invalid'
        response = stub.ResolveGraph(
            resolver_pb2.ResolveRequest(package_name=package_name, current_version=version),
            metadata=(('authorization', f'Bearer {token}'),),
            timeout=5,
        )
        assert response.is_valid is expected_valid
        assert response.resolved_tree == expected_tree

    mapped = False
    for pid in _server_processes():
        try:
            with open(f'/proc/{pid}/maps', 'r') as f:
                if '/app/dep_resolver/libresolver.so' in f.read():
                    mapped = True
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert mapped, 'The running /app/server.py process did not load libresolver.so.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
