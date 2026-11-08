#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'HOOK_EOF' > /tmp/sitecustomize.py
import os

_target = os.environ.get('CURATOR_TRACE_TARGET')
_log = os.environ.get('CURATOR_TRACE_LOG')
if _target:
    _target = os.path.abspath(_target)

def _path(value):
    try:
        return os.path.abspath(os.fsdecode(value))
    except Exception:
        return None

def _record(line):
    if not _log:
        return
    with open(_log, 'a', encoding='utf-8') as f:
        f.write(line + '\n')

def _audit(event, args):
    if not _target:
        return
    if event == 'open' and len(args) >= 3:
        path, mode, flags = args[:3]
        if _path(path) == _target:
            mode = mode or ''
            writing = any(c in mode for c in 'wax+')
            if isinstance(flags, int):
                writing = writing or bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND))
            if writing:
                _record('DIRECT_WRITE')
    elif event == 'os.rename' and len(args) >= 2:
        src, dst = _path(args[0]), _path(args[1])
        if dst == _target:
            _record('ATOMIC_RENAME\t' + str(src) + '\t' + str(dst))

import sys
sys.addaudithook(_audit)
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import struct
import subprocess
import tempfile

SCRIPT = '/home/user/curator.py'
WATERMARK = b'SECURE_REPO_2024'


def rle_encode(data):
    out = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        out.extend((count, data[i]))
        i += count
    return bytes(out)


def make_artifact(metadata_bytes, magic=b'ARTX', watermark=WATERMARK, declared_size=None, payload=None):
    if declared_size is None:
        declared_size = len(metadata_bytes)
    if payload is None:
        payload = rle_encode(metadata_bytes)
    return magic + watermark + struct.pack('<I', declared_size) + payload


def decode_reference(path):
    raw = open(path, 'rb').read()
    assert len(raw) >= 24
    assert raw[:4] == b'ARTX'
    assert raw[4:20] == WATERMARK
    declared = struct.unpack('<I', raw[20:24])[0]
    encoded = raw[24:]
    assert len(encoded) % 2 == 0
    decoded = bytearray()
    for i in range(0, len(encoded), 2):
        count, char = encoded[i], encoded[i + 1]
        assert 1 <= count <= 255
        assert char < 128
        decoded.extend(bytes((char,)) * count)
    assert len(decoded) == declared
    value = json.loads(decoded.decode('ascii'))
    assert isinstance(value, dict) and 'artifact_id' in value
    return value


def invoke(input_path, output_path):
    trace = output_path + '.trace'
    env = os.environ.copy()
    env['CURATOR_TRACE_TARGET'] = output_path
    env['CURATOR_TRACE_LOG'] = trace
    env['PYTHONPATH'] = '/tmp' + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        ['python3', SCRIPT, input_path, output_path],
        capture_output=True,
        env=env,
        timeout=10,
    )
    events = []
    if os.path.exists(trace):
        with open(trace, encoding='utf-8') as f:
            events = [line.rstrip('\n') for line in f]
    return result, events


def assert_valid(input_path, output_path, expected):
    result, events = invoke(input_path, output_path)
    assert result.returncode == 0, f'valid artifact rejected: {os.path.basename(input_path)}: {result.stderr!r}'
    assert os.path.isfile(output_path), f'valid artifact produced no output: {os.path.basename(input_path)}'
    with open(output_path, encoding='utf-8') as f:
        actual = json.load(f)
    assert actual == expected, f'decoded metadata differs for {os.path.basename(input_path)}'
    assert 'DIRECT_WRITE' not in events, f'output was written directly for {os.path.basename(input_path)}'
    renames = [event for event in events if event.startswith('ATOMIC_RENAME\t')]
    assert renames, f'no atomic rename to output for {os.path.basename(input_path)}'
    good_rename = False
    for event in renames:
        _, src, dst = event.split('\t', 2)
        if src != dst and os.path.dirname(src) == os.path.dirname(dst) == os.path.dirname(output_path):
            good_rename = True
    assert good_rename, f'temporary file was not renamed from the output directory for {os.path.basename(input_path)}'


