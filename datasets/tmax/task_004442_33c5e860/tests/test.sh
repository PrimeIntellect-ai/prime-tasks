#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import ast
import fcntl
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

ARCHIVE = Path('/home/user/update.tar.gz')
MANIFEST = Path('/home/user/patch_manifest.txt')
PATCH_BYTES = b'LZMA:OPT:12345'
EXPECTED_IDS = set(range(1, 101))


def find_pipeline_script():
    candidates = []
    for p in Path('/home/user').rglob('*.py'):
        try:
            if p.is_file() and '/app/patch_gen' in p.read_text(errors='replace'):
                candidates.append(p)
        except OSError:
            pass
    assert candidates, 'No Python pipeline script invoking /app/patch_gen was found.'

    for p in candidates:
        source = p.read_text(errors='replace')
        try:
            tree = ast.parse(source)
        except SyntaxError:
            continue
        calls = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                fn = node.func
                if isinstance(fn, ast.Name):
                    calls.append(fn.id)
                elif isinstance(fn, ast.Attribute):
                    calls.append(fn.attr)
        has_concurrency = any(x in source for x in (
            'ThreadPoolExecutor', 'ProcessPoolExecutor', 'multiprocessing.Pool',
            'multiprocessing.pool', 'concurrent.futures'
        )) or any(x in calls for x in ('ThreadPoolExecutor', 'ProcessPoolExecutor', 'Pool'))
        has_locking = 'fcntl' in source and 'flock' in calls
        has_redaction = all(x in source for x in ('API_KEY=', 'DB_PASS=', 'REDACTED'))
        has_optimization = '--lzma-pack' in source
        if has_concurrency and has_locking and has_redaction and has_optimization:
            return p

    raise AssertionError(
        'The patch-generating Python script must use concurrent workers, fcntl.flock, '
        'both required redactions, and patch_gen --lzma-pack.'
    )


def assert_read_only_squashfs_mount():
    result = subprocess.run(
        ['findmnt', '-n', '-o', 'FSTYPE,OPTIONS', '--target', '/home/user/mnt_old'],
        text=True, capture_output=True
    )
    assert result.returncode == 0, '/home/user/mnt_old is not a mounted filesystem.'
    fields = result.stdout.strip().split(None, 1)
    assert fields and fields[0] == 'squashfs', 'mnt_old must be a SquashFS mount.'
    options = fields[1].split(',') if len(fields) > 1 else []
    assert 'ro' in options, 'The SquashFS filesystem must be mounted read-only.'
    for i in EXPECTED_IDS:
        assert (Path('/home/user/mnt_old') / f'config_{i}.conf').is_file()


def install_instrumented_patch_gen():
    real = Path('/app/patch_gen.real_for_verifier')
    wrapper = Path('/app/patch_gen')
    assert wrapper.is_file(), '/app/patch_gen is missing.'
    assert not real.exists(), 'Unexpected verifier backup already exists.'
    os.replace(wrapper, real)
    code = r'''#!/usr/bin/env python3
import fcntl, json, os, re, subprocess, sys, time
from pathlib import Path

STATE = Path('/tmp/patch_gen_audit_state.json')
LOCK = Path('/tmp/patch_gen_audit.lock')
LOG = Path('/tmp/patch_gen_audit.jsonl')

def transform(data):
    out = []
    for line in data.splitlines(True):
        body = line.rstrip('\\r\\n')
        ending = line[len(body):]
        if body.startswith('API_KEY='):
            body = 'API_KEY=REDACTED'
        elif body.startswith('DB_PASS='):
            body = 'DB_PASS=REDACTED'
        out.append(body + ending)
    return ''.join(out)

def update_state(delta):
    with LOCK.open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            state = {'active': 0, 'maximum': 0}
            if STATE.exists():
                state = json.loads(STATE.read_text())
            state['active'] += delta
            state['maximum'] = max(state['maximum'], state['active'])
            STATE.write_text(json.dumps(state))
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)

def fail(message):
    print(message, file=sys.stderr)
    sys.exit(90)

if len(sys.argv) != 5 or sys.argv[4] != '--lzma-pack':
    fail('patch_gen was not invoked with exactly old, new, output, --lzma-pack')
old, new, output = map(Path, sys.argv[1:4])
try:
    old_real = old.resolve(strict=True)
    new_real = new.resolve(strict=True)
except Exception as e:
    fail('Missing patch input: ' + str(e))
mount = Path('/home/user/mnt_old').resolve()
try:
    old_real.relative_to(mount)
except ValueError:
    fail('Old input is not from the mounted SquashFS')
try:
    new_real.relative_to(Path('/home/user/new_configs').resolve())
    fail('Original new_configs file was passed instead of a redacted temporary file')
except ValueError:
    pass
m = re.fullmatch(r'config_(\\d+)\\.conf', old_real.name)
if not m or int(m.group(1)) not in range(1, 101) or new_real.name != old_real.name:
    fail('Unexpected configuration pair')
original = Path('/home/user/new_configs', old_real.name).read_text()
redacted = new_real.read_text()
if redacted != transform(original):
    fail('Temporary input is not the exact required redaction of the new config')
if 'secretxyz' in redacted or 'dbsecret' in redacted:
    fail('Sensitive data remains in temporary input')
update_state(1)
try:
    time.sleep(0.08)
    result = subprocess.run(['/app/patch_gen.real_for_verifier', str(old), str(new), str(output), '--lzma-pack'])
finally:
    update_state(-1)
if result.returncode != 0:
    sys.exit(result.returncode)
with LOCK.open('a+') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        with LOG.open('a') as log:
            log.write(json.dumps({'id': int(m.group(1)), 'output': str(output)}) + '\\n')
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
'''
    wrapper.write_text(code)
    wrapper.chmod(0o755)
    return real, wrapper


