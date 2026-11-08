#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import posixpath
import pwd
import secrets
import shutil
import struct
import subprocess
import tarfile
import zipfile
from pathlib import Path, PurePosixPath

import pytest

INCOMING = Path('/home/user/incoming_artifacts')
PROJECT = Path('/home/user/curator')
RELEASE = Path('/home/user/curated_release.zip')
CURATED = Path('/home/user/curated_artifacts')


def create_bx_bytes(magic=b'BX01', version=2, payload=b'', length_override=None):
    length = len(payload) if length_override is None else length_override
    return magic + struct.pack('<H', version) + struct.pack('<I', length) + payload


def valid_bx(data):
    if len(data) < 10 or data[:4] != b'BX01':
        return False
    version = struct.unpack('<H', data[4:6])[0]
    payload_length = struct.unpack('<I', data[6:10])[0]
    return version >= 2 and len(data) == 10 + payload_length


def get_expected_valid_artifacts():
    expected = [
        ('valid1.bx', b'hello world'),
        ('valid2.bx', b'rust programming is fun!'),
        ('zip_valid.bx', b'inside zip file'),
        ('tar_valid.bx', b'inside tar gz'),
    ]
    artifacts = {}
    for basename, payload in expected:
        data = create_bx_bytes(payload=payload)
        artifacts[f'{hashlib.sha256(data).hexdigest()}.bx'] = (basename, data)
    return artifacts


def add_expected(result, basename, data):
    if valid_bx(data):
        name = hashlib.sha256(data).hexdigest() + '.bx'
        entry = result.setdefault(name, {'basenames': set(), 'bytes': data})
        assert entry['bytes'] == data
        entry['basenames'].add(basename)


def compute_expected_from_incoming():
    result = {}
    for path in INCOMING.rglob('*'):
        if not path.is_file():
            continue
        lower_name = path.name.lower()
        if path.suffix == '.bx':
            add_expected(result, path.name, path.read_bytes())
        elif lower_name.endswith('.zip'):
            try:
                with zipfile.ZipFile(path, 'r') as archive:
                    for info in archive.infolist():
                        if not info.is_dir() and info.filename.endswith('.bx'):
                            add_expected(result, posixpath.basename(info.filename), archive.read(info))
            except (OSError, zipfile.BadZipFile, RuntimeError):
                pass
        elif lower_name.endswith('.tar.gz'):
            try:
                with tarfile.open(path, 'r:gz') as archive:
                    for member in archive.getmembers():
                        if member.isfile() and member.name.endswith('.bx'):
                            extracted = archive.extractfile(member)
                            if extracted is not None:
                                add_expected(result, posixpath.basename(member.name), extracted.read())
            except (OSError, tarfile.TarError):
                pass
    return result


def install_dynamic_fixtures():
    token = secrets.token_hex(8)
    root = INCOMING / ('verifier_' + token)
    (root / 'deep' / 'one').mkdir(parents=True)
    (root / 'deep' / 'two').mkdir(parents=True)

    (root / 'deep' / 'one' / f'standalone_{token}.bx').write_bytes(
        create_bx_bytes(version=513, payload=os.urandom(37))
    )
    (root / f'empty_{token}.bx').write_bytes(create_bx_bytes(version=2, payload=b''))

    shared_basename = f'same_name_{token}.bx'
    (root / 'deep' / 'one' / shared_basename).write_bytes(
        create_bx_bytes(payload=b'A' + os.urandom(29))
    )
    (root / 'deep' / 'two' / shared_basename).write_bytes(
        create_bx_bytes(payload=b'B' + os.urandom(31))
    )

    (root / f'bad_magic_{token}.bx').write_bytes(create_bx_bytes(magic=b'NOPE', payload=os.urandom(9)))
    (root / f'bad_version_{token}.bx').write_bytes(create_bx_bytes(version=1, payload=os.urandom(9)))
    (root / f'truncated_{token}.bx').write_bytes(create_bx_bytes(payload=os.urandom(5), length_override=99))
    (root / f'trailing_{token}.bx').write_bytes(create_bx_bytes(payload=os.urandom(12), length_override=4))

    inner_buffer = io.BytesIO()
    with zipfile.ZipFile(inner_buffer, 'w') as inner:
        inner.writestr(f'ignored_nested_{token}.bx', create_bx_bytes(payload=os.urandom(17)))

    with zipfile.ZipFile(root / f'dynamic_{token}.zip', 'w') as archive:
        archive.writestr(f'nested/zip_good_{token}.bx', create_bx_bytes(version=7, payload=os.urandom(43)))
        archive.writestr(f'nested/zip_bad_{token}.bx', create_bx_bytes(version=0, payload=os.urandom(13)))
        archive.writestr('nested_archive.zip', inner_buffer.getvalue())

    tar_member_data = create_bx_bytes(version=3, payload=os.urandom(47))
    with tarfile.open(root / f'dynamic_{token}.tar.gz', 'w:gz') as archive:
        info = tarfile.TarInfo(f'folder/tar_good_{token}.bx')
        info.size = len(tar_member_data)
        archive.addfile(info, io.BytesIO(tar_member_data))

    return root


