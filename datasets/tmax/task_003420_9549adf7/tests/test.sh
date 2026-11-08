#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import secrets
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

HOME = Path('/home/user')
CSV = HOME / 'data/usage.csv'
SOURCE = HOME / 'src/analyzer.rs'
DEPLOY = HOME / 'deploy.sh'
APP = HOME / 'planner_app'
RELEASES = APP / 'releases'
CURRENT = APP / 'current'
CERT = APP / 'shared/certs/cert.pem'
KEY = APP / 'shared/certs/key.pem'


def fetch_report(expected_cpu, expected_mem):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    last_error = None
    for _ in range(5):
        try:
            with urllib.request.urlopen(
                'https://localhost:9443/report.json', context=ctx, timeout=3
            ) as response:
                assert response.status == 200
                data = json.loads(response.read().decode('utf-8'))
                assert round(float(data['avg_cpu']), 2) == expected_cpu
                assert round(float(data['avg_mem']), 2) == expected_mem
                return
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last_error = exc
            time.sleep(1)
    pytest.fail(f'Failed to fetch report over TLS: {last_error}')


def test_deploy_script_exists():
    script_path = '/home/user/deploy.sh'
    assert os.path.isfile(script_path), f'Deployment script {script_path} is missing.'


def test_symlink_and_release_directory():
    current_link = '/home/user/planner_app/current'
    assert os.path.islink(current_link), f'{current_link} is not a symlink.'
    target_dir = os.readlink(current_link)
    assert os.path.isdir(current_link), f'Symlink {current_link} does not point to a valid directory.'
    assert 'releases' in target_dir or target_dir.startswith('/home/user/planner_app/releases/'), \
        f'Symlink target {target_dir} does not seem to be in the releases directory.'


def test_tls_certificates_exist():
    assert CERT.is_file(), f'TLS certificate missing at {CERT}'
    assert KEY.is_file(), f'TLS private key missing at {KEY}'


def test_analyzer_binary_and_report_json():
    analyzer_path = CURRENT / 'analyzer'
    report_path = CURRENT / 'report.json'
    assert analyzer_path.is_file(), f'Analyzer binary missing at {analyzer_path}'
    assert os.access(analyzer_path, os.X_OK), f'Analyzer binary at {analyzer_path} is not executable'
    assert report_path.is_file(), f'report.json missing at {report_path}'
    try:
        data = json.loads(report_path.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'File {report_path} does not contain valid JSON.')
    assert 'avg_cpu' in data, "report.json missing 'avg_cpu' key"
    assert 'avg_mem' in data, "report.json missing 'avg_mem' key"
    assert round(float(data['avg_cpu']), 2) == 53.67
    assert round(float(data['avg_mem']), 2) == 1536.00


def test_web_server_serving_report():
    fetch_report(53.67, 1536.00)


def make_fixture():
    rng = secrets.SystemRandom()
    cpu = [rng.randrange(1000, 9000) for _ in range(4)]
    cpu[-1] += (-sum(cpu)) % 4
    mem = [rng.randrange(50000, 400000) for _ in range(4)]
    mem[-1] += (-sum(mem)) % 4
    base = rng.randrange(1700000000, 1900000000)
    rows = [f'{base + i * 60},{cpu[i] / 100:.2f},{mem[i] / 100:.2f}' for i in range(4)]
    return '\n'.join(rows) + '\n', sum(cpu) / 400, sum(mem) / 400


def assert_exact_report(path, cpu, mem):
    expected = f'{{"avg_cpu": {cpu:.2f}, "avg_mem": {mem:.2f}}}'
    actual = Path(path).read_text().strip()
    assert actual == expected, f'Expected exact report {expected!r}, got {actual!r}'
    assert json.loads(actual) == {'avg_cpu': cpu, 'avg_mem': mem}


def openssl_pids():
    result = subprocess.run(['pgrep', '-x', 'openssl'], text=True, capture_output=True)
    if result.returncode != 0:
        return set()
    return {int(value) for value in result.stdout.split() if value.isdigit()}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def wait_past(epoch):
    while int(time.time()) <= epoch:
        time.sleep(0.1)


