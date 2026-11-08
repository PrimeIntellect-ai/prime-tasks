#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest

PROJECT = Path('/home/user/crc_service')
PROTO = PROJECT / 'proto/crc.proto'
FFI = PROJECT / 'src/crc_ffi.rs'
NGINX_CONF = Path('/home/user/proxy/nginx.conf')
BINARY = PROJECT / 'target/release/crc_service'
CALL_LOG = Path('/tmp/custom_crc_calls.log')
PRELOAD = Path('/tmp/libcrc_audit.so')


def reference_crc(data: bytes, init_val: int) -> int:
    value = init_val
    for b in data:
        value ^= b
        value = (value * 0x811C9DC5) & 0xFFFFFFFF
    return value


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != '0A':
                continue
            if int(fields[1].rsplit(':', 1)[1], 16) == port:
                inodes.add(fields[9])

    owners = set()
    if not inodes:
        return owners
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    owners.add(int(proc.name))
        except (OSError, PermissionError):
            pass
    return owners


def kill_port_users(*ports):
    victims = set()
    for port in ports:
        victims.update(listener_pids(port))
    victims.discard(os.getpid())
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        if not any(listener_pids(port) for port in ports):
            return
        time.sleep(0.1)
    assert not any(listener_pids(port) for port in ports), 'Could not clear required listening ports'


def wait_for_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f'Port {port} did not become ready')


def run_checked(cmd, **kwargs):
    result = subprocess.run(cmd, text=True, capture_output=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(map(str, cmd))}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def build_audit_preload():
    source = Path('/tmp/crc_audit.c')
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef uint32_t (*crc_fn)(const uint8_t *, uint64_t, uint32_t);

uint32_t calculate_crc(const uint8_t *data, uint64_t len, uint32_t init_val) {
    static crc_fn original;
    if (!original) {
        original = (crc_fn)dlsym(RTLD_NEXT, "calculate_crc");
        if (!original) _exit(121);
    }
    uint32_t result = original(data, len, init_val);
    char line[128];
    int n = snprintf(line, sizeof(line), "%llu %u %u\n",
                     (unsigned long long)len, (unsigned)init_val, (unsigned)result);
    int fd = open("/tmp/custom_crc_calls.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        if (n > 0) write(fd, line, (size_t)n);
        close(fd);
    }
    return result;
}
''')
    run_checked(['gcc', '-shared', '-fPIC', '-O2', '-o', str(PRELOAD), str(source), '-ldl'])


def test_complete_system():
    # Preserve the original artifact-existence assertions.
    assert PROTO.is_file(), f'Proto file not found at {PROTO}'
    assert NGINX_CONF.is_file(), f'Nginx configuration not found at {NGINX_CONF}'
    assert FFI.is_file(), f'FFI binding file not found at {FFI}'

    # Semantically type-check the binding, including the C ABI and all three
    # argument types, rather than relying on textual spelling of Rust aliases.
    Path('/tmp/ffi_contract.rs').write_text(f'''
