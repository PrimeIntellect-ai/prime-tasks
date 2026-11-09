#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import uuid
import zipfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/backup_processor')
MANIFEST = PROJECT / 'Cargo.toml'


def run_cmd(cmd, timeout=120, **kwargs):
    return subprocess.run(cmd, timeout=timeout, text=True, **kwargs)


@pytest.fixture(scope='session', autouse=True)
def build_project():
    assert MANIFEST.is_file(), f'Missing Cargo manifest: {MANIFEST}'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'Missing Rust application entry point'
    result = run_cmd(
        ['cargo', 'build', '--manifest-path', str(MANIFEST)],
        timeout=240,
        capture_output=True,
    )
    assert result.returncode == 0, result.stdout + '\n' + result.stderr


def run_verify(path):
    result = run_cmd(
        ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST), '--', 'verify', str(path)],
        timeout=90,
        capture_output=True,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def assert_verdict(path, clean):
    code, out, err = run_verify(path)
    if clean:
        assert code == 0 and 'ACCEPT' in out, (
            f'Expected ACCEPT for generated clean backup {path}; '
            f'code={code}, stdout={out!r}, stderr={err!r}'
        )
    else:
        assert code == 1 and 'REJECT' in out, (
            f'Expected REJECT for generated invalid backup {path}; '
            f'code={code}, stdout={out!r}, stderr={err!r}'
        )


def write_log(root, records):
    with open(Path(root) / 'backup.log', 'w') as f:
        for rel, checksum in records:
            f.write(f'BEGIN FILE: {rel}\nCHECKSUM: {checksum}\nEND FILE\n')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def new_case(parent):
    path = Path(parent) / uuid.uuid4().hex
    path.mkdir()
    return path


def test_original_adversarial_corpus():
    # Preserve the original verifier's corpus assertions.
    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'
    assert os.path.isdir(clean_dir), f'Clean corpus missing at {clean_dir}'
    assert os.path.isdir(evil_dir), f'Evil corpus missing at {evil_dir}'

    clean_items = [d for d in os.listdir(clean_dir) if os.path.isdir(os.path.join(clean_dir, d))]
    evil_items = [d for d in os.listdir(evil_dir) if os.path.isdir(os.path.join(evil_dir, d))]

    clean_failed = []
    for item in clean_items:
        code, out, err = run_verify(os.path.join(clean_dir, item))
        if code != 0 or 'ACCEPT' not in out:
            clean_failed.append(item)

    evil_failed = []
    for item in evil_items:
        code, out, err = run_verify(os.path.join(evil_dir, item))
        if code == 0 or 'REJECT' not in out:
            evil_failed.append(item)

    errors = []
    if clean_failed:
        errors.append(f'{len(clean_failed)} of {len(clean_items)} clean modified/rejected: {", ".join(clean_failed)}')
    if evil_failed:
        errors.append(f'{len(evil_failed)} of {len(evil_items)} evil bypassed: {", ".join(evil_failed)}')
    assert not errors, ' | '.join(errors)


def test_verify_generated_content_and_archives(tmp_path):
    # Paths are randomized and contain no clean/evil classification component.
    root = tmp_path / uuid.uuid4().hex
    root.mkdir()

    good = new_case(root)
    (good / 'docs').mkdir()
    payload = os.urandom(73)
    (good / 'docs' / 'payload.bin').write_bytes(payload)
    with zipfile.ZipFile(good / 'nested.zip', 'w') as zf:
        zf.writestr('notes/readme.txt', 'harmless nested data')
    write_log(good, [('docs/payload.bin', digest(payload))])
    assert_verdict(good, True)

    mismatch = new_case(root)
    (mismatch / 'blob.dat').write_bytes(b'actual contents')
    write_log(mismatch, [('blob.dat', digest(b'different contents'))])
    assert_verdict(mismatch, False)

    missing = new_case(root)
    write_log(missing, [('not-present.dat', digest(b'anything'))])
    assert_verdict(missing, False)

    executable = new_case(root)
    (executable / 'data.txt').write_bytes(b'ok')
    tool = executable / 'tool'
    tool.write_bytes(b'not allowed')
    tool.chmod(0o755)
    write_log(executable, [('data.txt', digest(b'ok'))])
    assert_verdict(executable, False)

    script = new_case(root)
    (script / 'data.txt').write_bytes(b'ok')
    (script / 'hidden.sh').write_text('echo prohibited\n')
    write_log(script, [('data.txt', digest(b'ok'))])
    assert_verdict(script, False)

    elf = new_case(root)
    (elf / 'data.txt').write_bytes(b'ok')
    (elf / 'payload.elf').write_bytes(b'not really an elf')
    write_log(elf, [('data.txt', digest(b'ok'))])
    assert_verdict(elf, False)

    nested_zip = new_case(root)
    (nested_zip / 'data.txt').write_bytes(b'ok')
    with zipfile.ZipFile(nested_zip / 'bundle.zip', 'w') as zf:
        zf.writestr('deep/run.sh', '#!/bin/sh\necho bad\n')
    write_log(nested_zip, [('data.txt', digest(b'ok'))])
    assert_verdict(nested_zip, False)

    nested_tar = new_case(root)
    (nested_tar / 'data.txt').write_bytes(b'ok')
    staging = Path(tempfile.mkdtemp(dir=root))
    try:
        bad = staging / 'inside.elf'
        bad.write_bytes(b'bad')
        with tarfile.open(nested_tar / 'bundle.tar.gz', 'w:gz') as tf:
            tf.add(bad, arcname='deeper/inside.elf')
    finally:
        shutil.rmtree(staging)
    write_log(nested_tar, [('data.txt', digest(b'ok'))])
    assert_verdict(nested_tar, False)

    no_log = new_case(root)
    (no_log / 'data.txt').write_bytes(b'ok')
    assert_verdict(no_log, False)


