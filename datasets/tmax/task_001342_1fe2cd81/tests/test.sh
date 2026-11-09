#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import stat
import subprocess
import tarfile
import tempfile

DEPLOY_ENCRYPTED = '/home/user/deploy_bundle.enc'
DEPLOY_BUNDLE = '/home/user/deploy_bundle.tar.gz'
DEPLOY_DIR = '/home/user/deploy'
APP_DIR = os.path.join(DEPLOY_DIR, 'app')
CERTS_DIR = os.path.join(DEPLOY_DIR, 'certs')
NGINX_CONF = os.path.join(DEPLOY_DIR, 'nginx.conf')
CONFIG_JSON = os.path.join(APP_DIR, 'config.json')
INDEX_HTML = os.path.join(APP_DIR, 'index.html')
SERVER_CRT = os.path.join(CERTS_DIR, 'server.crt')
SERVER_KEY = os.path.join(CERTS_DIR, 'server.key')
AUDIT_LOG = '/home/user/audit_log.txt'

EXPECTED_CSP = '''add_header Content-Security-Policy "default-src 'self'; script-src 'self' https://trusted.cdn.com; object-src 'none';";'''
EXPECTED_PASSWORD = 'Deploy2023_4921'
ORIGINAL_NGINX = b'''server {
    listen 443 ssl;
    server_name secure.internal.dev;
    add_header Content-Security-Policy "default-src *";
    location / {
        root /app;
    }
}
'''
EXPECTED_NGINX = ORIGINAL_NGINX.replace(
    b'''add_header Content-Security-Policy "default-src *";''',
    EXPECTED_CSP.encode(),
)
EXPECTED_ARCHIVE_FILES = {
    'nginx.conf': ORIGINAL_NGINX,
    'app/config.json': b'''{"db_password": "super_secret_db_pass"}
''',
    'app/index.html': b'''<html><body>Hello Secure World</body></html>
''',
}
EXPECTED_ARCHIVE_DIRS = {'app', 'certs'}


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, timeout=20, **kwargs)


def inventory(root):
    result = {}

    def visit(directory, prefix=''):
        for entry in os.scandir(directory):
            relative = os.path.join(prefix, entry.name)
            mode = os.lstat(entry.path).st_mode
            if stat.S_ISDIR(mode):
                result[relative] = 'dir'
                visit(entry.path, relative)
            elif stat.S_ISREG(mode):
                result[relative] = 'file'
            else:
                result[relative] = 'other'

    visit(root)
    return result


def test_decryption_and_extraction():
    assert os.path.isfile(DEPLOY_BUNDLE), f'Decrypted tarball not found at {DEPLOY_BUNDLE}.'
    assert os.path.isdir(DEPLOY_DIR), f'Extracted directory not found at {DEPLOY_DIR}.'
    assert os.path.isdir(APP_DIR), f'App directory not found at {APP_DIR}.'
    assert os.path.isfile(CONFIG_JSON), f'config.json not extracted to {CONFIG_JSON}.'
    assert os.path.isfile(DEPLOY_ENCRYPTED), f'Encrypted input missing at {DEPLOY_ENCRYPTED}.'

    with tempfile.NamedTemporaryFile() as decrypted:
        result = run([
            'openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2',
            '-in', DEPLOY_ENCRYPTED, '-out', decrypted.name,
            '-pass', f'pass:{EXPECTED_PASSWORD}',
        ])
        assert result.returncode == 0, f'Original encrypted bundle does not decrypt with the discovered password: {result.stderr.decode(errors="replace")}'
        with open(DEPLOY_BUNDLE, 'rb') as submitted:
            submitted_data = submitted.read()
        decrypted.seek(0)
        expected_data = decrypted.read()
        assert submitted_data == expected_data, 'deploy_bundle.tar.gz is not the exact decryption of deploy_bundle.enc.'

    with tarfile.open(DEPLOY_BUNDLE, 'r:gz') as archive:
        members = archive.getmembers()
        names = []
        for member in members:
            name = member.name.rstrip('/')
            assert name and not name.startswith('/') and '..' not in name.split('/'), f'Unsafe archive member: {member.name}'
            assert member.isfile() or member.isdir(), f'Unexpected archive member type: {member.name}'
            names.append(name)
        assert len(names) == len(set(names)), 'The decrypted archive contains duplicate paths.'
        assert set(names) == set(EXPECTED_ARCHIVE_FILES) | EXPECTED_ARCHIVE_DIRS, 'The decrypted archive is incomplete or does not match the deployment bundle.'
        for path in EXPECTED_ARCHIVE_DIRS:
            assert archive.getmember(path).isdir(), f'{path} is not a directory in the decrypted archive.'
        for path, expected in EXPECTED_ARCHIVE_FILES.items():
            member = archive.getmember(path)
            assert member.isfile(), f'{path} is not a regular file in the decrypted archive.'
            extracted = archive.extractfile(member)
            assert extracted is not None and extracted.read() == expected, f'Unexpected content for {path} in the decrypted archive.'

    expected_deploy = {
        'app': 'dir',
        'app/config.json': 'file',
        'app/index.html': 'file',
        'certs': 'dir',
        'certs/server.crt': 'file',
        'certs/server.key': 'file',
        'nginx.conf': 'file',
    }
    assert inventory(DEPLOY_DIR) == expected_deploy, 'Extracted deployment is incomplete, contains extra entries, or has incorrect entry types.'
    with open(CONFIG_JSON, 'rb') as handle:
        assert handle.read() == EXPECTED_ARCHIVE_FILES['app/config.json'], 'Extracted config.json does not match the encrypted archive.'
    with open(INDEX_HTML, 'rb') as handle:
        assert handle.read() == EXPECTED_ARCHIVE_FILES['app/index.html'], 'Extracted index.html does not match the encrypted archive.'


