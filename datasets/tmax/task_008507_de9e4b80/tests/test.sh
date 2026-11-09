#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import signal
import socket
import ssl
import subprocess
import tempfile
import time
import urllib.request
import uuid
from pathlib import Path

HOME = Path('/home/user')
REPO = HOME / 'obs-gitops.git'
DASH = HOME / 'public_html' / 'dashboards'


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def test_git_repo_bare():
    assert REPO.is_dir(), f'{REPO} does not exist or is not a directory'
    res = run(['git', 'rev-parse', '--is-bare-repository'], cwd=REPO)
    assert res.returncode == 0 and res.stdout.strip() == 'true', f'{REPO} is not bare: {res.stderr}'


def test_hook_exists_and_executable():
    hook = REPO / 'hooks' / 'post-receive'
    assert hook.is_file(), f'{hook} does not exist'
    assert os.access(hook, os.X_OK), f'{hook} is not executable'


def test_git_push_and_hook_dynamic_content():
    token = uuid.uuid4().hex
    valid_names = [f'{token}_alpha.json', f'{token}_nested.json', f'{token}_null.json']
    invalid_name = f'{token}_missing.json'
    broken_name = f'{token}_broken.json'
    uppercase_name = f'{token}_upper.JSON'
    text_name = f'{token}.txt'
    expected = {
        valid_names[0]: {'dashboard_id': token, 'name': 'CPU', 'values': [1, 3, 5]},
        valid_names[1]: {'dashboard_id': {'generated': token}, 'enabled': False},
        valid_names[2]: {'dashboard_id': None, 'nonce': token[::-1]},
    }

    # Do not rely on the bare repository's symbolic HEAD: explicitly create and push main.
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(['git', 'init', '-b', 'main', td], check=True, capture_output=True, text=True)
        subprocess.run(['git', 'config', 'user.email', 'test@example.com'], cwd=td, check=True)
        subprocess.run(['git', 'config', 'user.name', 'Test User'], cwd=td, check=True)
        Path(td, valid_names[0]).write_text(json.dumps(expected[valid_names[0]]))
        nested = Path(td, 'nested')
        nested.mkdir()
        Path(nested, valid_names[1]).write_text(json.dumps(expected[valid_names[1]]))
        Path(td, valid_names[2]).write_text(json.dumps(expected[valid_names[2]]))
        Path(td, invalid_name).write_text(json.dumps({'not_dashboard_id': token}))
        Path(td, broken_name).write_text('{ definitely not json')
        Path(td, uppercase_name).write_text(json.dumps({'dashboard_id': token}))
        Path(td, text_name).write_text(json.dumps({'dashboard_id': token}))
        subprocess.run(['git', 'add', '.'], cwd=td, check=True)
        subprocess.run(['git', 'commit', '-m', token], cwd=td, check=True, capture_output=True, text=True)
        subprocess.run(['git', 'remote', 'add', 'origin', str(REPO)], cwd=td, check=True)
        res = run(['git', 'push', '--force', 'origin', 'HEAD:refs/heads/main'], cwd=td)
        assert res.returncode == 0, f'Git push failed: {res.stderr}'

    assert DASH.is_dir(), f'{DASH} was not created'
    # The instruction says to keep the original filename, including for a file in a subdirectory.
    for name, obj in expected.items():
        out = DASH / name
        assert out.is_file(), f'{name} was not extracted'
        assert out.read_bytes() == json.dumps(obj).encode(), f'{name} content was not copied from the commit'
    assert not (DASH / invalid_name).exists(), 'JSON without dashboard_id was copied'
    assert not (DASH / broken_name).exists(), 'malformed JSON was copied'
    assert not (DASH / uppercase_name).exists(), 'non-.json suffix was copied'
    assert not (DASH / text_name).exists(), 'non-JSON filename was copied'

    # A non-main update must be ignored.
    other = f'{token}_other.json'
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(['git', 'init', '-b', 'topic', td], check=True, capture_output=True, text=True)
        subprocess.run(['git', 'config', 'user.email', 'test@example.com'], cwd=td, check=True)
        subprocess.run(['git', 'config', 'user.name', 'Test User'], cwd=td, check=True)
        Path(td, other).write_text(json.dumps({'dashboard_id': token}))
        subprocess.run(['git', 'add', '.'], cwd=td, check=True)
        subprocess.run(['git', 'commit', '-m', token], cwd=td, check=True, capture_output=True, text=True)
        subprocess.run(['git', 'remote', 'add', 'origin', str(REPO)], cwd=td, check=True)
        res = run(['git', 'push', '--force', 'origin', 'HEAD:refs/heads/topic'], cwd=td)
        assert res.returncode == 0, f'topic push failed: {res.stderr}'
    assert not (DASH / other).exists(), 'hook processed a branch other than main'


