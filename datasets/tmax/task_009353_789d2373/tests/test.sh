#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import subprocess
import time
import uuid
from pathlib import Path

SUPERVISOR = Path('/home/user/supervisor.py')
FLAPPY = Path('/home/user/flappy.py')
FSTAB = Path('/home/user/fstab_mock')
LOG_DIR = Path('/home/user/logs')
SUMMARY = Path('/home/user/summary.txt')
ORIGINAL_BACKUP = Path('/home/user/secure_backups')


def parse_summary():
    content = SUMMARY.read_text(errors='replace')
    restarts_match = re.search(r'Restarts:\s*(\d+)', content)
    backups_match = re.search(r'Backups:\s*(\d+)', content)
    backup_dir_match = re.search(r'Backup_Dir:\s*(\S+)', content)
    assert restarts_match, "Could not find 'Restarts: <number>' in summary.txt"
    assert backups_match, "Could not find 'Backups: <number>' in summary.txt"
    assert backup_dir_match, "Could not find 'Backup_Dir: <path>' in summary.txt"
    return int(restarts_match.group(1)), int(backups_match.group(1)), backup_dir_match.group(1)


def remove_path(path):
    path = Path(path)
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def write_test_flappy(token, launch_marker, term_marker):
    source = f'''#!/usr/bin/env python3
import os
import signal
import sys
import time

TOKEN = {token!r}
LAUNCH_MARKER = {str(launch_marker)!r}
TERM_MARKER = {str(term_marker)!r}
started = time.time()
with open(LAUNCH_MARKER, "a") as marker:
    marker.write(str(started) + "\\n")
    marker.flush()

def terminate(signum, frame):
    with open(TERM_MARKER, "a") as marker:
        marker.write(TOKEN + " terminated " + str(time.time()) + "\\n")
        marker.flush()
    raise SystemExit(0)

signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)
print("STDERR-" + TOKEN, file=sys.stderr, flush=True)
i = 0
while True:
    print(TOKEN + " line=" + str(i) + " " + ("X" * 380), flush=True)
    i += 1
    time.sleep(0.04)
    if time.time() - started >= 1.8:
        print("FATAL ERROR " + TOKEN, file=sys.stderr, flush=True)
        raise SystemExit(7)
'''
    FLAPPY.write_text(source)
    FLAPPY.chmod(0o755)


def residual_flappy_processes():
    found = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            args = (entry / 'cmdline').read_bytes().split(b'\0')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b'/home/user/flappy.py' in args:
            found.append(int(entry.name))
    return found


