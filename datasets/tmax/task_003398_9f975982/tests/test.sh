#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import tempfile
import time
import secrets
from pathlib import Path

import pytest

WORK = Path('/home/user/workspace')
API = WORK / 'api.sh'
NGINX_CONF = WORK / 'nginx.conf'
AUDIT_DIR = WORK / 'audit'
AUDIT_BIN = AUDIT_DIR / 'audit'
RECONCILE = WORK / 'reconcile.sh'
DIFF_OUT = WORK / 'diff.out'


def listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            cols = line.split()
            if len(cols) >= 10 and cols[1].split(':')[-1].upper() == wanted and cols[3] == '0A':
                inodes.add(cols[9])

    owners = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m and m.group(1) in inodes:
                    owners.add(int(proc.name))
        except OSError:
            pass
    return owners


def proc_exe(pid):
    try:
        return os.path.realpath(f'/proc/{pid}/exe').replace(' (deleted)', '')
    except OSError:
        return ''


def proc_cmdline(pid):
    try:
        return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def expected_from_evaluator(payload):
    result = subprocess.run(['/app/evaluator'], input=payload.encode(), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=3, check=True)
    return result.stdout


def raw_http(port, payload, split_body=False):
    body = payload.encode()
    headers = (
        f'POST /api/v1/check HTTP/1.1\r\n'
        f'Host: 127.0.0.1\r\n'
        f'Content-Length: {len(body)}\r\n'
        f'Content-Type: text/plain\r\n'
        f'Connection: close\r\n\r\n'
    ).encode()

    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(headers)
        if split_body and len(body) > 1:
            cut = secrets.randbelow(len(body) - 1) + 1
            sock.sendall(body[:cut])
            time.sleep(0.15)
            sock.sendall(body[cut:])
        else:
            sock.sendall(body)

        data = bytearray()
        header_end = -1
        content_length = None
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                if header_end >= 0 and content_length is not None and len(data) >= header_end + 4 + content_length:
                    break
                raise
            if not chunk:
                break
            data.extend(chunk)
            if header_end < 0:
                header_end = data.find(b'\r\n\r\n')
                if header_end >= 0:
                    header_blob = bytes(data[:header_end]).decode('iso-8859-1')
                    m = re.search(r'(?im)^Content-Length:\s*(\d+)\s*$', header_blob)
                    assert m, f'Response lacks a valid Content-Length header: {header_blob!r}'
                    content_length = int(m.group(1))
            if header_end >= 0 and content_length is not None and len(data) >= header_end + 4 + content_length:
                break

    assert header_end >= 0, f'Invalid HTTP response: {bytes(data)!r}'
    head = bytes(data[:header_end]).decode('iso-8859-1')
    response_body = bytes(data[header_end + 4:])
    assert re.match(r'^HTTP/1\.[01] 200(?: |$)', head), f'Expected HTTP 200 OK, got: {head!r}'
    assert content_length == len(response_body), (
        f'Content-Length was {content_length}, but response body has {len(response_body)} bytes'
    )
    return response_body


