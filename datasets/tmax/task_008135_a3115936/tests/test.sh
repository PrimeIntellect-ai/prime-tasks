#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_legit_txt_extracted_and_converted():
    legit_path = '/home/user/extracted/legit.txt'
    assert os.path.exists(legit_path), f"File {legit_path} is missing. It should have been extracted."

    with open(legit_path, 'rb') as f:
        content = f.read()

    expected_content = "Café".encode('utf-8')
    assert content == expected_content, f"Content of {legit_path} is incorrect. Expected UTF-8 'Café', got {content}."

def test_zip_slip_prevented():
    evil_path = '/home/user/evil.txt'
    assert not os.path.exists(evil_path), f"File {evil_path} exists! Zip slip vulnerability was not prevented."

def test_skipped_log():
    log_path = '/home/user/skipped.log'
    assert os.path.exists(log_path), f"Log file {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert '../evil.txt' in lines, f"Expected '../evil.txt' in {log_path}, but got {lines}."
    assert len(lines) == 1, f"Expected exactly 1 skipped file in {log_path}, but got {len(lines)}."

def test_incremental_extraction_old_file_not_overwritten():
    old_path = '/home/user/extracted/subdir/old.txt'
    assert os.path.exists(old_path), f"File {old_path} is missing."

    with open(old_path, 'r') as f:
        content = f.read()

    assert content == "Original Old", f"File {old_path} was overwritten incorrectly. Expected 'Original Old', got '{content}'."

def test_incremental_extraction_new_file_overwritten():
    new_path = '/home/user/extracted/subdir/new.txt'
    assert os.path.exists(new_path), f"File {new_path} is missing."

    with open(new_path, 'r') as f:
        content = f.read()

    assert content == "Archive New", f"File {new_path} was not overwritten correctly. Expected 'Archive New', got '{content}'."

def test_lock_file_exists():
    lock_path = '/home/user/extracted/.extract.lock'
    assert os.path.exists(lock_path), f"Lock file {lock_path} is missing."

def test_script_exists():
    script_path = '/home/user/safe_extract.py'
    assert os.path.exists(script_path), f"Script {script_path} is missing."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_behavior.py
import collections
import fcntl
import io
import os
import secrets
import subprocess
import tarfile
import tempfile
import time

SCRIPT = '/home/user/safe_extract.py'
LOG = '/home/user/skipped.log'

assert os.path.isfile(SCRIPT), f'{SCRIPT} must be a regular file'
with open(SCRIPT, 'rb') as f:
    compile(f.read(), SCRIPT, 'exec')

root = tempfile.mkdtemp(prefix='safe-extract-verifier-')
target = os.path.join(root, 'target')
os.makedirs(target)
token = secrets.token_hex(8)
archive = os.path.join(root, 'challenge.tar')

newer_name = f'newer-{token}.txt'
equal_name = f'equal-{token}.txt'
older_name = f'nested/older-{token}.txt'
latin_name = f'nested/latin-{token}.txt'
binary_name = f'nested/raw-{token}.bin'
traversal_name = f'../escape-{token}.txt'
absolute_escape = os.path.join(root, f'absolute-escape-{token}.txt')
symlink_name = f'linkdir/symlink-escape-{token}.txt'

newer_path = os.path.join(target, newer_name)
equal_path = os.path.join(target, equal_name)
older_path = os.path.join(target, older_name)
os.makedirs(os.path.dirname(older_path), exist_ok=True)

with open(newer_path, 'wb') as f:
    f.write(b'KEEP NEWER')
os.utime(newer_path, (3000, 3000))
with open(equal_path, 'wb') as f:
    f.write(b'KEEP EQUAL')
os.utime(equal_path, (2000, 2000))
with open(older_path, 'wb') as f:
    f.write(b'REPLACE OLD')
os.utime(older_path, (1000, 1000))

outside_dir = os.path.join(root, 'outside-dir')
os.makedirs(outside_dir)
os.symlink(outside_dir, os.path.join(target, 'linkdir'))

latin_text = f'Café-{secrets.token_hex(5)}'
replacement_text = f'Crème-{secrets.token_hex(5)}'
binary_data = os.urandom(41)

