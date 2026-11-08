#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import signal
import subprocess
import time
from pathlib import Path
from zoneinfo import ZoneInfo

CONF = Path('/home/user/config/daemon.conf')
ENV_FILE = Path('/home/user/config/daemon.env')
SOURCE = Path('/home/user/src/daemon.cpp')
BINARY = Path('/home/user/bin/daemon')
MANAGER = Path('/home/user/bin/service_manager.sh')
PID_FILE = Path('/home/user/run/daemon.pid')
LOG_FILE = Path('/home/user/logs/daemon_output.log')
TEMP_BINARY = Path('/tmp/daemon_source_build')


def running(pid):
    proc = Path(f'/proc/{pid}')
    if not proc.exists():
        return False
    try:
        state = (proc / 'stat').read_text().split()[2]
        return state != 'Z'
    except (FileNotFoundError, ProcessLookupError):
        return False


def wait_for(predicate, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if predicate():
                return True
        except (FileNotFoundError, ProcessLookupError, ValueError):
            pass
        time.sleep(0.05)
    return False


def read_pid():
    assert PID_FILE.is_file(), f'PID file {PID_FILE} is missing.'
    text = PID_FILE.read_text().strip()
    assert text.isdigit(), f"PID file {PID_FILE} does not contain a valid integer PID. Found: '{text}'"
    return int(text)


def assert_real_daemon(pid):
    assert running(pid), f'Process with PID {pid} is not running.'
    cmdline_file = Path(f'/proc/{pid}/cmdline')
    assert cmdline_file.exists(), f'Process with PID {pid} is not running.'
    cmdline = cmdline_file.read_bytes().replace(b'\0', b' ').decode(errors='replace').strip()
    assert 'daemon' in cmdline, f'Process {pid} is running, but it does not appear to be the daemon (cmdline: {cmdline}).'
    proc_exe = Path(f'/proc/{pid}/exe')
    assert os.path.samefile(proc_exe, BINARY), f'PID {pid} is not executing {BINARY}.'


def legacy_checks(expected_time):
    pid = read_pid()
    assert_real_daemon(pid)
    assert LOG_FILE.is_file(), f'Log file {LOG_FILE} is missing. The daemon did not write it.'
    content = LOG_FILE.read_text().strip()
    assert expected_time in content, f"Log file {LOG_FILE} does not contain the correctly formatted time. Expected '{expected_time}', found '{content}'."
    return pid


def expected(epoch, timezone):
    return datetime.datetime.fromtimestamp(epoch, ZoneInfo(timezone)).strftime('%Y-%m-%d %H:%M:%S')


def write_inputs(epoch, timezone):
    CONF.write_text(f'TARGET_TIME={epoch}\n')
    ENV_FILE.write_text(f'TZ={timezone}\n')


def run_manager(command, parent_tz='UTC'):
    env = os.environ.copy()
    env['TZ'] = parent_tz
    result = subprocess.run(
        [str(MANAGER), command], env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8
    )
    assert result.returncode == 0, f'service_manager.sh {command} failed with status {result.returncode}'


def stop_and_check(pid):
    run_manager('stop')
    assert wait_for(lambda: not running(pid)), f'service_manager.sh stop did not terminate PID {pid}'
    assert not PID_FILE.exists(), 'service_manager.sh stop did not remove the PID file'


def kill_if_running(pid):
    if pid and running(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def main():
    assert SOURCE.is_file(), f'Missing source file {SOURCE}'
    assert MANAGER.is_file() and os.access(MANAGER, os.X_OK), f'{MANAGER} is missing or not executable'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), f'{BINARY} is missing or not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', f'{BINARY} is not a compiled ELF executable'

    original_conf = CONF.read_bytes()
    original_env = ENV_FILE.read_bytes()
    active_pid = None
    direct_proc = None
    completed = False

    try:
        # Preserve the original verifier's assertions against the state left by the agent.
        active_pid = legacy_checks('2023-11-14 12:13:20')

        # Exercise the required stop operation before changing test inputs.
        stop_and_check(active_pid)
        active_pid = None

        rng = random.SystemRandom()
        zones = ['America/New_York', 'Europe/Berlin', 'Asia/Tokyo', 'Australia/Adelaide']
        timezone = rng.choice(zones)
        epoch = rng.randrange(946684800, 1893456000)
        wanted = expected(epoch, timezone)
        write_inputs(epoch, timezone)
        PID_FILE.unlink(missing_ok=True)
        LOG_FILE.unlink(missing_ok=True)

        # Use a conflicting parent TZ so success requires sourcing daemon.env.
        run_manager('start', parent_tz='UTC')
        assert wait_for(lambda: PID_FILE.is_file() and LOG_FILE.is_file()), 'start did not create the PID and log files'
        active_pid = read_pid()
        assert_real_daemon(active_pid)
        assert wait_for(lambda: LOG_FILE.read_text().strip() == wanted), \
            f"Daemon did not derive '{wanted}' from the generated config and timezone"
        assert LOG_FILE.read_text().strip() == wanted
        stop_and_check(active_pid)
        active_pid = None

        # Compile and execute the submitted source independently, proving the source itself implements the daemon.
        TEMP_BINARY.unlink(missing_ok=True)
        build = subprocess.run(
            ['g++', '-std=c++17', str(SOURCE), '-o', str(TEMP_BINARY)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert build.returncode == 0, f'Submitted C++ source does not compile: {build.stderr}'
        assert TEMP_BINARY.read_bytes()[:4] == b'\x7fELF'

        timezone2 = rng.choice([z for z in zones if z != timezone])
        epoch2 = rng.randrange(946684800, 1893456000)
        wanted2 = expected(epoch2, timezone2)
        write_inputs(epoch2, timezone2)
        PID_FILE.unlink(missing_ok=True)
        LOG_FILE.unlink(missing_ok=True)
        direct_env = os.environ.copy()
        direct_env['TZ'] = timezone2
        direct_proc = subprocess.Popen(
            [str(TEMP_BINARY)], env=direct_env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        assert wait_for(lambda: PID_FILE.is_file() and LOG_FILE.is_file()), 'Daemon built from submitted source did not initialize'
        direct_pid = read_pid()
        assert direct_pid == direct_proc.pid, 'Daemon did not write its own PID'
        assert running(direct_pid), 'Daemon built from submitted source did not remain running'
        assert os.path.samefile(f'/proc/{direct_pid}/exe', TEMP_BINARY)
        assert wait_for(lambda: LOG_FILE.read_text().strip() == wanted2), 'Source-built daemon produced an incorrect timestamp'
        direct_proc.terminate()
        direct_proc.wait(timeout=6)
        direct_proc = None
        PID_FILE.unlink(missing_ok=True)

        # Restore the supplied configuration and leave the real managed service running.
        CONF.write_bytes(original_conf)
        ENV_FILE.write_bytes(original_env)
        LOG_FILE.unlink(missing_ok=True)
        run_manager('start', parent_tz='UTC')
        assert wait_for(lambda: PID_FILE.is_file() and LOG_FILE.is_file()), 'Final service start did not initialize'
        active_pid = legacy_checks('2023-11-14 12:13:20')
        completed = True
    finally:
        if not completed:
            if direct_proc is not None:
                kill_if_running(direct_proc.pid)
            kill_if_running(active_pid)
            CONF.write_bytes(original_conf)
            ENV_FILE.write_bytes(original_env)
        TEMP_BINARY.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