def exercise_pipeline(script):
    saved_archive = ARCHIVE.read_bytes() if ARCHIVE.exists() else None
    saved_manifest = MANIFEST.read_bytes() if MANIFEST.exists() else None

    for p in Path('/home/user').rglob('*'):
        try:
            if p.is_file() and p not in (ARCHIVE, MANIFEST) and p.read_bytes() == PATCH_BYTES:
                p.unlink()
        except (OSError, MemoryError):
            pass
    for p in ('/tmp/patch_gen_audit_state.json', '/tmp/patch_gen_audit.lock', '/tmp/patch_gen_audit.jsonl'):
        try:
            os.unlink(p)
        except FileNotFoundError:
            pass
    try:
        MANIFEST.unlink(missing_ok=True)
        real, wrapper = install_instrumented_patch_gen()
        try:
            result = subprocess.run(
                ['python3', str(script)], cwd=str(script.parent),
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
            )
            assert result.returncode == 0, 'Pipeline script failed when executed:\n' + result.stdout[-4000:]
        finally:
            if real.exists():
                wrapper.unlink(missing_ok=True)
                os.replace(real, wrapper)
    finally:
        if saved_archive is not None:
            ARCHIVE.write_bytes(saved_archive)
        else:
            ARCHIVE.unlink(missing_ok=True)
        if saved_manifest is not None:
            MANIFEST.write_bytes(saved_manifest)
        else:
            MANIFEST.unlink(missing_ok=True)

    state_path = Path('/tmp/patch_gen_audit_state.json')
    log_path = Path('/tmp/patch_gen_audit.jsonl')
    assert state_path.exists() and log_path.exists(), 'The executed script did not invoke patch_gen.'
    state = json.loads(state_path.read_text())
    assert state.get('maximum', 0) >= 2, 'patch_gen invocations did not overlap; processing was not concurrent.'
    records = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
    ids = [r['id'] for r in records]
    assert len(ids) == 100 and set(ids) == EXPECTED_IDS, 'patch_gen must be invoked once for each of the 100 selected configs.'
    assert len(ids) == len(set(ids)), 'A selected configuration was patched more than once.'


def parse_manifest(data):
    text = data.decode('utf-8')
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == 100, 'Manifest must contain exactly one non-empty entry per patch.'
    found = {}
    for line in lines:
        match_id = re.search(r'config_(\d+)', line)
        match_size = re.search(r'(?:^|[\s,:=])(\d+)\s*$', line)
        assert match_id and match_size, f'Invalid manifest entry: {line!r}'
        ident, size = int(match_id.group(1)), int(match_size.group(1))
        assert ident in EXPECTED_IDS and ident not in found, 'Manifest has an unexpected or duplicate config.'
        assert size == len(PATCH_BYTES), f'Wrong patch size recorded for config_{ident}: {size}'
        found[ident] = size
    assert set(found) == EXPECTED_IDS


def validate_final_archive():
    # Preserve the original verifier's assertions.
    assert ARCHIVE.exists(), f'Archive {ARCHIVE} does not exist.'
    size = ARCHIVE.stat().st_size
    threshold = 25000
    assert size <= threshold, (
        f'Archive size is {size} bytes, which exceeds the strict threshold of {threshold} bytes. '
        'Did you find and use the undocumented flag for patch_gen?'
    )
    assert tarfile.is_tarfile(ARCHIVE), f'File {ARCHIVE} is not a valid tar archive.'

    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        names = tar.getnames()
        assert any(name.endswith('patch_manifest.txt') for name in names), 'patch_manifest.txt not found in the archive.'
        assert len(names) > 1, 'The archive should contain patch files along with the manifest.'

        regular = [m for m in tar.getmembers() if m.isfile()]
        assert len(regular) == 101, 'Archive must contain exactly 100 patches and one manifest.'
        manifests = [m for m in regular if m.name.endswith('patch_manifest.txt')]
        assert len(manifests) == 1, 'Archive must contain exactly one patch_manifest.txt.'
        manifest_data = tar.extractfile(manifests[0]).read()
        assert MANIFEST.is_file(), '/home/user/patch_manifest.txt is missing.'
        assert MANIFEST.read_bytes() == manifest_data, 'Archived manifest differs from /home/user/patch_manifest.txt.'
        parse_manifest(manifest_data)

        patches = [m for m in regular if m is not manifests[0]]
        patch_ids = set()
        for member in patches:
            match = re.search(r'config_(\d+)', member.name)
            assert match, f'Patch member does not identify its config: {member.name}'
            ident = int(match.group(1))
            assert ident in EXPECTED_IDS and ident not in patch_ids, 'Unexpected or duplicate patch member.'
            patch_ids.add(ident)
            data = tar.extractfile(member).read()
            assert data == PATCH_BYTES, f'{member.name} is not optimized patch_gen output.'
        assert patch_ids == EXPECTED_IDS


def test_complete_pipeline():
    assert_read_only_squashfs_mount()
    script = find_pipeline_script()
    exercise_pipeline(script)
    validate_final_archive()
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    # Restore the real binary if an interrupted test left the verifier wrapper installed.
    if [ -e /app/patch_gen.real_for_verifier ]; then
        rm -f /app/patch_gen
        mv /app/patch_gen.real_for_verifier /app/patch_gen
    fi
    echo "0" > /logs/verifier/reward.txt
fi