def add_file(tf, name, data, mtime=2000):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = mtime
    info.mode = 0o644
    tf.addfile(info, io.BytesIO(data))

with tarfile.open(archive, 'w') as tf:
    add_file(tf, newer_name, b'ARCHIVE NEWER')
    add_file(tf, equal_name, b'ARCHIVE EQUAL')
    add_file(tf, older_name, replacement_text.encode('iso-8859-1'))
    add_file(tf, latin_name, latin_text.encode('iso-8859-1'))
    add_file(tf, binary_name, binary_data)
    add_file(tf, traversal_name, b'TRAVERSAL')
    add_file(tf, absolute_escape, b'ABSOLUTE')
    add_file(tf, symlink_name, b'SYMLINK ESCAPE')

try:
    os.unlink(LOG)
except FileNotFoundError:
    pass

cp = subprocess.run(
    ['python3', SCRIPT, archive, target],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=10,
)
assert cp.returncode == 0, f'script failed on generated archive: stdout={cp.stdout!r}, stderr={cp.stderr!r}'
assert os.path.isfile(os.path.join(target, '.extract.lock')), 'lock file was not created'

with open(newer_path, 'rb') as f:
    assert f.read() == b'KEEP NEWER', 'newer existing file was overwritten'
with open(equal_path, 'rb') as f:
    assert f.read() == b'KEEP EQUAL', 'equal-mtime existing file was overwritten'
with open(older_path, 'rb') as f:
    assert f.read() == replacement_text.encode('utf-8'), 'older text file was not replaced and converted'
with open(os.path.join(target, latin_name), 'rb') as f:
    assert f.read() == latin_text.encode('utf-8'), 'new ISO-8859-1 text was not converted to UTF-8'
with open(os.path.join(target, binary_name), 'rb') as f:
    assert f.read() == binary_data, 'non-text file content changed'

assert not os.path.exists(os.path.join(root, f'escape-{token}.txt')), 'parent traversal escaped target'
assert not os.path.exists(absolute_escape), 'absolute archive path escaped target'
assert not os.path.exists(os.path.join(outside_dir, f'symlink-escape-{token}.txt')), 'path escaped through a symlink'

assert os.path.isfile(LOG), 'skipped.log was not created'
with open(LOG, encoding='utf-8') as f:
    logged = [line.rstrip('\n') for line in f if line.rstrip('\n')]
expected_skips = [traversal_name, absolute_escape, symlink_name]
assert collections.Counter(logged) == collections.Counter(expected_skips), (
    f'expected exact skipped member names {expected_skips!r}, got {logged!r}'
)

# Verify that extraction interoperates with a real advisory flock and does not
# begin extracting while another process owns the exclusive lock.
lock_target = os.path.join(root, 'locked-target')
os.makedirs(lock_target)
lock_archive = os.path.join(root, 'locked.tar')
lock_member = f'payload-{secrets.token_hex(6)}.bin'
lock_payload = os.urandom(29)
with tarfile.open(lock_archive, 'w') as tf:
    add_file(tf, lock_member, lock_payload, mtime=4000)

lock_path = os.path.join(lock_target, '.extract.lock')
lock_handle = open(lock_path, 'a+b')
fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
proc = subprocess.Popen(
    ['python3', SCRIPT, lock_archive, lock_target],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
time.sleep(0.75)
was_blocked = proc.poll() is None
extracted_while_locked = os.path.exists(os.path.join(lock_target, lock_member))
fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
lock_handle.close()
try:
    stdout, stderr = proc.communicate(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()
    stdout, stderr = proc.communicate()
    raise AssertionError('script did not finish after the lock was released')

assert was_blocked, f'script did not wait for the externally held flock: stdout={stdout!r}, stderr={stderr!r}'
assert not extracted_while_locked, 'script began extraction before acquiring the lock'
assert proc.returncode == 0, f'locked invocation failed: stdout={stdout!r}, stderr={stderr!r}'
with open(os.path.join(lock_target, lock_member), 'rb') as f:
    assert f.read() == lock_payload, 'locked invocation did not extract correctly after release'
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
python3 /tmp/test_behavior.py 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
