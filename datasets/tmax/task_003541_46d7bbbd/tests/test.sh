#!/bin/bash
set -u
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

PROCESSOR=/home/user/dataset/processor
SOURCE=/home/user/dataset/processor.cpp

[ -f "$SOURCE" ] || fail
[ -f "$PROCESSOR" ] || fail
[ -x "$PROCESSOR" ] || fail

# Ensure the submitted source is valid C++ and the submitted executable is an ELF binary.
g++ -std=c++17 -fsyntax-only "$SOURCE" >/tmp/processor_compile.log 2>&1 || fail
python3 - <<'PY' || exit 10
with open('/home/user/dataset/processor', 'rb') as f:
    assert f.read(4) == b'\x7fELF', 'processor is not an ELF executable'
PY
[ $? -eq 0 ] || fail

# Remove any pre-fabricated results before exercising the watcher.
mkdir -p /home/user/dataset/incoming /home/user/dataset/chunks /home/user/dataset/archive
find /home/user/dataset/incoming -mindepth 1 -maxdepth 1 -delete || fail
find /home/user/dataset/chunks -mindepth 1 -maxdepth 1 -delete || fail
find /home/user/dataset/archive -mindepth 1 -maxdepth 1 -delete || fail
rm -f /home/user/dataset/manifest.txt /tmp/expected_inputs.json

# Start the actual submitted artifact before producing readiness markers.
timeout 30s "$PROCESSOR" >/tmp/processor.stdout 2>/tmp/processor.stderr &
processor_job=$!

# Generate fresh inputs at verification time. Record their hashes independently so
# modifications to the incoming files cannot make fabricated chunks self-consistent.
python3 - <<'PY' || fail
import hashlib
import json
import os
import time

incoming = '/home/user/dataset/incoming'
expected = {}

for name, size in [('dataset_A.dat', 250000), ('dataset_B.dat', 80000)]:
    path = os.path.join(incoming, name)
    remaining = size
    h = hashlib.sha256()
    with open(path, 'wb') as f:
        while remaining:
            data = os.urandom(min(65536, remaining))
            f.write(data)
            h.update(data)
            remaining -= len(data)
        f.flush()
        os.fsync(f.fileno())
    expected[name] = {'size': size, 'sha256': h.hexdigest()}
    ready = path[:-4] + '.ready'
    with open(ready, 'a'):
        pass
    # Give polling implementations time to observe each completed dataset.
    time.sleep(2)

with open('/tmp/expected_inputs.json', 'w') as f:
    json.dump(expected, f)

with open(os.path.join(incoming, 'DONE.ready'), 'a'):
    pass
PY

if wait "$processor_job"; then
    :
else
    fail
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os


def file_sha256(path):
    sha256 = hashlib.sha256()
    with open(path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256.update(byte_block)
    return sha256.hexdigest()


def test_manifest_exists_and_line_count():
    manifest_path = "/home/user/dataset/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in manifest.txt, found {len(lines)}"


def test_hard_links_correct():
    files_to_check = ["dataset_A.dat", "dataset_B.dat"]

    for filename in files_to_check:
        incoming_path = os.path.join("/home/user/dataset/incoming", filename)
        archive_path = os.path.join("/home/user/dataset/archive", filename)

        assert os.path.isfile(incoming_path), f"Original file missing: {incoming_path}"
        assert os.path.isfile(archive_path), f"Archived file missing: {archive_path}"

        stat_incoming = os.stat(incoming_path)
        stat_archive = os.stat(archive_path)

        assert stat_incoming.st_ino == stat_archive.st_ino, (
            f"File {archive_path} is not a hard link to {incoming_path} "
            f"(inodes: {stat_archive.st_ino} vs {stat_incoming.st_ino})"
        )


def test_chunk_files_sizes():
    expected_chunks = {
        "dataset_A_part0.bin": 100000,
        "dataset_A_part1.bin": 100000,
        "dataset_A_part2.bin": 50000,
        "dataset_B_part0.bin": 80000,
    }

    chunks_dir = "/home/user/dataset/chunks"
    assert os.path.isdir(chunks_dir), f"Chunks directory missing at {chunks_dir}"

    for chunk_name, expected_size in expected_chunks.items():
        chunk_path = os.path.join(chunks_dir, chunk_name)
        assert os.path.isfile(chunk_path), f"Expected chunk file missing: {chunk_path}"

        actual_size = os.path.getsize(chunk_path)
        assert actual_size == expected_size, (
            f"Chunk {chunk_name} has incorrect size. "
            f"Expected {expected_size}, got {actual_size}"
        )


def test_inputs_unchanged_and_chunks_match_dat_files():
    with open('/tmp/expected_inputs.json', 'r') as f:
        expected_inputs = json.load(f)

    incoming_dir = '/home/user/dataset/incoming'
    chunks_dir = '/home/user/dataset/chunks'
    chunk_map = {
        'dataset_A.dat': [
            'dataset_A_part0.bin',
            'dataset_A_part1.bin',
            'dataset_A_part2.bin',
        ],
        'dataset_B.dat': ['dataset_B_part0.bin'],
    }

    for dat_name, chunk_names in chunk_map.items():
        dat_path = os.path.join(incoming_dir, dat_name)
        assert os.path.getsize(dat_path) == expected_inputs[dat_name]['size']
        assert file_sha256(dat_path) == expected_inputs[dat_name]['sha256'], (
            f"Input file was modified: {dat_name}"
        )

        with open(dat_path, 'rb') as f:
            original = f.read()
        rebuilt = b''
        for chunk_name in chunk_names:
            with open(os.path.join(chunks_dir, chunk_name), 'rb') as f:
                rebuilt += f.read()
        assert rebuilt == original, f"Chunks do not reproduce {dat_name} exactly"


def test_manifest_checksums():
    manifest_path = "/home/user/dataset/manifest.txt"
    chunks_dir = "/home/user/dataset/chunks"

    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, "Manifest should have exactly 4 entries."

    manifest_data = {}
    for line in lines:
        parts = line.split()
        assert len(parts) >= 2, f"Invalid manifest line format: '{line}'"
        checksum = parts[0]
        filename = parts[-1].lstrip("*")
        manifest_data[filename] = checksum

    expected_filenames = [
        "dataset_A_part0.bin",
        "dataset_A_part1.bin",
        "dataset_A_part2.bin",
        "dataset_B_part0.bin"
    ]

    for expected_file in expected_filenames:
        matching_keys = [k for k in manifest_data.keys() if k.endswith(expected_file)]
        assert matching_keys, f"File {expected_file} not found in manifest.txt"

        manifest_filename = matching_keys[0]
        expected_checksum = manifest_data[manifest_filename]

        chunk_path = os.path.join(chunks_dir, expected_file)
        assert os.path.isfile(chunk_path), f"Chunk file {chunk_path} missing"

        actual_checksum = file_sha256(chunk_path)
        assert actual_checksum == expected_checksum, (
            f"Checksum mismatch for {expected_file}. "
            f"Manifest says {expected_checksum}, actual is {actual_checksum}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
