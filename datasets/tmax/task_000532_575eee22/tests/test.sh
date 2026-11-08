#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import subprocess
import threading
import time
from pathlib import Path

import pytest

ROOT = Path('/home/user/stack_restore')
APP = ROOT / 'app'
BINARY = APP / 'target/release/restore_verifier'
RESULT = Path('/home/user/restore_results.log')
EXPECTED = 'RESTORE_SUCCESS: Verified data connection'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def kill_listeners(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])

    for procdir in Path('/proc').iterdir():
        if not procdir.name.isdigit():
            continue
        fd_dir = procdir / 'fd'
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(procdir.name), 9)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    time.sleep(0.3)


@pytest.fixture(scope='module', autouse=True)
def exercise_submission():
    assert (APP / 'Cargo.toml').is_file(), 'Cargo.toml is missing.'
    assert (APP / 'src/main.rs').is_file(), 'src/main.rs is missing.'

    clean = run(['cargo', 'clean'], cwd=APP, timeout=60)
    assert clean.returncode == 0, f'cargo clean failed:\n{clean.stdout}\n{clean.stderr}'
    build = run(['cargo', 'build', '--release'], cwd=APP, timeout=120)
    assert build.returncode == 0, f'cargo build --release failed:\n{build.stdout}\n{build.stderr}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'Release artifact is not an ELF executable.'

    # Derive an unpredictable port and verify that the freshly compiled program
    # only reports success after making a real TCP connection to that port.
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 0))
    random_port = listener.getsockname()[1]

    RESULT.unlink(missing_ok=True)
    env = os.environ.copy()
    env['BACKEND_PORT'] = str(random_port)
    closed_run = run([str(BINARY)], cwd=ROOT, env=env, timeout=10)
    assert not RESULT.exists(), 'Application reported success when the selected port was not listening.'

    accepted = threading.Event()
    listener.listen(1)
    listener.settimeout(10)

    def accept_one():
        try:
            conn, _ = listener.accept()
            accepted.set()
            conn.close()
        finally:
            listener.close()

    thread = threading.Thread(target=accept_one, daemon=True)
    thread.start()
    connected_run = run([str(BINARY)], cwd=ROOT, env=env, timeout=10)
    thread.join(timeout=10)
    assert connected_run.returncode == 0, f'Application failed with a listening backend:\n{connected_run.stderr}'
    assert accepted.is_set(), 'Application did not make a TCP connection to BACKEND_PORT.'
    assert RESULT.is_file() and RESULT.read_text().strip() == EXPECTED

    # Exercise start_all.sh against a controlled backend that cannot become
    # ready until after a delay. This verifies launch, log redirection, waiting,
    # BACKEND_PORT propagation, and execution of the compiled application.
    backend = ROOT / 'backend_service.sh'
    original_backend = backend.read_bytes()
    original_mode = backend.stat().st_mode
    marker = f'CONTROLLED_BACKEND_{os.getpid()}_{time.time_ns()}'
    controlled = f'''#!/bin/bash
echo "{marker}: starting"
sleep 3
exec python3 -u -c 'import socket\ns=socket.socket()\ns.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)\ns.bind(("127.0.0.1",8085))\ns.listen(8)\nprint("[INFO] Listening for connections on port 8085",flush=True)\nwhile True:\n c,a=s.accept()\n c.close()'
'''

    kill_listeners(8085)
    backend.write_text(controlled)
    os.chmod(backend, 0o755)
    RESULT.unlink(missing_ok=True)
    (ROOT / 'backend.log').unlink(missing_ok=True)
    started = time.monotonic()
    try:
        startup = run(['bash', str(ROOT / 'start_all.sh')], cwd=ROOT,
                      env=os.environ.copy(), timeout=20)
        elapsed = time.monotonic() - started
    finally:
        kill_listeners(8085)
        backend.write_bytes(original_backend)
        os.chmod(backend, original_mode)

    assert startup.returncode == 0, f'start_all.sh failed:\n{startup.stdout}\n{startup.stderr}'
    assert elapsed >= 2.5, 'start_all.sh proceeded before the delayed backend could be ready.'
    backend_log = ROOT / 'backend.log'
    assert backend_log.is_file(), 'start_all.sh did not create backend.log.'
    log_content = backend_log.read_text(errors='replace')
    assert marker in log_content, 'Backend output was not redirected to backend.log.'
    assert 'Listening for connections' in log_content
    assert RESULT.is_file() and RESULT.read_text().strip() == EXPECTED


def test_restore_results_log_exists():
    """Test that the restore_results.log file was created."""
    filepath = '/home/user/restore_results.log'
    assert os.path.isfile(filepath), f'Expected file {filepath} to exist after running the startup sequence.'


def test_restore_results_log_content():
    """Test that the restore_results.log contains the exact success message."""
    filepath = '/home/user/restore_results.log'
    assert os.path.isfile(filepath), f'File {filepath} is missing.'
    with open(filepath, 'r') as f:
        content = f.read().strip()
    expected = 'RESTORE_SUCCESS: Verified data connection'
    assert content == expected, f"Content of {filepath} was '{content}', expected '{expected}'."


def test_rust_binary_compiled():
    """Test that the Rust application was compiled in release mode."""
    filepath = '/home/user/stack_restore/app/target/release/restore_verifier'
    assert os.path.isfile(filepath), f"Compiled binary {filepath} is missing. Did you run 'cargo build --release'?"
    assert os.access(filepath, os.X_OK), f'File {filepath} is not executable.'


def test_rust_code_modified():
    """Test that the Rust application source code was modified to use BACKEND_PORT."""
    filepath = '/home/user/stack_restore/app/src/main.rs'
    assert os.path.isfile(filepath), f'Source file {filepath} is missing.'
    with open(filepath, 'r') as f:
        content = f.read()
    assert 'BACKEND_PORT' in content, 'The Rust source code does not appear to read the BACKEND_PORT environment variable.'


def test_start_script_modified():
    """Test that start_all.sh was modified to include the port and export it."""
    filepath = '/home/user/stack_restore/start_all.sh'
    assert os.path.isfile(filepath), f'Script {filepath} is missing.'
    with open(filepath, 'r') as f:
        content = f.read()
    assert '8085' in content, 'The start_all.sh script does not seem to contain the required port 8085.'
    assert 'BACKEND_PORT' in content, 'The start_all.sh script does not seem to export or set the BACKEND_PORT environment variable.'

    active = '\n'.join(line for line in content.splitlines() if not line.lstrip().startswith('#'))
    assert 'backend_service.sh' in active, 'start_all.sh does not launch backend_service.sh.'
    assert re.search(r'backend\.log', active), 'start_all.sh does not redirect backend output to backend.log.'
    assert re.search(r'(grep|awk|sed|tail|\bnc\b|netcat|curl|/dev/tcp)', active), \
        'start_all.sh does not contain a log/port readiness diagnostic.'
    assert 'app/target/release/restore_verifier' in active, \
        'start_all.sh does not execute the compiled restore_verifier binary.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
