#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
from pathlib import Path
import random
import re
import string
import subprocess
import sys
import tempfile
import urllib.parse
import zlib

import pytest
import requests

WORKSPACE = Path('/app/workspace')
sys.path.insert(0, str(WORKSPACE))

EXPECTED_C_SOURCE = '''#include <stdint.h>
#include <string.h>

uint32_t compute_crc32(const char *s) {
    uint32_t crc = 0xFFFFFFFF;
    while (*s) {
        crc ^= *s++;
        for (int i = 0; i < 8; i++) {
            crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
        }
    }
    return ~crc;
}
'''


def _listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                local_port = int(fields[1].split(':')[1], 16)
                if local_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def _random_cases(count=8):
    cases = []
    alphabet = string.ascii_letters + string.digits + ' _-+&='
    while len(cases) < count:
        value = ''.join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(12, 50)))
        crc = zlib.crc32(value.encode('utf-8')) & 0xffffffff
        # expected_crc is int32, so valid test values must fit its positive range.
        if crc <= 0x7fffffff:
            cases.append((value, crc))
    return cases


def test_required_artifacts_sources_and_build():
    c_source = WORKSPACE / 'vendored_crc' / 'fastcrc.c'
    makefile = WORKSPACE / 'vendored_crc' / 'Makefile'
    library = WORKSPACE / 'vendored_crc' / 'libfastcrc.so'
    proto = WORKSPACE / 'crc.proto'
    server_source = WORKSPACE / 'server.py'

    assert c_source.read_text() == EXPECTED_C_SOURCE, 'fastcrc.c was modified'
    assert makefile.is_file(), 'vendored_crc/Makefile is missing'
    make_text = makefile.read_text()
    assert '/usr/bin/false' not in make_text
    assert 'fastcrc.c' in make_text and 'libfastcrc.so' in make_text and '-shared' in make_text

    # The backend that owns the gRPC listening socket must actually have loaded
    # the requested shared library, rather than merely emulating the four fixed answers.
    backend_pids = _listener_pids(50051)
    assert backend_pids, 'No process owns a listening socket on port 50051'
    loaded_by_backend = False
    for pid in backend_pids:
        try:
            maps = Path(f'/proc/{pid}/maps').read_text()
        except OSError:
            continue
        if '/app/workspace/vendored_crc/libfastcrc.so' in maps:
            loaded_by_backend = True
            break
    assert loaded_by_backend, 'The gRPC backend has not loaded libfastcrc.so'

    source_text = server_source.read_text()
    assert 'ctypes.CDLL' in source_text
    assert 'libfastcrc.so' in source_text
    assert 'compute_crc32' in source_text

    # Remove any pre-existing output so success requires the submitted Makefile
    # to recreate a usable shared library from the vendored package.
    if library.exists() or library.is_symlink():
        library.unlink()
    result = subprocess.run(
        ['make'], cwd=WORKSPACE / 'vendored_crc', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f'make failed:\n{result.stdout}'
    assert library.is_file(), 'make did not produce libfastcrc.so'
    assert library.read_bytes()[:4] == b'\x7fELF', 'libfastcrc.so is not an ELF library'

    lib = ctypes.CDLL(str(library))
    lib.compute_crc32.argtypes = [ctypes.c_char_p]
    lib.compute_crc32.restype = ctypes.c_uint32
    for value, expected in _random_cases(5):
        assert lib.compute_crc32(value.encode()) == expected

    assert proto.is_file(), 'crc.proto is missing'
    with tempfile.TemporaryDirectory() as generated:
        compile_result = subprocess.run(
            [sys.executable, '-m', 'grpc_tools.protoc', f'-I{WORKSPACE}',
             f'--python_out={generated}', f'--grpc_python_out={generated}', str(proto)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert compile_result.returncode == 0, f'crc.proto does not compile:\n{compile_result.stdout}'

    assert (WORKSPACE / 'crc_pb2.py').is_file()
    assert (WORKSPACE / 'crc_pb2_grpc.py').is_file()
    import crc_pb2
    descriptor = crc_pb2.DESCRIPTOR
    assert descriptor.package == 'crc'
    service = descriptor.services_by_name['ChecksumService']
    method = service.methods_by_name['Verify']
    assert method.input_type.full_name == 'crc.VerifyRequest'
    assert method.output_type.full_name == 'crc.VerifyResponse'
    request_fields = descriptor.message_types_by_name['VerifyRequest'].fields_by_name
    assert request_fields['data'].type == request_fields['data'].TYPE_STRING
    assert request_fields['expected_crc'].type == request_fields['expected_crc'].TYPE_INT32
    response_fields = descriptor.message_types_by_name['VerifyResponse'].fields_by_name
    assert response_fields['is_valid'].type == response_fields['is_valid'].TYPE_BOOL


def test_http_gateway_valid_crc():
    url = 'http://127.0.0.1:8080/verify?data=hello&crc=907060870'
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to HTTP gateway: {e}')
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f'Expected JSON response, got: {response.text}')
    assert data.get('valid') is True, f"Expected {{'valid': True}}, got {data}"


def test_http_gateway_invalid_crc():
    url = 'http://127.0.0.1:8080/verify?data=hello&crc=123'
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to HTTP gateway: {e}')
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f'Expected JSON response, got: {response.text}')
    assert data.get('valid') is False, f"Expected {{'valid': False}}, got {data}"


def test_grpc_backend():
    try:
        import grpc
        import crc_pb2
        import crc_pb2_grpc
    except ImportError as e:
        pytest.fail(f'Failed to import gRPC modules (agent may not have generated them correctly): {e}')
    try:
        with grpc.insecure_channel('127.0.0.1:50051') as channel:
            stub = crc_pb2_grpc.ChecksumServiceStub(channel)
            request = crc_pb2.VerifyRequest(data='world', expected_crc=980881731)
            response = stub.Verify(request, timeout=5)
    except grpc.RpcError as e:
        pytest.fail(f'gRPC call failed: {e}')
    assert response.is_valid is True, f"Expected is_valid=True for 'world' and 980881731, got {response.is_valid}"


def test_grpc_backend_invalid():
    try:
        import grpc
        import crc_pb2
        import crc_pb2_grpc
    except ImportError as e:
        pytest.fail(f'Failed to import gRPC modules: {e}')
    try:
        with grpc.insecure_channel('127.0.0.1:50051') as channel:
            stub = crc_pb2_grpc.ChecksumServiceStub(channel)
            request = crc_pb2.VerifyRequest(data='world', expected_crc=12345)
            response = stub.Verify(request, timeout=5)
    except grpc.RpcError as e:
        pytest.fail(f'gRPC call failed: {e}')
    assert response.is_valid is False, f"Expected is_valid=False for 'world' and 12345, got {response.is_valid}"


def test_dynamic_grpc_inputs():
    import grpc
    import crc_pb2
    import crc_pb2_grpc
    with grpc.insecure_channel('127.0.0.1:50051') as channel:
        stub = crc_pb2_grpc.ChecksumServiceStub(channel)
        for value, expected in _random_cases():
            valid = stub.Verify(crc_pb2.VerifyRequest(data=value, expected_crc=expected), timeout=5)
            assert valid.is_valid is True, (value, expected)
            wrong = expected ^ 1
            invalid = stub.Verify(crc_pb2.VerifyRequest(data=value, expected_crc=wrong), timeout=5)
            assert invalid.is_valid is False, (value, wrong)


def test_dynamic_http_inputs_and_routing():
    for value, expected in _random_cases():
        response = requests.get(
            'http://127.0.0.1:8080/verify',
            params={'data': value, 'crc': str(expected)}, timeout=5
        )
        assert response.status_code == 200
        assert response.headers.get('Content-Type', '').split(';')[0] == 'application/json'
        assert response.json() == {'valid': True}

        response = requests.get(
            'http://127.0.0.1:8080/verify',
            params={'data': value, 'crc': str(expected ^ 1)}, timeout=5
        )
        assert response.status_code == 200
        assert response.json() == {'valid': False}

    assert requests.get('http://127.0.0.1:8080/verify?data=x', timeout=5).status_code == 400
    assert requests.get('http://127.0.0.1:8080/verify?crc=1', timeout=5).status_code == 400
    assert requests.get('http://127.0.0.1:8080/verify?data=x&crc=not-an-int', timeout=5).status_code == 400
    assert requests.get('http://127.0.0.1:8080/not-verify?data=x&crc=1', timeout=5).status_code == 404
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