def wait_for(predicate, timeout=20, interval=0.2, description='condition'):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(interval)
    raise AssertionError(f'Timed out waiting for {description}')


def make_backup_archive(output, backup_id, valid=True):
    staging = Path(tempfile.mkdtemp())
    try:
        data = b'daemon payload ' + os.urandom(16)
        (staging / 'data.bin').write_bytes(data)
        (staging / 'ID.txt').write_text(backup_id + '\n')
        checksum = digest(data) if valid else '0' * 64
        write_log(staging, [('data.bin', checksum)])
        with tarfile.open(output, 'w:gz') as tf:
            for name in ('data.bin', 'ID.txt', 'backup.log'):
                tf.add(staging / name, arcname=name)
    finally:
        shutil.rmtree(staging)


def test_daemon_redis_api_move_and_reject(tmp_path):
    spool = tmp_path / uuid.uuid4().hex
    dest = tmp_path / uuid.uuid4().hex
    incoming = tmp_path / uuid.uuid4().hex
    spool.mkdir()
    dest.mkdir()
    incoming.mkdir()

    subprocess.run(['pkill', '-f', '/app/flask_api.py'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

    service_log = tmp_path / 'service.log'
    log_handle = open(service_log, 'w')
    env = os.environ.copy()
    env['PYTHONUNBUFFERED'] = '1'
    try:
        started = subprocess.run(['/app/start_services.sh'], env=env, stdout=log_handle,
                                 stderr=subprocess.STDOUT, timeout=20)
        assert started.returncode == 0

        def services_ready():
            redis_ok = subprocess.run(['redis-cli', '-p', '6379', 'ping'],
                                      capture_output=True, text=True).stdout.strip() == 'PONG'
            try:
                req = urllib.request.Request(
                    'http://localhost:8080/register_backup',
                    data=json.dumps({'backup_id': 'readiness-probe', 'file_count': 0}).encode(),
                    headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=1) as response:
                    api_ok = response.status == 200
            except Exception:
                api_ok = False
            return redis_ok and api_ok

        wait_for(services_ready, timeout=15, description='Redis and metadata API')
        subprocess.run(['redis-cli', '-p', '6379', 'FLUSHDB'], check=True,
                       stdout=subprocess.DEVNULL)

        daemon_log = open(tmp_path / 'daemon.log', 'w')
        daemon = subprocess.Popen(
            ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST), '--',
             'daemon', str(spool), str(dest)],
            stdout=daemon_log, stderr=subprocess.STDOUT, text=True,
            start_new_session=True,
        )
        try:
            time.sleep(1.5)
            assert daemon.poll() is None, 'daemon exited instead of watching continuously'

            backup_id = 'id-' + uuid.uuid4().hex
            archive_name = uuid.uuid4().hex + '.tar.gz'
            prepared = incoming / archive_name
            make_backup_archive(prepared, backup_id, valid=True)
            os.replace(prepared, spool / archive_name)

            wait_for(lambda: (dest / archive_name).is_file(), timeout=25,
                     description='valid archive to be moved to destination')
            assert not (spool / archive_name).exists()

            def redis_has_id():
                result = subprocess.run(
                    ['redis-cli', '-p', '6379', 'SISMEMBER', 'processed_backups', backup_id],
                    capture_output=True, text=True)
                return result.stdout.strip() == '1'

            wait_for(redis_has_id, timeout=10, description='backup ID to be recorded in Redis')

            def registration_logged():
                log_handle.flush()
                text = service_log.read_text(errors='replace')
                return backup_id in text and "'file_count': 3" in text

            wait_for(registration_logged, timeout=10,
                     description='metadata API registration with backup ID and file count')

            bad_name = uuid.uuid4().hex + '.tar.gz'
            bad_prepared = incoming / bad_name
            make_backup_archive(bad_prepared, 'id-' + uuid.uuid4().hex, valid=False)
            os.replace(bad_prepared, spool / bad_name)
            wait_for(lambda: not (spool / bad_name).exists(), timeout=25,
                     description='invalid archive deletion')
            assert not (dest / bad_name).exists(), 'invalid archive was moved to destination'
            assert daemon.poll() is None, 'daemon stopped after processing files'
        finally:
            if daemon.poll() is None:
                os.killpg(daemon.pid, signal.SIGTERM)
                try:
                    daemon.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(daemon.pid, signal.SIGKILL)
            daemon_log.close()
    finally:
        log_handle.close()
        subprocess.run(['pkill', '-f', '/app/flask_api.py'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
        subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
