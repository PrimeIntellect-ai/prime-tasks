#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tarfile
from pathlib import Path

REPO = Path('/home/user/repo_out')
ARCHIVE = Path('/home/user/artifacts.tar.gz')


def read_expected_artifacts():
    expected = {}
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        members = [m for m in tar.getmembers() if m.isfile() and m.name.endswith('.bin')]
        assert members, 'Input archive contains no .bin files'
        for member in members:
            f = tar.extractfile(member)
            assert f is not None
            raw = f.read()
            assert raw[:4] == b'ARTF', f'Bad magic in {member.name}'
            assert raw[4] == 1, f'Bad version in {member.name}'
            name_len = struct.unpack_from('<H', raw, 5)[0]
            name_end = 7 + name_len
            name = raw[7:name_end].decode('utf-8')
            payload_len = struct.unpack_from('<Q', raw, name_end)[0]
            payload_start = name_end + 8
            payload = raw[payload_start:payload_start + payload_len]
            assert len(payload) == payload_len, f'Truncated payload in {member.name}'
            assert payload_start + payload_len == len(raw), f'Unexpected trailing bytes in {member.name}'
            assert name not in expected, f'Duplicate artifact name {name}'
            expected[name] = payload
    return expected


EXPECTED = read_expected_artifacts()


def manifest_has_expected_outputs():
    try:
        with open(REPO / 'manifest.json', 'r') as f:
            manifest = json.load(f)
        artifacts = manifest['artifacts']
        if set(artifacts) != set(EXPECTED):
            return False
        for name, payload in EXPECTED.items():
            count = (len(payload) + 1023) // 1024
            entries = artifacts[name]
            if len(entries) != count:
                return False
            for i, entry in enumerate(entries):
                if entry.get('chunk') != f'chunk_{i}.gz':
                    return False
                if not (REPO / name / f'chunk_{i}.gz').is_file():
                    return False
        return True
    except Exception:
        return False


