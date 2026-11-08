#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import pwd
import secrets
import subprocess
import tarfile
import uuid
import zipfile
import zlib
from collections import Counter
from pathlib import Path

SCRIPT = Path('/home/user/process_data.py')
DATASET = Path('/home/user/dataset.rp')
INCOMING = Path('/home/user/incoming_data')


def _user_preexec():
    account = pwd.getpwnam('user')
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def _run_as_user(command, **kwargs):
    env = kwargs.pop('env', os.environ.copy())
    env['HOME'] = '/home/user'
    return subprocess.run(command, env=env, preexec_fn=_user_preexec, **kwargs)


def _decompress_members(blob):
    output = bytearray()
    remaining = blob
    members = 0
    while remaining:
        decoder = zlib.decompressobj()
        output.extend(decoder.decompress(remaining))
        output.extend(decoder.flush())
        assert decoder.eof, 'dataset.rp contains a truncated or invalid zlib stream'
        members += 1
        next_remaining = decoder.unused_data
        assert next_remaining != remaining, 'zlib decoder made no progress'
        remaining = next_remaining
    assert members > 0, 'dataset.rp contains no compressed streams'
    return bytes(output)


def _archive_csvs(blob, name):
    lower_name = name.lower()
    if lower_name.endswith('.csv'):
        return [blob]

    found = []
    stream = io.BytesIO(blob)
    if zipfile.is_zipfile(stream):
        stream.seek(0)
        with zipfile.ZipFile(stream) as archive:
            for member in archive.infolist():
                if not member.is_dir():
                    found.extend(_archive_csvs(archive.read(member), member.filename))
        return found

    try:
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode='r:*') as archive:
            for member in archive.getmembers():
                if member.isfile():
                    extracted = archive.extractfile(member)
                    assert extracted is not None
                    found.extend(_archive_csvs(extracted.read(), member.name))
        return found
    except tarfile.ReadError:
        return []


def _all_expected_csvs():
    result = []
    for archive_path in sorted(INCOMING.glob('*.tar.gz')):
        result.extend(_archive_csvs(archive_path.read_bytes(), archive_path.name))
    return result


def _incoming_snapshot():
    return {
        str(path.relative_to(INCOMING)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(INCOMING.rglob('*')) if path.is_file()
    }


def _make_dynamic_nested_archive(path):
    token = secrets.token_hex(24)
    csv_data = ('timestamp,sensor_id,value,token\n' +
                ''.join(f'2026-01-01T00:00:{i:02d}Z,verify_sensor,{i},{token}\n' for i in range(30))).encode()

    inner_buffer = io.BytesIO()
    with zipfile.ZipFile(inner_buffer, 'w', zipfile.ZIP_DEFLATED) as inner:
        inner.writestr('dynamic/deep.csv', csv_data)

    outer_buffer = io.BytesIO()
    with zipfile.ZipFile(outer_buffer, 'w', zipfile.ZIP_DEFLATED) as outer:
        outer.writestr('nested/inner.zip', inner_buffer.getvalue())

    with tarfile.open(path, 'w:gz') as outer_tar:
        info = tarfile.TarInfo('outer.zip')
        payload = outer_buffer.getvalue()
        info.size = len(payload)
        outer_tar.addfile(info, io.BytesIO(payload))
    os.chmod(path, 0o644)


def _assert_packer_works(env=None):
    target = Path('/tmp') / f'packer-check-{uuid.uuid4().hex}.rp'
    block = secrets.token_bytes(1024)
    payload = block * 2048
    try:
        result = _run_as_user(
            ['python3', '-m', 'research_packer', 'pack', '--append', str(target)],
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            env=env,
        )
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        packed = target.read_bytes()
        assert _decompress_members(packed) == payload, 'research_packer did not preserve its input'
        assert len(packed) < len(payload) // 10, (
            f'research_packer output is still inefficient: {len(packed)} bytes for {len(payload)} input bytes'
        )
    finally:
        target.unlink(missing_ok=True)


def test_process_data_script_exists():
    path = '/home/user/process_data.py'
    assert os.path.isfile(path), f'The script {path} does not exist.'


