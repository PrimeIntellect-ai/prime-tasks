#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/flock_probe
mkdir -p /tmp/flock_probe
cat << 'PY_EOF' > /tmp/flock_probe/sitecustomize.py
import fcntl
import json
import os

_original_flock = fcntl.flock
_log_path = os.environ.get('FLOCK_PROBE_LOG')

def _tracked_flock(fd, operation):
    result = _original_flock(fd, operation)
    try:
        number = fd if isinstance(fd, int) else fd.fileno()
        target = os.path.realpath(os.readlink('/proc/self/fd/%d' % number))
        if _log_path:
            with open(_log_path, 'a', encoding='utf-8') as log:
                log.write(json.dumps({'path': target, 'operation': operation}) + '\n')
    except Exception:
        pass
    return result

fcntl.flock = _tracked_flock
PY_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import zipfile

script_path = '/home/user/update_configs.py'
root = Path('/home/user/app_configs')
zip_path = Path('/home/user/pre_update_backup.zip')
lock_log = Path('/tmp/flock_probe.log')

# Preserve the original artifact checks before creating fresh fixtures.
assert os.path.exists(script_path), f"Script {script_path} does not exist."
assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."
with open(script_path, 'r') as f:
    code = f.read()
assert 'fcntl.flock' in code, "Script does not use fcntl.flock as required."
compile(code, script_path, 'exec')

# Recreate the public fixtures so direct edits made before verification cannot pass.
shutil.rmtree(root, ignore_errors=True)
root.mkdir(parents=True)
(root / 'serviceA').mkdir()
(root / 'serviceB' / 'nested').mkdir(parents=True)
(root / 'serviceC').mkdir()

original_a = """[general]
name = serviceA
[auth_v1]
token_expiry = 3600
retry = 3
"""
original_b = """[database]
host = localhost
[auth_v1]
token_expiry = 3600
"""
original_c = """[general]
name = serviceC
[auth_v2]
token_expiry = 86400
"""
(root / 'serviceA' / 'config.ini').write_text(original_a)
(root / 'serviceB' / 'nested' / 'settings.ini').write_text(original_b)
(root / 'serviceC' / 'config.ini').write_text(original_c)

# Add unpredictable recursive cases that only the submitted script can discover.
tag = secrets.token_hex(10)
hidden_dir = root / ('generated_' + tag) / 'one' / 'two'
hidden_dir.mkdir(parents=True)
hidden_changed = hidden_dir / ('changed_' + tag + '.ini')
hidden_header_only = hidden_dir / ('header_' + tag + '.ini')
hidden_unchanged = hidden_dir / ('unchanged_' + tag + '.ini')
hidden_non_ini = hidden_dir / ('ignored_' + tag + '.txt')

original_changed = """[general]
token_expiry = 3600
[auth_v1]
token_expiry = 3600
keep = yes
[other]
token_expiry = 3600
"""
expected_changed = """[general]
token_expiry = 3600
[auth_v2]
token_expiry = 86400
keep = yes
[other]
token_expiry = 3600
"""
original_header_only = """[auth_v1]
mode = legacy
[next]
token_expiry = 3600
"""
expected_header_only = """[auth_v2]
mode = legacy
[next]
token_expiry = 3600
"""
original_unchanged = """[auth_v2]
token_expiry = 86400
"""
original_non_ini = """[auth_v1]
token_expiry = 3600
"""

hidden_changed.write_text(original_changed)
hidden_header_only.write_text(original_header_only)
hidden_unchanged.write_text(original_unchanged)
hidden_non_ini.write_text(original_non_ini)

all_ini_files = sorted(path.resolve() for path in root.rglob('*.ini'))
if zip_path.exists():
    zip_path.unlink()
if lock_log.exists():
    lock_log.unlink()

