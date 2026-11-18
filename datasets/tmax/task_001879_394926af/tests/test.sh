#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

HOME = '/home/user'
SOURCE_BIN = HOME + '/vulnerable_server'
PATCHED_BIN = HOME + '/patched_server'
PATCHER_GO = HOME + '/patcher.go'
CHECKSUM_FILE = HOME + '/checksum.txt'
REFERENCE_BIN = '/opt/vulnerable_server'
OLD = b'http://super-secret-backend.local/'
NEW = b'http://redacted-secure-domain.com/'


def run_patcher():
    for path in (PATCHED_BIN, CHECKSUM_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env['HOME'] = HOME
    result = subprocess.run(
        ['go', 'run', PATCHER_GO],
        cwd=HOME,
        env=env,
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        text=True,
    )
    assert result.returncode == 0, (
        f'patcher.go failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r} stderr={result.stderr!r}'
    )
    assert os.path.isfile(PATCHED_BIN), 'patcher.go did not create patched_server.'
    assert os.path.isfile(CHECKSUM_FILE), 'patcher.go did not create checksum.txt.'


def assert_generated_output(source, expected):
    with open(PATCHED_BIN, 'rb') as f:
        actual = f.read()
    assert actual == expected, 'patched_server is not the exact requested transformation of vulnerable_server.'
    assert actual.startswith(b'\x7fELF'), 'patched_server is not an ELF binary.'
    assert OLD not in actual, 'The sensitive backend URL remains in patched_server.'
    assert actual.count(NEW) == source.count(OLD), 'Not every sensitive URL occurrence was replaced exactly once.'

    actual_checksum = hashlib.sha256(actual).hexdigest()
    with open(CHECKSUM_FILE, 'r') as f:
        written_checksum = f.read().strip()
    assert written_checksum == actual_checksum, 'patcher.go wrote an incorrect checksum.'


@pytest.fixture(scope='session', autouse=True)
def regenerate_with_submitted_patcher():
    assert os.path.isfile(PATCHER_GO), f'Go source file {PATCHER_GO} is missing.'
    assert os.path.isfile(REFERENCE_BIN), f'Reference binary {REFERENCE_BIN} is missing.'
    assert os.path.isfile(SOURCE_BIN), f'Retrieved binary {SOURCE_BIN} is missing.'

    with open(REFERENCE_BIN, 'rb') as f:
        reference = f.read()
    with open(SOURCE_BIN, 'rb') as f:
        retrieved = f.read()

    assert retrieved == reference, '/home/user/vulnerable_server is not the binary from /opt/vulnerable_server.'
    assert reference.startswith(b'\x7fELF'), 'The retrieved source is not an ELF binary.'
    assert reference.count(OLD) > 0, 'The source binary does not contain the vulnerable URL.'
    assert len(OLD) == len(NEW), 'Replacement strings do not have equal length.'

    original_mode = os.stat(SOURCE_BIN).st_mode
    probe = b'\nPATCHER_INPUT_PROBE_' + secrets.token_bytes(32)
    try:
        with open(SOURCE_BIN, 'wb') as f:
            f.write(reference + probe)
        os.chmod(SOURCE_BIN, original_mode)
        run_patcher()
        assert_generated_output(reference + probe, reference.replace(OLD, NEW) + probe)
    finally:
        with open(SOURCE_BIN, 'wb') as f:
            f.write(reference)
        os.chmod(SOURCE_BIN, original_mode)

    run_patcher()
    expected = reference.replace(OLD, NEW)
    assert_generated_output(reference, expected)
    assert expected != reference, 'patched_server is byte-identical to the vulnerable binary.'


def test_patched_server_exists_and_executable():
    assert os.path.isfile(PATCHED_BIN), f'Patched binary {PATCHED_BIN} is missing.'
    assert os.access(PATCHED_BIN, os.X_OK), f'Patched binary {PATCHED_BIN} is not executable.'


def test_patcher_go_exists():
    assert os.path.isfile(PATCHER_GO), f'Go source file {PATCHER_GO} is missing.'


def test_checksum_txt():
    assert os.path.isfile(CHECKSUM_FILE), f'Checksum file {CHECKSUM_FILE} is missing.'

    with open(PATCHED_BIN, 'rb') as f:
        actual_checksum = hashlib.sha256(f.read()).hexdigest()
    with open(CHECKSUM_FILE, 'r') as f:
        written_checksum = f.read().strip()

    assert actual_checksum == written_checksum, f'Checksum in {CHECKSUM_FILE} does not match the actual SHA256 of {PATCHED_BIN}.'


def kill_port_8080_users():
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r') as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                        socket_inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    os.kill(int(entry), signal.SIGKILL)
                    break
        except OSError:
            pass
    time.sleep(0.2)


def request_redirect(opener, path):
    encoded = urllib.parse.urlencode({'path': path})
    url = f'http://127.0.0.1:8080/redirect?{encoded}'
    expected = f'http://redacted-secure-domain.com/{path}'
    try:
        response = opener.open(urllib.request.Request(url), timeout=2)
        return response.status == 302 and response.getheader('Location') == expected
    except urllib.error.HTTPError as e:
        return e.code == 302 and e.headers.get('Location') == expected
    except Exception:
        return False


def test_patched_server_functionality():
    kill_port_8080_users()
    process = subprocess.Popen([PATCHED_BIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            if process.poll() is not None:
                pytest.fail(f'patched_server exited early with status {process.returncode}.')
            try:
                with urllib.request.urlopen('http://127.0.0.1:8080/', timeout=0.2):
                    pass
            except urllib.error.HTTPError:
                break
            except Exception:
                time.sleep(0.1)

        class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None

        opener = urllib.request.build_opener(NoRedirectHandler)

        fixed_paths = [f'test{i}' for i in range(10)]
        success_count = sum(request_redirect(opener, path) for path in fixed_paths)
        accuracy = success_count / float(len(fixed_paths))
        assert accuracy >= 1.0, f'Accuracy = {accuracy}. Expected >= 1.0. Server did not redirect correctly for all payloads.'

        random_paths = [secrets.token_hex(12) for _ in range(10)]
        assert all(request_redirect(opener, path) for path in random_paths), 'Server failed dynamically generated redirect payloads.'
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