def test_research_packer_source_is_fixed_and_installed():
    source_env = os.environ.copy()
    source_env['PYTHONPATH'] = '/app/research_packer'
    _assert_packer_works(source_env)

    installed_env = os.environ.copy()
    installed_env.pop('PYTHONPATH', None)
    _assert_packer_works(installed_env)


def test_pipeline_executes_and_preserves_all_csv_data():
    challenge = INCOMING / f'verifier_challenge_{uuid.uuid4().hex}.tar.gz'
    hook_dir = Path('/tmp') / f'research-packer-hook-{uuid.uuid4().hex}'
    hook_package = hook_dir / 'research_packer'
    invocation_log = Path('/tmp') / f'research-packer-invocations-{uuid.uuid4().hex}.jsonl'

    _make_dynamic_nested_archive(challenge)
    before = _incoming_snapshot()
    expected_csvs = _all_expected_csvs()
    assert expected_csvs, 'No source CSV files were found in incoming_data'

    hook_package.mkdir(parents=True)
    (hook_package / '__init__.py').write_text('')
    (hook_package / '__main__.py').write_text(
        "import json, os, sys, zlib\n"
        "log = os.environ['RP_VERIFIER_LOG']\n"
        "with open(log, 'a') as f:\n"
        "    f.write(json.dumps({'pid': os.getpid(), 'argv': sys.argv[1:]}) + '\\n')\n"
        "if sys.argv[1:] != ['pack', '--append', '/home/user/dataset.rp']:\n"
        "    raise SystemExit(2)\n"
        "data = sys.stdin.buffer.read()\n"
        "with open('/home/user/dataset.rp', 'ab') as out:\n"
        "    out.write(zlib.compress(data, 9))\n"
    )
    invocation_log.touch()
    os.chmod(invocation_log, 0o666)

    DATASET.unlink(missing_ok=True)
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['PYTHONPATH'] = str(hook_dir)
    env['RP_VERIFIER_LOG'] = str(invocation_log)

    try:
        process = subprocess.Popen(
            ['python3', str(SCRIPT)],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=_user_preexec,
        )
        stdout, stderr = process.communicate(timeout=240)
        assert process.returncode == 0, (
            f'process_data.py failed with exit code {process.returncode}:\n'
            f'{stdout.decode(errors="replace")}\n{stderr.decode(errors="replace")}'
        )
        assert _incoming_snapshot() == before, 'process_data.py altered the raw incoming data'
        assert DATASET.is_file(), 'process_data.py did not generate dataset.rp'

        records = [json.loads(line) for line in invocation_log.read_text().splitlines() if line.strip()]
        assert records, 'process_data.py did not invoke research_packer as a Python subprocess'
        for record in records:
            assert record['pid'] != process.pid, 'research_packer was not run in a child process'
            assert record['argv'] == ['pack', '--append', '/home/user/dataset.rp'], (
                'research_packer must be invoked as: python -m research_packer pack --append '
                '/home/user/dataset.rp'
            )

        decoded = _decompress_members(DATASET.read_bytes())
        expected_size = sum(len(item) for item in expected_csvs)
        assert len(decoded) == expected_size, 'dataset.rp does not contain the same amount of CSV data as the inputs'
        expected_lines = Counter(line for item in expected_csvs for line in item.splitlines(keepends=True))
        actual_lines = Counter(decoded.splitlines(keepends=True))
        assert actual_lines == expected_lines, 'dataset.rp does not preserve all source CSV contents'
    finally:
        challenge.unlink(missing_ok=True)
        invocation_log.unlink(missing_ok=True)
        if hook_package.exists():
            for child in hook_package.iterdir():
                child.unlink()
            hook_package.rmdir()
        hook_dir.rmdir()


def test_dataset_rp_exists():
    path = '/home/user/dataset.rp'
    assert os.path.isfile(path), f'The final output file {path} does not exist. Did the pipeline run successfully?'


def test_dataset_rp_file_size():
    path = '/home/user/dataset.rp'
    assert os.path.isfile(path), f'File {path} does not exist.'

    size = os.path.getsize(path)
    threshold = 8000000

    assert size <= threshold, (
        f'File size of {path} is {size} bytes, which exceeds the threshold of {threshold} bytes. '
        'This indicates that the compression bug in `research_packer` was not properly fixed.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
