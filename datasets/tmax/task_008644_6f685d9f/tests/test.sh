#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_restore_task.py
import io
import os
import re
import json
import shutil
import hashlib
import secrets
import tarfile
import subprocess
import sys
from pathlib import Path

BACKUPS = Path('/home/user/backups')
RESTORE = Path('/home/user/project_restore')
SKIPPED = Path('/home/user/skipped.log')
MANIFEST = Path('/home/user/manifest.json')


def parse_log(backups):
    text = (backups / 'backup.log').read_text()
    records = []
    for block in text.split('=== Backup Record ===')[1:]:
        values = {}
        for key in ('ID', 'Date', 'File', 'Type'):
            match = re.search(r'^' + key + r':\s*(.+?)\s*$', block, re.MULTILINE)
            assert match, f'Missing {key} in a backup.log record'
            values[key] = match.group(1)
        records.append(values)
    assert records, 'backup.log contains no records'
    records.sort(key=lambda item: item['Date'])
    assert records[0]['Type'] == 'Full', 'Chronologically first backup is not Full'
    return records


def expected_from_archives(backups):
    root = os.path.abspath(str(RESTORE))
    files = {}
    skipped = []
    escaped_targets = []
    for record in parse_log(backups):
        archive = backups / record['File']
        assert archive.is_file(), f'Archive listed in log is missing: {archive}'
        with tarfile.open(archive, 'r:*') as tf:
            for member in tf.getmembers():
                if not member.isfile():
                    continue
                target = os.path.abspath(os.path.join(root, member.name))
                try:
                    safe = os.path.commonpath((root, target)) == root
                except ValueError:
                    safe = False
                if not safe:
                    skipped.append(member.name)
                    escaped_targets.append(target)
                    continue
                extracted = tf.extractfile(member)
                assert extracted is not None
                rel = os.path.relpath(target, root).replace(os.sep, '/')
                files[rel] = extracted.read()
    return files, skipped, escaped_targets


def read_skipped():
    assert SKIPPED.is_file(), f'Skipped log file is missing at {SKIPPED}'
    return [line.strip() for line in SKIPPED.read_text().splitlines() if line.strip()]


def validate_outputs(backups):
    expected_files, expected_skipped, escaped_targets = expected_from_archives(backups)
    assert RESTORE.is_dir(), f'Restore directory missing at {RESTORE}'

    actual_files = {}
    for base, dirs, names in os.walk(RESTORE, followlinks=False):
        for name in names:
            path = Path(base) / name
            assert not path.is_symlink(), f'Unexpected symbolic link in restored state: {path}'
            rel = path.relative_to(RESTORE).as_posix()
            actual_files[rel] = path.read_bytes()
        for name in list(dirs):
            path = Path(base) / name
            assert not path.is_symlink(), f'Unexpected symbolic link in restored state: {path}'

    assert set(actual_files) == set(expected_files), \
        f'Restored file set mismatch: expected {sorted(expected_files)}, got {sorted(actual_files)}'
    for rel, content in expected_files.items():
        assert actual_files[rel] == content, f'Content mismatch in {RESTORE / rel}'

    actual_skipped = read_skipped()
    assert actual_skipped == expected_skipped, \
        f'Expected skipped paths {expected_skipped}, got {actual_skipped}'

    assert MANIFEST.is_file(), f'Manifest file missing at {MANIFEST}'
    try:
        manifest = json.loads(MANIFEST.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'Manifest is not valid JSON: {exc}')
    expected_manifest = {
        rel: hashlib.sha256(content).hexdigest()
        for rel, content in expected_files.items()
    }
    assert isinstance(manifest, dict), 'Manifest should be a JSON object'
    assert manifest == expected_manifest, \
        f'Manifest mismatch: expected {expected_manifest}, got {manifest}'

    for target in escaped_targets:
        assert not os.path.lexists(target), f'Malicious archive member escaped to {target}'


# Preserve and strengthen all checks of the originally supplied fixture, deriving
# the expected state from backup.log and the archives rather than constants.
validate_outputs(BACKUPS)
assert not os.path.exists('/home/user/system_config.txt'), 'Malicious file was extracted to /home/user/system_config.txt'
assert not os.path.exists('/home/system_config.txt'), 'Malicious file was extracted to /home/system_config.txt'


