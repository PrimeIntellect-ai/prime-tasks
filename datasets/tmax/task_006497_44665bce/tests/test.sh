#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import py_compile
import re
import secrets
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path('/home/user/malware_analysis')
ANALYZER = REPO / 'analyzer.py'
REQUIREMENTS = REPO / 'requirements.txt'
FLAG_PATH = Path('/home/user/decrypted_flag.txt')


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def recover_key_from_git():
    result = run(['git', '-C', str(REPO), 'rev-list', '--all', '--', 'secret.key'])
    assert result.returncode == 0, result.stderr
    for commit in result.stdout.splitlines():
        shown = run(['git', '-C', str(REPO), 'show', f'{commit}:secret.key'])
        if shown.returncode == 0 and shown.stdout.strip():
            return shown.stdout.strip()
    raise AssertionError('Could not recover secret.key from Git history')


def declared_requirement_names(path, seen=None):
    seen = seen or set()
    path = path.resolve()
    if path in seen:
        return set()
    seen.add(path)
    names = set()
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if ' #' in line:
            line = line.split(' #', 1)[0].rstrip()
        match = re.match(r'^(?:-r|--requirement)\s+(.+)$', line)
        if match:
            included = (path.parent / match.group(1).strip()).resolve()
            assert included.is_file(), f'Missing included requirements file: {included}'
            names |= declared_requirement_names(included, seen)
            continue
        if line.startswith('-'):
            continue
        try:
            from packaging.requirements import Requirement
            names.add(Requirement(line).name.lower().replace('_', '-'))
        except Exception as exc:
            raise AssertionError(f'Invalid requirement line {line!r}: {exc}')
    return names


def test_completed_workflow():
    assert REPO.is_dir(), f'Missing repository: {REPO}'
    for path in (ANALYZER, REQUIREMENTS):
        assert path.is_file(), f'Missing required file: {path}'
        assert stat.S_ISREG(path.stat().st_mode), f'{path} is not a regular file'

    py_compile.compile(str(ANALYZER), doraise=True)

    names = declared_requirement_names(REQUIREMENTS)
    assert 'requests' in names, 'requirements.txt does not declare the required requests package'

    install = run([
        sys.executable, '-m', 'pip', 'install', '--disable-pip-version-check',
        '--no-input', '-r', str(REQUIREMENTS)
    ], cwd=str(REPO), timeout=180)
    assert install.returncode == 0, (
        'pip install -r requirements.txt failed:\n' + install.stdout + install.stderr
    )

    imports = run([sys.executable, '-c', 'import requests, urllib3'])
    assert imports.returncode == 0, imports.stderr

    # Exercise the submitted analyzer with verifier-generated data. The filename
    # containing spaces makes the original split-based parser fail.
    dynamic_key = 'VERIFY_' + secrets.token_hex(12)
    dynamic_plaintext = 'DYNAMIC{' + secrets.token_hex(24) + '}'
    plaintext_bytes = dynamic_plaintext.encode('utf-8')
    ciphertext = bytes(
        b ^ ord(dynamic_key[i % len(dynamic_key)])
        for i, b in enumerate(plaintext_bytes)
    )

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        manifest_lines = [
            '/ordinary/path ' + hashlib.md5(b'one').hexdigest(),
            '/tmp/filename containing several spaces.bin ' + hashlib.md5(b'two').hexdigest(),
        ]
        (tmp_path / 'file_manifest.txt').write_text('\n'.join(manifest_lines) + '\n')
        (tmp_path / 'payload.enc').write_bytes(ciphertext)
        FLAG_PATH.unlink(missing_ok=True)

        exercised = run([sys.executable, str(ANALYZER), dynamic_key], cwd=tmp)
        assert exercised.returncode == 0, (
            'analyzer.py failed on a valid manifest containing spaces:\n'
            + exercised.stdout + exercised.stderr
        )
        assert FLAG_PATH.is_file(), 'analyzer.py did not create decrypted_flag.txt'
        assert FLAG_PATH.read_text() == dynamic_plaintext, (
            'analyzer.py did not decrypt verifier-generated payload data correctly'
        )

        # Ensure the manifest integrity assertion was not simply removed.
        (tmp_path / 'file_manifest.txt').write_text('/tmp/a filename with spaces badhash\n')
        FLAG_PATH.unlink(missing_ok=True)
        rejected = run([sys.executable, str(ANALYZER), dynamic_key], cwd=tmp)
        assert rejected.returncode != 0, 'analyzer.py accepted an invalid manifest hash'
        assert not FLAG_PATH.exists(), 'analyzer.py produced output for an invalid manifest'

    # Recover the key from repository history and execute the repaired application
    # against its real manifest and payload.
    recovered_key = recover_key_from_git()
    FLAG_PATH.unlink(missing_ok=True)
    executed = run([sys.executable, str(ANALYZER), recovered_key], cwd=str(REPO))
    assert executed.returncode == 0, (
        'analyzer.py failed with the key recovered from Git history:\n'
        + executed.stdout + executed.stderr
    )

    assert FLAG_PATH.is_file(), (
        f'The file {FLAG_PATH} does not exist. Did you run the analyzer script and save its output?'
    )
    content = FLAG_PATH.read_text().strip()
    expected_flag = 'FLAG{malware_analyzed_successfully_8842}'
    assert content == expected_flag, (
        f"The decrypted flag in {FLAG_PATH} is incorrect. Expected "
        f"'{expected_flag}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