def test_rust_program_builds_and_regenerates_repository():
    manifests = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'target', 'repo_out', '.cargo', '.rustup'}]
        if 'Cargo.toml' in files:
            manifests.append(Path(root) / 'Cargo.toml')

    preferred = Path('/home/user/artifact_processor/Cargo.toml')
    manifests.sort(key=lambda p: (p != preferred, len(p.parts), str(p)))
    assert manifests, 'No Rust Cargo project found under /home/user'

    errors = []
    for cargo_manifest in manifests:
        project = cargo_manifest.parent
        rust_sources = [p for p in project.rglob('*.rs') if 'target' not in p.parts]
        if not rust_sources or not any(p.stat().st_size > 0 for p in rust_sources):
            errors.append(f'{cargo_manifest}: no non-empty Rust source')
            continue

        shutil.rmtree(REPO, ignore_errors=True)
        try:
            subprocess.run(
                ['cargo', 'build', '--manifest-path', str(cargo_manifest)],
                cwd=project, check=True, timeout=180,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            subprocess.run(
                ['cargo', 'run', '--manifest-path', str(cargo_manifest)],
                cwd=project, check=True, timeout=180,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
        except (subprocess.SubprocessError, OSError) as exc:
            errors.append(f'{cargo_manifest}: {exc}')
            continue

        if manifest_has_expected_outputs():
            return
        errors.append(f'{cargo_manifest}: running it did not generate the expected repository structure')

    assert False, 'No Rust project successfully regenerated the repository: ' + '; '.join(errors)


def test_manifest_exists_and_valid():
    manifest_path = '/home/user/repo_out/manifest.json'
    assert os.path.exists(manifest_path), f'Manifest file not found at {manifest_path}'
    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, 'manifest.json is not valid JSON'

    assert 'artifacts' in manifest, "'artifacts' key missing in manifest.json"
    artifacts = manifest['artifacts']
    assert 'lib_core.so' in artifacts, "'lib_core.so' missing in artifacts"
    assert 'config.dat' in artifacts, "'config.dat' missing in artifacts"


def test_manifest_sha256_matches_files():
    manifest_path = '/home/user/repo_out/manifest.json'
    assert os.path.exists(manifest_path), 'Manifest file is missing'

    with open(manifest_path, 'r') as f:
        manifest = json.load(f)

    assert 'artifacts' in manifest, "'artifacts' key missing in manifest.json"

    for art_name, chunks in manifest['artifacts'].items():
        assert isinstance(chunks, list), f'Expected list of chunks for {art_name}'
        for chunk_info in chunks:
            chunk_filename = chunk_info.get('chunk')
            expected_sha256 = chunk_info.get('sha256')

            assert chunk_filename, f"Missing 'chunk' key in manifest for {art_name}"
            assert expected_sha256, f"Missing 'sha256' key in manifest for {art_name}"

            filepath = os.path.join('/home/user/repo_out', art_name, chunk_filename)
            assert os.path.exists(filepath), f'Chunk file {filepath} does not exist'

            with open(filepath, 'rb') as f2:
                actual_sha256 = hashlib.sha256(f2.read()).hexdigest()

            assert actual_sha256 == expected_sha256, f'SHA256 mismatch for {filepath}. Expected {expected_sha256}, got {actual_sha256}'


def test_exact_manifest_chunking_and_indexing():
    with open(REPO / 'manifest.json', 'r') as f:
        manifest = json.load(f)

    assert isinstance(manifest, dict)
    assert set(manifest.keys()) == {'artifacts'}, 'manifest.json must contain exactly the artifacts key'
    artifacts = manifest['artifacts']
    assert isinstance(artifacts, dict)
    assert set(artifacts.keys()) == set(EXPECTED), 'Manifest artifact names do not exactly match parsed input names'

    for art_name, payload in EXPECTED.items():
        entries = artifacts[art_name]
        expected_count = (len(payload) + 1023) // 1024
        assert isinstance(entries, list)
        assert len(entries) == expected_count, f'Wrong chunk count for {art_name}'

        artifact_dir = REPO / art_name
        assert artifact_dir.is_dir(), f'Missing artifact directory {artifact_dir}'
        expected_files = {f'chunk_{i}.gz' for i in range(expected_count)}
        actual_files = {p.name for p in artifact_dir.iterdir() if p.is_file()}
        assert actual_files == expected_files, f'Unexpected or missing chunk files for {art_name}'

        rebuilt = bytearray()
        for i, entry in enumerate(entries):
            assert isinstance(entry, dict)
            assert set(entry.keys()) == {'chunk', 'sha256'}, f'Wrong manifest entry schema for {art_name} chunk {i}'
            filename = f'chunk_{i}.gz'
            assert entry['chunk'] == filename, f'Chunks for {art_name} are missing or out of order'
            assert isinstance(entry['sha256'], str)
            assert re.fullmatch(r'[0-9a-f]{64}', entry['sha256']), f'Invalid lowercase SHA-256 for {art_name} chunk {i}'

            path = artifact_dir / filename
            compressed = path.read_bytes()
            assert hashlib.sha256(compressed).hexdigest() == entry['sha256']
            with gzip.open(path, 'rb') as f:
                chunk = f.read()

            expected_chunk = payload[i * 1024:(i + 1) * 1024]
            assert chunk == expected_chunk, f'Incorrect payload bytes in {art_name} chunk {i}'
            if i < expected_count - 1:
                assert len(chunk) == 1024, f'Non-final chunk {i} for {art_name} is not exactly 1024 bytes'
            else:
                assert 0 < len(chunk) <= 1024, f'Invalid final chunk size for {art_name}'
            rebuilt.extend(chunk)

        assert bytes(rebuilt) == payload, f'Reconstructed payload for {art_name} is incorrect'


def test_uncompressed_payloads():
    def verify_payload(art_name, expected_data):
        data = b''
        chunk_idx = 0
        while True:
            filepath = f'/home/user/repo_out/{art_name}/chunk_{chunk_idx}.gz'
            if not os.path.exists(filepath):
                break
            with gzip.open(filepath, 'rb') as f:
                data += f.read()
            chunk_idx += 1

        assert chunk_idx > 0, f'No chunks found for {art_name}'
        assert len(data) == len(expected_data), f'Uncompressed data length for {art_name} is {len(data)}, expected {len(expected_data)}'
        assert data == expected_data, f'Uncompressed data for {art_name} does not match expected payload'

    payload1 = bytes([i % 256 for i in range(2500)])
    verify_payload('lib_core.so', payload1)

    payload2 = bytes([(i * 2) % 256 for i in range(1024)])
    verify_payload('config.dat', payload2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