def run_deploy(previous_release=None):
    before_dirs = set(RELEASES.iterdir()) if RELEASES.exists() else set()
    old_server_pids = openssl_pids()
    start = int(time.time())
    with tempfile.TemporaryDirectory() as work:
        result = subprocess.run(
            ['bash', str(DEPLOY)], cwd=work, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
        )
    assert result.returncode == 0, f'deploy.sh failed:\n{result.stdout}'
    end = int(time.time())

    assert CURRENT.is_symlink(), 'deploy.sh did not create current as a symlink'
    release = CURRENT.resolve(strict=True)
    releases_root = RELEASES.resolve(strict=True)
    assert release.parent == releases_root, f'{release} is not directly under releases/'
    assert release not in before_dirs, 'deploy.sh did not create a new release directory'
    if previous_release is not None:
        assert release != previous_release, 'successive deployments reused a release directory'
    assert release.name.isdigit(), 'release directory name is not a Unix epoch timestamp'
    stamp = int(release.name)
    assert start - 1 <= stamp <= end + 1, 'release timestamp does not match deployment time'

    for pid in old_server_pids:
        assert not Path(f'/proc/{pid}').exists(), f'old openssl s_server process {pid} was not killed'
    assert openssl_pids(), 'no openssl s_server process is running after deployment'

    analyzer = release / 'analyzer'
    assert analyzer.is_file() and os.access(analyzer, os.X_OK)
    assert analyzer.read_bytes()[:4] == b'\x7fELF', 'deployed analyzer is not a compiled native binary'
    return release


def validate_certificate():
    subject = subprocess.run(
        ['openssl', 'x509', '-in', str(CERT), '-noout', '-subject'],
        check=True, text=True, capture_output=True
    ).stdout
    assert 'CN = localhost' in subject or 'CN=localhost' in subject
    assert subprocess.run(
        ['openssl', 'x509', '-in', str(CERT), '-noout', '-checkend', str(364 * 86400)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0, 'certificate is not valid for approximately 365 days'
    assert subprocess.run(
        ['openssl', 'x509', '-in', str(CERT), '-noout', '-checkend', str(366 * 86400)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode != 0, 'certificate validity is longer than requested'

    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', str(CERT), '-pubkey', '-noout'],
        check=True, capture_output=True
    ).stdout
    key_pub = subprocess.run(
        ['openssl', 'pkey', '-in', str(KEY), '-pubout'],
        check=True, capture_output=True
    ).stdout
    assert cert_pub == key_pub, 'TLS certificate and private key do not match'
    key_text = subprocess.run(
        ['openssl', 'pkey', '-in', str(KEY), '-text', '-noout'],
        check=True, text=True, capture_output=True
    ).stdout
    assert 'Private-Key:' in key_text and ('2048 bit' in key_text or 'RSA' in key_text)


def test_dynamic_analyzer_and_deployment_sequence():
    assert SOURCE.is_file(), f'Rust source is missing at {SOURCE}'
    fixture1, cpu1, mem1 = make_fixture()
    fixture2, cpu2, mem2 = make_fixture()
    while fixture2 == fixture1:
        fixture2, cpu2, mem2 = make_fixture()

    CSV.write_text(fixture1)

    # Independently compile and execute the submitted Rust source on unpredictable input.
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / 'analyzer'
        compile_result = subprocess.run(
            ['rustc', str(SOURCE), '-o', str(binary)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert compile_result.returncode == 0, f'analyzer.rs does not compile:\n{compile_result.stdout}'
        run_result = subprocess.run(
            [str(binary)], cwd=tmp, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert run_result.returncode == 0, f'compiled analyzer failed:\n{run_result.stdout}'
        assert_exact_report(Path(tmp) / 'report.json', cpu1, mem1)

    # Force deploy.sh to exercise certificate generation rather than accepting fixtures.
    CERT.unlink(missing_ok=True)
    KEY.unlink(missing_ok=True)
    release1 = run_deploy()
    assert_exact_report(release1 / 'report.json', cpu1, mem1)
    assert CERT.is_file() and KEY.is_file()
    validate_certificate()
    fetch_report(cpu1, mem1)

    cert_hash = sha256(CERT)
    key_hash = sha256(KEY)
    wait_past(int(release1.name))

    # A second changed input checks new releases and certificate preservation.
    CSV.write_text(fixture2)
    release2 = run_deploy(release1)
    assert sha256(CERT) == cert_hash, 'deploy.sh replaced an existing certificate'
    assert sha256(KEY) == key_hash, 'deploy.sh replaced an existing private key'
    assert_exact_report(release2 / 'report.json', cpu2, mem2)

    # Execute the deployed artifact itself, proving the release contains the analyzer.
    (release2 / 'report.json').unlink()
    result = subprocess.run(
        [str(release2 / 'analyzer')], cwd=release2, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f'deployed analyzer failed:\n{result.stdout}'
    assert_exact_report(release2 / 'report.json', cpu2, mem2)
    fetch_report(cpu2, mem2)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