def test_tls_certificates():
    assert os.path.isfile(SERVER_CRT), f'Certificate not found at {SERVER_CRT}.'
    assert os.path.isfile(SERVER_KEY), f'Private key not found at {SERVER_KEY}.'

    result = run(['openssl', 'x509', '-in', SERVER_CRT, '-noout', '-subject'], text=True)
    assert result.returncode == 0, f'Failed to parse certificate at {SERVER_CRT}.'
    assert 'secure.internal.dev' in result.stdout, f'Certificate subject does not contain CN=secure.internal.dev. Got: {result.stdout.strip()}'

    exact_subject = run(['openssl', 'x509', '-in', SERVER_CRT, '-noout', '-subject', '-nameopt', 'RFC2253'], text=True)
    assert exact_subject.returncode == 0
    assert exact_subject.stdout.strip().replace('subject=', 'subject = ', 1) == 'subject = CN=secure.internal.dev', f'Certificate subject must be exactly CN=secure.internal.dev, got {exact_subject.stdout.strip()}'

    cert_text = run(['openssl', 'x509', '-in', SERVER_CRT, '-noout', '-text'], text=True)
    assert cert_text.returncode == 0
    assert 'Public Key Algorithm: rsaEncryption' in cert_text.stdout, 'Certificate public key is not RSA.'
    assert 'Public-Key: (2048 bit)' in cert_text.stdout, 'Certificate RSA key is not 2048 bits.'

    key_check = run(['openssl', 'rsa', '-in', SERVER_KEY, '-check', '-noout'], text=True)
    assert key_check.returncode == 0, f'server.key is not a valid RSA private key: {key_check.stderr}'
    key_text = run(['openssl', 'rsa', '-in', SERVER_KEY, '-text', '-noout'], text=True)
    assert key_text.returncode == 0 and 'Private-Key: (2048 bit' in key_text.stdout, 'Private key is not RSA-2048.'

    cert_pub = run(['openssl', 'x509', '-in', SERVER_CRT, '-pubkey', '-noout'])
    key_pub = run(['openssl', 'pkey', '-in', SERVER_KEY, '-pubout'])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0
    assert cert_pub.stdout == key_pub.stdout, 'server.key does not correspond to server.crt.'

    issuer = run(['openssl', 'x509', '-in', SERVER_CRT, '-noout', '-issuer', '-nameopt', 'RFC2253'], text=True)
    assert issuer.returncode == 0
    assert issuer.stdout.strip().replace('issuer=', 'issuer = ', 1) == 'issuer = CN=secure.internal.dev', 'Certificate is not self-issued.'
    verified = run(['openssl', 'verify', '-CAfile', SERVER_CRT, SERVER_CRT], text=True)
    assert verified.returncode == 0, f'Certificate is not a valid self-signed certificate: {verified.stderr}'

    dates = run(['openssl', 'x509', '-in', SERVER_CRT, '-noout', '-startdate', '-enddate'], text=True)
    assert dates.returncode == 0
    date_values = dict(line.split('=', 1) for line in dates.stdout.strip().splitlines())
    not_before = datetime.datetime.strptime(date_values['notBefore'], '%b %d %H:%M:%S %Y %Z').replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(date_values['notAfter'], '%b %d %H:%M:%S %Y %Z').replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), 'Certificate validity period is not exactly 365 days.'
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, 'Certificate is not currently valid.'


