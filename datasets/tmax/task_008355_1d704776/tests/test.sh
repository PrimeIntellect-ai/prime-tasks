#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import glob
import gzip
import os
import pwd
import re
import shutil
import subprocess
import tempfile
import time

HOME = '/home/user'
USER_INFO = pwd.getpwnam('user')


def test_directories_exist():
    """Check that logs and backups directories exist."""
    assert os.path.isdir('/home/user/logs'), "/home/user/logs directory does not exist."
    assert os.path.isdir('/home/user/backups'), "/home/user/backups directory does not exist."


def test_c_program_and_binary_exist():
    """Check that the C source code and executable binary exist."""
    assert os.path.isfile('/home/user/disk_monitor.c'), "disk_monitor.c does not exist."
    assert os.path.isfile('/home/user/disk_monitor'), "disk_monitor binary does not exist."
    assert os.access('/home/user/disk_monitor', os.X_OK), "disk_monitor is not executable."


def test_backup_script_exists_and_executable():
    """Check that the backup script exists and is executable."""
    assert os.path.isfile('/home/user/backup.sh'), "backup.sh does not exist."
    assert os.access('/home/user/backup.sh', os.X_OK), "backup.sh is not executable."


def test_logrotate_conf_exists():
    """Check that the logrotate configuration file exists."""
    assert os.path.isfile('/home/user/logrotate.conf'), "logrotate.conf does not exist."


def test_vm_disk_size():
    """Verify that the VM disk is exactly 20 Megabytes (20971520 bytes)."""
    disk_path = '/home/user/vm_disk.img'
    assert os.path.isfile(disk_path), f"{disk_path} does not exist."
    size = os.path.getsize(disk_path)
    assert size == 20971520, f"Expected VM disk size to be 20971520 bytes, got {size} bytes."


def test_backups_created():
    """Verify that at least one valid backup was created and no more than 3 exist."""
    backups = glob.glob('/home/user/backups/vm_disk_backup_*.img')
    assert len(backups) >= 1, "No backup files found in /home/user/backups/."
    assert len(backups) <= 3, f"Found {len(backups)} backups, but expected at most 3."
    assert any(filecmp.cmp('/home/user/vm_disk.img', p, shallow=False) for p in backups), \
        "No existing backup has the same contents as vm_disk.img."


def test_log_rotation_and_contents():
    """Verify that the log was rotated and contains the correct threshold message."""
    log_files = glob.glob('/home/user/logs/monitor.log*')
    assert len(log_files) > 0, "No monitor.log files found in /home/user/logs/."
    rotated_logs = [f for f in log_files if f != '/home/user/logs/monitor.log']
    assert len(rotated_logs) > 0, "Log file was not rotated. Expected monitor.log.1 or monitor.log.1.gz to exist."

    expected_message = "THRESHOLD_EXCEEDED: 20971520"
    message_found = False
    for log_file in log_files:
        try:
            if log_file.endswith('.gz'):
                with gzip.open(log_file, 'rt') as f:
                    content = f.read()
            else:
                with open(log_file, 'r') as f:
                    content = f.read()
            if expected_message in content:
                message_found = True
                break
        except Exception:
            pass
    assert message_found, f"Expected log message '{expected_message}' not found in any log files."


def _replace_directory(path):
    """Temporarily replace a fixed-path directory and return its saved path."""
    saved_parent = tempfile.mkdtemp(prefix='verifier-save-', dir='/tmp')
    saved = os.path.join(saved_parent, os.path.basename(path))
    os.rename(path, saved)
    os.mkdir(path, 0o755)
    os.chown(path, USER_INFO.pw_uid, USER_INFO.pw_gid)
    return saved_parent, saved


def _restore_directory(path, saved_parent, saved):
    shutil.rmtree(path, ignore_errors=True)
    os.rename(saved, path)
    shutil.rmtree(saved_parent, ignore_errors=True)


