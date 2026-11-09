#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import shutil
import subprocess
import tarfile
from pathlib import Path

import pytest

SCATTER = Path('/home/user/project_scatter')
ASSEMBLER = Path('/home/user/assembler')
ARCHIVE = Path('/home/user/reassembled_project.tar.gz')
MANIFEST = Path('/home/user/manifest.txt')
SUMMARY = Path('/home/user/manifest_summary.txt')


def ordered_chunks(root):
    chunks = []
    for path in root.rglob('*.chunk'):
        match = re.search(r'_part([0-9]+)\.chunk$', path.name)
        assert match, f'Chunk has an invalid filename: {path}'
        chunks.append((int(match.group(1)), path))
    assert chunks, 'No chunks were found.'
    chunks.sort(key=lambda item: item[0])
    assert [number for number, _ in chunks] == list(range(1, len(chunks) + 1)), \
        'Chunk part numbers are not contiguous starting at 1.'
    return chunks


def concatenate_chunks(root):
    return b''.join(path.read_bytes() for _, path in ordered_chunks(root))


def archive_manifest(archive_bytes):
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:gz') as archive:
        members = [m for m in archive.getmembers()
                   if m.isfile() and m.name.lstrip('./') == 'manifest.txt']
        assert len(members) == 1, 'Archive must contain exactly one manifest.txt file.'
        extracted = archive.extractfile(members[0])
        assert extracted is not None
        return extracted.read()


def clear_outputs():
    for path in (ARCHIVE, MANIFEST, SUMMARY):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_assembler():
    result = subprocess.run(
        [str(ASSEMBLER)], cwd='/home/user', timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, (
        f'assembler exited with {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


@pytest.fixture(scope='session', autouse=True)
def execute_original_artifact():
    global ORIGINAL_ARCHIVE, ORIGINAL_MANIFEST
    ORIGINAL_ARCHIVE = concatenate_chunks(SCATTER)
    ORIGINAL_MANIFEST = archive_manifest(ORIGINAL_ARCHIVE)
    clear_outputs()
    run_assembler()


def test_assembler_cpp_exists_and_contains_required_headers():
    """Test that assembler.cpp exists and includes required headers."""
    cpp_path = '/home/user/assembler.cpp'
    assert os.path.isfile(cpp_path), f'File {cpp_path} does not exist.'

    with open(cpp_path, 'r', encoding='utf-8') as f:
        content = f.read()

    has_traversal = ('<dirent.h>' in content) or ('<filesystem>' in content)
    has_fstream = '<fstream>' in content

    assert has_traversal, 'assembler.cpp must include <dirent.h> or <filesystem> for directory traversal.'
    assert has_fstream, 'assembler.cpp must include <fstream> for file I/O operations.'


def test_assembler_executable_exists():
    """Test that the compiled assembler executable exists."""
    exe_path = '/home/user/assembler'
    assert os.path.isfile(exe_path), f'Executable {exe_path} does not exist.'
    assert os.access(exe_path, os.X_OK), f'File {exe_path} is not executable.'
    with open(exe_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'assembler must be a compiled executable.'


def test_reassembled_tarball_exists():
    """Test that the reassembled tarball exists and has gzip magic bytes."""
    tarball_path = '/home/user/reassembled_project.tar.gz'
    assert os.path.isfile(tarball_path), f'Reassembled tarball {tarball_path} does not exist.'

    with open(tarball_path, 'rb') as f:
        magic = f.read(2)
    assert magic == b'\x1f\x8b', f'{tarball_path} does not appear to be a valid gzip file.'


def test_reassembled_tarball_matches_actual_chunks_and_extracts():
    assert ARCHIVE.read_bytes() == ORIGINAL_ARCHIVE, \
        'The reconstructed archive is not the exact ordered concatenation of the chunks.'
    assert archive_manifest(ARCHIVE.read_bytes()) == ORIGINAL_MANIFEST, \
        'The reconstructed archive cannot be extracted correctly.'


def test_manifest_txt_exists():
    """Test that manifest.txt was extracted."""
    manifest_path = '/home/user/manifest.txt'
    assert os.path.isfile(manifest_path), f'Extracted manifest {manifest_path} does not exist.'
    assert Path(manifest_path).read_bytes() == ORIGINAL_MANIFEST, \
        'manifest.txt does not match the manifest in the reconstructed archive.'


def test_manifest_summary_content():
    """Test that manifest_summary.txt contains the correct first line."""
    summary_path = '/home/user/manifest_summary.txt'
    assert os.path.isfile(summary_path), f'Summary file {summary_path} does not exist.'

    with open(summary_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_content = 'PROJECT_ID: ALPHA_7782_OMEGA\n'
    assert content == expected_content, f'manifest_summary.txt content is incorrect. Expected: {repr(expected_content)}, Got: {repr(content)}'


def test_z_dynamic_recursive_traversal_sorting_merging_and_extraction(tmp_path):
    token = secrets.token_hex(16)
    first_line = f'PROJECT_ID: DYNAMIC_{token}'
    source = tmp_path / 'source'
    source.mkdir()
    (source / 'manifest.txt').write_text(first_line + '\nsecond line\nthird line\n', encoding='utf-8')
    (source / 'random.bin').write_bytes(os.urandom(4096))

    test_archive = tmp_path / 'dynamic.tar.gz'
    subprocess.run(
        ['tar', '-czf', str(test_archive), '-C', str(source), '.'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    expected_archive = test_archive.read_bytes()
    expected_manifest = archive_manifest(expected_archive)

    shutil.rmtree(SCATTER)
    locations = [
        SCATTER / 'deep' / 'one' / 'two',
        SCATTER / 'elsewhere',
        SCATTER / 'deep' / 'other',
        SCATTER,
    ]
    for location in locations:
        location.mkdir(parents=True, exist_ok=True)

    pieces = [expected_archive[i:i + 97] for i in range(0, len(expected_archive), 97)]
    prefixes = ['backup', 'misc', 'payload', 'random_name']
    for index, piece in enumerate(pieces, 1):
        location = locations[(index * 3) % len(locations)]
        prefix = prefixes[index % len(prefixes)]
        (location / f'{prefix}_part{index}.chunk').write_bytes(piece)

    clear_outputs()
    run_assembler()

    assert ARCHIVE.is_file(), 'assembler did not create the archive on the dynamic input.'
    assert ARCHIVE.read_bytes() == expected_archive, \
        'assembler did not recursively find and numerically order the dynamic chunks.'
    assert archive_manifest(ARCHIVE.read_bytes()) == expected_manifest
    assert MANIFEST.read_bytes() == expected_manifest, \
        'assembler did not extract the dynamic manifest from the archive.'
    assert SUMMARY.read_bytes() == (first_line + '\n').encode(), \
        'assembler did not write exactly the dynamic manifest first line and newline.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