include!(r"{FFI}");
fn main() {{
    let _: unsafe extern "C" fn(*const std::os::raw::c_uchar, u64, u32) -> u32 = calculate_crc;
}}
''')
    run_checked([
        'rustc', '/tmp/ffi_contract.rs', '-o', '/tmp/ffi_contract',
        '-L', 'native=/app', '-l', 'dylib=custom_crc'
    ])

    # Compile the submitted project and verify its executable dynamically links
    # the supplied library and imports the required C symbol.
    run_checked(['cargo', 'build', '--release'], cwd=str(PROJECT))
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), f'Missing executable {BINARY}'
    dynamic = run_checked(['readelf', '-d', str(BINARY)]).stdout
    symbols = run_checked(['readelf', '-Ws', str(BINARY)]).stdout
    assert 'libcustom_crc.so' in dynamic, 'Rust service does not dynamically depend on libcustom_crc.so'
    assert any('UND' in line and 'calculate_crc' in line for line in symbols.splitlines()), \
        'Rust service does not import calculate_crc from the shared library'

    # Compile the submitted protobuf definition, retaining the original schema checks.
    generated = Path('/tmp/crc_generated')
    generated.mkdir(exist_ok=True)
    for stale in generated.glob('crc_pb2*.py'):
        stale.unlink()
    run_checked([
        sys.executable, '-m', 'grpc_tools.protoc',
        f'-I{PROJECT / "proto"}', f'--python_out={generated}',
        f'--grpc_python_out={generated}', str(PROTO)
    ])
    sys.path.insert(0, str(generated))
    import grpc
    import crc_pb2
    import crc_pb2_grpc
    assert hasattr(crc_pb2_grpc, 'CrcServiceStub'), 'Service must be named CrcService'

    kill_port_users(50051, 8080)
    CALL_LOG.unlink(missing_ok=True)
    build_audit_preload()

    service_log = open('/tmp/crc_service_verifier.log', 'wb')
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = '/app' + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    env['LD_PRELOAD'] = str(PRELOAD)
    service = subprocess.Popen([str(BINARY)], cwd=str(PROJECT), env=env,
                               stdout=service_log, stderr=subprocess.STDOUT,
                               start_new_session=True)
    wait_for_port(50051)
    assert service.poll() is None, 'Rust gRPC server exited during startup'
    assert service.pid in listener_pids(50051), 'Submitted Rust executable is not listening on 50051'
    maps = Path(f'/proc/{service.pid}/maps').read_text()
    assert '/app/libcustom_crc.so' in maps, 'Running Rust service did not load /app/libcustom_crc.so'

    # Validate and execute the submitted Nginx configuration itself.
    run_checked(['nginx', '-t', '-p', '/home/user/proxy/', '-c', str(NGINX_CONF)])
    try:
        Path('/run/nginx.pid').unlink()
    except FileNotFoundError:
        pass
    nginx_log = open('/tmp/nginx_verifier.log', 'wb')
    nginx_launcher = subprocess.Popen(
        ['nginx', '-p', '/home/user/proxy/', '-c', str(NGINX_CONF)],
        stdout=nginx_log, stderr=subprocess.STDOUT, start_new_session=True
    )
    wait_for_port(8080)
    nginx_owners = listener_pids(8080)
    assert nginx_owners, 'Nothing is listening on port 8080'
    assert any(Path(f'/proc/{pid}/comm').read_text().strip() == 'nginx' for pid in nginx_owners), \
        'Port 8080 is not served by Nginx'

    channel = grpc.insecure_channel('127.0.0.1:8080')
    stub = crc_pb2_grpc.CrcServiceStub(channel)
    requested = []
    correct = 0
    total = 100

    for _ in range(total):
        data_len = random.randint(10, 1000)
        data = os.urandom(data_len)
        init_val = random.randint(0, 0xFFFFFFFF)
        request = crc_pb2.CrcRequest(data=data, initial_value=init_val)
        response = stub.ComputeCrc(request, timeout=5)
        expected = reference_crc(data, init_val)
        requested.append((data_len, init_val, expected))
        if getattr(response, 'checksum', None) == expected:
            correct += 1

    accuracy = correct / total
    assert accuracy >= 1.0, (
        f'Metric accuracy: {accuracy} is below threshold 1.0. Correct: {correct}/{total}'
    )

    # Every tested RPC must reach calculate_crc with its actual length and
    # initial value, and the result returned by the real library must agree.
    deadline = time.time() + 2
    while time.time() < deadline and not CALL_LOG.exists():
        time.sleep(0.05)
    assert CALL_LOG.is_file(), 'No calls to calculate_crc were observed'
    observed = collections.Counter()
    for line in CALL_LOG.read_text().splitlines():
        parts = line.split()
        if len(parts) == 3:
            observed[tuple(map(int, parts))] += 1
    for call in requested:
        assert observed[call] > 0, f'calculate_crc was not called with tested request {call[:2]}'
        observed[call] -= 1

    assert service.poll() is None, 'Rust gRPC server is no longer running'
    assert listener_pids(8080), 'Nginx is no longer listening on port 8080'
    channel.close()


if __name__ == '__main__':
    raise SystemExit(pytest.main([__file__, '-x', '--tb=short']))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
