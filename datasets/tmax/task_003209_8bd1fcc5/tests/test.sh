#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import re
import socket
import ssl
import subprocess
import tarfile
import urllib.request
from pathlib import Path

import pytest

HOME = Path('/home/user')


def read_json_metric(path):
    path = Path(path)
    assert path.exists(), f'{path} does not exist.'
    raw = path.read_text().strip()
    assert re.fullmatch(r'\{"vmem_pages"\s*:\s*\d+\}', raw), f'Invalid metrics JSON: {raw}'
    data = json.loads(raw)
    assert set(data) == {'vmem_pages'}, 'Metrics JSON must contain only vmem_pages.'
    assert isinstance(data['vmem_pages'], int) and not isinstance(data['vmem_pages'], bool)
    return data['vmem_pages']


def statm_pages(pid):
    return int(Path(f'/proc/{pid}/statm').read_text().split()[0])


def option_value(args, option):
    for index, arg in enumerate(args):
        if arg == option and index + 1 < len(args):
            return args[index + 1]
        if arg.startswith(option + '='):
            return arg.split('=', 1)[1]
    return None


def run_analyzer(binary, output, expected_pid):
    output = Path(output)
    output.unlink(missing_ok=True)
    before = statm_pages(expected_pid)
    env = os.environ.copy()
    env['METRICS_FILE'] = str(output)
    result = subprocess.run([str(binary)], env=env, text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f'Analyzer failed: {result.stdout}\n{result.stderr}'
    after = statm_pages(expected_pid)
    measured = read_json_metric(output)
    assert measured in {before, after}, f'Analyzer reported {measured}, but /proc/{expected_pid}/statm reported {before}/{after}.'


def test_required_directories():
    for path in [
        HOME / 'capacity_planner', HOME / 'metrics', HOME / 'tls',
        HOME / 'nginx_temp', HOME / 'backups'
    ]:
        assert path.is_dir(), f'Required directory {path} does not exist.'


def test_qemu_process():
    pid_file = HOME / 'qemu.pid'
    assert pid_file.exists(), 'QEMU PID file /home/user/qemu.pid does not exist.'
    pid_text = pid_file.read_text().strip()
    assert pid_text.isdigit(), f'PID file does not contain a valid integer: {pid_text}'
    pid = int(pid_text)

    proc = Path(f'/proc/{pid}')
    assert proc.exists(), f'Process with PID {pid} is not running.'
    comm = (proc / 'comm').read_text().strip()
    assert 'qemu-system-x86' in comm, f'Process {pid} is not qemu-system-x86_64 (found {comm}).'
    executable = os.path.realpath(proc / 'exe')
    assert os.path.basename(executable) == 'qemu-system-x86_64', f'Unexpected QEMU executable: {executable}'

    args = [part.decode(errors='replace') for part in (proc / 'cmdline').read_bytes().split(b'\0') if part]
    memory = option_value(args, '-m')
    assert memory is not None and re.fullmatch(r'128(?:[mM](?:[bB])?)?', memory), f'QEMU memory is not 128 MB: {memory}'
    assert option_value(args, '-vnc') == '127.0.0.1:5', f'QEMU VNC arguments are incorrect: {args}'
    assert '-daemonize' in args, 'QEMU was not started with -daemonize.'

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(2)
        assert sock.connect_ex(('127.0.0.1', 5905)) == 0, 'QEMU is not listening on 127.0.0.1:5905.'


def test_cpp_analyzer():
    cpp_file = HOME / 'capacity_planner/analyzer.cpp'
    bin_file = HOME / 'capacity_planner/analyzer'
    assert cpp_file.is_file(), '/home/user/capacity_planner/analyzer.cpp does not exist.'
    assert bin_file.is_file() and os.access(bin_file, os.X_OK), '/home/user/capacity_planner/analyzer is missing or not executable.'

    bash_profile = HOME / '.bash_profile'
    assert bash_profile.exists(), '/home/user/.bash_profile does not exist.'
    assert 'export METRICS_FILE=/home/user/metrics/current.json' in bash_profile.read_text(), 'METRICS_FILE export is missing in .bash_profile.'

    rebuilt = Path('/tmp/analyzer_rebuilt')
    compile_result = subprocess.run(
        ['g++', str(cpp_file), '-o', str(rebuilt)], text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, f'analyzer.cpp does not compile: {compile_result.stdout}\n{compile_result.stderr}'

    pid_file = HOME / 'qemu.pid'
    original_pid = pid_file.read_text()
    sleeper = subprocess.Popen(['/bin/sleep', '30'])
    try:
        pid_file.write_text(str(sleeper.pid) + '\n')
        run_analyzer(bin_file, HOME / 'metrics/verifier_binary.json', sleeper.pid)
        run_analyzer(rebuilt, HOME / 'metrics/verifier_source.json', sleeper.pid)
    finally:
        pid_file.write_text(original_pid)
        sleeper.terminate()
        try:
            sleeper.wait(timeout=5)
        except subprocess.TimeoutExpired:
            sleeper.kill()

    qemu_pid = int(original_pid.strip())
    run_analyzer(bin_file, HOME / 'metrics/current.json', qemu_pid)


def openssl(*args):
    result = subprocess.run(['openssl', *args], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"OpenSSL command failed: {' '.join(args)}\n{result.stderr}"
    return result.stdout


def test_nginx_tls():
    cert_file = HOME / 'tls/cert.pem'
    key_file = HOME / 'tls/key.pem'
    assert cert_file.is_file(), '/home/user/tls/cert.pem does not exist.'
    assert key_file.is_file(), '/home/user/tls/key.pem does not exist.'

    cert_text = openssl('x509', '-in', str(cert_file), '-noout', '-text')
    assert re.search(r'Public-Key:\s*\(2048 bit\)', cert_text), 'Certificate is not RSA 2048-bit.'
    assert 'rsaEncryption' in cert_text, 'Certificate public key is not RSA.'

    dates = openssl('x509', '-in', str(cert_file), '-noout', '-dates')
    values = dict(line.split('=', 1) for line in dates.strip().splitlines())
    fmt = '%b %d %H:%M:%S %Y %Z'
    not_before = datetime.datetime.strptime(values['notBefore'], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values['notAfter'], fmt).replace(tzinfo=datetime.timezone.utc)
    validity = (not_after - not_before).total_seconds()
    assert 364.5 * 86400 <= validity <= 365.5 * 86400, 'Certificate is not valid for 365 days.'
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, 'Certificate is not currently valid.'

    subject = openssl('x509', '-in', str(cert_file), '-noout', '-subject').split('=', 1)[-1].strip()
    issuer = openssl('x509', '-in', str(cert_file), '-noout', '-issuer').split('=', 1)[-1].strip()
    assert subject == issuer, 'Certificate is not self-signed.'
    openssl('verify', '-CAfile', str(cert_file), str(cert_file))
    cert_pub = openssl('x509', '-in', str(cert_file), '-pubkey', '-noout').strip()
    key_pub = openssl('pkey', '-in', str(key_file), '-pubout').strip()
    assert cert_pub == key_pub, 'TLS private key does not match the certificate.'

    nginx_conf = HOME / 'nginx.conf'
    assert nginx_conf.is_file(), '/home/user/nginx.conf does not exist.'
    nginx_test = subprocess.run(
        ['nginx', '-T', '-c', str(nginx_conf)], text=True, capture_output=True, timeout=10
    )
    assert nginx_test.returncode == 0, f'Nginx configuration is invalid: {nginx_test.stdout}\n{nginx_test.stderr}'
    config = re.sub(r'#.*', '', nginx_test.stdout + '\n' + nginx_test.stderr)

    required_patterns = {
        'SSL listen': r'\blisten\s+8443\s+ssl(?:\s|;)',
        'certificate': r'\bssl_certificate\s+/home/user/tls/cert\.pem\s*;',
        'private key': r'\bssl_certificate_key\s+/home/user/tls/key\.pem\s*;',
        'metrics root': r'\broot\s+/home/user/metrics/?\s*;',
        'pid': r'\bpid\s+(/home/user/nginx_temp/[^;\s]+)\s*;',
        'client body temp': r'\bclient_body_temp_path\s+/home/user/nginx_temp(?:/[^;\s]+)?\s*;',
        'proxy temp': r'\bproxy_temp_path\s+/home/user/nginx_temp(?:/[^;\s]+)?\s*;',
        'fastcgi temp': r'\bfastcgi_temp_path\s+/home/user/nginx_temp(?:/[^;\s]+)?\s*;',
        'uwsgi temp': r'\buwsgi_temp_path\s+/home/user/nginx_temp(?:/[^;\s]+)?\s*;',
        'scgi temp': r'\bscgi_temp_path\s+/home/user/nginx_temp(?:/[^;\s]+)?\s*;',
        'access log': r'\baccess_log\s+/home/user/nginx_temp/access\.log(?:\s+[^;]+)?\s*;',
        'error log': r'\berror_log\s+/home/user/nginx_temp/error\.log(?:\s+\w+)?\s*;'
    }
    matches = {}
    for description, pattern in required_patterns.items():
        match = re.search(pattern, config)
        assert match, f'Nginx configuration is missing or has an incorrect {description} directive.'
        matches[description] = match

    nginx_pid_file = Path(matches['pid'].group(1))
    assert nginx_pid_file.exists(), f'Configured Nginx PID file {nginx_pid_file} does not exist.'
    nginx_pid = nginx_pid_file.read_text().strip()
    assert nginx_pid.isdigit() and Path(f'/proc/{nginx_pid}').exists(), 'Configured Nginx process is not running.'
    assert 'nginx' in Path(f'/proc/{nginx_pid}/comm').read_text(), 'Configured PID is not an Nginx process.'

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen('https://127.0.0.1:8443/current.json', context=context, timeout=5) as response:
            assert response.getcode() == 200, f'Expected HTTP 200, got {response.getcode()}'
            served = response.read().decode().strip()
    except Exception as exc:
        pytest.fail(f'Failed to fetch metrics from Nginx over HTTPS: {exc}')
    assert served == (HOME / 'metrics/current.json').read_text().strip(), 'Nginx did not serve current.json directly from the metrics directory.'
    read_json_metric(HOME / 'metrics/current.json')


def test_backup():
    script = HOME / 'backup.sh'
    assert script.is_file(), '/home/user/backup.sh does not exist.'
    backup_file = HOME / 'backups/metrics_backup.tar.gz'
    backup_file.unlink(missing_ok=True)
    result = subprocess.run(['/bin/bash', str(script)], text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, f'backup.sh failed: {result.stdout}\n{result.stderr}'
    assert backup_file.exists(), 'Backup tarball /home/user/backups/metrics_backup.tar.gz does not exist.'
    assert tarfile.is_tarfile(backup_file), 'Backup file is not a valid tar archive.'

    current = (HOME / 'metrics/current.json').read_text().strip()
    with tarfile.open(backup_file, 'r:gz') as archive:
        names = archive.getnames()
        found = any('current.json' in name for name in names)
        assert found, 'current.json not found inside the backup tarball.'
        members = [member for member in archive.getmembers() if Path(member.name).name == 'current.json' and member.isfile()]
        assert members, 'A regular current.json file was not found inside the backup tarball.'
        extracted = archive.extractfile(members[0])
        assert extracted is not None, 'Could not extract current.json from tarball.'
        content = extracted.read().decode().strip()
        assert re.fullmatch(r'\{"vmem_pages"\s*:\s*\d+\}', content), 'JSON inside backup tarball is invalid.'
        assert content == current, 'Backup does not contain the current metrics file.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
