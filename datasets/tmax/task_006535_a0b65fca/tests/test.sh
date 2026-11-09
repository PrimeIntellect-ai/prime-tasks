#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import secrets
import socket
import ssl
import subprocess
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path

HOME = Path('/home/user')
CONF = HOME / 'supervisord.conf'
SCRIPT = HOME / 'cicd_restore.py'
LOG = HOME / 'restore_log.txt'
DEPLOY = HOME / 'deploy'
SUPERVISORCTL = ['/usr/bin/supervisorctl', '-c', str(CONF)]


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('capture_output', True)
    return subprocess.run(cmd, **kwargs)


def as_user(cmd, **kwargs):
    return run(['/usr/sbin/runuser', '-u', 'user', '--'] + cmd, **kwargs)


def https_get(path='/'):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request('https://127.0.0.1:8443' + path)
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        return response.read()


def wait_for_https(expected=None, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            body = https_get()
            if expected is None or body == expected:
                return body
            last = body
        except Exception as exc:
            last = exc
        time.sleep(0.2)
    raise AssertionError(f'TLS endpoint did not become ready; last result: {last!r}')


def supervisor(*args, check=True):
    result = as_user(SUPERVISORCTL + list(args), timeout=10)
    if check:
        assert result.returncode == 0, result.stdout + result.stderr
    return result


def test_files_exist():
    required_files = [
        '/home/user/certs/cert.pem',
        '/home/user/certs/key.pem',
        '/home/user/tls_proxy.py',
        '/home/user/supervisord.conf',
        '/home/user/cicd_restore.py',
    ]
    for filepath in required_files:
        assert os.path.isfile(filepath), f'Required file {filepath} does not exist.'


def test_supervisord_running():
    try:
        output = subprocess.check_output(['pgrep', '-f', 'supervisord'], text=True)
        assert output.strip(), 'supervisord is not running.'
    except subprocess.CalledProcessError:
        assert False, 'supervisord is not running.'


def test_supervisor_configuration_and_managed_programs():
    parser = configparser.RawConfigParser()
    assert parser.read(CONF) == [str(CONF)]
    for section in ('unix_http_server', 'supervisord', 'supervisorctl',
                    'program:tls_proxy', 'program:app'):
        assert parser.has_section(section), f'Missing [{section}] section'

    app_command = parser.get('program:app', 'command')
    proxy_command = parser.get('program:tls_proxy', 'command')
    assert 'python' in app_command and '/home/user/deploy/app.py' in app_command
    assert '/home/user/tls_proxy.py' in proxy_command

    socket_file = parser.get('unix_http_server', 'file')
    serverurl = parser.get('supervisorctl', 'serverurl')
    assert os.path.abspath(socket_file).startswith('/home/user/')
    assert serverurl.startswith('unix://') and socket_file in serverurl

    for option in ('logfile', 'pidfile', 'childlogdir'):
        value = parser.get('supervisord', option)
        assert os.path.abspath(value).startswith('/home/user/'), \
            f'{option} is not stored in /home/user'

    status = supervisor('status').stdout
    assert 'app' in status and 'tls_proxy' in status
    for name, required_fragment in (
        ('app', '/home/user/deploy/app.py'),
        ('tls_proxy', '/home/user/tls_proxy.py'),
    ):
        line = supervisor('status', name).stdout
        assert 'RUNNING' in line, line
        pid_text = supervisor('pid', name).stdout.strip()
        assert pid_text.isdigit() and int(pid_text) > 1
        cmdline = Path(f'/proc/{pid_text}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        assert required_fragment in cmdline, cmdline


def test_certificate_files_are_valid_and_used_by_proxy():
    cert = str(HOME / 'certs/cert.pem')
    key = str(HOME / 'certs/key.pem')
    validation_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    validation_context.load_cert_chain(cert, key)

    pem = Path(cert).read_text()
    expected_der = ssl.PEM_cert_to_DER_cert(pem)
    expected_der = __import__('base64').b64decode(expected_der)
    with socket.create_connection(('127.0.0.1', 8443), timeout=5) as raw:
        client_context = ssl.create_default_context()
        client_context.check_hostname = False
        client_context.verify_mode = ssl.CERT_NONE
        with client_context.wrap_socket(raw, server_hostname='127.0.0.1') as tls:
            assert tls.getpeercert(binary_form=True) == expected_der


def test_cicd_restore_and_proxy():
    backup_path = '/home/user/archive/v2.tar.gz'
    try:
        result = as_user(['python3', str(SCRIPT), backup_path], timeout=20)
        assert result.returncode == 0, result.stderr
    except subprocess.TimeoutExpired:
        assert False, 'CI/CD script timed out'

    time.sleep(1)
    assert LOG.is_file(), f'Log file {LOG} was not created.'
    lines = LOG.read_text().strip().splitlines()
    assert len(lines) > 0, 'Log file is empty.'
    assert 'APP_VERSION_2_RESTORED' in lines[-1], \
        'The last line of the log file does not contain the expected response.'

    try:
        body = https_get().decode('utf-8')
        assert 'APP_VERSION_2_RESTORED' in body, f'Proxy returned unexpected response: {body}'
    except Exception as exc:
        assert False, f'Failed to connect to the TLS proxy or verify response: {exc}'


def make_backup(directory, response):
    source = (
        "from http.server import BaseHTTPRequestHandler, HTTPServer\n"
        "class H(BaseHTTPRequestHandler):\n"
        "    def do_GET(self):\n"
        f"        body = {response!r}.encode('utf-8')\n"
        "        self.send_response(200)\n"
        "        self.send_header('Content-Length', str(len(body)))\n"
        "        self.end_headers()\n"
        "        self.wfile.write(body)\n"
        "    def log_message(self, *args):\n"
        "        pass\n"
        "HTTPServer.allow_reuse_address = True\n"
        "HTTPServer(('127.0.0.1', 8080), H).serve_forever()\n"
    ).encode()
    app = directory / 'app.py'
    marker_dir = directory / 'payload'
    marker_dir.mkdir()
    marker = marker_dir / 'marker.txt'
    app.write_bytes(source)
    marker_value = secrets.token_hex(24).encode()
    marker.write_bytes(marker_value)
    archive = directory / 'test.tar.gz'
    with tarfile.open(archive, 'w:gz') as tf:
        tf.add(app, arcname='app.py')
        tf.add(marker, arcname='payload/marker.txt')
    os.chmod(archive, 0o644)
    return archive, source, marker_value


def exercise_random_restore():
    response = 'DYNAMIC_' + secrets.token_urlsafe(30)
    with tempfile.TemporaryDirectory() as tmp:
        archive, source, marker = make_backup(Path(tmp), response)

        DEPLOY.mkdir(exist_ok=True)
        (DEPLOY / 'must_be_deleted.txt').write_text(secrets.token_hex(20))
        (DEPLOY / 'old_directory').mkdir(exist_ok=True)
        (DEPLOY / 'old_directory' / 'old.txt').write_text('old')
        subprocess.run(['chown', '-R', 'user:user', str(DEPLOY)], check=True)
        LOG.write_text('PREEXISTING\n')
        os.chown(LOG, 1000, 1000)
        os.chmod(LOG, 0o666)

        result = as_user(['python3', str(SCRIPT), str(archive)], timeout=20)
        assert result.returncode == 0, result.stdout + result.stderr

        assert (DEPLOY / 'app.py').read_bytes() == source
        assert (DEPLOY / 'payload/marker.txt').read_bytes() == marker
        assert not (DEPLOY / 'must_be_deleted.txt').exists()
        assert not (DEPLOY / 'old_directory').exists()
        assert sorted(p.name for p in DEPLOY.iterdir()) == ['app.py', 'payload']

        expected = response.encode()
        assert wait_for_https(expected) == expected
        assert LOG.read_text().splitlines() == ['PREEXISTING', response]
        status = supervisor('status', 'app').stdout
        assert 'RUNNING' in status, status


def test_restore_uses_supplied_archives_and_clears_deploy():
    exercise_random_restore()
    exercise_random_restore()


def test_script_requires_exactly_one_argument():
    no_arg = as_user(['python3', str(SCRIPT)], timeout=5)
    two_args = as_user(['python3', str(SCRIPT), '/tmp/a', '/tmp/b'], timeout=5)
    assert no_arg.returncode != 0
    assert two_args.returncode != 0


def test_proxy_really_forwards_exact_upstream_body():
    token = ('UPSTREAM_' + secrets.token_urlsafe(40)).encode()
    helper = Path('/tmp/verifier_upstream.py')
    helper.write_text(
        "from http.server import BaseHTTPRequestHandler, HTTPServer\n"
        f"BODY = {token!r}\n"
        "class H(BaseHTTPRequestHandler):\n"
        "    def do_GET(self):\n"
        "        self.send_response(200)\n"
        "        self.send_header('Content-Length', str(len(BODY)))\n"
        "        self.end_headers()\n"
        "        self.wfile.write(BODY)\n"
        "    def log_message(self, *args): pass\n"
        "HTTPServer.allow_reuse_address = True\n"
        "HTTPServer(('127.0.0.1', 8080), H).serve_forever()\n"
    )
    os.chmod(helper, 0o644)

    supervisor('stop', 'app')
    proc = subprocess.Popen(
        ['/usr/sbin/runuser', '-u', 'user', '--', 'python3', str(helper)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                with urllib.request.urlopen('http://127.0.0.1:8080/', timeout=1) as r:
                    if r.read() == token:
                        break
            except Exception:
                time.sleep(0.1)
        else:
            raise AssertionError('Temporary upstream did not start')
        assert wait_for_https(token) == token
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        supervisor('start', 'app')

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
