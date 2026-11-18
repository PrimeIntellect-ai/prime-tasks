#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
from pathlib import Path

import pytest

HOME = Path('/home/user')
LEGACY = HOME / 'legacy_sensor_bin'
LAUNCHER = HOME / 'launcher.exp'
WATCHDOG = HOME / 'watchdog.sh'
LOG = HOME / 'telemetry.log'
ROTATED = HOME / 'telemetry.log.1'
ROTATE_CONF = HOME / 'rotate.conf'

EXPECTED_LEGACY = b'''#!/bin/bash
echo -n "Device Name? "
read dev_name
echo -n "Mode? "
read mode
echo "Initializing $dev_name in $mode mode..."
while true; do
    echo "$(date +%s) - $dev_name - $mode - Sensor reading: $RANDOM"
    sleep 0.5
done
'''


def matching_pids(path):
    target = os.fsencode(str(path))
    found = set()
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            args = (entry / 'cmdline').read_bytes().split(b'\0')
            if target in args:
                found.add(int(entry.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def stop_deployment():
    paths = (LEGACY, LAUNCHER)
    for sig in ('TERM', 'KILL'):
        pids = set().union(*(matching_pids(path) for path in paths))
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, getattr(__import__('signal'), 'SIG' + sig))
            except ProcessLookupError:
                pass
        time.sleep(0.8)


def wait_until(predicate, timeout=8, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def log_text():
    try:
        return LOG.read_text(errors='replace')
    except FileNotFoundError:
        return ''


# Original assertions retained.
def test_legacy_sensor_bin_running():
    try:
        result = subprocess.run(
            ['pgrep', '-f', '/home/user/legacy_sensor_bin'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert result.returncode == 0, 'legacy_sensor_bin is not running. The watchdog script may not have started it correctly.'
    except FileNotFoundError:
        pytest.fail('pgrep command not found. Ensure procps is installed.')


def test_log_rotated():
    rotated_log_path = '/home/user/telemetry.log.1'
    assert os.path.exists(rotated_log_path), f'Rotated log file {rotated_log_path} does not exist. Log rotation did not occur or was not configured correctly.'
    assert os.path.isfile(rotated_log_path), f'{rotated_log_path} is not a regular file.'


def test_watchdog_script_exists_and_executable():
    watchdog_path = '/home/user/watchdog.sh'
    assert os.path.exists(watchdog_path), f'Watchdog script {watchdog_path} does not exist.'
    assert os.path.isfile(watchdog_path), f'{watchdog_path} is not a regular file.'
    st = os.stat(watchdog_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Watchdog script {watchdog_path} is not executable.'


def test_launcher_expect_script_exists():
    launcher_path = '/home/user/launcher.exp'
    assert os.path.exists(launcher_path), f'Expect script {launcher_path} does not exist.'
    assert os.path.isfile(launcher_path), f'{launcher_path} is not a regular file.'


def test_rotate_conf_exists():
    rotate_conf_path = '/home/user/rotate.conf'
    assert os.path.exists(rotate_conf_path), f'Logrotate config {rotate_conf_path} does not exist.'
    assert os.path.isfile(rotate_conf_path), f'{rotate_conf_path} is not a regular file.'


def test_telemetry_log_exists():
    log_path = '/home/user/telemetry.log'
    assert os.path.exists(log_path), f'Active log file {log_path} does not exist.'
    assert os.path.isfile(log_path), f'{log_path} is not a regular file.'


# Added behavioral checks.
def test_launcher_automates_prompts_logs_and_stays_running():
    assert LEGACY.read_bytes() == EXPECTED_LEGACY, 'The supplied legacy sensor binary was modified.'
    stop_deployment()
    LOG.unlink(missing_ok=True)
    proc = subprocess.Popen(
        ['expect', str(LAUNCHER)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        assert wait_until(lambda: bool(matching_pids(LEGACY))), 'launcher.exp did not spawn legacy_sensor_bin.'
        assert wait_until(
            lambda: 'Initializing edge-node-01 in telemetry mode...' in log_text()
            and log_text().count('edge-node-01 - telemetry - Sensor reading:') >= 2,
            timeout=8,
        ), 'launcher.exp did not answer both prompts correctly and log sensor output.'
        time.sleep(1)
        assert proc.poll() is None, 'launcher.exp exited while the sensor was meant to keep running.'
        assert matching_pids(LEGACY), 'The spawned sensor did not remain running.'
    finally:
        stop_deployment()


def test_watchdog_restarts_only_when_needed_and_detaches():
    stop_deployment()
    LOG.unlink(missing_ok=True)
    result = subprocess.run(
        [str(WATCHDOG)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=5,
        text=True,
    )
    assert result.returncode == 0, f'watchdog.sh failed: {result.stderr}'
    assert wait_until(lambda: bool(matching_pids(LEGACY))), 'watchdog.sh did not restart the stopped sensor.'
    assert wait_until(lambda: bool(matching_pids(LAUNCHER))), 'watchdog.sh did not start launcher.exp in the background.'
    assert wait_until(
        lambda: 'Initializing edge-node-01 in telemetry mode...' in log_text()
        and 'edge-node-01 - telemetry - Sensor reading:' in log_text(),
        timeout=8,
    ), 'The watchdog-started deployment was not correctly configured or logged.'

    before = matching_pids(LEGACY)
    subprocess.run(
        [str(WATCHDOG)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=5,
        check=True,
    )
    time.sleep(1.5)
    after = matching_pids(LEGACY)
    assert after == before, 'watchdog.sh started another sensor even though one was already running.'


def run_logrotate(state):
    return subprocess.run(
        ['logrotate', '-s', str(state), str(ROTATE_CONF)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )


def test_logrotate_rules_and_restore_running_final_state():
    stop_deployment()
    state = HOME / '.verifier-lr.state'
    state.unlink(missing_ok=True)
    for suffix in ('', '.1', '.2', '.3', '.1.gz', '.2.gz', '.3.gz'):
        Path(str(LOG) + suffix).unlink(missing_ok=True)

    # A small log must not rotate.
    LOG.write_bytes(b'a' * 50)
    old_inode = LOG.stat().st_ino
    result = run_logrotate(state)
    assert result.returncode == 0, f'logrotate rejected rotate.conf: {result.stderr}'
    assert LOG.exists() and LOG.stat().st_ino == old_inode
    assert not ROTATED.exists(), 'rotate.conf rotates logs below the configured 100-byte size.'

    # A log over 100 bytes must rotate, preserve its data, and create a new empty file.
    LOG.write_bytes(b'b' * 150)
    old_inode = LOG.stat().st_ino
    result = run_logrotate(state)
    assert result.returncode == 0, f'logrotate failed to rotate a large log: {result.stderr}'
    assert ROTATED.read_bytes() == b'b' * 150, 'The rotated backup did not preserve the old log contents.'
    assert LOG.exists() and LOG.is_file() and LOG.stat().st_size == 0, 'No new empty telemetry.log was created.'
    assert LOG.stat().st_ino != old_inode, 'The configuration did not create a new log file after rotation.'

    # Two more rotations must retain exactly two uncompressed backups.
    for byte in (b'c', b'd'):
        LOG.write_bytes(byte * 150)
        result = run_logrotate(state)
        assert result.returncode == 0, f'logrotate failed during retention testing: {result.stderr}'
    assert Path(str(LOG) + '.1').is_file()
    assert Path(str(LOG) + '.2').is_file()
    assert not Path(str(LOG) + '.3').exists(), 'rotate.conf retains more than two backups.'
    assert not list(HOME.glob('telemetry.log.*.gz')), 'rotate.conf compresses rotated logs.'

    # Restore and verify the required final live state.
    result = subprocess.run(
        [str(WATCHDOG)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=5,
        text=True,
    )
    assert result.returncode == 0, f'watchdog failed after rotation: {result.stderr}'
    assert wait_until(lambda: bool(matching_pids(LEGACY))), 'Sensor is not running after rotation.'
    assert wait_until(lambda: LOG.exists() and LOG.stat().st_size > 0), 'Fresh telemetry.log is not receiving data.'
    size_before = LOG.stat().st_size
    time.sleep(1.2)
    assert LOG.stat().st_size > size_before, 'Fresh telemetry.log is not actively receiving new data.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
