#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_verify_storage.py
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import time
import uuid
import zipfile

SCRIPT = Path('/home/user/verify_storage.py')
ROOT = Path('/home/user/data_mount')
CORRUPT_REPORT = Path('/home/user/corrupt_backups.txt')
VALID_REPORT = Path('/home/user/valid_backups.txt')

BASE_CORRUPT = [
    '/home/user/data_mount/projects/corrupt_old.tar.gz',
    '/home/user/data_mount/users/bob/corrupt_old.zip',
]
BASE_VALID = [
    '/home/user/data_mount/projects/valid_old.zip',
    '/home/user/data_mount/users/alice/valid_old.tar.gz',
]


def run_submission():
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'verify_storage.py exited with {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )


def original_style_lines(path):
    with open(path, 'r') as handle:
        return [line.strip() for line in handle if line.strip()]


def strict_lines(path):
    raw = path.read_text()
    lines = raw.splitlines()
    assert all(line and line == line.strip() for line in lines), (
        f'{path} must contain exactly one unpadded path per line'
    )
    assert all(os.path.isabs(line) for line in lines), f'{path} contains a non-absolute path'
    assert lines == sorted(lines), f'{path} is not sorted alphabetically'
    assert len(lines) == len(set(lines)), f'{path} contains duplicate paths'
    return lines


def set_age(path, days):
    stamp = time.time() - days * 24 * 60 * 60
    os.utime(path, (stamp, stamp))


def make_zip(path, size=80000):
    payload = os.urandom(size)
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_STORED) as archive:
        archive.writestr('payload.bin', payload)


def make_crc_bad_zip(path):
    make_zip(path, 80000)
    with zipfile.ZipFile(path, 'r') as archive:
        info = archive.getinfo('payload.bin')
        data_offset = info.header_offset + 30 + len(info.filename.encode('utf-8')) + len(info.extra)
    with open(path, 'r+b') as handle:
        handle.seek(data_offset + 100)
        original = handle.read(1)
        handle.seek(data_offset + 100)
        handle.write(bytes([original[0] ^ 0xFF]))


def make_tar(path, size=90000):
    payload = os.urandom(size)
    info = tarfile.TarInfo('payload.bin')
    info.size = len(payload)
    with tarfile.open(path, 'w:gz') as archive:
        archive.addfile(info, io.BytesIO(payload))


def archive_is_valid(path):
    try:
        if path.endswith('.zip'):
            with zipfile.ZipFile(path, 'r') as archive:
                return archive.testzip() is None
        if path.endswith('.tar.gz'):
            with tarfile.open(path, 'r:gz') as archive:
                for member in archive:
                    if member.isfile():
                        extracted = archive.extractfile(member)
                        if extracted is None:
                            return False
                        while extracted.read(65536):
                            pass
                return True
    except (OSError, EOFError, tarfile.TarError, zipfile.BadZipFile, RuntimeError):
        return False
    return False


def derive_expected():
    cutoff = time.time() - 30 * 24 * 60 * 60
    seen = set()
    valid = []
    corrupt = []

    for directory, _, filenames in os.walk(ROOT):
        for filename in filenames:
            if not (filename.endswith('.zip') or filename.endswith('.tar.gz')):
                continue
            discovered = os.path.join(directory, filename)
            resolved = os.path.realpath(discovered)
            try:
                stat_result = os.stat(resolved)
            except OSError:
                continue
            if not os.path.isfile(resolved):
                continue

            physical_id = (stat_result.st_dev, stat_result.st_ino)
            if physical_id in seen:
                continue
            seen.add(physical_id)

            if stat_result.st_size <= 51200 or stat_result.st_mtime >= cutoff:
                continue
            if archive_is_valid(resolved):
                valid.append(resolved)
            else:
                corrupt.append(resolved)

    return sorted(corrupt), sorted(valid)


# Preserve the original existence and fixed-fixture assertions, but execute the artifact first.
assert os.path.isfile(SCRIPT), 'The script /home/user/verify_storage.py is missing.'
run_submission()
assert CORRUPT_REPORT.exists(), 'The file /home/user/corrupt_backups.txt is missing.'
assert VALID_REPORT.exists(), 'The file /home/user/valid_backups.txt is missing.'
assert original_style_lines(CORRUPT_REPORT) == BASE_CORRUPT, (
    f'Expected corrupt_backups.txt to contain {BASE_CORRUPT}, '
    f'but got {original_style_lines(CORRUPT_REPORT)}.'
)
assert original_style_lines(VALID_REPORT) == BASE_VALID, (
    f'Expected valid_backups.txt to contain {BASE_VALID}, '
    f'but got {original_style_lines(VALID_REPORT)}.'
)

# Add unpredictable fixtures after the agent has finished, covering traversal,
# filtering, integrity checks, canonical symlink handling, and deduplication.
token = uuid.uuid4().hex
fixture_dir = ROOT / ('.audit_' + token) / 'deep' / 'nested'
fixture_dir.mkdir(parents=True)
external_dir = Path('/home/user') / ('.audit_targets_' + token)
external_dir.mkdir()

valid_zip = fixture_dir / (uuid.uuid4().hex + '.zip')
valid_tar = fixture_dir / (uuid.uuid4().hex + '.tar.gz')
bad_zip = fixture_dir / (uuid.uuid4().hex + '.zip')
bad_tar = fixture_dir / (uuid.uuid4().hex + '.tar.gz')
recent_zip = fixture_dir / (uuid.uuid4().hex + '.zip')
small_zip = fixture_dir / (uuid.uuid4().hex + '.zip')
threshold_zip = fixture_dir / (uuid.uuid4().hex + '.zip')
external_zip = external_dir / (uuid.uuid4().hex + '.zip')

make_zip(valid_zip)
make_tar(valid_tar)
make_crc_bad_zip(bad_zip)
make_tar(bad_tar)
with open(bad_tar, 'r+b') as handle:
    handle.truncate(60000)
make_zip(recent_zip)
make_zip(small_zip, 10000)
threshold_zip.write_bytes(os.urandom(51200))
make_zip(external_zip, 75000)

for path in (valid_zip, valid_tar, bad_zip, bad_tar, small_zip, threshold_zip, external_zip):
    set_age(path, 45)
set_age(recent_zip, 1)

# The target is outside the traversed tree and old, while both symlinks are new.
# A correct implementation must inspect and report the canonical target only once.
os.symlink(external_zip, fixture_dir / (uuid.uuid4().hex + '.zip'))
os.symlink(external_zip, fixture_dir / (uuid.uuid4().hex + '.zip'))
os.symlink(valid_tar, fixture_dir / (uuid.uuid4().hex + '.tar.gz'))

before = {
    str(path): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in (valid_zip, valid_tar, bad_zip, bad_tar, recent_zip, small_zip,
                 threshold_zip, external_zip)
}
expected_corrupt, expected_valid = derive_expected()
run_submission()

assert CORRUPT_REPORT.is_file(), 'The corrupt report was not generated.'
assert VALID_REPORT.is_file(), 'The valid report was not generated.'
assert strict_lines(CORRUPT_REPORT) == expected_corrupt, (
    f'Expected corrupt report {expected_corrupt}, got {strict_lines(CORRUPT_REPORT)}'
)
assert strict_lines(VALID_REPORT) == expected_valid, (
    f'Expected valid report {expected_valid}, got {strict_lines(VALID_REPORT)}'
)

for name, digest in before.items():
    path = Path(name)
    assert path.is_file(), f'The submission deleted {name}'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f'The submission modified {name}'
PY_EOF

if python3 /tmp/test_verify_storage.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