def run_and_validate(backup_dir, fstab_text, token):
    launch_marker = Path('/tmp') / ('flappy_launches_' + token)
    term_marker = Path('/tmp') / ('flappy_terms_' + token)
    for path in (LOG_DIR, SUMMARY, backup_dir, launch_marker, term_marker):
        remove_path(path)

    FSTAB.write_text(fstab_text)
    write_test_flappy(token, launch_marker, term_marker)

    started = time.monotonic()
    proc = subprocess.Popen(
        ['python3', str(SUPERVISOR)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=28)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        raise AssertionError('supervisor.py did not exit after its required 20-second run')
    elapsed = time.monotonic() - started

    assert proc.returncode == 0, f'supervisor.py exited with {proc.returncode}: {stderr}'
    assert 18.0 <= elapsed <= 25.5, f'Expected an approximately 20-second run, observed {elapsed:.2f} seconds'
    assert SUMMARY.is_file(), 'Supervisor did not generate /home/user/summary.txt'

    restarts, reported_backups, reported_dir = parse_summary()
    assert reported_dir == str(backup_dir), f'Expected parsed backup directory {backup_dir}, got {reported_dir}'
    assert backup_dir.is_dir(), f'Parsed backup directory was not created: {backup_dir}'

    launches = [float(x) for x in launch_marker.read_text().splitlines()] if launch_marker.exists() else []
    assert len(launches) >= 3, f'flappy.py was not repeatedly restarted after crashes; launches={len(launches)}'
    assert restarts == len(launches) - 1, f'Reported {restarts} restarts, but observed {len(launches) - 1}'
    assert all((b - a) < 4.0 for a, b in zip(launches, launches[1:])), 'A crashed process was not promptly restarted'

    assert term_marker.is_file() and token in term_marker.read_text(errors='replace'), 'The final flappy.py process was not gracefully terminated'
    time.sleep(0.3)
    assert not residual_flappy_processes(), 'flappy.py was left running after the supervisor exited'

    assert LOG_DIR.is_dir(), 'Supervisor did not create /home/user/logs'
    main_log = LOG_DIR / 'flappy.log'
    assert main_log.is_file(), 'Supervisor did not create flappy.log'
    rotated = sorted(p for p in LOG_DIR.iterdir() if re.fullmatch(r'flappy\.log\.[1-3]', p.name))
    assert rotated, 'No rotated logs were produced despite sustained output above 1024 bytes'
    assert len(rotated) <= 3, 'More than three old logs were retained'
    assert not any(re.fullmatch(r'flappy\.log\.\d+', p.name) and int(p.name.rsplit('.', 1)[1]) > 3 for p in LOG_DIR.iterdir()), 'A rotated log beyond flappy.log.3 was retained'
    assert all(p.stat().st_size > 0 for p in rotated), 'A rotated log is empty'

    backup_files = sorted(p for p in backup_dir.iterdir() if p.name.startswith('backup_') and p.name.endswith('.log'))
    assert len(backup_files) >= 2, 'Repeated rotations did not create backup files'
    assert reported_backups == len(backup_files), f'Reported {reported_backups} backups, found {len(backup_files)}'
    assert all(p.stat().st_size > 0 for p in backup_files), 'A copied backup is empty'

    log_bytes = b''.join(p.read_bytes() for p in [main_log] + rotated + backup_files)
    assert token.encode() in log_bytes, 'flappy.py stdout was not captured in the log/rotation/backup pipeline'
    assert ('STDERR-' + token).encode() in log_bytes, 'flappy.py stderr was not captured in the log/rotation/backup pipeline'
    latest_rotated = (LOG_DIR / 'flappy.log.1').read_bytes()
    assert any(p.read_bytes() == latest_rotated for p in backup_files), 'flappy.log.1 was not copied to the backup directory when rotated'

    messages = (log_bytes.decode(errors='replace') + '\n' + stdout + '\n' + stderr).lower()
    assert re.search(r'crash|restart|exited|failure', messages), 'No internal crash/restart message was logged'


def test_00_execute_supervisor_and_observe_behavior():
    assert SUPERVISOR.is_file(), f'Supervisor script missing at {SUPERVISOR}'
    compile(SUPERVISOR.read_text(), str(SUPERVISOR), 'exec')

    original_flappy = FLAPPY.read_bytes()
    original_fstab = FSTAB.read_bytes()
    original_mode = FLAPPY.stat().st_mode
    token1 = 'VERIFY_' + uuid.uuid4().hex
    token2 = 'VERIFY_' + uuid.uuid4().hex
    alternate_backup = Path('/home/user') / ('parsed_backups_' + uuid.uuid4().hex)

    alternate_fstab = f'''# decoy: /dev/mapper/backup_vol /tmp/wrong commented ext4 defaults 0 2
/dev/sda1 / ext4 defaults 0 1
   /dev/mapper/backup_vol    {alternate_backup}    ext4    defaults    0 2
'''
    original_fstab_text = original_fstab.decode()

    try:
        run_and_validate(alternate_backup, alternate_fstab, token1)
        run_and_validate(ORIGINAL_BACKUP, original_fstab_text, token2)
    finally:
        FLAPPY.write_bytes(original_flappy)
        os.chmod(FLAPPY, original_mode)
        FSTAB.write_bytes(original_fstab)
        remove_path(alternate_backup)


def test_supervisor_script_exists():
    path = "/home/user/supervisor.py"
    assert os.path.isfile(path), f"Supervisor script missing at {path}"


def test_summary_file_exists_and_content():
    path = "/home/user/summary.txt"
    assert os.path.isfile(path), f"Summary file missing at {path}"

    with open(path, "r") as f:
        content = f.read()

    restarts_match = re.search(r"Restarts:\s*(\d+)", content)
    backups_match = re.search(r"Backups:\s*(\d+)", content)
    backup_dir_match = re.search(r"Backup_Dir:\s*(\S+)", content)

    assert restarts_match, "Could not find 'Restarts: <number>' in summary.txt"
    assert backups_match, "Could not find 'Backups: <number>' in summary.txt"
    assert backup_dir_match, "Could not find 'Backup_Dir: <path>' in summary.txt"

    restarts = int(restarts_match.group(1))
    backups = int(backups_match.group(1))
    backup_dir = backup_dir_match.group(1)

    assert restarts > 0, f"Expected Restarts > 0, got {restarts}"
    assert backups > 0, f"Expected Backups > 0, got {backups}"
    assert backup_dir == "/home/user/secure_backups", f"Expected Backup_Dir to be '/home/user/secure_backups', got {backup_dir}"


def test_backup_directory_and_files():
    backup_dir = "/home/user/secure_backups"
    assert os.path.isdir(backup_dir), f"Backup directory missing at {backup_dir}"

    files = os.listdir(backup_dir)
    backup_files = [f for f in files if f.startswith("backup_") and f.endswith(".log")]

    assert len(backup_files) > 0, f"No backup files found in {backup_dir}"

    summary_path = "/home/user/summary.txt"
    if os.path.isfile(summary_path):
        with open(summary_path, "r") as f:
            content = f.read()
            backups_match = re.search(r"Backups:\s*(\d+)", content)
            if backups_match:
                reported_backups = int(backups_match.group(1))
                assert len(backup_files) == reported_backups, f"Reported backups ({reported_backups}) does not match actual backup files count ({len(backup_files)})"


def test_logs_directory_and_files():
    logs_dir = "/home/user/logs"
    assert os.path.isdir(logs_dir), f"Logs directory missing at {logs_dir}"

    flappy_log = os.path.join(logs_dir, "flappy.log")
    assert os.path.isfile(flappy_log), f"Main log file missing at {flappy_log}"

    files = os.listdir(logs_dir)
    rotated_logs = [f for f in files if re.match(r"flappy\.log\.[1-3]", f)]
    assert len(rotated_logs) > 0, "No rotated log files found (e.g., flappy.log.1) in /home/user/logs"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