def wait_for_log(payload, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            contents = Path('/tmp/audit.log').read_text(errors='replace')
        except FileNotFoundError:
            contents = ''
        if f'AUDIT: {payload}' in contents:
            return contents
        time.sleep(0.1)
    return contents


def normalized_diff_body(data):
    lines = data.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith('@@'):
            return ''.join(lines[i:])
    return ''


def make_expected_diff(left, right):
    result = subprocess.run(['diff', '-u', str(left), str(right)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    assert result.returncode in (0, 1), result.stderr
    return normalized_diff_body(result.stdout)


def test_required_artifacts_and_running_implementations():
    assert API.is_file(), f'Missing {API}'
    assert NGINX_CONF.is_file(), f'Missing {NGINX_CONF}'
    assert AUDIT_BIN.is_file() and os.access(AUDIT_BIN, os.X_OK), f'Missing executable {AUDIT_BIN}'
    assert RECONCILE.is_file(), f'Missing {RECONCILE}'

    api_text = API.read_text(errors='replace')
    first_line = api_text.splitlines()[0] if api_text.splitlines() else ''
    assert 'bash' in first_line, 'api.sh must be a Bash script'
    assert not re.search(r'(^|[;&|]\s*)(python|python3)(\s|$)', api_text, re.M), \
        'api.sh must not implement the server with Python'

    api_processes = []
    for proc in Path('/proc').iterdir():
        if proc.name.isdigit() and str(API) in proc_cmdline(int(proc.name)):
            api_processes.append(int(proc.name))
    assert api_processes, 'api.sh is not running in the background'
    assert any(os.path.basename(proc_exe(pid)) in ('bash', 'sh') for pid in api_processes), \
        'The running api.sh is not executed by a shell'
    assert listener_pids(9001), 'Nothing is listening on TCP port 9001'

    nginx_pids = listener_pids(8080)
    assert nginx_pids, 'Nothing is listening on TCP port 8080'
    assert any(os.path.basename(proc_exe(pid)) == 'nginx' for pid in nginx_pids), \
        'TCP port 8080 is not owned by Nginx'
    all_nginx_cmds = [proc_cmdline(int(p.name)) for p in Path('/proc') if p.name.isdigit()
                      and os.path.basename(proc_exe(int(p.name))) == 'nginx']
    assert any('nginx.conf' in cmd and (str(NGINX_CONF) in cmd or '-c nginx.conf' in cmd)
               for cmd in all_nginx_cmds), 'Running Nginx was not started with the workspace nginx.conf'

    conf = NGINX_CONF.read_text(errors='replace')
    conf_no_comments = re.sub(r'#.*', '', conf)
    assert re.search(r'\blisten\s+(?:[^;]*:)?8080\b[^;]*;', conf_no_comments), 'nginx.conf does not listen on 8080'
    assert re.search(r'location\s+(?:=\s*)?/api/v1/check\b', conf_no_comments), \
        'nginx.conf lacks the /api/v1/check location'
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:9001(?:/)?\s*;', conf_no_comments), \
        'nginx.conf does not proxy the endpoint to 127.0.0.1:9001'
    assert re.search(r'\bpid\s+/tmp/', conf_no_comments), 'Nginx pid must be under /tmp/'
    assert re.search(r'\bclient_body_temp_path\s+/tmp/', conf_no_comments), \
        'Nginx client-body storage must be under /tmp/'
    assert re.search(r'\b(?:access_log|error_log)\s+/tmp/', conf_no_comments), \
        'Nginx logs must be configured under /tmp/'

    audit_pids = listener_pids(9002)
    assert audit_pids, 'Nothing is listening on TCP port 9002'
    expected_audit = os.path.realpath(AUDIT_BIN)
    assert any(proc_exe(pid) == expected_audit for pid in audit_pids), \
        'Port 9002 is not owned by the compiled workspace audit binary'


def test_makefile_rebuilds_c_audit_daemon():
    makefile = AUDIT_DIR / 'Makefile'
    source = AUDIT_DIR / 'audit.c'
    assert makefile.is_file() and source.is_file(), 'audit.c or Makefile is missing'
    make_text = makefile.read_text(errors='replace')
    assert re.search(r'(?<!\w)-(?:pthread|lpthread)\b', make_text), \
        'The repaired Makefile must link pthread support'

    with tempfile.TemporaryDirectory() as td:
        Path(td, 'audit.c').write_bytes(source.read_bytes())
        Path(td, 'Makefile').write_bytes(makefile.read_bytes())
        result = subprocess.run(['make'], cwd=td, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=15)
        assert result.returncode == 0, f'Makefile failed to build from source:\n{result.stdout}'
        rebuilt = Path(td, 'audit')
        assert rebuilt.is_file() and os.access(rebuilt, os.X_OK), 'Makefile did not create executable audit'
        assert rebuilt.read_bytes()[:4] == b'\x7fELF', 'The rebuilt audit artifact is not an ELF binary'


def test_bash_api_and_nginx_proxy_use_evaluator_and_audit():
    nonce = secrets.randbelow(7000) + 1001
    expressions = [
        f'{nonce} + {secrets.randbelow(500) + 2}',
        f'{nonce + 17} - {secrets.randbelow(400) + 1}',
        f'{secrets.randbelow(80) + 11} * {secrets.randbelow(30) + 3}',
    ]

    # Exercise the Bash listener directly with a fragmented body, requiring it
    # to honor Content-Length rather than relying on a single read.
    direct = expressions[0]
    assert raw_http(9001, direct, split_body=True) == expected_from_evaluator(direct)

    # Exercise independently generated inputs through the required Nginx route.
    for payload in expressions[1:]:
        actual = raw_http(8080, payload)
        expected = expected_from_evaluator(payload)
        assert actual == expected, f'For {payload!r}, expected {expected!r}, got {actual!r}'

    # Preserve the original evaluator assertion as well.
    assert raw_http(8080, '15 * 3').strip() == b'45'

    # A fresh unique proxy request must be forwarded by api.sh to the C daemon.
    audit_payload = f'{secrets.randbelow(8000) + 1000} + {secrets.randbelow(8000) + 1000}'
    try:
        Path('/tmp/audit.log').unlink()
    except FileNotFoundError:
        pass
    assert raw_http(8080, audit_payload) == expected_from_evaluator(audit_payload)
    logs = wait_for_log(audit_payload)
    assert Path('/tmp/audit.log').exists(), 'Audit log was not created by the audit daemon'
    assert f'AUDIT: {audit_payload}' in logs, \
        f'Audit log does not contain the proxied raw payload {audit_payload!r}. Contents:\n{logs}'


def test_reconciliation_script_produces_the_recomputed_diff():
    try:
        DIFF_OUT.unlink()
    except FileNotFoundError:
        pass

    result = subprocess.run(['bash', str(RECONCILE)], cwd=str(WORK), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode in (0, 1), f'reconcile.sh failed:\n{result.stderr}'
    assert DIFF_OUT.exists(), f'Diff output not found at {DIFF_OUT}'

    lines_a = Path('/app/logs/server_a.log').read_text().splitlines(keepends=True)
    lines_b = Path('/app/logs/server_b.log').read_text().splitlines(keepends=True)
    merged = sorted(set(lines_a + lines_b))

    with tempfile.TemporaryDirectory() as td:
        merged_path = Path(td, 'merged.log')
        merged_path.write_text(''.join(merged))
        baseline = Path('/app/logs/baseline.log')
        expected_forward = make_expected_diff(merged_path, baseline)
        expected_reverse = make_expected_diff(baseline, merged_path)

    actual_text = DIFF_OUT.read_text(errors='replace')
    actual_body = normalized_diff_body(actual_text)
    assert actual_body, 'diff.out is not a non-empty unified diff'
    assert actual_body in (expected_forward, expected_reverse), \
        f'diff.out does not match a recomputed diff. Actual:\n{actual_text}'

    # Retain the original content assertions.
    assert ('-192.168.1.20 - GET /unknown' in actual_text or
            '+192.168.1.20 - GET /unknown' in actual_text)
    assert '192.168.1.10' in actual_text
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
