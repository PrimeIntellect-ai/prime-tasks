#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_archiver.py
import os
import shutil
import subprocess
import tarfile
import time
import secrets

HOME = '/home/user'
ARCHIVER = os.path.join(HOME, 'archiver.py')
ARCHIVE_DIR = os.path.join(HOME, 'dataset_archive')
LIVE_LOG = os.path.join(HOME, 'live_sensor.log')
MERGED = os.path.join(HOME, 'final_merged.tar')
STATUS = os.path.join(HOME, 'status.txt')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def validate_outputs(expected_lines):
    require(os.path.isdir(ARCHIVE_DIR), f'{ARCHIVE_DIR} does not exist')
    require(os.path.isfile(STATUS), f'{STATUS} does not exist')
    with open(STATUS, 'rb') as f:
        status = f.read()
    require(status.strip() == b'SUCCESS', f'Expected status.txt to contain SUCCESS, got {status!r}')
    require(status == b'SUCCESS', 'status.txt must contain exactly SUCCESS')

    archive_bytes = {}
    for i in range(1, 6):
        archive_path = os.path.join(ARCHIVE_DIR, f'chunk_{i}.tar.gz')
        require(os.path.isfile(archive_path), f'{archive_path} does not exist')

        with open(archive_path, 'rb') as f:
            archive_bytes[f'chunk_{i}.tar.gz'] = f.read()

        with tarfile.open(archive_path, 'r:gz') as tar:
            members = tar.getmembers()
            require(len(members) == 1, f'{archive_path} must contain exactly one member')
            member = members[0]
            require(member.name == f'chunk_{i}.txt',
                    f'Unexpected member {member.name!r} in {archive_path}')
            require(member.isfile(), f'{member.name} is not a regular file')
            extracted = tar.extractfile(member)
            require(extracted is not None, f'Could not extract {member.name}')
            content = extracted.read()

        wanted = b''.join(expected_lines[(i - 1) * 10000:i * 10000])
        require(content == wanted, f'Contents of chunk_{i}.txt do not match the input stream')
        require(len(content.splitlines()) == 10000,
                f'chunk_{i}.txt does not contain exactly 10000 lines')

    latest = os.path.join(ARCHIVE_DIR, 'latest.tar.gz')
    require(os.path.islink(latest), f'{latest} is not a symlink')
    target = os.readlink(latest)
    require(os.path.basename(target) == 'chunk_5.tar.gz',
            f'latest.tar.gz points to {target!r}, not chunk_5.tar.gz')
    require(os.path.exists(latest), 'latest.tar.gz is a dangling symlink')
    require(os.path.samefile(latest, os.path.join(ARCHIVE_DIR, 'chunk_5.tar.gz')),
            'latest.tar.gz does not resolve to chunk_5.tar.gz')

    require(os.path.isfile(MERGED), f'{MERGED} does not exist')
    with tarfile.open(MERGED, 'r:') as tar:
        members = tar.getmembers()
        expected_names = [f'chunk_{i}.tar.gz' for i in range(1, 6)]
        require(len(members) == 5, 'final_merged.tar must contain exactly five members')
        require(sorted(m.name for m in members) == sorted(expected_names),
                'final_merged.tar has missing, extra, duplicated, or incorrectly named members')
        for member in members:
            require(member.isfile(), f'{member.name} in final_merged.tar is not a regular file')
            extracted = tar.extractfile(member)
            require(extracted is not None, f'Could not extract {member.name} from final_merged.tar')
            require(extracted.read() == archive_bytes[member.name],
                    f'{member.name} in final_merged.tar differs from the original archive')


def original_lines():
    return [
        f'2023-10-25T10:00:00Z,SENSOR_{i % 10},{i * 1.5}\n'.encode()
        for i in range(1, 50001)
    ]


def validate_initial_state():
    expected = original_lines()
    require(os.path.isfile(LIVE_LOG), f'{LIVE_LOG} does not exist')
    with open(LIVE_LOG, 'rb') as f:
        source = f.readlines()
    require(source == expected, 'live_sensor.log was modified or does not contain the writer output')
    validate_outputs(expected)


def exercise_archiver():
    require(os.path.isfile(ARCHIVER), f'{ARCHIVER} does not exist')
    require(not os.path.islink(ARCHIVER), f'{ARCHIVER} must be a regular file, not a symlink')

    subprocess.run(
        ['python3', '-m', 'py_compile', ARCHIVER],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=10,
    )

    shutil.rmtree(ARCHIVE_DIR, ignore_errors=True)
    for path in (LIVE_LOG, MERGED, STATUS):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Start the submitted program against an initially empty live file, then append
    # an unpredictable 50,000-line stream while it is running.
    with open(LIVE_LOG, 'wb'):
        pass

    token = secrets.token_hex(16)
    expected = [
        f'2026-09-12T12:34:56Z,VERIFY_{token}_{i},{(i * 7919) % 1000003}\n'.encode()
        for i in range(1, 50001)
    ]

    proc = subprocess.Popen(
        ['python3', ARCHIVER],
        cwd=HOME,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        time.sleep(0.2)
        require(proc.poll() is None, 'archiver.py exited before the writer began')

        with open(LIVE_LOG, 'ab', buffering=0) as writer:
            for offset in range(0, 50000, 100):
                writer.writelines(expected[offset:offset + 100])
                writer.flush()
                require(proc.poll() is None,
                        f'archiver.py exited before all input was written (after {offset + 100} lines)')
                time.sleep(0.003)

        try:
            return_code = proc.wait(timeout=35)
        except subprocess.TimeoutExpired:
            raise AssertionError('archiver.py did not finish after receiving 50,000 lines')
        require(return_code == 0, f'archiver.py exited with status {return_code}')
        validate_outputs(expected)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


validate_initial_state()
exercise_archiver()
PY

if python3 /tmp/verify_archiver.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
