#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import shutil
import socket
import subprocess
import tempfile
import threading
import time

CPP = pathlib.Path('/home/user/net_check.cpp')
BINARY = pathlib.Path('/home/user/net_check')
MONITOR = pathlib.Path('/home/user/monitor.sh')
ROUTES = pathlib.Path('/home/user/routes.txt')
LOG = pathlib.Path('/home/user/logs/net_status.log')


def test_net_check_cpp_exists():
    """Verify that /home/user/net_check.cpp exists."""
    path = "/home/user/net_check.cpp"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_net_check_binary_exists_and_executable():
    """Verify that /home/user/net_check exists and is executable."""
    path = "/home/user/net_check"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_monitor_script_exists_and_executable():
    """Verify that /home/user/monitor.sh exists and is executable."""
    path = "/home/user/monitor.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
    assert "America/New_York" in content, f"Timezone 'America/New_York' not found in {path}."


def test_net_status_log_contents():
    """Verify that /home/user/logs/net_status.log exists and has the correct contents."""
    path = "/home/user/logs/net_status.log"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = "CONNECT_SUCCESS\ndefault via 10.0.0.1 dev eth0 proto dhcp metric 100"
    assert content == expected_content, f"Contents of {path} do not match the expected output. Got:\n{content}"


def _listener_inodes():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                try:
                    port = int(fields[1].rsplit(':', 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if port == 8888:
                    inodes.add(fields[9])
    return inodes


def _stop_port_8888_listeners():
    for _ in range(20):
        inodes = _listener_inodes()
        if not inodes:
            return
        for proc in pathlib.Path('/proc').iterdir():
            if not proc.name.isdigit() or int(proc.name) == os.getpid():
                continue
            fd_dir = proc / 'fd'
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
                        os.kill(int(proc.name), 9)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        time.sleep(0.05)
    assert not _listener_inodes(), 'Could not obtain exclusive control of TCP port 8888'


def _run_checker(path, expect_success):
    _stop_port_8888_listeners()
    server = None
    accepted = []
    thread = None

    if expect_success:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('127.0.0.1', 8888))
        server.listen(1)
        server.settimeout(5)

        def accept_one():
            try:
                conn, _ = server.accept()
                accepted.append(True)
                conn.close()
            finally:
                server.close()

        thread = threading.Thread(target=accept_one, daemon=True)
        thread.start()

    try:
        result = subprocess.run(
            [str(path)], capture_output=True, text=True, timeout=5,
            cwd='/home/user'
        )
    finally:
        if thread is not None:
            thread.join(timeout=5)
            if thread.is_alive():
                server.close()

    expected = 'CONNECT_SUCCESS' if expect_success else 'CONNECT_FAIL'
    assert result.returncode == 0, f'{path} exited with {result.returncode}: {result.stderr}'
    assert result.stdout in (expected, expected + '\n'), f'Unexpected stdout from {path}: {result.stdout!r}'
    assert result.stderr == '', f'Unexpected stderr from {path}: {result.stderr!r}'
    if expect_success:
        assert accepted, f'{path} did not establish a TCP connection to port 8888'


def test_cpp_compiles_and_both_source_and_binary_check_the_socket():
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'net_check must be a compiled executable'

    with tempfile.TemporaryDirectory() as td:
        rebuilt = pathlib.Path(td) / 'net_check_rebuilt'
        compile_result = subprocess.run(
            ['g++', '-std=c++17', str(CPP), '-o', str(rebuilt)],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, f'net_check.cpp does not compile:\n{compile_result.stderr}'
        assert rebuilt.read_bytes()[:4] == b'\x7fELF'

        for candidate in (BINARY, rebuilt):
            _run_checker(candidate, expect_success=False)
            _run_checker(candidate, expect_success=True)


def test_monitor_executes_checker_appends_dynamic_route_and_sets_timezone():
    route_original = ROUTES.read_bytes()
    log_existed = LOG.exists()
    log_original = LOG.read_bytes() if log_existed else b''
    binary_original = BINARY.read_bytes()
    binary_mode = BINARY.stat().st_mode
    token = random.SystemRandom().randrange(100000, 999999)
    route_line = f'default via 198.51.100.{token % 250 + 1} dev verify{token} metric {token}'

    try:
        ROUTES.write_text(
            '203.0.113.0/24 dev test0 proto kernel\n'
            + route_line + '\n'
            + '192.0.2.0/24 dev test1 proto kernel\n'
        )

        # Exercise the submitted monitor with the submitted compiled checker.
        LOG.write_text('SENTINEL\n')
        _stop_port_8888_listeners()
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('127.0.0.1', 8888))
        server.listen(1)
        server.settimeout(5)
        accepted = []

        def accept_one():
            try:
                conn, _ = server.accept()
                accepted.append(True)
                conn.close()
            finally:
                server.close()

        thread = threading.Thread(target=accept_one, daemon=True)
        thread.start()
        env = os.environ.copy()
        env['TZ'] = 'UTC'
        result = subprocess.run([str(MONITOR)], capture_output=True, text=True,
                                timeout=10, cwd='/home/user', env=env)
        thread.join(timeout=5)
        if thread.is_alive():
            server.close()
        assert result.returncode == 0, f'monitor.sh failed: {result.stderr}'
        assert accepted, 'monitor.sh did not run the submitted network checker'
        assert LOG.read_text() == f'SENTINEL\nCONNECT_SUCCESS\n{route_line}\n'

        # Instrument the required checker path to observe the monitor's execution environment.
        tz_record = pathlib.Path(f'/tmp/monitor_tz_{token}')
        probe = (
            '#!/bin/sh\n'
            f'printf "%s\\n" "$TZ" > {tz_record}\n'
            'printf "CONNECT_SUCCESS\\n"\n'
        )
        BINARY.write_text(probe)
        BINARY.chmod(0o755)
        LOG.write_text('SENTINEL\n')
        env['TZ'] = 'UTC'
        result = subprocess.run([str(MONITOR)], capture_output=True, text=True,
                                timeout=10, cwd='/home/user', env=env)
        assert result.returncode == 0, f'monitor.sh failed with instrumented checker: {result.stderr}'
        assert tz_record.is_file(), 'monitor.sh did not execute /home/user/net_check'
        assert tz_record.read_text().strip() == 'America/New_York', 'monitor.sh did not set TZ for its execution scope'
        assert LOG.read_text() == f'SENTINEL\nCONNECT_SUCCESS\n{route_line}\n'
        tz_record.unlink(missing_ok=True)
    finally:
        ROUTES.write_bytes(route_original)
        BINARY.write_bytes(binary_original)
        os.chmod(BINARY, binary_mode)
        if log_existed:
            LOG.write_bytes(log_original)
        else:
            LOG.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