def assert_invalid(input_path, output_path):
    result, events = invoke(input_path, output_path)
    assert result.returncode != 0, f'invalid artifact accepted: {os.path.basename(input_path)}'
    assert not os.path.exists(output_path), f'invalid artifact created output: {os.path.basename(input_path)}'
    assert 'DIRECT_WRITE' not in events, f'invalid artifact wrote the final output: {os.path.basename(input_path)}'


def test_adversarial_corpus_and_generated_cases():
    assert os.path.isfile(SCRIPT), f'Agent script not found at {SCRIPT}'

    clean_files = sorted(glob.glob('/app/corpus/clean/*.artx'))
    evil_files = sorted(glob.glob('/app/corpus/evil/*.artx'))
    assert len(clean_files) > 0, 'No clean files found in /app/corpus/clean/'
    assert len(evil_files) > 0, 'No evil files found in /app/corpus/evil/'

    with tempfile.TemporaryDirectory() as tmpdir:
        # Preserve the original corpus assertions, while also checking exact metadata
        # and the required atomic-write behavior.
        for clean_file in clean_files:
            out = os.path.join(tmpdir, secrets.token_hex(10) + '.json')
            assert_valid(clean_file, out, decode_reference(clean_file))
        for evil_file in evil_files:
            out = os.path.join(tmpdir, secrets.token_hex(10) + '.json')
            assert_invalid(evil_file, out)

        cases = []
        valid_objects = [
            {'artifact_id': secrets.token_hex(18), 'nonce': secrets.token_hex(23), 'value': random.randint(-10**9, 10**9)},
            {'artifact_id': secrets.token_urlsafe(19), 'nested': {'ok': True, 'items': [1, 2, 3, None]}, 'padding': 'A' * 300},
            {'artifact_id': random.randint(1, 10**12), 'empty': '', 'flag': False},
            {'artifact_id': secrets.token_hex(12), 'text': 'spaces and punctuation !?[]{}', 'count': 0},
        ]
        for obj in valid_objects:
            raw = json.dumps(obj, separators=(',', ':'), ensure_ascii=True).encode('ascii')
            cases.append((make_artifact(raw), True, obj))

        good_obj = {'artifact_id': secrets.token_hex(16), 'secret_value': secrets.token_hex(28)}
        good_raw = json.dumps(good_obj, separators=(',', ':')).encode('ascii')
        good_payload = rle_encode(good_raw)
        invalid_blobs = [
            make_artifact(good_raw, magic=b'XRTX'),
            make_artifact(good_raw, watermark=b'SECURE_REPO_202X'),
            make_artifact(good_raw, declared_size=len(good_raw) + 1),
            make_artifact(good_raw, declared_size=max(0, len(good_raw) - 1)),
            make_artifact(good_raw, payload=good_payload + b'\x01'),
            make_artifact(good_raw, payload=b'\x00A' + good_payload),
            make_artifact(b'{not valid json]'),
            make_artifact(json.dumps({'other': secrets.token_hex(8)}).encode('ascii')),
            b'ARTX' + WATERMARK[:7],
            make_artifact(b'\xff', payload=b'\x01\xff'),
        ]
        for blob in invalid_blobs:
            cases.append((blob, False, None))

        random.SystemRandom().shuffle(cases)
        for blob, valid, expected in cases:
            stem = secrets.token_hex(16)
            input_path = os.path.join(tmpdir, stem + '.artx')
            output_path = os.path.join(tmpdir, secrets.token_hex(16) + '.json')
            with open(input_path, 'wb') as f:
                f.write(blob)
            if valid:
                assert_valid(input_path, output_path, expected)
            else:
                assert_invalid(input_path, output_path)

        # The program must require exactly two command-line arguments.
        no_args = subprocess.run(['python3', SCRIPT], capture_output=True, timeout=10)
        assert no_args.returncode != 0
        extra_out = os.path.join(tmpdir, secrets.token_hex(10) + '.json')
        extra = subprocess.run(
            ['python3', SCRIPT, clean_files[0], extra_out, 'unexpected'],
            capture_output=True,
            timeout=10,
        )
        assert extra.returncode != 0
        assert not os.path.exists(extra_out)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