env = os.environ.copy()
env['PYTHONPATH'] = '/tmp/flock_probe' + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
env['FLOCK_PROBE_LOG'] = str(lock_log)
try:
    completed = subprocess.run(
        ['python3', script_path],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
except subprocess.TimeoutExpired as exc:
    raise AssertionError('update_configs.py did not complete and may have left a lock hanging') from exc
assert completed.returncode == 0, (
    f"update_configs.py exited with {completed.returncode}.\n"
    f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
)

# Original backup assertions.
assert os.path.exists(zip_path), f"Backup zip {zip_path} does not exist."
with zipfile.ZipFile(zip_path, 'r') as z:
    names = z.namelist()
    assert 'serviceA/config.ini' in names, "serviceA/config.ini missing from backup zip."
    assert 'serviceB/nested/settings.ini' in names, "serviceB/nested/settings.ini missing from backup zip."
    assert 'serviceC/config.ini' not in names, "serviceC/config.ini should not be in backup zip because it didn't need modification."

    content_A = z.read('serviceA/config.ini').decode('utf-8')
    assert '[auth_v1]' in content_A, "Original [auth_v1] missing in backed up serviceA/config.ini."
    assert 'token_expiry = 3600' in content_A, "Original token_expiry missing in backed up serviceA/config.ini."

    content_B = z.read('serviceB/nested/settings.ini').decode('utf-8')
    assert '[auth_v1]' in content_B, "Original [auth_v1] missing in backed up serviceB/nested/settings.ini."
    assert 'token_expiry = 3600' in content_B, "Original token_expiry missing in backed up serviceB/nested/settings.ini."

    changed_arc = hidden_changed.relative_to(root).as_posix()
    header_arc = hidden_header_only.relative_to(root).as_posix()
    unchanged_arc = hidden_unchanged.relative_to(root).as_posix()
    assert changed_arc in names, 'Recursively discovered modified file is missing from backup zip.'
    assert header_arc in names, 'File whose auth header changed is missing from backup zip.'
    assert unchanged_arc not in names, 'Unmodified generated file must not be backed up.'
    assert z.read(changed_arc).decode('utf-8') == original_changed
    assert z.read(header_arc).decode('utf-8') == original_header_only

    expected_members = {
        'serviceA/config.ini',
        'serviceB/nested/settings.ini',
        changed_arc,
        header_arc,
    }
    assert sorted(names) == sorted(expected_members), 'Backup contains missing, extra, or duplicate entries.'

# Original updated-file assertions.
file_path_A = '/home/user/app_configs/serviceA/config.ini'
assert os.path.exists(file_path_A), f"File {file_path_A} missing."
with open(file_path_A, 'r') as f:
    content_A = f.read()
assert '[auth_v2]' in content_A, f"[auth_v2] not found in {file_path_A}."
assert 'token_expiry = 86400' in content_A, f"token_expiry = 86400 not found in {file_path_A}."
assert '[auth_v1]' not in content_A, f"[auth_v1] should be replaced in {file_path_A}."

file_path_B = '/home/user/app_configs/serviceB/nested/settings.ini'
assert os.path.exists(file_path_B), f"File {file_path_B} missing."
with open(file_path_B, 'r') as f:
    content_B = f.read()
assert '[auth_v2]' in content_B, f"[auth_v2] not found in {file_path_B}."
assert 'token_expiry = 86400' in content_B, f"token_expiry = 86400 not found in {file_path_B}."
assert '[auth_v1]' not in content_B, f"[auth_v1] should be replaced in {file_path_B}."

file_path_C = '/home/user/app_configs/serviceC/config.ini'
assert os.path.exists(file_path_C), f"File {file_path_C} missing."
with open(file_path_C, 'r') as f:
    content_C = f.read()
assert '[auth_v2]' in content_C, f"Expected [auth_v2] in {file_path_C}."
assert 'token_expiry = 86400' in content_C, f"Expected token_expiry = 86400 in {file_path_C}."

# Validate recursive and section-scoped behavior on generated inputs.
assert hidden_changed.read_text() == expected_changed
assert hidden_header_only.read_text() == expected_header_only
assert hidden_unchanged.read_text() == original_unchanged
assert hidden_non_ini.read_text() == original_non_ini
assert Path(file_path_A).read_text() == original_a.replace('[auth_v1]', '[auth_v2]').replace('token_expiry = 3600', 'token_expiry = 86400')
assert Path(file_path_B).read_text() == original_b.replace('[auth_v1]', '[auth_v2]').replace('token_expiry = 3600', 'token_expiry = 86400')
assert Path(file_path_C).read_text() == original_c

# The probe wraps the real fcntl.flock. Every .ini file must receive LOCK_EX.
assert lock_log.exists(), 'No fcntl.flock calls were observed while executing the script.'
records = [json.loads(line) for line in lock_log.read_text().splitlines() if line.strip()]
exclusive_paths = {
    Path(record['path']).resolve()
    for record in records
    if (record['operation'] & fcntl.LOCK_EX) == fcntl.LOCK_EX
}
for ini_path in all_ini_files:
    assert ini_path in exclusive_paths, f'No exclusive flock was acquired for {ini_path}'

# Confirm all files can be locked after completion, whether release was explicit or by close.
for ini_path in all_ini_files:
    with open(ini_path, 'r+') as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise AssertionError(f'Lock remains held for {ini_path}') from exc
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
