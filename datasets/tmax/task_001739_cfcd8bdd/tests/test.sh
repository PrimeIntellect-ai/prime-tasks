#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import grp
import stat
import ssl
import socket
import hashlib
import shutil
import signal
import subprocess
import time
import uuid
import re

import requests
import pytest

PACKAGE = '/app/tinyweb-1.0.0'
BINARY = os.path.join(PACKAGE, 'tinyweb')
SETUP = '/home/user/setup.sh'


def listener_inodes(port=8443):
    result = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == '0A' and fields[1].split(':')[-1].upper() == wanted:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_for_socket_inodes(inodes):
    pids = set()
    if not inodes:
        return pids
    targets = {f'socket:[{inode}]' for inode in inodes}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in targets:
                        pids.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return pids


def stop_pids(pids):
    pids = {p for p in pids if p != os.getpid()}
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pids.discard(pid)
        deadline = time.time() + 2
        while pids and time.time() < deadline:
            pids = {p for p in pids if os.path.exists(f'/proc/{p}')}
            time.sleep(0.05)
    assert not pids, f'Could not stop processes: {sorted(pids)}'


def stop_port_8443():
    stop_pids(pids_for_socket_inodes(listener_inodes()))
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), 'Port 8443 is still occupied'


def sha256(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


@pytest.fixture(scope='session', autouse=True)
def run_setup_from_clean_state():
    assert os.path.isfile(SETUP), f'{SETUP} does not exist.'
    assert os.access(SETUP, os.X_OK), f'{SETUP} is not executable.'

    stop_port_8443()
    try:
        old_uid = pwd.getpwnam('tinyweb_usr').pw_uid
    except KeyError:
        old_uid = None
    if old_uid is not None:
        owned = set()
        for entry in os.listdir('/proc'):
            if entry.isdigit():
                try:
                    if os.stat(f'/proc/{entry}').st_uid == old_uid:
                        owned.add(int(entry))
                except OSError:
                    pass
        stop_pids(owned)

    if os.path.lexists('/var/www/html'):
        remove_path('/var/www/html')
    if os.path.lexists('/etc/tinyweb'):
        remove_path('/etc/tinyweb')
    subprocess.run(['userdel', 'tinyweb_usr'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(['groupdel', 'webfiles'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)

    result1 = subprocess.run([SETUP], capture_output=True, text=True, timeout=30)
    assert result1.returncode == 0, f'First run of setup.sh failed: {result1.stderr}'

    assert os.path.isfile('/etc/tinyweb/cert.pem')
    assert os.path.isfile('/etc/tinyweb/key.pem')
    first_cert = sha256('/etc/tinyweb/cert.pem')
    first_key = sha256('/etc/tinyweb/key.pem')
    first_uid = pwd.getpwnam('tinyweb_usr').pw_uid
    first_gid = grp.getgrnam('webfiles').gr_gid

    result2 = subprocess.run([SETUP], capture_output=True, text=True, timeout=30)
    assert result2.returncode == 0, f'Second run of setup.sh failed (not idempotent): {result2.stderr}'
    assert sha256('/etc/tinyweb/cert.pem') == first_cert, 'Second setup run unexpectedly replaced the certificate'
    assert sha256('/etc/tinyweb/key.pem') == first_key, 'Second setup run unexpectedly replaced the private key'
    assert pwd.getpwnam('tinyweb_usr').pw_uid == first_uid
    assert grp.getgrnam('webfiles').gr_gid == first_gid


def test_setup_script_idempotence():
    assert os.path.isfile(SETUP), f'{SETUP} does not exist.'
    assert os.access(SETUP, os.X_OK), f'{SETUP} is not executable.'


def test_user_and_group_setup():
    try:
        group = grp.getgrnam('webfiles')
    except KeyError:
        pytest.fail("Group 'webfiles' does not exist.")
    try:
        user = pwd.getpwnam('tinyweb_usr')
    except KeyError:
        pytest.fail("User 'tinyweb_usr' does not exist.")

    assert user.pw_shell == '/usr/sbin/nologin', f'tinyweb_usr shell is {user.pw_shell}, expected /usr/sbin/nologin'
    assert user.pw_gid == group.gr_gid or group.gr_name in [g.gr_name for g in grp.getgrall() if user.pw_name in g.gr_mem], 'tinyweb_usr is not in webfiles group.'
    assert group.gr_gid in os.getgrouplist(user.pw_name, user.pw_gid)


def test_filesystem_and_permissions():
    web_dir = '/var/www/html'
    index_file = os.path.join(web_dir, 'index.html')
    assert os.path.isdir(web_dir), f'{web_dir} does not exist.'

    ds = os.stat(web_dir)
    assert pwd.getpwuid(ds.st_uid).pw_name == 'root', f'{web_dir} is not owned by root.'
    assert grp.getgrgid(ds.st_gid).gr_name == 'webfiles', f'{web_dir} group is not webfiles.'
    assert bool(ds.st_mode & stat.S_IRGRP), f'{web_dir} is not readable by group.'
    assert bool(ds.st_mode & stat.S_IXGRP), f'{web_dir} is not searchable by group.'
    assert not bool(ds.st_mode & stat.S_IWGRP), f'{web_dir} is writable by group.'
    assert not bool(ds.st_mode & stat.S_IRWXO), f'{web_dir} is accessible by others.'

    assert os.path.isfile(index_file), f'{index_file} does not exist.'
    fs = os.stat(index_file)
    assert pwd.getpwuid(fs.st_uid).pw_name == 'root'
    assert grp.getgrgid(fs.st_gid).gr_name == 'webfiles'
    assert bool(fs.st_mode & stat.S_IRGRP), f'{index_file} is not group-readable.'
    assert not bool(fs.st_mode & stat.S_IWGRP), f'{index_file} is group-writable.'
    assert not bool(fs.st_mode & stat.S_IRWXO), f'{index_file} is accessible by others.'
    with open(index_file) as f:
        content = f.read().strip()
    assert 'Welcome to the secure server' in content, f'Unexpected content in {index_file}: {content}'


def test_tls_certificates_exist_and_are_valid():
    cert = '/etc/tinyweb/cert.pem'
    key = '/etc/tinyweb/key.pem'
    assert os.path.isfile(cert), f'{cert} does not exist.'
    assert os.path.isfile(key), f'{key} does not exist.'
    assert stat.S_IMODE(os.stat(key).st_mode) & stat.S_IRWXO == 0, 'Private key is accessible by others'

    subprocess.run(['openssl', 'x509', '-in', cert, '-noout', '-checkend', '0'], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(['openssl', 'pkey', '-in', key, '-noout', '-check'], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(['openssl', 'verify', '-CAfile', cert, cert], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    cert_pub = subprocess.check_output(['openssl', 'x509', '-in', cert, '-pubkey', '-noout'])
    key_pub = subprocess.check_output(['openssl', 'pkey', '-in', key, '-pubout'])
    assert cert_pub == key_pub, 'Certificate and private key do not match'


def test_vendored_source_makefile_and_compilation():
    makefile_path = os.path.join(PACKAGE, 'Makefile')
    source_path = os.path.join(PACKAGE, 'server.c')
    assert os.path.isfile(makefile_path)
    assert os.path.isfile(source_path)

    with open(makefile_path) as f:
        makefile = f.read()
    assert re.search(r'(^|\s)-lssl(?=\s|$)', makefile, re.M), 'Makefile does not link libssl'
    assert re.search(r'(^|\s)-lcrypto(?=\s|$)', makefile, re.M), 'Makefile does not link libcrypto'

    with open(source_path) as f:
        source = f.read()
    env_pos = source.find('getenv("TLS_CERT_PATH")')
    fallback_pos = source.find('"/etc/tinyweb/cert.pem"')
    use_pos = source.find('SSL_CTX_use_certificate_file')
    assert env_pos >= 0, 'server.c does not read TLS_CERT_PATH'
    assert fallback_pos > env_pos, 'server.c does not provide the required certificate fallback'
    assert use_pos > fallback_pos, 'Fallback must be selected before loading the certificate'
    unsafe_pos = source.find('strlen(cert_path)', env_pos, fallback_pos)
    assert unsafe_pos == -1, 'server.c dereferences TLS_CERT_PATH before applying its fallback'

    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    built = subprocess.run(['make', '-B', 'tinyweb'], cwd=PACKAGE, capture_output=True, text=True)
    assert built.returncode == 0, f'Compiling tinyweb failed:\n{built.stdout}\n{built.stderr}'
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), 'Compiled tinyweb executable is missing'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'tinyweb is not an ELF executable'
    linked = subprocess.run(['ldd', BINARY], capture_output=True, text=True, check=True).stdout
    assert 'libssl' in linked, 'Compiled tinyweb is not linked to libssl'
    assert 'libcrypto' in linked, 'Compiled tinyweb is not linked to libcrypto'


def wait_for_https(timeout=5):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return requests.get('https://127.0.0.1:8443/index.html', verify=False, timeout=0.5)
        except requests.exceptions.RequestException as exc:
            last = exc
            time.sleep(0.1)
    raise AssertionError(f'Failed to connect to HTTPS server: {last}')


def test_web_server_running_and_serving_as_tinyweb_user():
    stop_port_8443()
    user = pwd.getpwnam('tinyweb_usr')

    def demote():
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env.pop('TLS_CERT_PATH', None)
    proc = subprocess.Popen([BINARY], cwd=PACKAGE, env=env, preexec_fn=demote,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    index = '/var/www/html/index.html'
    original = open(index, 'rb').read()
    try:
        response = wait_for_https()
        assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
        assert 'Welcome to the secure server' in response.text, 'Response body does not contain the expected message.'
        assert proc.poll() is None, 'Compiled tinyweb exited unexpectedly without TLS_CERT_PATH'
        assert os.stat(f'/proc/{proc.pid}').st_uid == user.pw_uid, 'Serving process is not running as tinyweb_usr'
        assert os.path.realpath(f'/proc/{proc.pid}/exe') == os.path.realpath(BINARY), 'Port 8443 is not served by the compiled tinyweb binary'

        child_sockets = set()
        for fd in os.listdir(f'/proc/{proc.pid}/fd'):
            try:
                target = os.readlink(f'/proc/{proc.pid}/fd/{fd}')
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m:
                    child_sockets.add(m.group(1))
            except OSError:
                pass
        found_loopback = False
        with open('/proc/net/tcp') as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[9] in child_sockets and fields[3] == '0A' and fields[1].endswith(':20FB'):
                    assert fields[1].split(':')[0] == '0100007F', 'tinyweb is not bound specifically to 127.0.0.1'
                    found_loopback = True
        assert found_loopback, 'Compiled tinyweb process is not listening on 127.0.0.1:8443'

        token = 'dynamic-' + uuid.uuid4().hex
        with open(index, 'w') as f:
            f.write(token + '\n')
        dynamic = requests.get('https://127.0.0.1:8443/' + uuid.uuid4().hex,
                               verify=False, timeout=5)
        assert dynamic.status_code == 200
        assert token in dynamic.text, 'Compiled server did not serve the current index.html contents'
    finally:
        with open(index, 'wb') as f:
            f.write(original)
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
