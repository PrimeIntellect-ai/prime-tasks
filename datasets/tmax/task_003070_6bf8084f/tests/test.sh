#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest

GATEWAY = Path('/home/user/gateway')
DEPLOY = Path('/home/user/deploy')
CURRENT = DEPLOY / 'current'


def test_config_updated():
    config_path = GATEWAY / 'config/settings.toml'
    assert config_path.is_file(), f'Config file {config_path} is missing'
    content = config_path.read_text()

    # Preserve the original assertion.
    assert 'upstream_port = 8081' in content, 'Config file was not updated to upstream_port = 8081'

    # The gateway reads every line beginning with upstream_port and uses the last
    # one. Require one real, parseable assignment rather than a matching comment
    # or an appended decoy alongside the bad setting.
    assignments = []
    for line in content.splitlines():
        if line.startswith('upstream_port'):
            parts = line.split('=', 1)
            assert len(parts) == 2, 'Malformed upstream_port assignment'
            assignments.append(parts[1].strip())
    assert assignments == ['8081'], f'Expected exactly one effective upstream_port assignment, got {assignments}'


def assert_elf_executable(path):
    path = Path(path)
    assert path.is_file(), f'Compiled binary {path} is missing'
    assert os.access(path, os.X_OK), f'Compiled binary {path} is not executable'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not a compiled ELF binary'


