#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import os
import re
import secrets
import socket
import string
import time
import pytest

HOST = '127.0.0.1'
PORT = 8080
TOKEN = '7391'
LOG_FILE = '/home/user/audit.log'
SOURCE = '/home/user/audit_server.c'
BINARY = '/home/user/audit_server'


def send_tcp_request(host, port, payload):
    if isinstance(payload, str):
        payload = payload.encode('utf-8')
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(3.0)
        s.connect((host, port))
        s.sendall(payload)
        s.shutdown(socket.SHUT_WR)
        response = s.recv(1024).decode('utf-8')
    return response


def listener_inode():
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            address, port = local_address.split(':')
            if address == '00000000' and int(port, 16) == PORT and state == '0A':
                return fields[9]
    return None


def listener_pids(inode):
    target = f'socket:[{inode}]'
    found = []
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == target:
                        found.append(int(pid))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return found


def extract_calls(source, names):
    calls = []
    pattern = re.compile(r'\b(' + '|'.join(map(re.escape, names)) + r')\s*\(')
    for match in pattern.finditer(source):
        start = match.end()
        depth = 1
        i = start
        while i < len(source) and depth:
            if source[i] == '(':
                depth += 1
            elif source[i] == ')':
                depth -= 1
            i += 1
        if depth:
            continue
        body = source[start:i - 1]
        args, last, nested = [], 0, 0
        for pos, ch in enumerate(body):
            if ch in '([{':
                nested += 1
            elif ch in ')]}':
                nested -= 1
            elif ch == ',' and nested == 0:
                args.append(body[last:pos].strip())
                last = pos + 1
        args.append(body[last:].strip())
        calls.append((match.group(1), args))
    return calls


def safe_integer(expression, constants, arrays):
    expr = expression
    expr = re.sub(r'\(\s*(?:size_t|ssize_t|unsigned|int|long)\s*\)', '', expr)

    def sizeof_repl(match):
        name = match.group(1) or match.group(2)
        if name not in arrays:
            raise ValueError(name)
        return str(arrays[name])

    expr = re.sub(r'sizeof\s*\(\s*([A-Za-z_]\w*)\s*\)|sizeof\s+([A-Za-z_]\w*)', sizeof_repl, expr)
    for name, value in sorted(constants.items(), key=lambda item: -len(item[0])):
        expr = re.sub(r'\b' + re.escape(name) + r'\b', str(value), expr)
    expr = re.sub(r'(?<=\d)[uUlL]+\b', '', expr)
    if not re.fullmatch(r'[0-9\s+\-*/%()<>|&]+', expr):
        raise ValueError(expression)
    node = ast.parse(expr, mode='eval')
    allowed = (ast.Expression, ast.Constant, ast.BinOp, ast.UnaryOp, ast.Add, ast.Sub,
               ast.Mult, ast.FloorDiv, ast.Div, ast.Mod, ast.LShift, ast.RShift,
               ast.BitOr, ast.BitAnd, ast.UAdd, ast.USub)
    if any(not isinstance(item, allowed) for item in ast.walk(node)):
        raise ValueError(expression)
    value = eval(compile(node, '<size>', 'eval'), {'__builtins__': {}}, {})
    if not isinstance(value, (int, float)) or int(value) != value:
        raise ValueError(expression)
    return int(value)


def test_files_exist():
    """Verify that the C source and compiled binary exist."""
    assert os.path.exists(SOURCE), 'Source code /home/user/audit_server.c is missing.'
    assert os.path.exists(BINARY), 'Compiled binary /home/user/audit_server is missing.'
    assert os.access(BINARY, os.X_OK), 'Compiled binary /home/user/audit_server is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'audit_server is not a compiled ELF executable.'


def test_c_source_has_bounded_reads():
    with open(SOURCE, 'r', errors='replace') as f:
        raw = f.read()
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', raw, flags=re.S)
    assert not re.search(r'\bgets\s*\(', source), 'Unsafe gets() is forbidden.'

    constants = {}
    for name, value in re.findall(r'^\s*#\s*define\s+([A-Za-z_]\w*)\s+(\d+)[uUlL]*\b', source, re.M):
        constants[name] = int(value)
    for name, value in re.findall(r'\b(?:const\s+)?(?:unsigned\s+)?(?:int|size_t)\s+([A-Za-z_]\w*)\s*=\s*(\d+)[uUlL]*\s*;', source):
        constants[name] = int(value)

    arrays = {}
    for name, size_expr in re.findall(r'\b(?:char|unsigned\s+char|uint8_t)\s+([A-Za-z_]\w*)\s*\[\s*([^\]]+)\s*\]', source):
        try:
            arrays[name] = safe_integer(size_expr, constants, arrays)
        except ValueError:
            pass

    calls = extract_calls(source, ('recv', 'read', 'fgets'))
    assert calls, 'C source does not contain a recognizable bounded input read.'
    checked = 0
    for name, args in calls:
        size_index = 2 if name in ('recv', 'read') else 1
        assert len(args) > size_index, f'Could not inspect the size argument to {name}().'
        try:
            maximum = safe_integer(args[size_index], constants, arrays)
        except ValueError:
            pytest.fail(f'Could not establish a fixed maximum read size for {name}({args[size_index]}).')
        assert 0 < maximum <= 512, f'{name}() may read {maximum} bytes; the maximum is 512.'
        checked += 1
    assert checked > 0


