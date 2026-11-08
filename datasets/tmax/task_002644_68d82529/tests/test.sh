#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import http.client
import json
import math
import os
import pathlib
import secrets
import shutil
import socket
import subprocess
import tempfile
import time

import pytest

ROOT = pathlib.Path('/app/vendored/ticket_server')
SOURCE = ROOT / 'server.c'
HEADER = ROOT / 'ticket.h'
MAKEFILE = ROOT / 'Makefile'
BINARY = ROOT / 'ticket_server'
TOKEN_FILE = pathlib.Path('/home/user/admin_token.txt')
EXPECTED_TOKEN = '8f92a-super-secret-admin-key'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def request(port, token=None, timeout=5):
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
    headers = {}
    if token is not None:
        headers['Auth-Token'] = token
    conn.request('GET', '/api/tickets', headers=headers)
    response = conn.getresponse()
    body = response.read().decode('utf-8', errors='strict')
    status = response.status
    conn.close()
    return status, body


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            try:
                local_port = int(fields[1].rsplit(':', 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port and fields[3] == '0A':
                inodes.add(fields[9])

    owners = set()
    for proc in pathlib.Path('/proc').iterdir():
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
                    break
        except OSError:
            continue
    return owners


def validate_ticket_json(body, expected_priority):
    try:
        data = json.loads(body)
    except ValueError:
        pytest.fail(f'Server did not return valid JSON. Response body: {body}')

    assert 'status' in data, "JSON response missing 'status' field."
    assert data['status'] == 'ok', f"Expected status 'ok', got {data['status']!r}"
    assert 'tickets' in data, "JSON response missing 'tickets' field."
    tickets = data['tickets']
    assert isinstance(tickets, list), "'tickets' field should be a list."
    assert len(tickets) >= 1, "'tickets' list is empty."
    ticket = tickets[0]
    assert 'id' in ticket, "Ticket missing 'id' field."
    assert ticket['id'] == 1, f"Expected ticket id 1, got {ticket['id']}"
    assert 'priority' in ticket, "Ticket missing 'priority' field."
    priority = ticket['priority']
    assert isinstance(priority, (int, float)) and not isinstance(priority, bool), \
        'Ticket priority should be a number.'
    assert math.isclose(priority, expected_priority, rel_tol=1e-5), \
        f'Expected priority {expected_priority}, got {priority}'


def test_admin_token_recovered():
    assert TOKEN_FILE.exists(), f'Token file {TOKEN_FILE} was not created.'
    token = TOKEN_FILE.read_text().strip()
    assert token == EXPECTED_TOKEN, \
        f'Incorrect token found in {TOKEN_FILE}. Expected {EXPECTED_TOKEN!r}, got {token!r}.'


def test_source_build_and_running_process_are_the_vendored_server():
    for path in (SOURCE, HEADER, MAKEFILE, BINARY):
        assert path.is_file(), f'Required vendored artifact is missing: {path}'
    assert os.access(BINARY, os.X_OK), f'{BINARY} is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', f'{BINARY} is not an ELF binary.'

    # Compile-time assertion that the precision-bearing struct member really is a
    # double, rather than merely faking the one expected HTTP response.
    with tempfile.TemporaryDirectory() as td:
        probe = pathlib.Path(td) / 'probe.c'
        probe.write_text(
            '#include "ticket.h"\n'
            '#include <stddef.h>\n'
            '_Static_assert(sizeof(((Ticket *)0)->priority) == sizeof(double), '
            '"Ticket.priority must retain double precision");\n'
            'int main(void) { Ticket t = {0}; t.priority = 1.23456789012345; '
            'return t.priority == 0.0; }\n'
        )
        result = subprocess.run(
            ['gcc', '-std=c11', '-Wall', '-Werror', '-I', str(ROOT), str(probe), '-o', str(pathlib.Path(td) / 'probe')],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f'Ticket definition is not double-precision:\n{result.stderr}'

    # Independently rebuild the submitted vendored source and ensure the deployed
    # executable is exactly the result of that build.
    rebuilt = pathlib.Path('/tmp/verifier_rebuilt_ticket_server')
    try:
        rebuilt.unlink()
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ['gcc', '-g', '-O0', 'server.c', '-o', str(rebuilt)], cwd=str(ROOT),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f'Vendored server.c does not compile:\n{result.stderr}'
    assert sha256(BINARY) == sha256(rebuilt), \
        'Deployed ticket_server does not match an independent build of the vendored source.'

    pids = listener_pids(9090)
    assert pids, 'No process is listening on TCP port 9090.'
    matching = []
    for pid in pids:
        try:
            exe = pathlib.Path(f'/proc/{pid}/exe')
            if sha256(exe) == sha256(rebuilt):
                cmdline = pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
                if b'9090' in cmdline:
                    matching.append(pid)
        except OSError:
            pass
    assert matching, \
        'Port 9090 is not owned by the compiled vendored ticket_server launched with port 9090.'


def test_server_running_and_correct():
    try:
        status, body = request(9090, EXPECTED_TOKEN)
    except (ConnectionError, OSError, socket.timeout) as exc:
        pytest.fail(f'Could not query the server on 127.0.0.1:9090: {exc}')
    assert status == 200, f'Expected HTTP 200 OK, got {status}. Response body: {body}'
    validate_ticket_json(body, 4.50291)

    for bad_token in (None, 'definitely-not-the-admin-token', EXPECTED_TOKEN[:-1] + 'x'):
        status, _ = request(9090, bad_token)
        assert status == 401, f'Unauthenticated request with token {bad_token!r} returned HTTP {status}, not 401.'


def test_submitted_parser_on_derived_high_precision_values():
    original = SOURCE.read_text()
    marker = 'PRIORITY 4.50291'
    assert original.count(marker) == 1, \
        'The vendored source no longer contains the ticket data exercised by the required endpoint.'

    # Values are generated only after the agent has finished. Each server is built
    # directly from the submitted source with its internal ticket input replaced,
    # so a fixed fake response cannot satisfy these checks.
    values = []
    for exponent in (-7, -2, 2, 7):
        digits = 10**13 + secrets.randbelow(9 * 10**13)
        value = (digits / 10**13) * (10 ** exponent)
        if secrets.randbelow(2):
            value = -value
        values.append(value)

    for value in values:
        literal = format(value, '.15g')
        with tempfile.TemporaryDirectory() as td:
            td_path = pathlib.Path(td)
            shutil.copy2(HEADER, td_path / 'ticket.h')
            (td_path / 'server.c').write_text(original.replace(marker, 'PRIORITY ' + literal, 1))
            variant = td_path / 'ticket_server'
            result = subprocess.run(
                ['gcc', '-g', '-O0', 'server.c', '-o', str(variant)], cwd=td,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            assert result.returncode == 0, f'Submitted parser failed to compile:\n{result.stderr}'

            with socket.socket() as s:
                s.bind(('127.0.0.1', 0))
                port = s.getsockname()[1]

            proc = subprocess.Popen([str(variant), str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.time() + 3
                while True:
                    if proc.poll() is not None:
                        pytest.fail(f'Server crashed while preparing to parse high-precision value {literal}.')
                    try:
                        status, body = request(port, EXPECTED_TOKEN, timeout=0.5)
                        break
                    except (ConnectionError, OSError, socket.timeout):
                        if time.time() >= deadline:
                            pytest.fail(f'Server did not start for high-precision value {literal}.')
                        time.sleep(0.05)
                assert status == 200, f'High-precision request returned HTTP {status}: {body}'
                # server.c intentionally formats with %g, so compare against the
                # correctly parsed double after that documented formatting step.
                rendered_expected = float(format(float(literal), '.6g'))
                validate_ticket_json(body, rendered_expected)
                assert proc.poll() is None, f'Server crashed after parsing high-precision value {literal}.'
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
