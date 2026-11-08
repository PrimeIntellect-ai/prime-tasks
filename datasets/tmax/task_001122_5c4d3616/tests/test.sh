#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

SCANNER_PATH = Path('/home/user/scan_corpus/scanner')
SCANNER_DIR = Path('/home/user/scan_corpus')
SERVER_DIR = Path('/home/user/server')
GRPC_DIR = Path('/home/user/grpc')
LIB_DIR = Path('/app/vendored/libtextverify')
EVIL_CORPUS_DIR = Path('/home/user/corpus/evil')
CLEAN_CORPUS_DIR = Path('/home/user/corpus/clean')


def run_scanner(corpus_dir, scanner=SCANNER_PATH, timeout=10):
    assert scanner.is_file(), f'Scanner executable not found at {scanner}'
    assert os.access(scanner, os.X_OK), f'Scanner at {scanner} is not executable'
    try:
        return subprocess.run(
            [str(scanner), str(corpus_dir)],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=True,
        ).stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Scanner failed for {corpus_dir}: {e.stderr}')
    except subprocess.TimeoutExpired:
        pytest.fail(f'Scanner timed out for {corpus_dir}')


# Preserve the original corpus assertions.
def test_evil_corpus_rejected():
    assert EVIL_CORPUS_DIR.is_dir()
    stdout = run_scanner(EVIL_CORPUS_DIR)
    bypassed = []
    for path in EVIL_CORPUS_DIR.iterdir():
        if path.is_file() and f'{path.name}: REJECTED' not in stdout:
            bypassed.append(path.name)
    assert not bypassed, f'Evil files bypassed: {bypassed}'


def test_clean_corpus_accepted():
    assert CLEAN_CORPUS_DIR.is_dir()
    stdout = run_scanner(CLEAN_CORPUS_DIR)
    modified = []
    for path in CLEAN_CORPUS_DIR.iterdir():
        if path.is_file() and f'{path.name}: ACCEPTED' not in stdout:
            modified.append(path.name)
    assert not modified, f'Clean files rejected: {modified}'


def test_c_library_builds_and_is_safe():
    subprocess.run(['make', 'clean'], cwd=LIB_DIR, check=True, capture_output=True, text=True)
    subprocess.run(['make'], cwd=LIB_DIR, check=True, capture_output=True, text=True)
    library = LIB_DIR / 'libtextverify.so'
    assert library.is_file()
    assert library.read_bytes()[:4] == b'\x7fELF', 'libtextverify.so is not an ELF shared library'

    helper = r'''
import ctypes
lib = ctypes.CDLL('/app/vendored/libtextverify/libtextverify.so')
fn = lib.is_valid_text
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_int
assert fn(b'ordinary text') == 1
assert fn(b'\xffbad') == 0
assert fn(b'A' * 4096) == 0
'''
    result = subprocess.run(['python3', '-c', helper], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f'C validator crashed or returned unsafe results: {result.stderr}'


def test_proto_and_implementations_exist_and_build():
    proto = GRPC_DIR / 'verify.proto'
    assert proto.is_file()
    text = proto.read_text(errors='replace')
    assert re.search(r'\bservice\s+TextVerifier\b', text)
    assert re.search(r'\brpc\s+Verify\s*\(\s*VerifyRequest\s*\)\s*returns\s*\(\s*VerifyResponse\s*\)', text)
    assert re.search(r'\bstring\s+text\s*=\s*\d+\s*;', text)
    assert re.search(r'\bbool\s+valid\s*=\s*\d+\s*;', text)
    assert list(GRPC_DIR.rglob('*.pb.go')), 'Generated protobuf Go code is missing'
    assert list(GRPC_DIR.rglob('*_grpc.pb.go')), 'Generated gRPC Go code is missing'

    server_source = SERVER_DIR / 'main.go'
    scanner_source = SCANNER_DIR / 'main.go'
    assert server_source.is_file() and scanner_source.is_file()
    server_text = server_source.read_text(errors='replace')
    scanner_text = scanner_source.read_text(errors='replace')
    assert re.search(r'import\s+"C"', server_text), 'Server does not use cgo'
    assert 'is_valid_text' in server_text, 'Server does not call the vendored C function'
    assert 'RegisterTextVerifierServer' in server_text and '50051' in server_text
    assert ('grpc.Dial' in scanner_text or 'grpc.NewClient' in scanner_text)
    assert '.Verify(' in scanner_text, 'Scanner does not invoke the Verify RPC'

    subprocess.run(['go', 'build', '-o', '/tmp/server_checked', '.'], cwd=SERVER_DIR,
                   check=True, capture_output=True, text=True, timeout=120)
    subprocess.run(['go', 'build', '-o', '/tmp/scanner_checked', '.'], cwd=SCANNER_DIR,
                   check=True, capture_output=True, text=True, timeout=120)
    assert Path('/tmp/server_checked').read_bytes()[:4] == b'\x7fELF'
    assert Path('/tmp/scanner_checked').read_bytes()[:4] == b'\x7fELF'
    assert SCANNER_PATH.read_bytes()[:4] == b'\x7fELF', 'Installed scanner is not a compiled executable'


def stop_port_50051_listeners():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == 'C383' and fields[3] == '0A':
                inodes.add(fields[9])
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    os.kill(int(proc.name), signal.SIGTERM)
                    break
        except (OSError, PermissionError):
            pass
    time.sleep(0.3)


def wait_for_server(process):
    deadline = time.time() + 10
    while time.time() < deadline:
        if process.poll() is not None:
            out, err = process.communicate()
            pytest.fail(f'Rebuilt server exited before listening. stdout={out} stderr={err}')
        try:
            with socket.create_connection(('127.0.0.1', 50051), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail('Rebuilt server did not listen on 127.0.0.1:50051')


def test_rebuilt_server_and_scanner_on_unpredictable_mixed_corpus():
    stop_port_50051_listeners()
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(LIB_DIR) + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    server = subprocess.Popen(['/tmp/server_checked'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, env=env)
    try:
        wait_for_server(server)
        with tempfile.TemporaryDirectory(prefix='verifier-corpus-') as directory:
            corpus = Path(directory)
            token = secrets.token_hex(12)
            cases = {
                f'{token}_short.txt': (f'normal-{token}'.encode(), 'ACCEPTED'),
                f'{token}_empty.txt': (b'', 'ACCEPTED'),
                f'{token}_spaces in name.txt': (b'plain ASCII text with spaces', 'ACCEPTED'),
                f'{token}_large.txt': ((token.encode() * 300), 'REJECTED'),
                f'{token}_large2.dat': (b'Z' * 8192, 'REJECTED'),
            }
            for name, (content, _) in cases.items():
                (corpus / name).write_bytes(content)

            stdout = run_scanner(corpus, Path('/tmp/scanner_checked'))
            actual = stdout.splitlines()
            expected = [f'{name}: {status}' for name, (_, status) in cases.items()]
            assert len(actual) == len(expected), f'Expected exactly one output line per file, got: {stdout!r}'
            assert sorted(actual) == sorted(expected), f'Incorrect or extra scanner output: {stdout!r}'
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
