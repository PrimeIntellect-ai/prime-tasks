#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import os
import secrets
import stat
import subprocess
import tarfile

ARTIFACTS = '/home/user/artifacts'
CURATOR_C = '/home/user/curator.c'
CURATOR = '/home/user/curator'
LOG = '/home/user/curation.log'
SAFE = '/home/user/safe_artifacts.txt'
ARCHIVE = '/home/user/safe_archive.tar.gz'


def test_00_curator_exists_compiles_and_runs_with_dynamic_inputs():
    assert os.path.isfile(CURATOR_C), f'{CURATOR_C} does not exist.'
    st = os.stat(CURATOR)
    assert stat.S_ISREG(st.st_mode), f'{CURATOR} is not a regular file.'
    assert os.access(CURATOR, os.X_OK), f'{CURATOR} is not executable.'
    with open(CURATOR, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{CURATOR} is not an ELF executable.'

    with open(CURATOR_C, 'r', errors='replace') as f:
        source = f.read()
    assert 'fcntl' in source, 'curator.c does not use fcntl().'
    assert 'F_SETLK' in source, 'curator.c does not request a non-blocking record lock.'
    assert 'F_WRLCK' in source, 'curator.c does not request an exclusive record lock.'

    # Ensure the submitted source really is compilable as a C program.
    subprocess.run(
        ['gcc', '-std=c11', '-D_XOPEN_SOURCE=700', '-Wall', '-Wextra',
         CURATOR_C, '-o', '/tmp/curator_from_source'],
        check=True, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    token = secrets.token_hex(12)
    deep_dir = os.path.join(ARTIFACTS, 'verify_' + token, 'deep', 'nested')
    os.makedirs(deep_dir)
    safe_file = os.path.join(deep_dir, 'safe_' + token + '.dat')
    locked_file = os.path.join(deep_dir, 'locked_' + token + '.dat')
    valid_link = os.path.join(ARTIFACTS, 'verify_link_' + token + '.sym')
    loop1 = os.path.join(deep_dir, 'loop1_' + token + '.sym')
    loop2 = os.path.join(deep_dir, 'loop2_' + token + '.sym')

    with open(safe_file, 'wb') as f:
        f.write(('dynamic safe ' + token).encode())
    with open(locked_file, 'wb') as f:
        f.write(('dynamic locked ' + token).encode())
    os.symlink(safe_file, valid_link)
    os.symlink(loop2, loop1)
    os.symlink(loop1, loop2)

    # lockf uses POSIX fcntl record locks, matching the lock required by the task.
    locker_code = r'''
import fcntl, sys, time
files = [open(p, 'r+') for p in sys.argv[1:]]
for f in files:
    fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
print('READY', flush=True)
time.sleep(60)
'''
    locker = subprocess.Popen(
        ['python3', '-c', locker_code,
         '/home/user/artifacts/locked.dat', locked_file],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    def stop_locker():
        if locker.poll() is None:
            locker.terminate()
            try:
                locker.wait(timeout=3)
            except subprocess.TimeoutExpired:
                locker.kill()
                locker.wait(timeout=3)
    atexit.register(stop_locker)

    assert locker.stdout.readline().strip() == 'READY', 'POSIX record-lock helper failed to start.'
    assert locker.poll() is None, 'POSIX record-lock helper exited unexpectedly.'

    for path in (LOG, SAFE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    try:
        subprocess.run([CURATOR], check=True, timeout=20,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    finally:
        stop_locker()

    assert os.path.exists(LOG), f'{CURATOR} did not create {LOG}.'
    assert os.path.exists(SAFE), f'{CURATOR} did not create {SAFE}.'
    with open(LOG) as f:
        log_lines = {line.rstrip('\n') for line in f}
    with open(SAFE) as f:
        safe_lines = {line.rstrip('\n') for line in f}

    assert 'LOOP_DETECTED: ' + loop1 in log_lines
    assert 'LOOP_DETECTED: ' + loop2 in log_lines
    assert 'LOCKED: ' + locked_file in log_lines
    assert 'LOCKED: /home/user/artifacts/locked.dat' in log_lines
    assert os.path.realpath(safe_file) in safe_lines
    assert locked_file not in safe_lines


def test_curation_log():
    log_path = '/home/user/curation.log'
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, 'r') as f:
        log_content = f.read()

    expected_loops = [
        'LOOP_DETECTED: /home/user/artifacts/loop1.sym',
        'LOOP_DETECTED: /home/user/artifacts/loop2.sym'
    ]
    for loop in expected_loops:
        assert loop in log_content, f"Missing expected loop detection in log: {loop}"

    expected_locked = 'LOCKED: /home/user/artifacts/locked.dat'
    assert expected_locked in log_content, f"Missing expected locked file in log: {expected_locked}"


def test_safe_artifacts_txt():
    safe_path = '/home/user/safe_artifacts.txt'
    assert os.path.exists(safe_path), f"{safe_path} does not exist."

    with open(safe_path, 'r') as f:
        safe_content = f.read()

    expected_safe_files = [
        '/home/user/artifacts/bin1.dat',
        '/home/user/artifacts/module_a/bin2.dat',
        '/home/user/artifacts/module_b/bin3.dat'
    ]

    for safe_file in expected_safe_files:
        assert safe_file in safe_content, f"Expected safe file missing from {safe_path}: {safe_file}"

    assert 'locked.dat' not in safe_content, f"Locked file should not be in {safe_path}"


def test_safe_archive():
    archive_path = '/home/user/safe_archive.tar.gz'
    assert os.path.exists(archive_path), f"{archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."

    expected_paths = [
        '/home/user/artifacts/bin1.dat',
        '/home/user/artifacts/module_a/bin2.dat',
        '/home/user/artifacts/module_b/bin3.dat'
    ]

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()
        basenames = [os.path.basename(name) for name in names]
        expected_basenames = ['bin1.dat', 'bin2.dat', 'bin3.dat']
        for expected in expected_basenames:
            assert expected in basenames, f"Expected file {expected} missing from archive {archive_path}"

        normalized = {m.name.lstrip('./').lstrip('/'): m for m in tar.getmembers()}
        for path in expected_paths:
            key = path.lstrip('/')
            assert key in normalized, f'Expected path {path} missing from archive.'
            member = normalized[key]
            assert member.isfile(), f'Archive member {path} is not a regular file.'
            archived = tar.extractfile(member)
            assert archived is not None
            with open(path, 'rb') as original:
                assert archived.read() == original.read(), f'Archive content for {path} is incorrect.'

        assert not any(os.path.basename(n) == 'locked.dat' for n in names), \
            'Locked file must not be present in the archive.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
