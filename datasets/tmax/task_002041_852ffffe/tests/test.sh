#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_deploy.py
import os
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import uuid
from pathlib import Path

SCRIPT = Path('/home/user/deploy.sh')
HOME = Path('/home/user')
STORAGE = HOME / 'app_storage'
DEPLOY_LOG = HOME / 'deploy.log'
CURRENT_PID = STORAGE / 'current.pid'
APP_LOG = STORAGE / 'app.log'
APPS = HOME / 'apps'


def process_state(pid):
    try:
        return Path(f'/proc/{pid}/stat').read_text().split()[2]
    except (FileNotFoundError, IndexError, PermissionError):
        return None


def is_live(pid):
    state = process_state(pid)
    return state is not None and state != 'Z'


def wait_dead(pid, timeout=5):
    end = time.time() + timeout
    while time.time() < end:
        if not is_live(pid):
            return True
        time.sleep(0.1)
    return not is_live(pid)


def kill_storage_processes():
    pids = set()
    if CURRENT_PID.is_file():
        try:
            pids.add(int(CURRENT_PID.read_text().strip()))
        except (ValueError, OSError):
            pass
    if DEPLOY_LOG.is_file():
        for value in re.findall(r'with PID (\d+)', DEPLOY_LOG.read_text(errors='replace')):
            pids.add(int(value))
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmdline = (proc / 'cmdline').read_bytes().replace(b'\0', b' ')
            if b'/home/user/app_storage/' in cmdline:
                pids.add(int(proc.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in pids:
            try:
                os.kill(pid, sig)
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.3)


def reset_state():
    kill_storage_processes()
    shutil.rmtree(STORAGE, ignore_errors=True)
    try:
        DEPLOY_LOG.unlink()
    except FileNotFoundError:
        pass


def run_deploy(archive):
    return subprocess.run(
        ['runuser', '-u', 'user', '--', str(SCRIPT), str(archive)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def read_pid():
    assert CURRENT_PID.is_file(), f'{CURRENT_PID} does not exist'
    value = CURRENT_PID.read_text().strip()
    assert value.isdigit(), f'PID file does not contain a valid integer: {value!r}'
    return int(value)


def make_archive(name, run_text, extra=None):
    root = Path(tempfile.mkdtemp(prefix='deploy_probe_'))
    archive = Path('/tmp') / f'{name}.tar.gz'
    run_file = root / 'run.sh'
    run_file.write_text(run_text)
    run_file.chmod(0o755)
    if extra:
        for filename, data in extra.items():
            (root / filename).write_bytes(data)
    with tarfile.open(archive, 'w:gz') as tf:
        for item in root.iterdir():
            tf.add(item, arcname=item.name)
    archive.chmod(0o644)
    shutil.rmtree(root)
    return archive


def combined(result):
    return result.stdout + result.stderr


def assert_script_basics():
    assert SCRIPT.is_file(), f'Deployment script {SCRIPT} does not exist'
    assert os.access(SCRIPT, os.X_OK), f'Deployment script {SCRIPT} is not executable'
    text = SCRIPT.read_text(errors='replace')
    assert re.search(r'^\s*set\s+-euo\s+pipefail\s*$', text, re.MULTILINE), \
        'deploy.sh must use set -euo pipefail'


def exercise_unpredictable_inputs():
    reset_state()
    tag = uuid.uuid4().hex[:12]
    first_name = f'probe_{tag}_a'
    second_name = f'probe_{tag}_b'
    bad_name = f'probe_{tag}_unsafe'
    quota_name = f'probe_{tag}_quota'

    first = make_archive(first_name, f'#!/bin/bash\necho "{tag} first"\nsleep 3600\n')
    second = make_archive(second_name, f'#!/bin/bash\necho "{tag} second"\nsleep 3600\n')
    bad = make_archive(bad_name, '#!/bin/bash\necho unsafe\nwget http://invalid.example/\nsleep 3600\n')
    quota = make_archive(quota_name, '#!/bin/bash\necho quota-probe\nsleep 3600\n')

    result = run_deploy(first)
    assert result.returncode == 0, combined(result)
    first_pid = read_pid()
    assert is_live(first_pid), 'First probe process is not running'
    assert (STORAGE / f'app_{first_name}' / 'run.sh').is_file()

    result = run_deploy(second)
    assert result.returncode == 0, combined(result)
    second_pid = read_pid()
    assert second_pid != first_pid and is_live(second_pid), 'Rolling deployment did not start a new process'
    assert wait_dead(first_pid), 'Rolling deployment did not terminate the previous PID'
    assert (STORAGE / f'app_{second_name}' / 'run.sh').is_file()

    result = run_deploy(bad)
    assert result.returncode != 0, 'Archive containing wget was accepted'
    assert 'ERROR: Security violation detected' in combined(result)
    assert not (STORAGE / f'app_{bad_name}').exists()
    assert read_pid() == second_pid and is_live(second_pid), 'Rejected deployment changed the current process'
    log = DEPLOY_LOG.read_text(errors='replace')
    assert f'[FAILED] {bad.name} - Security violation' in log
    assert not any(STORAGE.glob('tmp_extract_*')), 'Security rejection left a temporary extraction directory'

    with open(STORAGE / 'quota_filler.bin', 'wb') as f:
        f.write(b'Q' * (6 * 1024 * 1024))
    result = run_deploy(quota)
    assert result.returncode != 0, 'Deployment was accepted while current storage exceeded 5000 KB'
    assert 'ERROR: Storage quota exceeded' in combined(result)
    assert not (STORAGE / f'app_{quota_name}').exists()
    assert read_pid() == second_pid and is_live(second_pid), 'Quota rejection changed the current process'
    log = DEPLOY_LOG.read_text(errors='replace')
    assert f'[FAILED] {quota.name} - Quota exceeded' in log

    for archive in (first, second, bad, quota):
        archive.unlink(missing_ok=True)


def exercise_required_sequence_and_final_state():
    reset_state()

    v1 = run_deploy(APPS / 'v1.tar.gz')
    assert v1.returncode == 0, combined(v1)
    v1_pid = read_pid()
    assert is_live(v1_pid), 'v1 process did not remain running'

    v2 = run_deploy(APPS / 'v2.tar.gz')
    assert v2.returncode != 0, 'v2 security violation did not abort'
    assert 'ERROR: Security violation detected' in combined(v2)
    assert read_pid() == v1_pid and is_live(v1_pid), 'v2 rejection changed the running deployment'

    # The quota is explicitly checked before extraction. Since current storage is
    # still small here, v3 must be accepted even though its payload is over 5 MB.
    v3 = run_deploy(APPS / 'v3.tar.gz')
    assert v3.returncode == 0, combined(v3)
    v3_pid = read_pid()
    assert v3_pid != v1_pid and is_live(v3_pid), 'v3 process is not running'
    assert wait_dead(v1_pid), f'v1 process with PID {v1_pid} is still running'

    # v3 has now made current storage exceed the quota, so the subsequent v4
    # attempt must be rejected before extraction.
    v4 = run_deploy(APPS / 'v4.tar.gz')
    assert v4.returncode != 0, 'v4 was accepted despite the current storage usage'
    assert 'ERROR: Storage quota exceeded' in combined(v4)
    assert read_pid() == v3_pid and is_live(v3_pid), 'v4 rejection changed the current process'

    assert DEPLOY_LOG.is_file(), f'Log file {DEPLOY_LOG} does not exist'
    log = DEPLOY_LOG.read_text(errors='replace')
    m1 = re.search(r'\[SUCCESS\] Deployed v1\.tar\.gz with PID (\d+)', log)
    m3 = re.search(r'\[SUCCESS\] Deployed v3\.tar\.gz with PID (\d+)', log)
    assert m1 and int(m1.group(1)) == v1_pid, 'v1 success log missing or incorrect'
    assert re.search(r'\[FAILED\] v2\.tar\.gz - Security violation', log), 'v2 failure log missing or incorrect'
    assert m3 and int(m3.group(1)) == v3_pid, 'v3 success log missing or incorrect'
    assert re.search(r'\[FAILED\] v4\.tar\.gz - Quota exceeded', log), 'v4 failure log missing or incorrect'

    app_v1 = STORAGE / 'app_v1'
    app_v3 = STORAGE / 'app_v3'
    assert app_v1.is_dir(), 'app_v1 directory should exist'
    assert app_v3.is_dir(), 'app_v3 directory should exist'
    assert not (STORAGE / 'app_v2').exists(), 'app_v2 directory should not exist'
    assert not (STORAGE / 'app_v4').exists(), 'app_v4 directory should not exist'
    assert not any(STORAGE.glob('tmp_extract_*')), 'Temporary extraction directories remain'

    with tarfile.open(APPS / 'v1.tar.gz', 'r:gz') as tf:
        expected_v1_run = tf.extractfile('run.sh').read()
    with tarfile.open(APPS / 'v3.tar.gz', 'r:gz') as tf:
        expected_v3_run = tf.extractfile('run.sh').read()
        expected_dummy_size = tf.getmember('dummy.dat').size
    assert (app_v1 / 'run.sh').read_bytes() == expected_v1_run
    assert (app_v3 / 'run.sh').read_bytes() == expected_v3_run
    assert (app_v3 / 'dummy.dat').stat().st_size == expected_dummy_size

    cmdline = Path(f'/proc/{v3_pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    assert '/home/user/app_storage/app_v3/run.sh' in cmdline, \
        f'Current PID is not the deployed v3 run.sh process: {cmdline}'

    assert APP_LOG.is_file(), f'{APP_LOG} does not exist'
    app_log = APP_LOG.read_text(errors='replace')
    assert 'v1 running' in app_log, 'v1 output missing from app.log'
    assert 'v3 running' in app_log, 'v3 output missing from app.log'
    assert 'v2 running' not in app_log, 'Rejected v2 was executed'
    assert 'v4 running' not in app_log, 'Rejected v4 was executed'


assert_script_basics()
exercise_unpredictable_inputs()
exercise_required_sequence_and_final_state()
PY_EOF

if python3 /tmp/test_deploy.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
