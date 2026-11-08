#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_artifact_manager.py
import csv
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

WORKSPACE = Path('/home/user/workspace')
ARTIFACTS_DIR = WORKSPACE / 'artifacts'
CURATED_DIR = WORKSPACE / 'curated'
CSV_PATH = WORKSPACE / 'curated_summary.csv'
INDEX_PATH = WORKSPACE / 'repo_index.json'
LOG_PATH = WORKSPACE / 'ingest.log'


def remove_outputs():
    if CURATED_DIR.is_symlink() or CURATED_DIR.is_file():
        CURATED_DIR.unlink()
    elif CURATED_DIR.exists():
        shutil.rmtree(CURATED_DIR)
    if CSV_PATH.exists() or CSV_PATH.is_symlink():
        CSV_PATH.unlink()


def discover_scripts():
    roots = [Path('/home/user'), Path('/root'), Path('/tmp'), Path('/workspace')]
    excluded_names = {'.cache', '.local', '__pycache__', 'site-packages', 'dist-packages', '.git'}
    found = []
    seen = set()

    for root in roots:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in excluded_names]
            path_dir = Path(dirpath)
            if path_dir == ARTIFACTS_DIR or path_dir == CURATED_DIR:
                dirnames[:] = []
                continue
            for name in filenames:
                path = path_dir / name
                if path == Path('/tmp/verify_artifact_manager.py'):
                    continue
                try:
                    if not path.is_file() or path.stat().st_size > 1024 * 1024:
                        continue
                    raw = path.read_bytes()
                except OSError:
                    continue
                is_python = name.endswith('.py') or raw.startswith(b'#!/usr/bin/env python') or raw.startswith(b'#!/usr/bin/python')
                if not is_python:
                    continue
                if not any(token in raw for token in (b'ingest.log', b'repo_index.json', b'curated_summary')):
                    continue
                try:
                    key = str(path.resolve())
                except OSError:
                    key = str(path)
                if key not in seen:
                    seen.add(key)
                    found.append(path)

    found.sort(key=lambda p: p.stat().st_mtime_ns if p.exists() else 0, reverse=True)
    return found


