#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_artifact_curator.py
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import uuid

ARTIFACTS_DIR = Path('/home/user/artifacts')
QUARANTINE_DIR = Path('/home/user/quarantine')
MANIFEST_PATH = Path('/home/user/manifest.json')

VALID_FILES = [
    'linux/amd64/app_v1.tar.gz',
    'linux/arm64/app_v1.tar.gz',
    'windows/amd64/app_v2.tar.gz',
]

CORRUPT_FILES = [
    ('linux/amd64/corrupt_app.tar.gz', 'corrupt_app.tar.gz'),
    ('windows/amd64/broken_v1.tar.gz', 'broken_v1.tar.gz'),
]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            digest.update(block)
    return digest.hexdigest()


def load_manifest():
    assert MANIFEST_PATH.is_file(), f'Manifest file not found at {MANIFEST_PATH}'
    try:
        with open(MANIFEST_PATH, 'r') as f:
            manifest = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError('Manifest is not a valid JSON file') from exc
    assert 'files' in manifest, "Manifest JSON missing 'files' key"
    assert isinstance(manifest['files'], list), "'files' in manifest is not a list"
    return manifest


def check_original_assertions():
    manifest = load_manifest()
    actual_files = manifest['files']

    paths = [item.get('path') for item in actual_files]
    assert paths == sorted(paths), "The 'files' array in manifest.json is not sorted alphabetically by 'path'"

    expected_files = []
    for rel_path in VALID_FILES:
        full_path = ARTIFACTS_DIR / rel_path
        assert full_path.is_file(), f'Valid artifact {full_path} should still exist'
        expected_files.append({'path': rel_path, 'checksum': sha256(full_path)})
    expected_files.sort(key=lambda item: item['path'])
    assert actual_files == expected_files, 'Manifest contents do not match the expected valid files and their checksums'

    assert QUARANTINE_DIR.is_dir(), f'Quarantine directory missing at {QUARANTINE_DIR}'
    quarantined_files = os.listdir(QUARANTINE_DIR)
    expected_quarantined = [name for _, name in CORRUPT_FILES]
    assert sorted(quarantined_files) == sorted(expected_quarantined), \
        f'Quarantine directory should contain exactly {expected_quarantined}, but found {quarantined_files}'

    for rel_path, _ in CORRUPT_FILES:
        full_path = ARTIFACTS_DIR / rel_path
        assert not full_path.exists(), f'Corrupted file {full_path} was not removed from the artifacts directory'


