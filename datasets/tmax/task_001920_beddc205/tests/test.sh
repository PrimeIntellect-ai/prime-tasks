#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import secrets
import shutil
import signal
import socket
import subprocess
import tempfile
import time

import pytest

PROJECT = pathlib.Path('/home/user/miniwaf')
SERVER_PID = None
SCRIPT_PROCESS = None


def listener_pids(port=8080):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(f':{port:04X}') and fields[3] == '0A':
                inodes.add(fields[9])

    found = set()
    for procdir in pathlib.Path('/proc').iterdir():
        if not procdir.name.isdigit():
            continue
        try:
            for fd in (procdir / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    found.add(int(procdir.name))
                    break
        except OSError:
            pass
    return found


def stop_existing_listeners():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.4)
    assert not listener_pids(), 'Could not clear the pre-existing listener on port 8080.'


def remove_generated_build_artifacts():
    # Force start_waf.sh to perform its own build rather than reuse a shipped binary.
    for path in sorted(PROJECT.rglob('CMakeFiles'), key=lambda p: len(p.parts), reverse=True):
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
    generated_names = {
        'CMakeCache.txt', 'Makefile', 'cmake_install.cmake',
        'miniwaf_server', 'libhttp_parser.so'
    }
    for path in list(PROJECT.rglob('*')):
        if path.name in generated_names or path.name.startswith('libhttp_parser.so.'):
            try:
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            except FileNotFoundError:
                pass