def run_script(path):
    try:
        result = subprocess.run(
            [sys.executable, str(path)],
            cwd=str(WORKSPACE),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=40,
            check=False,
            env=os.environ.copy(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def check_original_assertions():
    assert CSV_PATH.is_file(), f'Summary CSV not found at {CSV_PATH}'
    with CSV_PATH.open('r', newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, 'CSV file is empty'
    assert rows[0] == ['Project', 'Version', 'Filename', 'Status'], f'Incorrect CSV headers: {rows[0]}'
    expected_data = [
        ['Alpha', '2.0.0', 'alpha-2.0.0.zip', 'WARNING'],
        ['Alpha', '1.0.0', 'alpha-1.0.0.zip', 'SUCCESS'],
        ['Beta', '1.0.0', 'beta-1.0.0.zip', 'SUCCESS'],
    ]
    assert rows[1:] == expected_data, f'CSV data rows do not match expected output. Got: {rows[1:]}'

    assert CURATED_DIR.is_dir(), f'Curated directory not found at {CURATED_DIR}'
    expected_files = [
        ('Alpha', '1.0.0', 'alpha-1.0.0.zip'),
        ('Alpha', '2.0.0', 'alpha-2.0.0.zip'),
        ('Beta', '1.0.0', 'beta-1.0.0.zip'),
    ]
    for project, version, filename in expected_files:
        curated_path = CURATED_DIR / project / version / filename
        original_path = ARTIFACTS_DIR / filename
        assert curated_path.is_file(), f'Curated artifact not found at {curated_path}'
        assert curated_path.stat().st_ino == original_path.stat().st_ino, \
            f'File {curated_path} is not a hard link to {original_path}'

    for project, latest_version in [('Alpha', '2.0.0'), ('Beta', '1.0.0')]:
        symlink_path = CURATED_DIR / project / 'latest'
        assert symlink_path.is_symlink(), f"Symlink 'latest' not found for project {project} at {symlink_path}"
        resolved = Path(os.path.abspath(os.path.join(symlink_path.parent, os.readlink(symlink_path))))
        expected = Path(os.path.abspath(CURATED_DIR / project / latest_version))
        assert resolved == expected, f'Symlink for {project} does not point to the correct latest version directory'

    beta_bad_path = CURATED_DIR / 'Beta' / '1.1.0'
    gamma_path = CURATED_DIR / 'Gamma'
    assert not beta_bad_path.exists(), f'Corrupted artifact version directory should not exist: {beta_bad_path}'
    assert not gamma_path.exists(), f'Failed artifact project directory should not exist: {gamma_path}'


def parse_log(path):
    records = []
    current = None
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if line == '[START]':
            current = {}
        elif line == '[END]':
            if current is not None:
                records.append(current)
            current = None
        elif current is not None and ':' in line:
            key, value = line.split(':', 1)
            current[key.strip()] = value.strip()
    return records


def semver(value):
    parts = value.split('.')
    assert len(parts) == 3
    return tuple(int(part) for part in parts)


def derive_expected():
    index = json.loads(INDEX_PATH.read_text())
    statuses = {}
    for record in parse_log(LOG_PATH):
        artifact_id = record.get('Artifact-ID')
        status = record.get('Status')
        if artifact_id and status in ('SUCCESS', 'WARNING'):
            statuses[artifact_id] = status

    valid = []
    rejected = []
    for artifact_id, metadata in index.items():
        status = statuses.get(artifact_id)
        archive = ARTIFACTS_DIR / metadata['filename']
        good = False
        if status and archive.is_file():
            try:
                with zipfile.ZipFile(archive) as zf:
                    good = zf.testzip() is None
            except (OSError, zipfile.BadZipFile):
                good = False
        item = {
            'id': artifact_id,
            'project': metadata['project'],
            'version': metadata['version'],
            'filename': metadata['filename'],
            'status': status,
        }
        (valid if good else rejected).append(item)

    valid.sort(key=lambda item: semver(item['version']), reverse=True)
    valid.sort(key=lambda item: item['project'])
    return valid, rejected


def check_derived_output():
    valid, rejected = derive_expected()
    expected_rows = [['Project', 'Version', 'Filename', 'Status']]
    expected_rows += [[x['project'], x['version'], x['filename'], x['status']] for x in valid]

    assert CSV_PATH.is_file(), 'Dynamic summary CSV was not created'
    with CSV_PATH.open('r', newline='') as f:
        actual_rows = list(csv.reader(f))
    assert actual_rows == expected_rows, f'Dynamic CSV does not match parsed inputs: {actual_rows}'

    expected_files = set()
    by_project = {}
    for item in valid:
        original = ARTIFACTS_DIR / item['filename']
        curated = CURATED_DIR / item['project'] / item['version'] / item['filename']
        assert curated.is_file(), f'Missing dynamically selected artifact: {curated}'
        original_stat = original.stat()
        curated_stat = curated.stat()
        assert (curated_stat.st_dev, curated_stat.st_ino) == (original_stat.st_dev, original_stat.st_ino), \
            f'{curated} is not a hard link to its source archive'
        expected_files.add(curated.resolve())
        by_project.setdefault(item['project'], []).append(item['version'])

    for project, versions in by_project.items():
        latest_version = max(versions, key=semver)
        link = CURATED_DIR / project / 'latest'
        assert link.is_symlink(), f'Missing latest symlink for {project}'
        resolved = Path(os.path.abspath(os.path.join(link.parent, os.readlink(link))))
        expected = Path(os.path.abspath(CURATED_DIR / project / latest_version))
        assert resolved == expected, f'Incorrect latest target for {project}: {os.readlink(link)}'

    valid_locations = {(x['project'], x['version']) for x in valid}
    for item in rejected:
        location = (item['project'], item['version'])
        if location not in valid_locations:
            assert not (CURATED_DIR / item['project'] / item['version']).exists(), \
                f"Rejected artifact was curated: {item['id']}"


def write_dynamic_fixture():
    token = secrets.token_hex(5)
    p1 = f'Aster_{token}'
    p2 = f'Zephyr_{token}'
    p3 = f'Failed_{token}'
    index = {
        f'{token}-01': {'filename': f'{token}-old.zip', 'project': p1, 'version': '1.9.0'},
        f'{token}-02': {'filename': f'{token}-new.zip', 'project': p1, 'version': '1.10.0'},
        f'{token}-03': {'filename': f'{token}-other.zip', 'project': p2, 'version': '3.2.1'},
        f'{token}-04': {'filename': f'{token}-corrupt.zip', 'project': p2, 'version': '4.0.0'},
        f'{token}-05': {'filename': f'{token}-failed.zip', 'project': p3, 'version': '9.0.0'},
    }
    INDEX_PATH.write_text(json.dumps(index, indent=2))
    entries = [
        (f'{token}-01', 'SUCCESS', 'accepted first version'),
        (f'{token}-02', 'WARNING', 'accepted newer version'),
        (f'{token}-03', 'SUCCESS', 'accepted other project'),
        (f'{token}-04', 'SUCCESS', 'archive is corrupt'),
        (f'{token}-05', 'FAILED', 'must be ignored'),
    ]
    blocks = []
    for artifact_id, status, message in entries:
        blocks.append(f'[START]\nDate: 2026-01-01\nArtifact-ID: {artifact_id}\nStatus: {status}\nMessage: {message}.\n[END]\n')
    LOG_PATH.write_text(''.join(blocks))

    if ARTIFACTS_DIR.exists():
        shutil.rmtree(ARTIFACTS_DIR)
    ARTIFACTS_DIR.mkdir(parents=True)
    for metadata in index.values():
        path = ARTIFACTS_DIR / metadata['filename']
        if 'corrupt' in metadata['filename']:
            path.write_bytes(b'not a zip file')
        else:
            with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
                zf.writestr('payload.txt', f"payload for {metadata['project']} {metadata['version']}")


def main():
    assert INDEX_PATH.is_file() and LOG_PATH.is_file() and ARTIFACTS_DIR.is_dir()
    original_index = INDEX_PATH.read_bytes()
    original_log = LOG_PATH.read_bytes()
    original_artifacts = {}
    for path in ARTIFACTS_DIR.iterdir():
        if path.is_file():
            original_artifacts[path.name] = path.read_bytes()

    def restore_original_inputs():
        INDEX_PATH.write_bytes(original_index)
        LOG_PATH.write_bytes(original_log)
        if ARTIFACTS_DIR.exists():
            shutil.rmtree(ARTIFACTS_DIR)
        ARTIFACTS_DIR.mkdir(parents=True)
        for name, data in original_artifacts.items():
            (ARTIFACTS_DIR / name).write_bytes(data)

    scripts = discover_scripts()
    assert scripts, 'No submitted Python processing script was found'

    errors = []
    for script in scripts:
        try:
            restore_original_inputs()
            remove_outputs()
            assert run_script(script), 'script failed on original inputs'
            check_original_assertions()

            write_dynamic_fixture()
            remove_outputs()
            assert run_script(script), 'script failed on dynamic inputs'
            check_derived_output()
            return
        except Exception as exc:
            errors.append(f'{script}: {exc}')

    raise AssertionError('No submitted Python script implemented the required workflow. ' + ' | '.join(errors))


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_artifact_manager.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
