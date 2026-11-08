#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import stat
import subprocess
import tarfile
import time
import zipfile
from pathlib import Path

import pytest
import redis
from minio import Minio

SCRIPT_PATH = Path('/home/user/pipeline/archive_filter.py')
BUCKET = 'ingest-bucket'
CHUNK_SIZE = 1024 * 1024


def wait_for_services():
    last = None
    for _ in range(30):
        try:
            r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True,
                            socket_connect_timeout=1, socket_timeout=1)
            r.ping()
            m = Minio('127.0.0.1:9000', access_key='minioadmin',
                      secret_key='minioadmin', secure=False)
            m.list_buckets()
            return r, m
        except Exception as exc:
            last = exc
            time.sleep(1)
    pytest.fail(f'Redis and MinIO must be running and reachable: {last}')


@pytest.fixture(scope='session')
def services():
    return wait_for_services()


def clear_storage(r, m):
    r.flushdb()
    if not m.bucket_exists(BUCKET):
        m.make_bucket(BUCKET)
    for obj in list(m.list_objects(BUCKET, recursive=True)):
        m.remove_object(BUCKET, obj.object_name)


def run_script(path):
    try:
        return subprocess.run(
            ['python3', str(SCRIPT_PATH), 'process', str(path)],
            capture_output=True, text=True, timeout=45
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'archive_filter.py timed out on {path.name}')


def make_safe_zip(path, files):
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in files.items():
            zf.writestr(name, data)


def make_safe_tar(path, files):
    with tarfile.open(path, 'w:gz') as tf:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))


def recursive_strings(value):
    result = set()
    if isinstance(value, str):
        result.add(value)
    elif isinstance(value, dict):
        for key, item in value.items():
            if isinstance(key, str):
                result.add(key)
            result.update(recursive_strings(item))
    elif isinstance(value, list):
        for item in value:
            result.update(recursive_strings(item))
    return result


def expected_chunks(files):
    chunks = []
    for path, data in files.items():
        for offset in range(0, len(data), CHUNK_SIZE):
            chunk = data[offset:offset + CHUNK_SIZE]
            chunks.append((path, chunk, hashlib.sha256(chunk).hexdigest()))
    return chunks


def assert_accepted_and_persisted(archive, files, r, m):
    clear_storage(r, m)
    result = run_script(archive)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ACCEPTED' in result.stdout

    key = f'manifest:{archive.name}'
    raw = r.get(key)
    assert raw is not None, f'missing Redis key {key}'
    try:
        manifest = json.loads(raw)
    except Exception as exc:
        pytest.fail(f'Redis manifest is not valid JSON: {exc}')

    strings = recursive_strings(manifest)
    for path in files:
        assert path in strings, f'manifest does not contain original path {path}'

    objects = list(m.list_objects(BUCKET, recursive=True))
    assert objects, 'no chunks were uploaded to ingest-bucket'
    object_data = {}
    for obj in objects:
        response = m.get_object(BUCKET, obj.object_name)
        try:
            object_data[obj.object_name] = response.read()
        finally:
            response.close()
            response.release_conn()

    expected = expected_chunks(files)
    assert len(object_data) == len(expected), (
        f'expected exactly {len(expected)} uploaded chunks, got {len(object_data)}'
    )

    unmatched = dict(object_data)
    for original_path, data, digest in expected:
        matches = [name for name, uploaded in unmatched.items() if uploaded == data]
        assert len(matches) == 1, f'missing or duplicate uploaded chunk for {original_path}'
        object_name = matches[0]
        assert object_name in strings, f'manifest does not name uploaded chunk {object_name}'
        assert digest in strings, f'manifest lacks SHA256 {digest} for {object_name}'
        del unmatched[object_name]
    assert not unmatched


def test_script_exists_and_is_a_file():
    assert SCRIPT_PATH.exists(), f'{SCRIPT_PATH} does not exist'
    assert SCRIPT_PATH.is_file(), f'{SCRIPT_PATH} is not a regular file'
    assert not SCRIPT_PATH.is_symlink(), f'{SCRIPT_PATH} must not be a symlink'


@pytest.mark.parametrize('kind', ['zip', 'tar'])
def test_clean_archives_are_accepted_chunked_and_stored(tmp_path, services, kind):
    r, m = services
    # Incompressible, randomized data prevents a hard-coded manifest or upload.
    files = {
        'nested/large.bin': os.urandom(CHUNK_SIZE + 7319),
        'small.txt': b'safe archive payload\n' + os.urandom(257),
    }
    if kind == 'zip':
        archive = tmp_path / 'clean.zip'
        make_safe_zip(archive, files)
    else:
        archive = tmp_path / 'clean.tar.gz'
        make_safe_tar(archive, files)
    assert_accepted_and_persisted(archive, files, r, m)


def build_evil_archives(tmp_path):
    archives = []

    p = tmp_path / 'zip-traversal.zip'
    with zipfile.ZipFile(p, 'w') as zf:
        zf.writestr('../escape.txt', b'escape')
    archives.append(p)

    p = tmp_path / 'zip-absolute.zip'
    with zipfile.ZipFile(p, 'w') as zf:
        zf.writestr('/etc/archive-filter-test', b'escape')
    archives.append(p)

    p = tmp_path / 'zip-symlink.zip'
    with zipfile.ZipFile(p, 'w') as zf:
        info = zipfile.ZipInfo('outside-link')
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        zf.writestr(info, '../../outside')
    archives.append(p)

    p = tmp_path / 'zip-bomb.zip'
    with zipfile.ZipFile(p, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('bomb.bin', b'0' * (6 * 1024 * 1024))
    archives.append(p)

    p = tmp_path / 'tar-traversal.tar.gz'
    with tarfile.open(p, 'w:gz') as tf:
        data = b'escape'
        info = tarfile.TarInfo('../../escape.txt')
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))
    archives.append(p)

    p = tmp_path / 'tar-absolute.tar.gz'
    with tarfile.open(p, 'w:gz') as tf:
        data = b'escape'
        info = tarfile.TarInfo('/etc/archive-filter-test')
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))
    archives.append(p)

    p = tmp_path / 'tar-symlink.tar.gz'
    with tarfile.open(p, 'w:gz') as tf:
        info = tarfile.TarInfo('outside-link')
        info.type = tarfile.SYMTYPE
        info.linkname = '../../outside'
        tf.addfile(info)
    archives.append(p)

    p = tmp_path / 'tar-hardlink.tar.gz'
    with tarfile.open(p, 'w:gz') as tf:
        info = tarfile.TarInfo('outside-hardlink')
        info.type = tarfile.LNKTYPE
        info.linkname = '../../outside'
        tf.addfile(info)
    archives.append(p)

    p = tmp_path / 'malformed.zip'
    p.write_bytes(b'not actually an archive')
    archives.append(p)
    return archives


def test_evil_corpus_rejected(tmp_path, services):
    r, m = services
    for archive in build_evil_archives(tmp_path):
        clear_storage(r, m)
        result = run_script(archive)
        assert result.returncode == 1, (
            f'{archive.name} was not rejected\nstdout={result.stdout}\nstderr={result.stderr}'
        )
        assert 'REJECTED' in result.stdout, f'{archive.name} did not print REJECTED'
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