def find_release_binaries():
    candidates = []
    seen = set()
    for manifest in Path('/home/user').rglob('Cargo.toml'):
        if 'target' in manifest.parts or '.cargo' in manifest.parts:
            continue
        try:
            result = subprocess.run(
                ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', str(manifest)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                continue
            metadata = json.loads(result.stdout)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            continue

        project_dir = manifest.parent
        rust_sources = [p for p in project_dir.rglob('*.rs') if 'target' not in p.parts]
        if not rust_sources:
            continue

        target_dir = Path(metadata['target_directory'])
        for package in metadata.get('packages', []):
            for target in package.get('targets', []):
                if 'bin' not in target.get('kind', []):
                    continue
                binary = target_dir / 'release' / target['name']
                key = str(binary.resolve()) if binary.exists() else str(binary)
                if key in seen or not binary.is_file() or not os.access(binary, os.X_OK):
                    continue
                try:
                    with open(binary, 'rb') as f:
                        assert f.read(4) == b'\x7fELF'
                except (OSError, AssertionError):
                    continue
                seen.add(key)
                candidates.append((project_dir, binary))
    assert candidates, 'No compiled Rust release binary from a Cargo project was found under /home/user'
    return candidates


def create_valid_archive(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = text.encode()
    info = tarfile.TarInfo('payload/data.txt')
    info.size = len(payload)
    info.mode = 0o644
    with tarfile.open(path, 'w:gz') as archive:
        archive.addfile(info, io.BytesIO(payload))


def archive_is_valid(path):
    try:
        with gzip.open(path, 'rb') as stream:
            decompressed = stream.read()
        with tarfile.open(fileobj=io.BytesIO(decompressed), mode='r:') as archive:
            archive.getmembers()
        return True
    except (OSError, EOFError, tarfile.TarError):
        return False


def restore_tree(source, destination):
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def exercise_binary(candidates):
    token = uuid.uuid4().hex
    valid_relpaths = [
        f'dynamic/{token}/one/deep_valid_{token}.tar.gz',
        f'dynamic/{token}/two/more/nested_valid_{token}.tar.gz',
    ]
    corrupt_relpaths = [
        f'dynamic/{token}/bad/corrupt_gzip_{token}.tar.gz',
        f'dynamic/{token}/bad/deeper/corrupt_tar_{token}.tar.gz',
    ]
    corrupt_names = [Path(path).name for path in corrupt_relpaths]

    with tempfile.TemporaryDirectory(prefix='curator-baseline-') as temp:
        temp = Path(temp)
        baseline_artifacts = temp / 'artifacts'
        baseline_quarantine = temp / 'quarantine'
        shutil.copytree(ARTIFACTS_DIR, baseline_artifacts)
        shutil.copytree(QUARANTINE_DIR, baseline_quarantine)
        baseline_manifest = MANIFEST_PATH.read_bytes()

        errors = []
        for project_dir, binary in candidates:
            restore_tree(baseline_artifacts, ARTIFACTS_DIR)
            restore_tree(baseline_quarantine, QUARANTINE_DIR)
            MANIFEST_PATH.write_bytes(baseline_manifest)

            create_valid_archive(ARTIFACTS_DIR / valid_relpaths[0], 'runtime generated valid archive one ' + token)
            create_valid_archive(ARTIFACTS_DIR / valid_relpaths[1], 'runtime generated valid archive two ' + token)

            bad_gzip = ARTIFACTS_DIR / corrupt_relpaths[0]
            bad_gzip.parent.mkdir(parents=True, exist_ok=True)
            bad_gzip.write_bytes(os.urandom(257))

            bad_tar = ARTIFACTS_DIR / corrupt_relpaths[1]
            bad_tar.parent.mkdir(parents=True, exist_ok=True)
            with gzip.open(bad_tar, 'wb') as stream:
                stream.write(os.urandom(1024))

            expected_files = []
            invalid = []
            for path in ARTIFACTS_DIR.rglob('*.tar.gz'):
                rel = path.relative_to(ARTIFACTS_DIR).as_posix()
                if archive_is_valid(path):
                    expected_files.append({'path': rel, 'checksum': sha256(path)})
                else:
                    invalid.append((path, path.name))
            expected_files.sort(key=lambda item: item['path'])
            expected_quarantine = sorted(os.listdir(QUARANTINE_DIR) + [name for _, name in invalid])

            try:
                result = subprocess.run(
                    [str(binary)],
                    cwd=str(project_dir),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=60,
                )
                assert result.returncode == 0, f'exited with status {result.returncode}: {result.stderr}'

                manifest = load_manifest()
                assert set(manifest.keys()) == {'files'}, 'Manifest must contain exactly the top-level files key'
                assert manifest['files'] == expected_files, 'Rust tool failed runtime-generated recursive archive tests'
                for item in manifest['files']:
                    assert set(item.keys()) == {'path', 'checksum'}, 'Manifest entries must contain exactly path and checksum'
                assert [item['path'] for item in manifest['files']] == sorted(item['path'] for item in manifest['files'])

                for relpath in valid_relpaths:
                    assert (ARTIFACTS_DIR / relpath).is_file(), f'Valid generated archive was removed: {relpath}'
                for path, _ in invalid:
                    assert not path.exists(), f'Corrupt generated archive was not removed: {path}'
                assert sorted(os.listdir(QUARANTINE_DIR)) == expected_quarantine, \
                    'Corrupt runtime-generated archives were not moved flat into quarantine'
                for name in corrupt_names:
                    assert (QUARANTINE_DIR / name).is_file(), f'Generated corrupt archive was not quarantined: {name}'
                return
            except (AssertionError, OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f'{binary}: {exc}')

        raise AssertionError('No compiled Rust release binary performed the required work. ' + ' | '.join(errors))


def main():
    check_original_assertions()
    candidates = find_release_binaries()
    exercise_binary(candidates)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_artifact_curator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
