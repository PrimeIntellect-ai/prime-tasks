#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PREP_EOF' > /tmp/prepare_inputs.py
import os
import secrets

base = os.path.join('/home/user/raw_data', 'verifier_' + secrets.token_hex(8), 'deep', 'tree')
os.makedirs(base, exist_ok=True)

files = {
    'probe.elf': b'\x7fELF' + b'A' * 300 + b'B',
    'probe.wal': b'\x37\x7f\x06\x83' + b'W' * 260 + b'Z',
    'probe.gcode': b'; FLAVOR:Verifier\nG0 X1 Y2\n' + b'G' * 256,
    'ignored.bin': b'not a recognized file type',
}
for name, data in files.items():
    with open(os.path.join(base, name), 'wb') as f:
        f.write(data)
PREP_EOF

cat << 'RUN_EOF' > /tmp/build_and_run_submission.py
import json
import os
import shutil
import stat
import subprocess

project = '/home/user/dataset_packer'
manifest = os.path.join(project, 'Cargo.toml')
assert os.path.isdir(project), 'Rust project directory is missing'
assert os.path.isfile(manifest), 'Cargo.toml is missing'

metadata = json.loads(subprocess.check_output([
    'cargo', 'metadata', '--format-version', '1', '--no-deps',
    '--manifest-path', manifest,
], cwd=project, timeout=60))

manifest_real = os.path.realpath(manifest)
packages = [p for p in metadata['packages'] if os.path.realpath(p['manifest_path']) == manifest_real]
assert packages, 'Cargo.toml does not define a Rust package'
package = packages[0]
bins = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
assert bins, 'Rust project has no binary target'

default_run = package.get('default_run')
if default_run:
    selected = next((t for t in bins if t['name'] == default_run), None)
    assert selected is not None, 'default-run does not name a binary target'
elif len(bins) == 1:
    selected = bins[0]
else:
    selected = next((t for t in bins if t['name'] == package['name']), None)
    assert selected is not None, 'Multiple binaries exist without an unambiguous default'

source = os.path.realpath(selected['src_path'])
assert source.startswith(os.path.realpath(project) + os.sep), 'Binary source is outside the requested project'
assert os.path.isfile(source) and source.endswith('.rs'), 'Binary target is not backed by a Rust source file'

subprocess.run([
    'cargo', 'build', '--manifest-path', manifest, '--bin', selected['name']
], cwd=project, check=True, timeout=120)

binary = os.path.join(metadata['target_directory'], 'debug', selected['name'])
assert os.path.isfile(binary), f'Compiled binary not found: {binary}'
assert os.stat(binary).st_mode & stat.S_IXUSR, 'Compiled binary is not executable'
with open(binary, 'rb') as f:
    assert f.read(4) == b'\x7fELF', 'Compiled artifact is not an ELF binary'

categorized = '/home/user/categorized'
if os.path.lexists(categorized):
    if os.path.isdir(categorized) and not os.path.islink(categorized):
        shutil.rmtree(categorized)
    else:
        os.unlink(categorized)
for category in ('elf', 'wal', 'gcode'):
    os.makedirs(os.path.join(categorized, category), exist_ok=True)

archive = '/home/user/dataset.cpack'
if os.path.lexists(archive):
    if os.path.isdir(archive) and not os.path.islink(archive):
        shutil.rmtree(archive)
    else:
        os.unlink(archive)

subprocess.run([binary], cwd=project, check=True, timeout=60)
RUN_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import hashlib
import pytest

RAW_DATA_DIR = "/home/user/raw_data"
CATEGORIZED_DIR = "/home/user/categorized"
CPACK_PATH = "/home/user/dataset.cpack"

def get_expected_files():
    """
    Returns a dictionary of expected valid files, their types, and absolute paths.
    """
    expected = []
    for root, _, files in os.walk(RAW_DATA_DIR):
        for f in files:
            abs_path = os.path.join(root, f)
            with open(abs_path, 'rb') as file_obj:
                header = file_obj.read(16)

            if header.startswith(b'\x7F\x45\x4C\x46'):
                file_type = 'elf'
            elif header.startswith(b'\x37\x7F\x06\x82') or header.startswith(b'\x37\x7F\x06\x83'):
                file_type = 'wal'
            elif header.startswith(b'; FLAVOR:'):
                file_type = 'gcode'
            else:
                continue

            expected.append((abs_path, file_type))
    return expected

def expected_archive_paths():
    paths = []
    for abs_path, file_type in get_expected_files():
        path_hash = hashlib.sha256(abs_path.encode('utf-8')).hexdigest()
        filename = os.path.basename(abs_path)
        paths.append(f"{file_type}/{path_hash}_{filename}")
    return sorted(paths)

def test_symlinks_created_correctly():
    expected_files = get_expected_files()
    assert len(expected_files) > 0, "No valid files found in raw_data"

    for abs_path, file_type in expected_files:
        path_hash = hashlib.sha256(abs_path.encode('utf-8')).hexdigest()
        filename = os.path.basename(abs_path)
        symlink_name = f"{path_hash}_{filename}"
        symlink_path = os.path.join(CATEGORIZED_DIR, file_type, symlink_name)

        assert os.path.islink(symlink_path), f"Expected symlink missing or not a symlink: {symlink_path}"
        target = os.readlink(symlink_path)
        assert target == abs_path, f"Symlink {symlink_path} points to {target}, expected {abs_path}"

def test_cpack_archive_exists_and_valid():
    assert os.path.isfile(CPACK_PATH), f"Archive file not found: {CPACK_PATH}"

    with open(CPACK_PATH, 'rb') as f:
        header = f.read(8)
        assert header == b'CPACK\0\0\0', f"Invalid CPACK header: {header}"

        prev_path = ""
        entry_count = 0
        archived_paths = []

        while True:
            len_bytes = f.read(2)
            if not len_bytes:
                break

            assert len(len_bytes) == 2, "Unexpected EOF reading path length"
            path_len = struct.unpack('<H', len_bytes)[0]

            path_bytes = f.read(path_len)
            assert len(path_bytes) == path_len, "Unexpected EOF reading path"
            path = path_bytes.decode('utf-8')

            assert path > prev_path, f"Paths are not lexicographically sorted: '{path}' came after '{prev_path}'"
            prev_path = path
            archived_paths.append(path)

            size_bytes = f.read(8)
            assert len(size_bytes) == 8, "Unexpected EOF reading uncompressed size"
            uncompressed_size = struct.unpack('<Q', size_bytes)[0]

            decoded = bytearray()
            while len(decoded) < uncompressed_size:
                pair = f.read(2)
                assert len(pair) == 2, "Unexpected EOF in RLE data"
                count, val = pair[0], pair[1]
                assert count > 0, "RLE count cannot be 0"
                decoded.extend([val] * count)

            assert len(decoded) == uncompressed_size, f"Decoded size mismatch for {path}"

            actual_path = os.path.join(CATEGORIZED_DIR, path)
            assert os.path.islink(actual_path), f"Path in archive does not point to a valid symlink: {actual_path}"

            with open(actual_path, 'rb') as orig:
                orig_data = orig.read()
                assert orig_data == decoded, f"Content mismatch for archived file {path}"

            entry_count += 1

        expected_count = len(get_expected_files())
        assert entry_count == expected_count, f"Archive contains {entry_count} files, expected {expected_count}"
        assert archived_paths == expected_archive_paths(), \
            f"Archive paths do not match expected categorized files: {archived_paths}"
TEST_EOF

if python3 /tmp/prepare_inputs.py && \
   python3 /tmp/build_and_run_submission.py && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
