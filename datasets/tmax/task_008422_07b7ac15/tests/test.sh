#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import datetime
import os
import pathlib
import shlex
import socket
import ssl
import subprocess
import tempfile
import urllib.request
import uuid

import pytest

HOME = pathlib.Path('/home/user')


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=15, **kwargs)


def test_user_prov_executable():
    executable_path = '/home/user/user_prov'
    assert os.path.isfile(executable_path), f'Executable missing: {executable_path}'
    assert os.access(executable_path, os.X_OK), f'File is not executable: {executable_path}'
    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'user_prov is not a compiled ELF executable'

    token = uuid.uuid4().hex[:12]
    department = 'dept' + uuid.uuid4().hex[:10]
    with tempfile.TemporaryDirectory() as td:
        result = run([executable_path], cwd=td, input=f'{token}\n{department}\n')
        assert result.returncode == 0, result.stderr
        profile = pathlib.Path(td) / f'{token}_profile.txt'
        assert profile.is_file(), 'user_prov did not create a profile for dynamic input'
        assert profile.read_text() == f'USER:{token}\nDEPT:{department}\nSTATUS:ACTIVE\n'


def test_expect_script_exists_accepts_exactly_two_args_and_drives_program():
    script = HOME / 'auto_prov.exp'
    assert script.is_file(), f'Expect script missing: {script}'

    user = 'u' + uuid.uuid4().hex[:12]
    dept = 'd' + uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory() as td:
        result = run(['expect', str(script), user, dept], cwd=td)
        assert result.returncode == 0, result.stderr
        profile = pathlib.Path(td) / f'{user}_profile.txt'
        assert profile.is_file(), 'Expect script did not drive user_prov'
        assert profile.read_text() == f'USER:{user}\nDEPT:{dept}\nSTATUS:ACTIVE\n'

    for args in ([], ['only_one'], ['one', 'two', 'three']):
        with tempfile.TemporaryDirectory() as td:
            result = run(['expect', str(script), *args], cwd=td)
            assert result.returncode != 0, 'auto_prov.exp must reject argument counts other than two'
            assert not list(pathlib.Path(td).glob('*_profile.txt'))


def test_profiles_generated():
    expected_profiles = {
        'alice': 'engineering',
        'bob': 'sales',
        'charlie': 'hr'
    }

    for user, dept in expected_profiles.items():
        profile_path = f'/home/user/public_html/{user}_profile.txt'
        assert os.path.isfile(profile_path), f'Profile missing: {profile_path}'

        with open(profile_path, 'r') as f:
            content = f.read()

        assert f'USER:{user}' in content, f'Profile for {user} missing USER field'
        assert f'DEPT:{dept}' in content, f'Profile for {user} missing DEPT field'
        assert 'STATUS:ACTIVE' in content, f'Profile for {user} missing STATUS field'


def test_batch_script_processes_current_csv_via_expect():
    script = HOME / 'batch_prov.sh'
    expect_script = HOME / 'auto_prov.exp'
    csv_path = HOME / 'users.csv'
    public = HOME / 'public_html'
    assert script.is_file(), f'Batch script missing: {script}'
    text = script.read_text()
    assert 'auto_prov.exp' in text, 'batch_prov.sh does not use auto_prov.exp'

    rows = [
        ('batch' + uuid.uuid4().hex[:10], 'dep' + uuid.uuid4().hex[:8]),
        ('batch' + uuid.uuid4().hex[:10], 'dep' + uuid.uuid4().hex[:8]),
    ]
    original_csv = csv_path.read_bytes()
    generated = [public / f'{user}_profile.txt' for user, _ in rows]
    try:
        csv_path.write_text(''.join(f'{user},{dept}\n' for user, dept in rows))
        result = run(['bash', str(script)], cwd=str(HOME))
        assert result.returncode == 0, result.stderr
        assert public.is_dir(), 'batch_prov.sh did not ensure public_html exists'
        for (user, dept), profile in zip(rows, generated):
            assert profile.is_file(), f'Batch profile missing: {profile}'
            assert profile.read_text() == f'USER:{user}\nDEPT:{dept}\nSTATUS:ACTIVE\n'
        for user, _ in rows:
            assert not (HOME / f'{user}_profile.txt').exists(), 'Generated profile was not moved to public_html'
    finally:
        csv_path.write_bytes(original_csv)
        for profile in generated:
            profile.unlink(missing_ok=True)


