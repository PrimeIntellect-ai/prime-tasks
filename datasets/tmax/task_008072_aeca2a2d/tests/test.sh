#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile


def get_expected_files():
    """Derive the expected files from the original manifest and initial archive."""
    return [
        '/home/user/artifacts/binaries/app_v1.bin',
        '/home/user/artifacts/binaries/app_v3.bin',
        '/home/user/artifacts/binaries/app_v4.bin'
    ]


def test_archive_index_contents():
    index_path = '/home/user/archive_index.txt'
    assert os.path.isfile(index_path), f"Index file {index_path} is missing."

    with open(index_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = get_expected_files()
    assert len(lines) == len(expected), f"Expected {len(expected)} entries in index, found {len(lines)}."
    assert lines[0] == expected[0], "The first entry in the index must remain app_v1.bin"
    assert set(lines) == set(expected), f"Index contents do not match expected stale files. Expected {expected}, got {lines}."


def test_stale_archive_binary_format():
    archive_path = '/home/user/stale_archive.bin'
    assert os.path.isfile(archive_path), f"Archive file {archive_path} is missing."

    expected_paths = get_expected_files()
    expected_data = {}
    for path in expected_paths:
        with open(path, 'rb') as f:
            expected_data[path] = f.read()

    archived_paths = []
    with open(archive_path, 'rb') as f:
        while True:
            header = f.read(256)
            if not header:
                break
            assert len(header) == 256, "Archive header is not exactly 256 bytes."
            path_bytes = header.rstrip(b'\x00')
            path_str = path_bytes.decode('utf-8')
            archived_paths.append(path_str)
            assert path_str in expected_data, f"Unexpected file path found in archive: {path_str}"

            size_data = f.read(8)
            assert len(size_data) == 8, f"Incomplete size header for {path_str}."
            size = struct.unpack('<Q', size_data)[0]
            expected_size = len(expected_data[path_str])
            assert size == expected_size, f"Size header for {path_str} is {size}, expected {expected_size}."

            payload = f.read(size)
            assert len(payload) == size, f"Incomplete payload for {path_str}. Expected {size} bytes, got {len(payload)}."
            assert payload == expected_data[path_str], f"Payload data mismatch for {path_str}."

    assert archived_paths[0] == expected_paths[0], "The first archived file must remain app_v1.bin"
    assert set(archived_paths) == set(expected_paths), f"Archived paths do not match expected. Expected {expected_paths}, got {archived_paths}."


def test_scripts_exist():
    assert os.path.isfile('/home/user/find_stale.sh'), "Script /home/user/find_stale.sh is missing."
    assert os.access('/home/user/find_stale.sh', os.X_OK), "Script /home/user/find_stale.sh is not executable."
    assert os.path.isfile('/home/user/archiver.c'), "Source file /home/user/archiver.c is missing."
    assert os.path.isfile('/home/user/archiver'), "Compiled executable /home/user/archiver is missing."
    assert os.access('/home/user/archiver', os.X_OK), "Executable /home/user/archiver is not executable."


def _archive_record(path, data):
    encoded = path.encode('utf-8')
    assert len(encoded) < 256
    return encoded + b'\x00' * (256 - len(encoded)) + struct.pack('<Q', len(data)) + data


def _parse_archive(blob):
    records = []
    offset = 0
    while offset < len(blob):
        header = blob[offset:offset + 256]
        assert len(header) == 256, "Archive contains a partial filename header."
        offset += 256
        nul = header.find(b'\x00')
        assert nul >= 0, "Filename header is not null-terminated."
        assert header[nul:] == b'\x00' * (256 - nul), "Filename header is not null-padded."
        path = header[:nul].decode('utf-8')

        size_bytes = blob[offset:offset + 8]
        assert len(size_bytes) == 8, "Archive contains a partial size header."
        offset += 8
        size = struct.unpack('<Q', size_bytes)[0]
        payload = blob[offset:offset + size]
        assert len(payload) == size, "Archive contains a partial payload."
        offset += size
        records.append((path, payload))
    return records


def test_tools_execute_on_derived_inputs_and_are_incremental():
    manifest = '/home/user/artifacts/manifest.txt'
    index = '/home/user/archive_index.txt'
    archive = '/home/user/stale_archive.bin'
    saved = {p: open(p, 'rb').read() if os.path.exists(p) else None for p in (manifest, index, archive)}
    work = tempfile.mkdtemp(prefix='stale_verifier_', dir='/home/user')

    try:
        # The submitted source must still compile, while the submitted executable itself
        # is what is exercised below.
        compiled = os.path.join(work, 'compiled_archiver')
        subprocess.run(
            ['gcc', '-std=c11', '-Wall', '-Wextra', '/home/user/archiver.c', '-o', compiled],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )

        already = os.path.join(work, 'already.bin')
        prefix_extension = already + '.more'
        fresh = os.path.join(work, 'fresh.bin')
        active = os.path.join(work, 'active.bin')
        status_lookalike = os.path.join(work, 'lookalike.bin')
        missing = os.path.join(work, 'missing.bin')

        data = {
            already: b'PREEXISTING\x00DATA',
            prefix_extension: b'PREFIX-DIFFERENT\x00\xff',
            fresh: bytes(range(256)) + b'\x00tail',
            active: b'ACTIVE',
            status_lookalike: b'NOT EXACT STATUS'
        }
        for path, payload in data.items():
            with open(path, 'wb') as f:
                f.write(payload)

        with open(manifest, 'w') as f:
            f.write(f"101 {already} 2020-01-01 STALE\n")
            f.write(f"102 {active} 2020-01-01 ACTIVE\n")
            f.write(f"103 {missing} 2020-01-01 STALE\n")
            f.write(f"104 {prefix_extension} 2020-01-01 STALE\n")
            f.write(f"105 {status_lookalike} 2020-01-01 STALEISH\n")
            f.write(f"106 {fresh} 2020-01-01 STALE\n")

        finder = subprocess.run(
            ['/home/user/find_stale.sh'], check=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=20
        )
        expected_paths = [already, prefix_extension, fresh]
        assert finder.stdout.splitlines() == expected_paths, (
            f"find_stale.sh produced {finder.stdout.splitlines()}, expected {expected_paths}."
        )

        with open(index, 'w') as f:
            f.write(already + '\n')
        initial_archive = _archive_record(already, data[already])
        with open(archive, 'wb') as f:
            f.write(initial_archive)

        subprocess.run(
            ['/home/user/archiver'], input=finder.stdout.encode(), check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )

        with open(index, 'r') as f:
            index_lines = f.read().splitlines()
        assert index_lines == expected_paths, f"Incremental index is incorrect: {index_lines}"

        with open(archive, 'rb') as f:
            first_result = f.read()
        assert _parse_archive(first_result) == [
            (already, data[already]),
            (prefix_extension, data[prefix_extension]),
            (fresh, data[fresh])
        ], "The executable did not append records in the required binary format."

        # Reprocessing the same paths must append neither index entries nor archive bytes.
        subprocess.run(
            ['/home/user/archiver'], input=finder.stdout.encode(), check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        with open(index, 'rb') as f:
            second_index = f.read()
        with open(archive, 'rb') as f:
            second_archive = f.read()
        assert second_index == ('\n'.join(expected_paths) + '\n').encode()
        assert second_archive == first_result, "Repeated input was archived more than once."
    finally:
        for path, contents in saved.items():
            if contents is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, 'wb') as f:
                    f.write(contents)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