def test_certificate_and_key():
    cert = HOME / 'certs' / 'cert.pem'
    key = HOME / 'certs' / 'key.pem'
    assert cert.is_file(), f'{cert} does not exist'
    assert key.is_file(), f'{key} does not exist'
    res = run(['openssl', 'x509', '-in', str(cert), '-noout', '-subject', '-checkend', '0'])
    assert res.returncode == 0, f'invalid or expired certificate: {res.stderr}'
    assert 'CN = localhost' in res.stdout or 'CN=localhost' in res.stdout, f'certificate CN is not localhost: {res.stdout}'
    cert_pub = subprocess.run(['openssl', 'x509', '-in', str(cert), '-pubkey', '-noout'], capture_output=True, check=True).stdout
    key_pub = subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout'], capture_output=True, check=True).stdout
    assert cert_pub == key_pub, 'certificate and private key do not match'


def test_webserver_pid_tls_and_document_root():
    script = HOME / 'start_server.py'
    pid_file = HOME / 'webserver.pid'
    assert script.is_file(), f'{script} does not exist'
    assert pid_file.is_file(), f'{pid_file} does not exist'
    try:
        pid = int(pid_file.read_text().strip())
    except ValueError:
        assert False, 'PID file does not contain an integer'
    os.kill(pid, 0)
    cmdline = Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    assert str(script) in cmdline, f'PID {pid} is not running {script}: {cmdline}'

    marker = f'root-{uuid.uuid4().hex}.txt'
    marker_path = HOME / 'public_html' / marker
    marker_body = uuid.uuid4().hex
    marker_path.parent.mkdir(parents=True, exist_ok=True)
    marker_path.write_text(marker_body)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(f'https://localhost:8443/{marker}', context=ctx, timeout=5) as resp:
            assert resp.status == 200
            assert resp.read().decode() == marker_body, 'server is not serving /home/user/public_html'
        # Confirm the live endpoint presents the required certificate CN.
        with socket.create_connection(('localhost', 8443), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname='localhost') as tls:
                der = tls.getpeercert(binary_form=True)
        with tempfile.NamedTemporaryFile() as tf:
            tf.write(ssl.DER_cert_to_PEM_cert(der).encode()); tf.flush()
            subject = run(['openssl', 'x509', '-in', tf.name, '-noout', '-subject'])
        assert 'CN = localhost' in subject.stdout or 'CN=localhost' in subject.stdout
    finally:
        marker_path.unlink(missing_ok=True)


def test_health_check_dynamic_count_and_down_path():
    script = HOME / 'health_check.py'
    health = HOME / 'public_html' / 'health.json'
    pid_file = HOME / 'webserver.pid'
    assert script.is_file(), f'{script} does not exist'
    DASH.mkdir(parents=True, exist_ok=True)

    # Derive a fresh expected count rather than accepting a fixed answer.
    names = [f'health-{uuid.uuid4().hex}.json' for _ in range(4)]
    noise = f'health-{uuid.uuid4().hex}.txt'
    for name in names:
        (DASH / name).write_text('{}')
    (DASH / noise).write_text('{}')
    expected = sum(1 for p in DASH.iterdir() if p.is_file() and p.name.endswith('.json'))
    res = run(['python3', str(script)], timeout=15)
    assert res.returncode == 0, f'health check failed: {res.stderr}'
    data = json.loads(health.read_text())
    assert data == {'status': 'up', 'dashboard_count': expected}, f'incorrect health result: {data}, expected count {expected}'

    # Stop the actual recorded server and require the script to detect failure.
    pid = int(pid_file.read_text().strip())
    os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(.1)
    else:
        os.kill(pid, signal.SIGKILL)
        time.sleep(.2)
    res = run(['python3', str(script)], timeout=15)
    assert res.returncode == 0, f'health check failed on down path: {res.stderr}'
    assert json.loads(health.read_text()) == {'status': 'down', 'dashboard_count': 0}


def test_cron_job():
    res = run(['crontab', '-l', '-u', 'user'])
    assert res.returncode == 0, "Failed to read crontab for user 'user'"
    active = [line.strip() for line in res.stdout.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    assert any(line.split()[:5] == ['*', '*', '*', '*', '*'] and '/home/user/health_check.py' in line for line in active), 'required every-minute health-check cron entry missing'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
