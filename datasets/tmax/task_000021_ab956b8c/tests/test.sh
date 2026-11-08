#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_vm_operator.py
import glob
import json
import os
import pathlib
import secrets
import shutil
import signal
import stat
import subprocess
import time

HOME = pathlib.Path('/home/user')
SCRIPT = HOME / 'vm-operator.sh'
MANIFEST_DIR = HOME / 'manifests'
NETWORK_DIR = HOME / 'network'
BACKUP_DIR = HOME / 'backups'
LOG_FILE = HOME / 'operator.log'
READY_FILE = NETWORK_DIR / 'routing.ready'
MOCK_DIR = pathlib.Path('/tmp/vm-operator-mock-bin')
TRACE_FILE = pathlib.Path('/tmp/qemu-trace.jsonl')
STATE_FILE = pathlib.Path('/tmp/qemu-state')

assert SCRIPT.is_file(), f'{SCRIPT} does not exist or is not a regular file'
assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable'

MOCK_DIR.mkdir(parents=True, exist_ok=True)
mock = MOCK_DIR / 'qemu-system-x86_64'
mock.write_text(r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path

trace = Path(os.environ['QEMU_TRACE'])
state = Path(os.environ['QEMU_STATE'])
try:
    count = int(state.read_text()) + 1
except Exception:
    count = 1
state.write_text(str(count))
with trace.open('a') as f:
    f.write(json.dumps(os.sys.argv[1:]) + '\n')
with open('/home/user/operator.log', 'a') as f:
    f.write('RUNNING QEMU: ' + ' '.join(os.sys.argv[1:]) + '\n')
failures = int(os.environ.get('QEMU_FAILURES', '0'))
raise SystemExit(1 if count <= failures else 0)
''')
mock.chmod(0o755)

def manifest_text(name, host_port, vm_port):
    return f'VM_NAME={name}\nHOST_PORT={host_port}\nVM_PORT={vm_port}\n'

def expected_args(name, host_port, vm_port):
    return [
        '-m', '256', '-name', name,
        '-netdev', f'user,id=net0,hostfwd=tcp:127.0.0.1:{host_port}-:{vm_port}',
        '-device', 'e1000,netdev=net0',
    ]

def reset(manifest):
    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
    NETWORK_DIR.mkdir(parents=True, exist_ok=True)
    for path in MANIFEST_DIR.glob('*.conf'):
        path.unlink()
    (MANIFEST_DIR / 'app.conf').write_text(manifest)
    if BACKUP_DIR.exists():
        shutil.rmtree(BACKUP_DIR)
    if LOG_FILE.exists():
        LOG_FILE.unlink()
    if READY_FILE.exists():
        READY_FILE.unlink()
    for path in (TRACE_FILE, STATE_FILE):
        if path.exists():
            path.unlink()

def environment(failures):
    env = os.environ.copy()
    env['PATH'] = str(MOCK_DIR) + os.pathsep + env.get('PATH', '')
    env['QEMU_TRACE'] = str(TRACE_FILE)
    env['QEMU_STATE'] = str(STATE_FILE)
    env['QEMU_FAILURES'] = str(failures)
    return env

def finish(proc, timeout=12):
    try:
        return proc.communicate(timeout=timeout)[0], proc.returncode
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError('vm-operator.sh did not terminate within the timeout')

def trace_calls():
    if not TRACE_FILE.exists():
        return []
    return [json.loads(line) for line in TRACE_FILE.read_text().splitlines() if line]

def assert_backup(expected_contents):
    assert BACKUP_DIR.is_dir(), f'Backup directory {BACKUP_DIR} does not exist.'
    backups = glob.glob(str(BACKUP_DIR / 'app.conf.*.bak'))
    assert len(backups) == 1, f'Expected exactly 1 backup file for app.conf, found {len(backups)}.'
    filename = pathlib.Path(backups[0]).name
    parts = filename.split('.')
    assert len(parts) == 4 and parts[0:2] == ['app', 'conf'] and parts[3] == 'bak'
    assert parts[2].isdigit(), f'Backup timestamp is not date +%s output: {filename}'
    assert pathlib.Path(backups[0]).read_text() == expected_contents, 'Backup does not match the processed manifest'

# Main scenario: verify that the script really waits before reading the manifest,
# invokes the supplied QEMU mock exactly, backs up the manifest, and retries twice.
reset(manifest_text('decoy', 1111, 2222))
proc = subprocess.Popen(
    [str(SCRIPT)], env=environment(2), stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, text=True, start_new_session=True
)
deadline = time.time() + 5
while time.time() < deadline:
    contents = LOG_FILE.read_text() if LOG_FILE.exists() else ''
    if contents.count('WAITING FOR NETWORK') >= 2:
        break
    if proc.poll() is not None:
        raise AssertionError('vm-operator.sh exited before routing.ready was created')
    time.sleep(0.05)
else:
    os.killpg(proc.pid, signal.SIGKILL)
    proc.communicate()
    raise AssertionError('Expected repeated WAITING FOR NETWORK messages while routing.ready was absent')

assert trace_calls() == [], 'QEMU was invoked before routing.ready existed'
app_manifest = manifest_text('backend', 9090, 3000)
(MANIFEST_DIR / 'app.conf').write_text(app_manifest)
READY_FILE.touch()
_, rc = finish(proc)
assert rc == 0, f'vm-operator.sh exited with status {rc} after the mock eventually succeeded'

calls = trace_calls()
expected = expected_args('backend', 9090, 3000)
assert calls == [expected, expected, expected], f'Unexpected QEMU invocations: {calls!r}'

# Preserve the original verifier's assertions.
assert LOG_FILE.exists(), f'Log file {LOG_FILE} does not exist.'
log_contents = LOG_FILE.read_text()
wait_count = log_contents.count('WAITING FOR NETWORK')
assert wait_count >= 1, "Expected 'WAITING FOR NETWORK' to appear in operator.log while waiting for routing.ready."
assert_backup(app_manifest)
expected_qemu_cmd = 'RUNNING QEMU: -m 256 -name backend -netdev user,id=net0,hostfwd=tcp:127.0.0.1:9090-:3000 -device e1000,netdev=net0'
assert expected_qemu_cmd in log_contents, f'Expected QEMU command not found in {LOG_FILE}.'
restart_count = log_contents.count('RESTARTING backend')
assert restart_count == 2, f"Expected exactly 2 'RESTARTING backend' messages in {LOG_FILE}, found {restart_count}."

# Exercise values not disclosed in the task and verify that a successful VM is not restarted.
suffix = secrets.token_hex(4)
name = 'vm' + suffix
host_port = 20000 + secrets.randbelow(20000)
vm_port = 1024 + secrets.randbelow(8000)
dynamic_manifest = manifest_text(name, host_port, vm_port)
reset(dynamic_manifest)
READY_FILE.touch()
proc = subprocess.Popen(
    [str(SCRIPT)], env=environment(0), stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, text=True, start_new_session=True
)
_, rc = finish(proc)
assert rc == 0, f'vm-operator.sh exited with status {rc} when QEMU succeeded'
assert trace_calls() == [expected_args(name, host_port, vm_port)], 'Successful QEMU process was not invoked exactly once with the manifest values'
assert LOG_FILE.exists(), 'operator.log was not created'
assert LOG_FILE.read_text().count(f'RESTARTING {name}') == 0, 'A successful QEMU process must not be restarted'
assert_backup(dynamic_manifest)

# Verify the maximum-restart boundary: four runs and only three restart messages.
name = 'fail' + secrets.token_hex(4)
host_port = 40000 + secrets.randbelow(10000)
vm_port = 10000 + secrets.randbelow(10000)
failing_manifest = manifest_text(name, host_port, vm_port)
reset(failing_manifest)
READY_FILE.touch()
proc = subprocess.Popen(
    [str(SCRIPT)], env=environment(99), stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, text=True, start_new_session=True
)
finish(proc)
expected = expected_args(name, host_port, vm_port)
assert trace_calls() == [expected, expected, expected, expected], 'A persistently failing VM must run exactly four times'
assert LOG_FILE.exists(), 'operator.log was not created'
assert LOG_FILE.read_text().count(f'RESTARTING {name}') == 3, 'A persistently failing VM must have exactly three restart messages'
assert_backup(failing_manifest)
PY_EOF

if python3 /tmp/test_vm_operator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
