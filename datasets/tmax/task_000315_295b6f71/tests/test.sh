#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import itertools
import os
import posixpath
import secrets
import subprocess
import sys
import tempfile
import zipfile

import pytest

SCRIPT = '/home/user/safe_converter.py'


def test_patool_fixed_and_installed():
    """Verify that patoolib can be imported without syntax errors."""
    try:
        import patoolib
    except SyntaxError as e:
        pytest.fail(f"patoolib still contains a SyntaxError: {e}")
    except ImportError as e:
        pytest.fail(f"patoolib is not installed or cannot be imported: {e}")


def run_converter(archive, out_dir, atomic=False):
    env = os.environ.copy()
    marker = None
    if atomic:
        hook_dir = tempfile.mkdtemp(prefix='atomic_hook_')
        marker = os.path.join(hook_dir, 'rename.marker')
        target = os.path.abspath(os.path.join(out_dir, 'converted.txt'))
        hook = r'''import os
_real_rename = os.rename
_real_replace = os.replace
_target = os.environ.get("ATOMIC_TARGET")
_marker = os.environ.get("ATOMIC_MARKER")

def _matches(src, dst):
    try:
        return (os.path.abspath(os.fspath(dst)) == _target and
                os.path.abspath(os.fspath(src)) != _target and
                os.path.isfile(src))
    except Exception:
        return False

def rename(src, dst, *args, **kwargs):
    matched = _matches(src, dst)
    result = _real_rename(src, dst, *args, **kwargs)
    if matched:
        with open(_marker, "a", encoding="utf-8") as f:
            f.write("rename\n")
    return result

def replace(src, dst, *args, **kwargs):
    matched = _matches(src, dst)
    result = _real_replace(src, dst, *args, **kwargs)
    if matched:
        with open(_marker, "a", encoding="utf-8") as f:
            f.write("replace\n")
    return result

os.rename = rename
os.replace = replace
'''
        with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
            f.write(hook)
        env['PYTHONPATH'] = hook_dir + os.pathsep + env.get('PYTHONPATH', '')
        env['ATOMIC_TARGET'] = target
        env['ATOMIC_MARKER'] = marker

    result = subprocess.run(
        [sys.executable, SCRIPT, archive, out_dir],
        capture_output=True, text=True, env=env, timeout=20
    )
    atomic_used = bool(marker and os.path.isfile(marker) and os.path.getsize(marker) > 0)
    if atomic:
        import shutil
        shutil.rmtree(hook_dir, ignore_errors=True)
    return result, atomic_used


def output_snapshot(path):
    snapshot = {}
    for root, dirs, files in os.walk(path):
        relroot = os.path.relpath(root, path)
        snapshot[('D', relroot)] = None
        for name in sorted(files):
            filename = os.path.join(root, name)
            with open(filename, 'rb') as f:
                snapshot[('F', os.path.relpath(filename, path))] = hashlib.sha256(f.read()).hexdigest()
    return snapshot


def expected_renderings(entries):
    """Allow either direct header/content concatenation or one newline after a header."""
    renderings = set()
    for order in itertools.permutations(entries):
        for separators in itertools.product(('', '\n'), repeat=len(order)):
            renderings.add(''.join(
                f"--- {basename} ---" + sep + content
                for (basename, content), sep in zip(order, separators)
            ))
    return renderings


def zip_entries(archive):
    entries = []
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir() or info.filename.endswith('/'):
                continue
            basename = posixpath.basename(posixpath.normpath(info.filename))
            entries.append((basename, zf.read(info).decode('utf-8')))
    return entries


def assert_malicious(archive, prepopulate=False):
    with tempfile.TemporaryDirectory(prefix='reject_out_') as out_dir:
        if prepopulate:
            with open(os.path.join(out_dir, 'existing.txt'), 'w', encoding='utf-8') as f:
                f.write('must remain unchanged')
        before = output_snapshot(out_dir)
        result, _ = run_converter(archive, out_dir)
        assert result.returncode == 1, (
            f"malicious archive returned {result.returncode}; stderr={result.stderr!r}"
        )
        assert result.stdout == 'MALICIOUS\n', (
            f"malicious archive stdout was not exactly 'MALICIOUS\\n': {result.stdout!r}"
        )
        assert output_snapshot(out_dir) == before, (
            "malicious archive created, removed, or modified files in the output directory"
        )


def assert_clean(archive):
    entries = zip_entries(archive)
    assert entries, 'clean test archive unexpectedly had no files'
    with tempfile.TemporaryDirectory(prefix='clean_out_') as out_dir:
        result, atomic_used = run_converter(archive, out_dir, atomic=True)
        assert result.returncode == 0, (
            f"clean archive returned {result.returncode}; stdout={result.stdout!r}; "
            f"stderr={result.stderr!r}"
        )
        assert sorted(os.listdir(out_dir)) == ['converted.txt'], (
            f"clean conversion left unexpected output entries: {os.listdir(out_dir)!r}"
        )
        out_file = os.path.join(out_dir, 'converted.txt')
        assert os.path.isfile(out_file), 'converted.txt not created'
        with open(out_file, 'r', encoding='utf-8') as f:
            content = f.read()
        assert '--- ' in content, 'converted.txt missing headers'
        assert content in expected_renderings(entries), (
            f"converted.txt did not contain every expected filename/content exactly once: {content!r}"
        )
        assert atomic_used, 'converted.txt was not installed by renaming/replacing a temporary file'


def test_adversarial_corpus():
    """Retain and strengthen checks against the shipped corpus."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    evil_zips = glob.glob('/app/corpora/evil/*.zip')
    clean_zips = glob.glob('/app/corpora/clean/*.zip')
    assert evil_zips, 'No evil zip files found in the corpus.'
    assert clean_zips, 'No clean zip files found in the corpus.'
    for archive in evil_zips:
        assert_malicious(archive)
    for archive in clean_zips:
        assert_clean(archive)


def test_randomized_traversal_and_conversion_variants():
    """Exercise unpredictable archive names, traversal depths, and safe normalized paths."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    token = secrets.token_hex(10)
    with tempfile.TemporaryDirectory(prefix='generated_archives_') as work:
        evil_names = [
            f'../escape_{token}.txt',
            f'nested/../../escape_{token}.txt',
            f'one/two/../../../escape_{token}.txt',
            f'/tmp/absolute_{token}.txt',
        ]
        for index, member in enumerate(evil_names):
            archive = os.path.join(work, f'{secrets.token_hex(8)}_{index}.zip')
            with zipfile.ZipFile(archive, 'w') as zf:
                zf.writestr(f'harmless_{token}.txt', 'decoy\n')
                zf.writestr(member, f'payload-{secrets.token_hex(12)}\n')
            assert_malicious(archive, prepopulate=True)

        archive = os.path.join(work, f'clean_{secrets.token_hex(12)}.zip')
        clean_members = [
            (f'nested_{token}/alpha_{token}.txt', f'alpha-{secrets.token_hex(12)}\n'),
            (f'branch_{token}/../beta_{token}.txt', f'beta-{secrets.token_hex(12)}\n'),
            (f'./gamma_{token}.txt', f'gamma-{secrets.token_hex(12)}\n'),
            (f'deep/{token}/delta_{token}.txt', f'delta-{secrets.token_hex(12)}\n'),
        ]
        with zipfile.ZipFile(archive, 'w') as zf:
            zf.writestr(f'emptydir_{token}/', '')
            for name, content in clean_members:
                zf.writestr(name, content)
        assert_clean(archive)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