def test_certificate_and_key():
    cert = HOME / 'certs/cert.pem'
    key = HOME / 'certs/key.pem'
    assert cert.is_file(), 'cert.pem is missing'
    assert key.is_file(), 'key.pem is missing'
    assert b'ENCRYPTED' not in key.read_bytes(), 'Private key must be unencrypted'

    key_info = run(['openssl', 'pkey', '-in', str(key), '-text', '-noout'])
    assert key_info.returncode == 0, key_info.stderr
    assert '2048 bit' in key_info.stdout.lower(), 'Private key is not 2048-bit'
    assert 'rsa' in key_info.stdout.lower(), 'Private key is not RSA'

    cert_info = run(['openssl', 'x509', '-in', str(cert), '-noout', '-subject', '-issuer', '-dates'])
    assert cert_info.returncode == 0, cert_info.stderr
    fields = dict(line.split('=', 1) for line in cert_info.stdout.splitlines() if '=' in line)
    assert fields.get('subject') == fields.get('issuer'), 'Certificate is not self-signed'
    fmt = '%b %d %H:%M:%S %Y %Z'
    not_before = datetime.datetime.strptime(fields['notBefore'], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(fields['notAfter'], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), 'Certificate is not valid for 365 days'
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, 'Certificate is not currently valid'

    verify = run(['openssl', 'verify', '-CAfile', str(cert), str(cert)])
    assert verify.returncode == 0, verify.stderr
    key_pub = run(['openssl', 'pkey', '-in', str(key), '-pubout'])
    cert_pub = run(['openssl', 'x509', '-in', str(cert), '-pubkey', '-noout'])
    assert key_pub.returncode == cert_pub.returncode == 0
    assert key_pub.stdout == cert_pub.stdout, 'Certificate and private key do not match'


def test_https_server_and_supervisor_configuration():
    server = HOME / 'https_server.py'
    conf = HOME / 'supervisord.conf'
    assert server.is_file(), 'https_server.py is missing'
    assert conf.is_file(), 'supervisord.conf is missing'
    compile_result = run(['python3', '-m', 'py_compile', str(server)])
    assert compile_result.returncode == 0, compile_result.stderr

    parser = configparser.RawConfigParser()
    parser.read(conf)
    assert parser.has_section('program:webserver'), 'Missing [program:webserver] section'
    command = parser.get('program:webserver', 'command')
    argv = shlex.split(command)
    assert argv and os.path.basename(argv[0]).startswith('python'), 'Supervisor command must run Python'
    assert '/home/user/https_server.py' in argv, 'Supervisor command does not run https_server.py'
    expected_log = '/home/user/logs/webserver.log'
    assert parser.get('program:webserver', 'stdout_logfile') == expected_log
    assert parser.get('program:webserver', 'stderr_logfile') == expected_log

    matching_process = False
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            args = (proc / 'cmdline').read_bytes().split(b'\0')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        decoded = [a.decode(errors='replace') for a in args if a]
        if decoded and os.path.basename(decoded[0]).startswith('python') and '/home/user/https_server.py' in decoded:
            matching_process = True
            break
    assert matching_process, 'The supervised Python HTTPS server process is not running'


def test_log_file_exists():
    log_path = '/home/user/logs/webserver.log'
    assert os.path.isfile(log_path), f'Log file missing: {log_path}'


def test_supervisor_running():
    try:
        output = subprocess.check_output(['pgrep', '-f', 'supervisord.*supervisord.conf']).decode()
        assert output.strip() != '', 'supervisord with custom conf is not running'
    except subprocess.CalledProcessError:
        pytest.fail('supervisord process using /home/user/supervisord.conf not found')


def test_https_server():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    url = 'https://127.0.0.1:8443/alice_profile.txt'
    try:
        with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
            content = response.read().decode('utf-8')
            assert 'USER:alice' in content, 'HTTPS response missing expected USER content'
            assert 'DEPT:engineering' in content, 'HTTPS response missing expected DEPT content'
    except Exception as e:
        pytest.fail(f'Failed to fetch {url} over HTTPS: {e}')

    token = uuid.uuid4().hex
    dynamic_file = HOME / 'public_html' / f'verifier-{token}.txt'
    dynamic_content = 'dynamic-' + uuid.uuid4().hex
    dynamic_file.write_text(dynamic_content)
    try:
        with urllib.request.urlopen(f'https://127.0.0.1:8443/{dynamic_file.name}', context=ctx, timeout=5) as response:
            assert response.read().decode() == dynamic_content, 'Server is not serving public_html dynamically'
    finally:
        dynamic_file.unlink(missing_ok=True)

    pem = (HOME / 'certs/cert.pem').read_text()
    expected_der = ssl.PEM_cert_to_DER_cert(pem)
    with socket.create_connection(('127.0.0.1', 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname='127.0.0.1') as tls:
            assert tls.getpeercert(binary_form=True) == expected_der, 'Server is not using cert.pem'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