def discover_scripts():
    roots = ['/home/user', '/home/oai/share', '/workspace', '/tmp']
    excluded = [
        os.path.realpath(str(BACKUPS)),
        os.path.realpath(str(RESTORE)),
        os.path.realpath(__file__),
    ]
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for base, dirs, names in os.walk(root):
            real_base = os.path.realpath(base)
            if any(real_base == item or real_base.startswith(item + os.sep) for item in excluded[:2]):
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d not in {'.cache', '.git', '__pycache__', 'site-packages'}]
            for name in names:
                if not name.endswith('.py'):
                    continue
                path = os.path.realpath(os.path.join(base, name))
                if path in excluded or path.startswith('/tmp/test_final_state.py'):
                    continue
                found.append(path)
    return sorted(set(found))


candidates = discover_scripts()
assert candidates, 'No Python extraction script was found'

# Construct an unpredictable replacement fixture. It retains the same task shape,
# but randomizes archive names, paths, contents, and escape destinations.
token = secrets.token_hex(8)
template = Path('/tmp') / ('backup_fixture_' + token)
template.mkdir()
archive_names = [f'full_{token}.tar.gz', f'delta_a_{token}.tar.gz', f'delta_b_{token}.tar.gz']
base_name = f'base_{token}.txt'
common_name = f'nested/common_{token}.txt'
new_name = f'nested/new_{token}.bin'
final_name = f'docs/final_{token}.md'
contents = {
    'base': secrets.token_bytes(37),
    'old': secrets.token_bytes(43),
    'new': secrets.token_bytes(51),
    'extra': secrets.token_bytes(29),
    'final': secrets.token_bytes(47),
}
malicious = [
    f'../escape_{token}.txt',
    f'nested/../../escape_deep_{token}.txt',
    f'/tmp/absolute_escape_{token}.txt',
]


def make_tar(path, entries):
    with tarfile.open(path, 'w:gz') as tf:
        for name, data in entries:
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))


make_tar(template / archive_names[0], [
    (base_name, contents['base']),
    (common_name, contents['old']),
])
make_tar(template / archive_names[1], [
    (common_name, contents['new']),
    (new_name, contents['extra']),
    (malicious[0], secrets.token_bytes(19)),
])
make_tar(template / archive_names[2], [
    (final_name, contents['final']),
    (malicious[1], secrets.token_bytes(23)),
    (malicious[2], secrets.token_bytes(31)),
])

records = [
    (3, '2041-07-13', archive_names[2], 'Incremental'),
    (1, '2041-07-11', archive_names[0], 'Full'),
    (2, '2041-07-12', archive_names[1], 'Incremental'),
]
with (template / 'backup.log').open('w') as log:
    for ident, date, filename, kind in records:
        log.write('=== Backup Record ===\n')
        log.write(f'ID: {ident}\nDate: {date}\nFile: {filename}\nType: {kind}\n')
        log.write('=====================\n')

_, _, dynamic_escape_targets = expected_from_archives(template)
errors = []
passed = False
for candidate in candidates:
    try:
        if BACKUPS.exists():
            shutil.rmtree(BACKUPS)
        shutil.copytree(template, BACKUPS)
        if RESTORE.exists() or RESTORE.is_symlink():
            if RESTORE.is_dir() and not RESTORE.is_symlink():
                shutil.rmtree(RESTORE)
            else:
                RESTORE.unlink()
        for output in (SKIPPED, MANIFEST):
            if output.exists() or output.is_symlink():
                output.unlink()
        for target in dynamic_escape_targets:
            if os.path.lexists(target):
                if os.path.isdir(target) and not os.path.islink(target):
                    shutil.rmtree(target)
                else:
                    os.unlink(target)

        result = subprocess.run(
            [sys.executable, candidate],
            cwd=os.path.dirname(candidate) or '/',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, \
            f'exited {result.returncode}; stderr: {result.stderr[-1000:]}'
        validate_outputs(BACKUPS)
        passed = True
        break
    except Exception as exc:
        errors.append(f'{candidate}: {exc}')

assert passed, 'No discovered Python script safely restored the generated fixture:\n' + '\n'.join(errors)
PY_EOF

if python3 /tmp/verify_restore_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