def send_http_request(payload: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(('127.0.0.1', 8080))
        s.sendall(payload.encode('utf-8'))
        return s.recv(4096).decode('utf-8', errors='ignore')
    finally:
        s.close()


@pytest.fixture(scope='session', autouse=True)
def run_submitted_orchestration():
    global SERVER_PID, SCRIPT_PROCESS
    script = pathlib.Path('/home/user/start_waf.sh')
    assert script.is_file(), '/home/user/start_waf.sh does not exist.'
    subprocess.run(['bash', '-n', str(script)], check=True)

    stop_existing_listeners()
    remove_generated_build_artifacts()
    started_at = time.time()

    try:
        SCRIPT_PROCESS = subprocess.Popen(
            ['bash', str(script)],
            cwd='/home/user',
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.time() + 30
        pids = set()
        while time.time() < deadline:
            pids = listener_pids()
            if pids:
                break
            if SCRIPT_PROCESS.poll() not in (None, 0):
                pytest.fail(f'start_waf.sh exited with status {SCRIPT_PROCESS.returncode}.')
            time.sleep(0.2)
        assert len(pids) == 1, 'start_waf.sh did not start exactly one listener on 127.0.0.1:8080.'
        SERVER_PID = next(iter(pids))

        exe = pathlib.Path(os.path.realpath(f'/proc/{SERVER_PID}/exe'))
        assert exe.name == 'miniwaf_server', f'Port 8080 is served by {exe.name}, not miniwaf_server.'
        assert PROJECT == exe or PROJECT in exe.parents, 'The running server is not the MiniWAF project artifact.'
        assert exe.stat().st_mtime >= started_at - 1, 'The running binary was not built by this start_waf.sh invocation.'

        cmdline = pathlib.Path(f'/proc/{SERVER_PID}/cmdline').read_bytes().split(b'\0')
        cmdline = [x.decode(errors='replace') for x in cmdline if x]
        assert len(cmdline) >= 2 and cmdline[1] == 'WAF-SEC-99821', \
            'start_waf.sh did not read and pass the extracted token as the first server argument.'

        build_dir = None
        for parent in (exe.parent, *exe.parents):
            cache = parent / 'CMakeCache.txt'
            if cache.is_file():
                text = cache.read_text(errors='ignore')
                if 'CMAKE_PROJECT_NAME:STATIC=MiniWAF' in text:
                    build_dir = parent
                    break
            if parent == PROJECT.parent:
                break
        assert build_dir is not None, 'The running server is not an artifact of a CMake MiniWAF build.'

        linked = subprocess.run(['ldd', str(exe)], text=True, capture_output=True, check=True).stdout
        assert 'libhttp_parser.so' in linked and 'not found' not in linked, \
            'miniwaf_server is not correctly linked to the http_parser shared library.'
        yield
    finally:
        if SCRIPT_PROCESS is not None and SCRIPT_PROCESS.poll() is None:
            try:
                os.killpg(SCRIPT_PROCESS.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if SERVER_PID is not None:
            try:
                os.kill(SERVER_PID, signal.SIGTERM)
            except ProcessLookupError:
                pass


def test_admin_token_extracted():
    token_path = '/home/user/admin_token.txt'
    assert os.path.isfile(token_path), f'{token_path} does not exist. The token was not extracted.'
    with open(token_path, 'r') as f:
        token = f.read().strip()
    assert token == 'WAF-SEC-99821', f"Extracted token is incorrect. Expected 'WAF-SEC-99821', got '{token}'."


def test_cmake_fixed():
    cmakelists_path = '/home/user/miniwaf/CMakeLists.txt'
    assert os.path.isfile(cmakelists_path), f'{cmakelists_path} is missing.'
    with open(cmakelists_path, 'r') as f:
        content = f.read()
    assert 'target_link_libraries' in content, "CMakeLists.txt does not contain 'target_link_libraries'. The build is likely still broken."

    with tempfile.TemporaryDirectory(prefix='miniwaf-clean-build-') as build:
        subprocess.run(['cmake', '-S', str(PROJECT), '-B', build], check=True, capture_output=True, text=True)
        subprocess.run(['cmake', '--build', build, '--clean-first'], check=True, capture_output=True, text=True)
        binary = pathlib.Path(build) / 'miniwaf_server'
        library = pathlib.Path(build) / 'libhttp_parser.so'
        assert binary.is_file() and os.access(binary, os.X_OK), 'A clean CMake build did not produce miniwaf_server.'
        assert library.is_file(), 'A clean CMake build did not produce libhttp_parser.so.'
        linked = subprocess.run(['ldd', str(binary)], check=True, capture_output=True, text=True).stdout
        assert 'libhttp_parser.so' in linked and 'not found' not in linked, \
            'The clean-built executable is not linked to libhttp_parser.so.'


def test_parser_memory_safety_fixed():
    parser_path = '/home/user/miniwaf/src/parser.c'
    assert os.path.isfile(parser_path), f'{parser_path} is missing.'
    with open(parser_path, 'r') as f:
        content = f.read()
    # Preserve the original assertion, then exercise the compiled parser under ASan.
    assert 'strcpy(buffer, input_header);' not in content, "parser.c still contains the vulnerable 'strcpy' call."

    with tempfile.TemporaryDirectory(prefix='parser-asan-') as td:
        harness = pathlib.Path(td) / 'harness.c'
        executable = pathlib.Path(td) / 'parser_test'
        harness.write_text(
            '#include <stdio.h>\n'
            'void parse_header(const char *input_header);\n'
            'int main(int argc, char **argv) {\n'
            '  if (argc != 2) return 2;\n'
            '  parse_header(argv[1]);\n'
            '  return 0;\n'
            '}\n'
        )
        subprocess.run([
            'gcc', '-std=c99', '-O0', '-g', '-fsanitize=address',
            '-fno-omit-frame-pointer', str(parser_path), str(harness), '-o', str(executable)
        ], check=True, capture_output=True, text=True)

        marker = 'short-' + secrets.token_hex(12)
        short = subprocess.run([str(executable), marker], capture_output=True, text=True, timeout=5)
        assert short.returncode == 0, short.stderr
        assert marker in short.stdout, 'The parser no longer correctly handles ordinary header values.'

        for _ in range(4):
            length = random.SystemRandom().randint(180, 700)
            value = secrets.token_hex((length + 1) // 2)[:length]
            result = subprocess.run(
                [str(executable), value], capture_output=True, text=True, timeout=5,
                env={**os.environ, 'ASAN_OPTIONS': 'abort_on_error=1:detect_leaks=0'}
            )
            assert result.returncode == 0, \
                f'Parser crashed or overflowed on a {length}-byte header.\n{result.stderr}'


def test_server_valid_request():
    req = 'GET / HTTP/1.1\r\nHost: localhost\r\nAdmin-Token: WAF-SEC-99821\r\n\r\n'
    try:
        resp = send_http_request(req)
    except ConnectionRefusedError:
        pytest.fail('Connection refused to 127.0.0.1:8080. Is the server running?')
    assert '200 OK' in resp, f"Expected '200 OK' in response, got: {resp}"


def test_server_waf_blocking():
    req = 'GET /?payload=<script>alert(1)</script> HTTP/1.1\r\nHost: localhost\r\n\r\n'
    try:
        resp = send_http_request(req)
    except ConnectionRefusedError:
        pytest.fail('Connection refused to 127.0.0.1:8080. Is the server running?')
    assert '403 Forbidden' in resp, f"Expected '403 Forbidden' in response, got: {resp}"


def test_server_memory_safety_long_header():
    long_header = 'A' * 250
    req = f'GET / HTTP/1.1\r\nHost: localhost\r\nX-Custom-Header: {long_header}\r\n\r\n'
    try:
        resp = send_http_request(req)
    except ConnectionRefusedError:
        pytest.fail('Connection refused to 127.0.0.1:8080. Is the server running?')
    except (socket.timeout, ConnectionResetError):
        pytest.fail('Server crashed or dropped connection on long header! Memory safety bug is not fixed.')
    assert '200 OK' in resp or '400 Bad Request' in resp, f"Expected '200 OK' or '400 Bad Request' after long header, got: {resp}"


def test_server_randomized_behaviour_and_survival():
    rng = random.SystemRandom()
    nonce = secrets.token_hex(16)
    benign = f'GET /{nonce} HTTP/1.1\r\nHost: localhost\r\nX-Test: {secrets.token_hex(20)}\r\n\r\n'
    assert '200 OK' in send_http_request(benign)

    attack = f'GET /{nonce}?q={secrets.token_hex(5)}<script>{secrets.token_hex(5)} HTTP/1.1\r\nHost: localhost\r\n\r\n'
    assert '403 Forbidden' in send_http_request(attack)

    for _ in range(3):
        size = rng.randint(180, 650)
        value = secrets.token_hex((size + 1) // 2)[:size]
        req = f'GET /{secrets.token_hex(4)} HTTP/1.1\r\nHost: localhost\r\nX-Custom-Header: {value}\r\n\r\n'
        response = send_http_request(req)
        assert '200 OK' in response or '400 Bad Request' in response
        assert SERVER_PID in listener_pids(), 'The actual MiniWAF server died after a randomized long header.'

    followup = f'GET /alive-{secrets.token_hex(8)} HTTP/1.1\r\nHost: localhost\r\n\r\n'
    assert '200 OK' in send_http_request(followup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