def _exercise_monitor(executable, work, case_number):
    watch = os.path.join(work, f'watch-{case_number}.img')
    marker = os.path.join(work, f'marker-{case_number}')
    script = os.path.join(work, f'trigger-{case_number}.sh')
    threshold = 123457 + case_number * 1000
    triggered_size = threshold + 4321

    with open(watch, 'wb') as f:
        f.truncate(threshold)
    with open(script, 'w') as f:
        f.write('#!/bin/bash\nprintf "ran\\n" >> ' + marker + '\n')
    os.chmod(script, 0o755)

    # Exactly three arguments are required; invalid invocations must terminate.
    for args in ([], [watch, str(threshold), script, 'extra']):
        result = subprocess.run([executable] + args, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=2)
        assert result.returncode != 0, f"{executable} accepted an invalid argument count"

    monitor_log = '/home/user/logs/monitor.log'
    if os.path.exists(monitor_log):
        os.unlink(monitor_log)

    proc = subprocess.Popen([executable, watch, str(threshold), script],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        time.sleep(1.25)
        assert proc.poll() is None, "Monitor exited before the watched file exceeded the threshold"
        assert not os.path.exists(marker), "Monitor triggered at a size equal to the threshold"

        with open(watch, 'r+b') as f:
            f.truncate(triggered_size)

        try:
            stdout, stderr = proc.communicate(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            raise AssertionError("Monitor did not detect the dynamically enlarged file")

        assert proc.returncode == 0, \
            f"Monitor exited unsuccessfully: {stderr.decode(errors='replace')}"
        assert os.path.isfile(marker), "Monitor did not execute the supplied script"
        with open(marker) as f:
            assert f.read() == 'ran\n', "Supplied script was not executed exactly once"
        with open(monitor_log) as f:
            assert f.read() == f'THRESHOLD_EXCEEDED: {triggered_size}\n', \
                "Monitor did not append the exact dynamically derived log entry once"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def test_monitor_source_compiles_and_both_artifacts_run_dynamically():
    build_dir = tempfile.mkdtemp(prefix='monitor-build-', dir='/tmp')
    rebuilt = os.path.join(build_dir, 'disk_monitor')
    result = subprocess.run(
        ['gcc', '/home/user/disk_monitor.c', '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, \
        f"disk_monitor.c does not compile successfully: {result.stderr.decode(errors='replace')}"

    saved_parent, saved_logs = _replace_directory('/home/user/logs')
    try:
        _exercise_monitor('/home/user/disk_monitor', build_dir, 1)
        _exercise_monitor(rebuilt, build_dir, 2)
    finally:
        _restore_directory('/home/user/logs', saved_parent, saved_logs)
        shutil.rmtree(build_dir, ignore_errors=True)


def test_backup_script_copies_disk_and_retains_three_newest():
    saved_parent, saved_backups = _replace_directory('/home/user/backups')
    try:
        backups_dir = '/home/user/backups'
        # Controlled old backups have matching filename and modification-time order.
        for stamp in (100, 200, 300, 400):
            path = os.path.join(backups_dir, f'vm_disk_backup_{stamp}.img')
            with open(path, 'wb') as f:
                f.write(str(stamp).encode())
            os.utime(path, (stamp, stamp))

        before = int(time.time())
        result = subprocess.run(['/home/user/backup.sh'], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=20)
        after = int(time.time())
        assert result.returncode == 0, \
            f"backup.sh failed: {result.stderr.decode(errors='replace')}"

        backups = sorted(glob.glob(os.path.join(backups_dir, 'vm_disk_backup_*.img')))
        assert len(backups) == 3, f"backup.sh retained {len(backups)} backups instead of exactly 3"

        parsed = []
        for path in backups:
            match = re.fullmatch(r'vm_disk_backup_([0-9]+)\.img', os.path.basename(path))
            assert match, f"Invalid backup filename: {path}"
            parsed.append((int(match.group(1)), path))

        new_backups = [(stamp, path) for stamp, path in parsed if before <= stamp <= after]
        assert len(new_backups) == 1, "backup.sh did not create one backup named with the current epoch time"
        assert filecmp.cmp('/home/user/vm_disk.img', new_backups[0][1], shallow=False), \
            "New backup contents do not match vm_disk.img"
        assert {stamp for stamp, _ in parsed if stamp < before} == {300, 400}, \
            "backup.sh did not delete the oldest backups"
    finally:
        _restore_directory('/home/user/backups', saved_parent, saved_backups)


def test_logrotate_configuration_is_parsed_and_performs_rotation():
    with open('/home/user/logrotate.conf') as f:
        conf_text = f.read()
    uncommented = '\n'.join(line.split('#', 1)[0] for line in conf_text.splitlines())
    assert re.search(r'(?m)^\s*size\s+10\s*$', uncommented), \
        "logrotate.conf must use a 10-byte size threshold"

    saved_parent, saved_logs = _replace_directory('/home/user/logs')
    state = '/home/user/.verifier-logrotate.state'
    try:
        if os.path.exists(state):
            os.unlink(state)
        for cycle in range(4):
            log = '/home/user/logs/monitor.log'
            with open(log, 'w') as f:
                f.write(f'cycle-{cycle}-content-over-ten-bytes\n')
            os.chown(log, USER_INFO.pw_uid, USER_INFO.pw_gid)
            cmd = ['runuser', '-u', 'user', '--', 'logrotate', '-f', '-s', state,
                   '/home/user/logrotate.conf']
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            assert result.returncode == 0, \
                f"logrotate rejected or failed the configuration: {result.stderr.decode(errors='replace')}"

        rotated = sorted(glob.glob('/home/user/logs/monitor.log.*'))
        assert len(rotated) == 2, f"Configuration retained {len(rotated)} rotated logs instead of exactly 2"
        assert all(path.endswith('.gz') for path in rotated), "Rotated logs are not compressed"
        for path in rotated:
            with gzip.open(path, 'rt') as f:
                assert 'content-over-ten-bytes' in f.read(), f"Compressed rotated log {path} is invalid"
    finally:
        if os.path.exists(state):
            os.unlink(state)
        _restore_directory('/home/user/logs', saved_parent, saved_logs)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
