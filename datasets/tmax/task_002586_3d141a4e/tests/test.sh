#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pathlib
import random
import re
import signal
import subprocess
import time

import pytest

ROOT = pathlib.Path('/app/data-server')
SERVER = ROOT / 'server'
PROCESSOR = ROOT / 'src/processor.cpp'
AUTH_OBJ = ROOT / 'lib/auth.o'
TOKEN = 'tr0ub4d0ur&3'


def stop_port_8080_listeners():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                inodes.add(fields[9])

    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            links = [os.readlink(fd) for fd in fd_dir.iterdir()]
        except (OSError, PermissionError):
            continue
        if any(link.startswith('socket:[') and link[8:-1] in inodes for link in links):
            try:
                os.kill(int(proc.name), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
    time.sleep(0.4)


def request(method, path='/', body=b'', headers=None, timeout=2):
    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=timeout)
    try:
        conn.request(method, path, body=body, headers=headers or {})
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


@pytest.fixture(scope='session', autouse=True)
def build_and_start_service():
    assert PROCESSOR.is_file(), 'src/processor.cpp is missing'
    assert AUTH_OBJ.is_file(), 'lib/auth.o is missing'
    assert AUTH_OBJ.read_bytes()[:4] == b'\x7fELF', 'auth.o is not an ELF object file'

    subprocess.run(['make', 'clean'], cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    build = subprocess.run(['make'], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, 'make failed:\n' + build.stdout
    assert SERVER.is_file() and os.access(SERVER, os.X_OK), 'make did not produce an executable server'
    assert SERVER.read_bytes()[:4] == b'\x7fELF', 'server is not an ELF executable'

    disassembly = subprocess.run(
        ['objdump', '-d', '-C', str(SERVER)], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    ).stdout
    assert re.search(r'call[q l]?\s+[^\n]*<check_token(?:@plt)?>', disassembly), \
        'the compiled service does not call check_token from auth.o'

    stop_port_8080_listeners()
    proc = subprocess.Popen([str(SERVER)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(30):
        assert proc.poll() is None, 'the compiled server exited before accepting connections'
        try:
            request('GET', '/', timeout=0.3)
            break
        except (OSError, http.client.HTTPException):
            time.sleep(0.1)
    else:
        proc.terminate()
        pytest.fail('compiled service is not listening on 127.0.0.1:8080')

    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_processor_bounds_directly():
    harness = r'''
#include <algorithm>
#include <cstring>
#include <vector>
extern void process_data(const char*, int, char*);

int main(int argc, char** argv) {
    for (int a = 1; a < argc; ++a) {
        int len = std::stoi(argv[a]);
        std::vector<char> input(len);
        for (int i = 0; i < len; ++i) input[i] = static_cast<char>((i * 37) % 251 + 1);
        unsigned char arena[300];
        std::memset(arena, 0xCC, sizeof(arena));
        char* output = reinterpret_cast<char*>(arena + 8);
        process_data(input.data(), len, output);
        int expected = std::min(len, 256);
        for (int i = 0; i < 8; ++i) if (arena[i] != 0xCC) return 10;
        for (int i = 0; i < expected; ++i) if (output[i] != input[i]) return 11;
        if (output[expected] != '\0') return 12;
        for (int i = 8 + expected + 1; i < 300; ++i) if (arena[i] != 0xCC) return 13;
    }
    return 0;
}
'''
    pathlib.Path('/tmp/processor_harness.cpp').write_text(harness)
    compiled = subprocess.run(
        ['g++', '-std=c++11', '-Wall', '-Wextra', '-o', '/tmp/processor_harness',
         '/tmp/processor_harness.cpp', str(PROCESSOR)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert compiled.returncode == 0, 'processor.cpp does not compile:\n' + compiled.stdout
    lengths = [0, 1, 2, 127, 255, 256, 257, 500, 1024]
    lengths.extend(random.SystemRandom().randint(3, 900) for _ in range(8))
    run = subprocess.run(['/tmp/processor_harness', *map(str, lengths)])
    assert run.returncode == 0, f'process_data failed bounds/content checks (code {run.returncode})'


def auth_headers(token=TOKEN):
    return {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/octet-stream'}


def test_valid_payload():
    payload = b'A' * 100
    status, content = request('POST', '/process', payload, auth_headers())
    assert status == 200, f'Expected 200 OK for valid payload, got {status}'
    assert len(content) == 100, f'Expected response length 100, got {len(content)}'
    assert content == payload, 'Response content does not match the input payload.'


def test_buffer_overflow_fix():
    payload = b'B' * 500
    try:
        status, content = request('POST', '/process', payload, auth_headers())
    except OSError as exc:
        pytest.fail(f'Service crashed when sending oversized payload: {exc}')
    assert status == 200, f'Expected 200 OK for oversized payload, got {status}'
    assert len(content) == 256, f'Expected exactly 256 bytes, got {len(content)}'
    assert content == b'B' * 256, 'Response should contain the first 256 input bytes.'


def test_randomized_payload_processing():
    rng = random.SystemRandom()
    alphabet = b'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-'
    lengths = [1, 254, 255, 256, 257, 258, 511, rng.randint(20, 240), rng.randint(300, 900)]
    for length in lengths:
        payload = bytes(rng.choice(alphabet) for _ in range(length))
        status, content = request('POST', '/process', payload, auth_headers())
        assert status == 200
        assert content == payload[:256]

    followup = b'service-still-alive-' + os.urandom(8).hex().encode()
    status, content = request('POST', '/process', followup, auth_headers())
    assert status == 200 and content == followup


def test_authentication():
    status, _ = request('POST', '/process', b'C' * 50, auth_headers('invalid_token_123'))
    assert status in (401, 403), f'Expected 401 or 403 for invalid token, got {status}'


def test_random_invalid_authentication():
    bad = 'invalid-' + os.urandom(18).hex()
    status, _ = request('POST', '/process', b'auth-check', auth_headers(bad))
    assert status in (401, 403), f'Expected 401 or 403 for random invalid token, got {status}'


def test_missing_authentication():
    status, _ = request('POST', '/process', b'D' * 50, {'Content-Type': 'application/octet-stream'})
    assert status in (401, 403), f'Expected 401 or 403 for missing authentication, got {status}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    reward=1
fi
exit 0