def test_nginx_csp_enforcement():
    assert os.path.isfile(NGINX_CONF), f'Nginx config not found at {NGINX_CONF}.'
    with open(NGINX_CONF, 'r') as handle:
        content = handle.read()
    assert EXPECTED_CSP in content, f'Strict CSP header not found in {NGINX_CONF}. Expected: {EXPECTED_CSP}'
    assert 'add_header Content-Security-Policy "default-src *";' not in content, f'The overly permissive CSP header was not removed from {NGINX_CONF}.'
    assert content.encode() == EXPECTED_NGINX, 'nginx.conf contains changes other than the required exact CSP replacement.'


def test_file_permissions():
    assert os.path.exists(APP_DIR), f'App directory missing: {APP_DIR}'
    assert os.path.exists(INDEX_HTML), f'Index file missing: {INDEX_HTML}'
    assert os.path.exists(CONFIG_JSON), f'Config file missing: {CONFIG_JSON}'

    app_dir_mode = stat.S_IMODE(os.stat(APP_DIR).st_mode)
    assert app_dir_mode == 0o755, f'Expected {APP_DIR} to have 0755 permissions, got {oct(app_dir_mode)}.'
    index_html_mode = stat.S_IMODE(os.stat(INDEX_HTML).st_mode)
    assert index_html_mode == 0o644, f'Expected {INDEX_HTML} to have 0644 permissions, got {oct(index_html_mode)}.'
    config_json_mode = stat.S_IMODE(os.stat(CONFIG_JSON).st_mode)
    assert config_json_mode == 0o400, f'Expected {CONFIG_JSON} to have strict 0400 permissions, got {oct(config_json_mode)}.'

    for root, directories, files in os.walk(APP_DIR, followlinks=False):
        for directory in directories:
            path = os.path.join(root, directory)
            assert stat.S_ISDIR(os.lstat(path).st_mode), f'Non-directory entry found where directory expected: {path}'
            mode = stat.S_IMODE(os.lstat(path).st_mode)
            assert mode == 0o755, f'Expected directory {path} to have 0755 permissions, got {oct(mode)}.'
        for filename in files:
            path = os.path.join(root, filename)
            assert stat.S_ISREG(os.lstat(path).st_mode), f'Non-regular file found in app tree: {path}'
            expected_mode = 0o400 if os.path.abspath(path) == CONFIG_JSON else 0o644
            mode = stat.S_IMODE(os.lstat(path).st_mode)
            assert mode == expected_mode, f'Expected {path} to have {oct(expected_mode)} permissions, got {oct(mode)}.'


def test_audit_log():
    assert os.path.isfile(AUDIT_LOG), f'Audit log not found at {AUDIT_LOG}.'
    with open(AUDIT_LOG, 'r') as handle:
        lines = [line.strip() for line in handle.readlines()]
    assert len(lines) == 4, f'Audit log must contain exactly 4 lines. Found {len(lines)} lines.'
    assert lines[0] == EXPECTED_PASSWORD, f'Line 1 (passphrase) is incorrect. Expected {EXPECTED_PASSWORD}, got {lines[0]}.'
    assert os.path.isfile(SERVER_CRT), f'Cannot compute SHA-256; {SERVER_CRT} is missing.'
    with open(SERVER_CRT, 'rb') as handle:
        expected_hash = hashlib.sha256(handle.read()).hexdigest()
    assert lines[1] == expected_hash, f'Line 2 (SHA-256) is incorrect. Expected {expected_hash}, got {lines[1]}.'
    assert lines[2] == EXPECTED_CSP, f'Line 3 (CSP) is incorrect. Expected {EXPECTED_CSP}, got {lines[2]}.'
    assert lines[3] in ['400', '0400'], f'Line 4 (permissions) is incorrect. Expected 400 or 0400, got {lines[3]}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