def run_submission():
    assert PROJECT.is_dir(), 'Rust project directory /home/user/curator does not exist'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing from /home/user/curator'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'src/main.rs is missing from the Rust project'

    if CURATED.exists():
        shutil.rmtree(CURATED)
    if RELEASE.exists():
        RELEASE.unlink()

    account = pwd.getpwnam('user')
    env = os.environ.copy()
    env.update({'HOME': account.pw_dir, 'USER': 'user', 'LOGNAME': 'user'})

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        result = subprocess.run(
            ['cargo', 'run', '--release', '--quiet'],
            cwd=PROJECT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=240,
            preexec_fn=demote,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('cargo run --release timed out')

    assert result.returncode == 0, 'cargo run --release failed:\n' + result.stdout[-8000:]


@pytest.fixture(scope='session', autouse=True)
def execute_on_dynamic_inputs():
    fixture_root = install_dynamic_fixtures()
    run_submission()
    yield
    shutil.rmtree(fixture_root, ignore_errors=True)


def read_release():
    assert RELEASE.is_file(), f'Expected release archive not found at {RELEASE}'
    assert zipfile.is_zipfile(RELEASE), f'{RELEASE} is not a valid zip file'

    with zipfile.ZipFile(RELEASE, 'r') as archive:
        infos = archive.infolist()
        for info in infos:
            path = PurePosixPath(info.filename)
            assert not path.is_absolute() and '..' not in path.parts, 'Release zip contains an unsafe path'

        manifests = [i for i in infos if not i.is_dir() and PurePosixPath(i.filename).name == 'manifest.json']
        assert len(manifests) == 1, 'Release zip must contain exactly one manifest.json'
        manifest_info = manifests[0]
        try:
            manifest = json.loads(archive.read(manifest_info).decode('utf-8'))
        except (UnicodeDecodeError, json.JSONDecodeError):
            pytest.fail('manifest.json is not valid UTF-8 JSON')

        assert isinstance(manifest, dict), 'manifest.json must contain a JSON object'
        manifest_dir = posixpath.dirname(manifest_info.filename)
        contents = {}
        names = {i.filename for i in infos if not i.is_dir()}
        for hashed_name in manifest:
            member_name = posixpath.join(manifest_dir, hashed_name) if manifest_dir else hashed_name
            assert member_name in names, f'Expected file {hashed_name} not found in the same directory as manifest.json'
            contents[hashed_name] = archive.read(member_name)
        return manifest, contents


def test_curated_release_zip_exists():
    assert RELEASE.is_file(), f'Expected release archive not found at {RELEASE}'
    assert zipfile.is_zipfile(RELEASE), f'{RELEASE} is not a valid zip file'


def test_curated_release_contents():
    expected = compute_expected_from_incoming()
    manifest, contents = read_release()

    assert set(manifest) == set(expected), (
        f'Manifest entries differ from valid artifacts. Missing: {set(expected) - set(manifest)}; '
        f'Extra: {set(manifest) - set(expected)}'
    )

    for hashed_name, details in expected.items():
        assert manifest[hashed_name] in details['basenames'], (
            f'Manifest mapping for {hashed_name} is not an original basename'
        )
        assert contents[hashed_name] == details['bytes'], f'Contents of {hashed_name} are incorrect'
        assert hashlib.sha256(contents[hashed_name]).hexdigest() + '.bx' == hashed_name

    # Preserve the original fixture-specific assertions as well.
    fixed = get_expected_valid_artifacts()
    for hashed_name, (basename, expected_bytes) in fixed.items():
        assert hashed_name in manifest, f'Manifest is missing expected entry {hashed_name}'
        assert manifest[hashed_name] == basename, (
            f'Manifest mapping for {hashed_name} should be {basename}, got {manifest[hashed_name]}'
        )
        assert contents[hashed_name] == expected_bytes, (
            f'Contents of {hashed_name} do not match the expected .bx format and payload'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
