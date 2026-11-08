#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
from pathlib import Path
import re
import secrets
import string
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

import pytest

WORKSPACE = Path('/home/user/workspace')
PROJECT = WORKSPACE / 'log-merger'
OUTPUT = WORKSPACE / 'output'
MERGED = OUTPUT / 'merged.log'
DIFF = OUTPUT / 'diff.txt'
BASELINE = WORKSPACE / 'logs/baseline.log'


def expected_hash(value):
    return sum(ord(c) for c in value) % 256


def random_cases(count=40):
    alphabet = string.ascii_letters + string.digits + ' !@#$%^&*()-_=+[]{}:,.?/'
    cases = ['', 'a', 'A B', '0' * 257]
    for _ in range(count):
        size = secrets.randbelow(500)
        cases.append(''.join(secrets.choice(alphabet) for _ in range(size)))
    return cases


def run_hash_module(extra_env=None):
    cases = random_cases()
    code = r'''import fast_hash, json, os
cases = json.loads(os.environ['HASH_CASES'])
print(json.dumps({'origin': fast_hash.__file__, 'values': [fast_hash.fast_hash(x) for x in cases]}))
'''
    env = os.environ.copy()
    env.pop('PYTHONPATH', None)
    env['HASH_CASES'] = json.dumps(cases)
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        [sys.executable, '-c', code], cwd='/tmp', env=env,
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, result.stdout + result.stderr
    data = json.loads(result.stdout.strip().splitlines()[-1])
    assert any(data['origin'].endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_hash is not a compiled extension: {data['origin']}"
    assert data['values'] == [expected_hash(x) for x in cases]


def test_fast_hash_installed_and_working():
    try:
        import fast_hash
    except ImportError:
        pytest.fail("The 'fast_hash' module could not be imported. Did you install the package?")

    assert hasattr(fast_hash, 'fast_hash'), "Module 'fast_hash' does not have function 'fast_hash'"
    assert any(str(fast_hash.__file__).endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_hash must be a C extension, not {fast_hash.__file__}"

    test_str = '2023-10-01T10:00:05 WARN High memory'
    expected = expected_hash(test_str)
    try:
        actual = fast_hash.fast_hash(test_str)
    except Exception as exc:
        pytest.fail(f'Calling fast_hash failed: {exc}')
    assert actual == expected, f'fast_hash returned {actual}, expected {expected}. C extension logic is incorrect.'

    # Unpredictable cases prevent an implementation hard-coded for verifier examples.
    run_hash_module()


def test_project_sources_really_build_extension():
    assert (PROJECT / 'setup.py').is_file()
    assert (PROJECT / 'fast_hash.c').is_file()

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        build_lib = td / 'lib'
        build_temp = td / 'obj'
        result = subprocess.run(
            [sys.executable, 'setup.py', 'build_ext', '--build-lib', str(build_lib),
             '--build-temp', str(build_temp), '--force'],
            cwd=PROJECT, text=True, capture_output=True, timeout=120
        )
        assert result.returncode == 0, result.stdout + result.stderr
        extensions = [p for p in build_lib.rglob('*')
                      if p.is_file() and any(p.name.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)]
        assert any(p.name.startswith('fast_hash') for p in extensions), \
            'setup.py did not build a fast_hash C extension from the project'
        run_hash_module({'PYTHONPATH': str(build_lib)})


def test_installed_cli_on_unpredictable_logs():
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        records = []
        for i in range(12):
            stamp = f'2042-07-{1 + secrets.randbelow(20):02d}T12:{i:02d}:{secrets.randbelow(60):02d}'
            payload = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))
            records.append(f'{stamp} INFO {payload}')
        secrets.SystemRandom().shuffle(records)
        first, second = records[:6], records[6:]
        (td / 'a.log').write_text('\n'.join(first) + '\n')
        (td / 'b.log').write_text('\n'.join(second) + '\n')

        env = os.environ.copy()
        env.pop('PYTHONPATH', None)
        result = subprocess.run(
            [sys.executable, '-m', 'log_merger', str(td / 'a.log'), str(td / 'b.log')],
            cwd=td, env=env, text=True, capture_output=True, timeout=20
        )
        assert result.returncode == 0, result.stdout + result.stderr
        expected = [f'[{expected_hash(line):03d}] {line}' for line in sorted(records, key=lambda x: x.split()[0])]
        assert result.stdout.splitlines() == expected


def test_merged_log_content():
    assert MERGED.is_file(), f'Merged log file not found at {MERGED}'
    lines = [line.strip() for line in MERGED.read_text().splitlines() if line.strip()]
    expected_lines = [
        '[105] 2023-10-01T10:00:01 INFO DB connected',
        '[114] 2023-10-01T10:00:02 INFO App started',
        '[152] 2023-10-01T10:00:04 ERROR Connection lost',
        '[242] 2023-10-01T10:00:05 WARN High memory'
    ]
    assert lines == expected_lines, 'The content of merged.log does not match the expected sorted and hashed output.'


