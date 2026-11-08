#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest

HOME = Path('/home/user')
MANAGED = HOME / 'managed_users'
LINKS = HOME / 'active_links'
LOG = HOME / 'monitor_log.txt'
MONITOR = HOME / 'account_monitor'
SOURCE = HOME / 'account_monitor.cpp'
SCRIPT = HOME / 'schedule_monitor.sh'


def read_log():
    if not LOG.exists():
        return []
    return [line.strip() for line in LOG.read_text().splitlines() if line.strip()]


def test_01_monitor_log_contents():
    assert LOG.exists(), f"Log file {LOG} does not exist."
    expected_lines = [
        "alice:ACTIVE",
        "bob:INACTIVE",
        "charlie:INACTIVE"
    ]
    assert sorted(read_log()) == expected_lines, \
        f"Log contents mismatch. Expected {expected_lines}, got {sorted(read_log())}"


def test_02_active_links_directory():
    assert LINKS.is_dir(), f"Directory {LINKS} does not exist."
    active_links = os.listdir(LINKS)
    assert "alice" in active_links, "Symlink 'alice' is missing from active_links directory."
    assert len(active_links) == 1, \
        f"active_links directory should only contain 'alice', found: {active_links}"
    link_path = LINKS / 'alice'
    assert link_path.is_symlink(), f"{link_path} is not a symbolic link."
    assert os.readlink(link_path) == '/home/user/managed_users/alice', \
        f"Symlink target mismatch. Expected /home/user/managed_users/alice, got {os.readlink(link_path)}"


def test_03_schedule_monitor_running():
    assert SCRIPT.exists(), f"Scheduling script {SCRIPT} does not exist."
    try:
        output = subprocess.check_output(['pgrep', '-f', 'schedule_monitor.sh'], text=True)
        assert output.strip(), 'schedule_monitor.sh is not running in the background.'
    except subprocess.CalledProcessError:
        pytest.fail('schedule_monitor.sh is not running in the background.')
    subprocess.run(['bash', '-n', str(SCRIPT)], check=True)


def test_04_cpp_program_exists():
    assert SOURCE.is_file(), f"C++ source file {SOURCE} does not exist."
    assert MONITOR.is_file(), f"Compiled executable {MONITOR} does not exist."
    assert os.access(MONITOR, os.X_OK), f"File {MONITOR} is not executable."


def scheduler_pids():
    found = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes().replace(b'\0', b' ')
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if b'/home/user/schedule_monitor.sh' in cmdline:
            found.append(int(entry.name))
    return found


def stop_existing_schedulers():
    for pid in scheduler_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while scheduler_pids() and time.time() < deadline:
        time.sleep(0.1)
    for pid in scheduler_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)


def start_named_worker(username):
    target = Path('/tmp') / f'worker_{username}'
    shutil.copy2('/home/user/worker_alice', target)
    target.chmod(0o755)
    proc = subprocess.Popen([str(target)], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    deadline = time.time() + 3
    while time.time() < deadline:
        result = subprocess.run(['pgrep', '-x', f'worker_{username}'],
                                stdout=subprocess.DEVNULL)
        if result.returncode == 0:
            return proc, target
        time.sleep(0.05)
    proc.terminate()
    raise AssertionError(f'Failed to start controlled worker_{username} process')


def expected_state():
    result = {}
    for user_dir in sorted(p for p in MANAGED.iterdir() if p.is_dir()):
        username = user_dir.name
        host = (user_dir / 'node.txt').read_text().strip()
        reachable = subprocess.run(
            ['ping', '-c', '1', '-W', '1', host],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode == 0
        running = subprocess.run(
            ['pgrep', '-x', f'worker_{username}'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode == 0
        result[username] = reachable and running
    return result


def assert_monitor_result(expected):
    expected_lines = sorted(
        f"{username}:{'ACTIVE' if active else 'INACTIVE'}"
        for username, active in expected.items()
    )
    assert read_log() == expected_lines, \
        f'Monitor did not report derived system state. Expected {expected_lines}, got {read_log()}'

    for username, active in expected.items():
        link = LINKS / username
        if active:
            assert link.is_symlink(), f'Active user {username} has no symbolic link'
            assert os.readlink(link) == str(MANAGED / username), \
                f'Link for {username} has the wrong target'
        else:
            assert not os.path.lexists(link), f'Inactive user {username} retained a link'


def test_05_monitor_source_and_executable_handle_derived_states():
    stop_existing_schedulers()
    users = {
        'tact': '127.0.0.1',       # reachable, controlled worker running
        'tnop': '127.0.0.1',       # reachable, no worker
        'thost': '198.51.100.254'  # controlled worker, unreachable host
    }
    workers = []
    compiled = Path('/tmp/account_monitor_from_source')
    try:
        for username, host in users.items():
            user_dir = MANAGED / username
            user_dir.mkdir()
            (user_dir / 'node.txt').write_text(host + '\n')

        for username in ('tnop', 'thost'):
            stale = LINKS / username
            if os.path.lexists(stale):
                os.unlink(stale)
            os.symlink(str(MANAGED / username), stale)

        for username in ('tact', 'thost'):
            workers.append(start_named_worker(username))

        expected = expected_state()
        assert expected['tact'] is True
        assert expected['tnop'] is False
        assert expected['thost'] is False

        subprocess.run([str(MONITOR)], check=True, timeout=15)
        assert_monitor_result(expected)

        subprocess.run(
            ['g++', '-std=c++17', str(SOURCE), '-o', str(compiled)],
            check=True, timeout=30
        )
        subprocess.run([str(compiled)], check=True, timeout=15)
        assert_monitor_result(expected)
    finally:
        for proc, target in workers:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
            target.unlink(missing_ok=True)
        compiled.unlink(missing_ok=True)
        for username in users:
            link = LINKS / username
            if os.path.lexists(link):
                os.unlink(link)
            shutil.rmtree(MANAGED / username, ignore_errors=True)


def wait_for_status(username, status, timeout):
    wanted = f'{username}:{status}'
    deadline = time.time() + timeout
    while time.time() < deadline:
        if wanted in read_log():
            return
        time.sleep(0.25)
    raise AssertionError(f'Scheduler did not produce {wanted} within {timeout} seconds')


def test_06_scheduler_repeatedly_executes_monitor():
    username = 'sprobe'
    user_dir = MANAGED / username
    user_dir.mkdir(exist_ok=True)
    (user_dir / 'node.txt').write_text('127.0.0.1\n')
    link = LINKS / username
    if os.path.lexists(link):
        os.unlink(link)

    scheduler = subprocess.Popen(
        ['bash', str(SCRIPT)], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    worker = None
    target = None
    try:
        wait_for_status(username, 'INACTIVE', 10)
        worker, target = start_named_worker(username)
        wait_for_status(username, 'ACTIVE', 75)
        assert link.is_symlink(), 'Recurring scheduler did not create the active-user link'
        assert os.readlink(link) == str(user_dir)
        assert scheduler.poll() is None or scheduler_pids(), \
            'Scheduling daemon exited instead of continuing to run'
    finally:
        if worker is not None:
            worker.terminate()
            try:
                worker.wait(timeout=2)
            except subprocess.TimeoutExpired:
                worker.kill()
        if target is not None:
            target.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