def test_deployment_pipeline():
    deploy_script = Path('/home/user/deploy.sh')
    assert deploy_script.is_file(), f'Deploy script {deploy_script} is missing'
    assert os.access(deploy_script, os.X_OK), f'Deploy script {deploy_script} is not executable'

    # Preserve the original final-state checks before exercising the script.
    assert CURRENT.is_symlink(), f'{CURRENT} is not a symlink'
    assert (CURRENT / 'payload_filter').is_file(), f'Compiled binary {CURRENT / "payload_filter"} is missing'
    assert (CURRENT / 'gateway_server').is_file(), f'Compiled binary {CURRENT / "gateway_server"} is missing'

    # Install a controlled prior active release so backup behavior is observable.
    previous = DEPLOY / 'releases' / ('verifier_previous_' + uuid.uuid4().hex)
    previous.mkdir(parents=True)
    (previous / 'marker.txt').write_text('previous release\n')
    CURRENT.unlink()
    os.symlink(str(previous.resolve()), CURRENT)

    backup = DEPLOY / 'backups/last_active.txt'
    if backup.exists() or backup.is_symlink():
        backup.unlink()

    # Removing Cargo's final artifacts ensures this invocation must recreate the
    # release outputs instead of merely re-pointing current at stale target files.
    for name in ('payload_filter', 'gateway_server'):
        target = GATEWAY / 'target/release' / name
        if target.exists() or target.is_symlink():
            target.unlink()

    started = int(time.time())
    result = subprocess.run(
        [str(deploy_script)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    finished = int(time.time())
    assert result.returncode == 0, f'deploy.sh failed with code {result.returncode}:\n{result.stdout}'

    assert CURRENT.is_symlink(), f'{CURRENT} is not a symlink after deploy.sh ran'
    new_release = CURRENT.resolve()
    assert new_release.is_dir(), 'current does not resolve to a release directory'
    assert new_release.parent.resolve() == (DEPLOY / 'releases').resolve(), 'current points outside deploy/releases'
    assert new_release != previous.resolve(), 'deploy.sh did not activate a new release'
    assert re.fullmatch(r'\d+', new_release.name), 'New release directory is not named with an epoch timestamp'
    stamp = int(new_release.name)
    assert started - 2 <= stamp <= finished + 2, 'Release timestamp was not created by this deploy invocation'

    assert backup.is_file(), 'last_active.txt was not created for the previous symlink target'
    assert backup.read_text().strip() == str(previous.resolve()), 'last_active.txt does not contain the absolute previous release path'

    assert_elf_executable(new_release / 'payload_filter')
    assert_elf_executable(new_release / 'gateway_server')


def run_filter(binary, path):
    try:
        return subprocess.run([str(binary), str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f'payload_filter timed out on {path}')


def is_malicious(value):
    if isinstance(value, dict):
        return any(k == '__proto__' or is_malicious(v) for k, v in value.items())
    if isinstance(value, list):
        return any(is_malicious(v) for v in value)
    return isinstance(value, str) and '<script>' in value


def random_clean(rng, depth=0):
    if depth >= 4:
        choices = [None, True, False, rng.randint(-100000, 100000), rng.random(),
                   uuid.uuid4().hex, '__proto__ is text', '<SCRIPT>', 'script>', '<script']
        return rng.choice(choices)
    kind = rng.choice(['scalar', 'list', 'dict'])
    if kind == 'scalar':
        return random_clean(rng, 4)
    if kind == 'list':
        return [random_clean(rng, depth + 1) for _ in range(rng.randint(0, 5))]
    result = {}
    for _ in range(rng.randint(0, 5)):
        key = rng.choice(['normal', '__proto__x', 'x__proto__', 'constructor', uuid.uuid4().hex])
        result[key] = random_clean(rng, depth + 1)
    return result


def test_adversarial_corpus():
    payload_filter = CURRENT / 'payload_filter'
    assert payload_filter.is_file(), 'payload_filter binary missing, cannot test corpus'

    # Preserve all original fixed-corpus assertions.
    clean_files = glob.glob('/home/user/corpora/clean/*')
    evil_files = glob.glob('/home/user/corpora/evil/*')
    assert clean_files, 'No clean corpus files found'
    assert evil_files, 'No evil corpus files found'
    clean_failed = [os.path.basename(p) for p in clean_files if run_filter(payload_filter, p) != 0]
    evil_failed = [os.path.basename(p) for p in evil_files if run_filter(payload_filter, p) != 1]
    errors = []
    if evil_failed:
        errors.append(f'{len(evil_failed)} of {len(evil_files)} evil bypassed: {", ".join(evil_failed)}')
    if clean_failed:
        errors.append(f'{len(clean_failed)} of {len(clean_files)} clean modified: {", ".join(clean_failed)}')
    assert not errors, ' | '.join(errors)

    # Generate an unpredictable corpus and derive every expected answer by
    # recursively inspecting the parsed JSON value.
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = []
    for _ in range(35):
        clean = random_clean(rng)
        cases.append(clean)
        token = uuid.uuid4().hex
        evil_variants = [
            {'outer_' + token: [clean, {'__proto__': {'admin': True}}]},
            {'outer_' + token: {'inner': ['safe', 'prefix<script>suffix']}},
            [clean, {'deep': [{'deeper': {'__proto__': token}}]}],
            {'text': ['safe', '<script>', {'tail': token}]},
        ]
        cases.append(rng.choice(evil_variants))

    with tempfile.TemporaryDirectory(prefix='payload_hidden_') as td:
        for value in cases:
            name = uuid.uuid4().hex + '.json'
            path = Path(td) / name
            # ensure_ascii also exercises escaped Unicode while the filter must
            # decide based on the decoded JSON strings and keys.
            path.write_text(json.dumps(value, ensure_ascii=True, separators=(',', ':')))
            expected = 1 if is_malicious(value) else 0
            actual = run_filter(payload_filter, path)
            assert actual == expected, f'Wrong exit code for generated JSON {name}: expected {expected}, got {actual}'


def kill_port_listeners(*ports):
    wanted = {format(p, '04X') for p in ports}
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            cols = line.split()
            if len(cols) > 9 and cols[1].rsplit(':', 1)[-1].upper() in wanted and cols[3] == '0A':
                inodes.add(cols[9])
    victims = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(proc.name))
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)


def test_deployed_gateway_proxies_to_backend():
    gateway = CURRENT / 'gateway_server'
    assert_elf_executable(gateway)
    kill_port_listeners(8080, 8081)

    nonce = 'upstream-' + uuid.uuid4().hex
    backend_code = r'''import socket, sys
body = sys.argv[1].encode()
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8081))
s.listen(20)
while True:
    c, _ = s.accept()
    try:
        c.settimeout(2)
        c.recv(8192)
        response = b'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ' + str(len(body)).encode() + b'\r\nConnection: close\r\n\r\n' + body
        c.sendall(response)
    finally:
        c.close()
'''
    backend = subprocess.Popen(['python3', '-c', backend_code, nonce], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    gateway_proc = None
    try:
        time.sleep(0.3)
        assert backend.poll() is None, f'Could not start verifier backend on 8081: {backend.stderr.read().decode(errors="replace")}'
        gateway_proc = subprocess.Popen([str(gateway)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        time.sleep(0.4)
        assert gateway_proc.poll() is None, f'Deployed gateway failed to bind/start: {gateway_proc.stderr.read().decode(errors="replace")}'

        response = None
        last_error = ''
        for _ in range(8):
            result = subprocess.run(
                ['curl', '--silent', '--show-error', '--max-time', '3', 'http://127.0.0.1:8080/api'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if result.returncode == 0:
                response = result.stdout
                break
            last_error = result.stderr
            time.sleep(0.2)
        assert response is not None, f'curl to deployed gateway failed: {last_error}'
        assert response == nonce, f'Gateway did not proxy the backend response; got {response!r}'
    finally:
        if gateway_proc is not None and gateway_proc.poll() is None:
            gateway_proc.terminate()
            try:
                gateway_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                gateway_proc.kill()
        if backend.poll() is None:
            backend.terminate()
            try:
                backend.wait(timeout=3)
            except subprocess.TimeoutExpired:
                backend.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