def test_diff_txt_content():
    assert DIFF.is_file(), f'Diff file not found at {DIFF}'
    content = DIFF.read_text()
    assert '065' in content and 'Normal memory' in content, 'diff.txt does not contain the removed baseline line.'
    assert '242' in content and 'WARN High memory' in content, 'diff.txt does not contain the added merged line.'

    generated = subprocess.run(
        ['diff', str(MERGED), str(BASELINE)], text=True, capture_output=True
    )
    assert generated.returncode in (0, 1)
    assert content == generated.stdout, 'diff.txt is not the exact standard diff output for merged.log and baseline.log'


def fetch(url):
    try:
        response = urllib.request.urlopen(url, timeout=3)
        body = response.read()
        return response, body
    except urllib.error.URLError as exc:
        pytest.fail(f'Could not connect to {url}: {exc}')


def socket_owner_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == port:
                inodes.add(fields[9])
    owners = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                target = os.readlink(fd)
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    owners.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            pass
    return owners


def process_info(pid):
    proc = Path('/proc') / str(pid)
    cmdline = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    comm = (proc / 'comm').read_text().strip()
    cwd = os.readlink(proc / 'cwd')
    return comm, cmdline, cwd


def test_python_http_server_port_9000():
    response, body = fetch('http://127.0.0.1:9000/diff.txt')
    assert response.status == 200, 'Python HTTP server did not return 200 OK for diff.txt'
    assert body == DIFF.read_bytes(), 'Python HTTP server did not serve the exact diff.txt file.'
    content = body.decode('utf-8')
    assert 'Normal memory' in content and 'WARN High memory' in content, 'Python HTTP server did not serve the correct diff.txt content.'

    owners = socket_owner_pids(9000)
    assert owners, 'No process owns a listening socket on port 9000'
    infos = [process_info(pid) for pid in owners]
    assert any('python' in comm.lower() and '-m http.server' in cmd and
               (str(OUTPUT) in cmd or cwd == str(OUTPUT)) for comm, cmd, cwd in infos), \
        f'Port 9000 is not the requested Python http.server serving {OUTPUT}: {infos}'


def test_nginx_reverse_proxy_port_8080():
    response, body = fetch('http://127.0.0.1:8080/diff.txt')
    assert response.status == 200, 'Nginx reverse proxy did not return 200 OK for diff.txt'
    assert body == DIFF.read_bytes(), 'Nginx reverse proxy did not serve the exact diff.txt file.'
    content = body.decode('utf-8')
    assert 'Normal memory' in content and 'WARN High memory' in content, 'Nginx reverse proxy did not serve the correct diff.txt content.'
    server_header = response.getheader('Server')
    assert server_header and 'nginx' in server_header.lower(), f'Expected Nginx server header, got {server_header}'

    owners = socket_owner_pids(8080)
    assert owners, 'No process owns a listening socket on port 8080'
    infos = [process_info(pid) for pid in owners]
    assert any(comm.lower().startswith('nginx') for comm, _, _ in infos), \
        f'Port 8080 is not owned by Nginx: {infos}'


def test_nginx_conf_exists_and_is_effective():
    conf = WORKSPACE / 'nginx.conf'
    assert conf.is_file(), f'Nginx configuration file not found at {conf}'
    content = conf.read_text()

    # Preserve the original assertions.
    assert '8080' in content, 'Nginx config does not contain port 8080.'
    assert '9000' in content, 'Nginx config does not contain proxy pass to port 9000.'
    assert 'nginx_temp' in content, 'Nginx config does not use nginx_temp directory for temp files.'

    active = '\n'.join(line.split('#', 1)[0] for line in content.splitlines())
    assert not re.search(r'(?m)^\s*user\s+', active), 'The custom config must not contain a user directive'
    assert re.search(r'\blisten\s+(?:127\.0\.0\.1:)?8080\s*;', active), 'Nginx must listen on port 8080'
    assert re.search(r'\bproxy_pass\s+http://127\.0\.0\.1:9000/?\s*;', active), \
        'Nginx must reverse proxy to 127.0.0.1:9000'
    assert re.search(r'\bpid\s+/home/user/workspace/nginx_temp/[^;]+;', active), \
        'The Nginx pid must be stored under nginx_temp'
    assert re.search(r'\bclient_body_temp_path\s+/home/user/workspace/nginx_temp(?:/[^;\s]+)?', active), \
        'Client body temporary files must be stored under nginx_temp'

    checked = subprocess.run(['nginx', '-t', '-c', str(conf)], text=True, capture_output=True, timeout=15)
    assert checked.returncode == 0, checked.stdout + checked.stderr

    nginx_cmds = []
    for proc in Path('/proc').iterdir():
        if proc.name.isdigit():
            try:
                comm, cmd, _ = process_info(int(proc.name))
                if comm.lower().startswith('nginx'):
                    nginx_cmds.append(cmd)
            except OSError:
                pass
    assert any(str(conf) in cmd for cmd in nginx_cmds), \
        f'No running Nginx master was started with the requested custom configuration: {nginx_cmds}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