def test_server_listening():
    """Verify connectivity, the required wildcard bind, and that the compiled artifact owns it."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex((HOST, PORT))
        assert result == 0, f'Server is not listening on {HOST}:{PORT}'

    inode = listener_inode()
    assert inode is not None, 'Port 8080 is not bound to IPv4 0.0.0.0.'
    pids = listener_pids(inode)
    assert pids, 'Could not identify the process owning the listening socket.'
    expected = os.path.realpath(BINARY)
    assert any(os.path.realpath(f'/proc/{pid}/exe') == expected for pid in pids), \
        'The running listener is not /home/user/audit_server.'


def test_valid_auth_and_logging():
    """Preserve the original fixed valid request and logging assertion."""
    payload = 'TOKEN: 7391 PAYLOAD: U2VjdXJlQXVkaXRMb2cxMjM=\n'
    try:
        response = send_tcp_request(HOST, PORT, payload)
    except Exception as e:
        pytest.fail(f'Failed to connect or receive response from server: {e}')
    assert response == 'SUCCESS\n', f"Expected response 'SUCCESS\\n', got '{response}'"
    assert os.path.exists(LOG_FILE), f'Log file {LOG_FILE} was not created.'
    with open(LOG_FILE, 'r', errors='replace') as f:
        lines = f.readlines()
    assert len(lines) > 0, f'Log file {LOG_FILE} is empty.'
    assert 'SecureAuditLog123' in lines[-1], \
        f"Expected 'SecureAuditLog123' in the last line of {LOG_FILE}, got '{lines[-1]}'"


def test_random_valid_payloads_are_decoded_and_appended_exactly():
    alphabet = string.ascii_letters + string.digits + '_- .'
    for _ in range(5):
        decoded = ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(80) + 17)).encode()
        encoded = base64.b64encode(decoded).decode('ascii')
        before = os.path.getsize(LOG_FILE) if os.path.exists(LOG_FILE) else 0
        response = send_tcp_request(HOST, PORT, f'TOKEN: {TOKEN} PAYLOAD: {encoded}\n')
        assert response == 'SUCCESS\n'
        with open(LOG_FILE, 'rb') as f:
            f.seek(before)
            appended = f.read()
        assert appended == decoded + b'\n', \
            f'Expected exactly the decoded randomized payload plus newline, got {appended!r}'


def test_invalid_auth():
    """Preserve the original fixed invalid-token assertion."""
    payload = 'TOKEN: 9999 PAYLOAD: YmFkX2FjdG9y\n'
    try:
        response = send_tcp_request(HOST, PORT, payload)
    except Exception as e:
        pytest.fail(f'Failed to connect or receive response from server: {e}')
    assert response == 'AUTH_FAILED\n', f"Expected response 'AUTH_FAILED\\n', got '{response}'"


def test_random_invalid_tokens_do_not_log():
    for _ in range(4):
        bad = f'{secrets.randbelow(10000):04d}'
        while bad == TOKEN:
            bad = f'{secrets.randbelow(10000):04d}'
        decoded = secrets.token_hex(13).encode()
        encoded = base64.b64encode(decoded).decode('ascii')
        before = os.path.getsize(LOG_FILE)
        response = send_tcp_request(HOST, PORT, f'TOKEN: {bad} PAYLOAD: {encoded}\n')
        assert response == 'AUTH_FAILED\n'
        assert os.path.getsize(LOG_FILE) == before, 'An invalid-token payload was logged.'


def test_wrong_formats_and_invalid_base64_are_rejected():
    encoded = base64.b64encode(secrets.token_bytes(19)).decode('ascii')
    malformed = [
        f'TOKEN:{TOKEN} PAYLOAD: {encoded}\n',
        f'TOKEN: {TOKEN} PAYLOAD:{encoded}\n',
        f'X TOKEN: {TOKEN} PAYLOAD: {encoded}\n',
        f'TOKEN: {TOKEN} PAYLOAD: {encoded} EXTRA\n',
        f'TOKEN: {TOKEN} PAYLOAD: !!!!{secrets.token_hex(5)}\n',
    ]
    for request in malformed:
        before = os.path.getsize(LOG_FILE)
        assert send_tcp_request(HOST, PORT, request) == 'AUTH_FAILED\n'
        assert os.path.getsize(LOG_FILE) == before, 'A malformed request was logged.'


def test_buffer_overflow_attempt():
    """Preserve the original oversized-request survival check."""
    large_payload_b64 = 'A' * 2000
    payload = f'TOKEN: 7391 PAYLOAD: {large_payload_b64}\n'
    try:
        send_tcp_request(HOST, PORT, payload)
    except Exception:
        pass
    time.sleep(1)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex((HOST, PORT))
        assert result == 0, 'Server crashed after receiving a large payload (buffer overflow vulnerability).'
    assert listener_inode() is not None, 'Server is no longer bound to 0.0.0.0 after the large request.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
