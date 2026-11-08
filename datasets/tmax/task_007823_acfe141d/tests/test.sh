#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import stat
import subprocess
import pytest


def encode_rle(data: bytes) -> bytes:
    """Helper to generate expected RLE encoded data."""
    if not data:
        return b""
    result = bytearray()
    current_byte = data[0]
    count = 1
    for i in range(1, len(data)):
        if data[i] == current_byte and count < 255:
            count += 1
        else:
            result.append(current_byte)
            result.append(count)
            current_byte = data[i]
            count = 1
    result.append(current_byte)
    result.append(count)
    return bytes(result)


def test_ignored_files_exist():
    # Files that should NOT be processed must remain untouched
    access_dat = '/home/user/logs_archive/web/access.dat'
    small_log = '/home/user/logs_archive/db/small.log'

    assert os.path.exists(access_dat), f"Ignored file {access_dat} was incorrectly deleted."
    assert os.path.exists(small_log), f"Ignored file {small_log} was incorrectly deleted."

    # Verify contents remain the same
    with open(access_dat, 'rb') as f:
        assert f.read() == b'C' * 15000, f"Contents of {access_dat} were altered."
    with open(small_log, 'rb') as f:
        assert f.read() == b'D' * 10240, f"Contents of {small_log} were altered."


def test_processed_files_deleted():
    # Files that SHOULD be processed must be deleted after processing
    large1_log = '/home/user/logs_archive/web/large1.log'
    large2_log = '/home/user/logs_archive/db/large2.log'

    assert not os.path.exists(large1_log), f"Processed file {large1_log} was not deleted."
    assert not os.path.exists(large2_log), f"Processed file {large2_log} was not deleted."


def test_compressed_chunks_created():
    compressed_dir = '/home/user/compressed_logs'
    assert os.path.isdir(compressed_dir), f"Directory {compressed_dir} does not exist."

    expected_chunks = [
        'large1.log.chunk0.rle',
        'large1.log.chunk1.rle',
        'large1.log.chunk2.rle',
        'large2.log.chunk0.rle',
        'large2.log.chunk1.rle',
        'large2.log.chunk2.rle',
    ]

    for chunk in expected_chunks:
        chunk_path = os.path.join(compressed_dir, chunk)
        assert os.path.exists(chunk_path), f"Expected chunk file {chunk_path} is missing."


def test_rle_encoding_correctness():
    compressed_dir = '/home/user/compressed_logs'

    # Define the original raw data for each chunk
    chunk_data = {
        'large1.log.chunk0.rle': b'A' * 5120,
        'large1.log.chunk1.rle': b'B' * 5120,
        'large1.log.chunk2.rle': b'C' * 1760,
        'large2.log.chunk0.rle': b'X' * 5000 + b'Y' * 120,
        'large2.log.chunk1.rle': b'Y' * 4880 + b'Z' * 240,
        'large2.log.chunk2.rle': b'Z' * 4760,
    }

    for chunk_name, raw_data in chunk_data.items():
        chunk_path = os.path.join(compressed_dir, chunk_name)
        if not os.path.exists(chunk_path):
            pytest.fail(f"Cannot verify encoding because {chunk_path} is missing.")

        with open(chunk_path, 'rb') as f:
            actual_rle = f.read()

        expected_rle = encode_rle(raw_data)
        assert actual_rle == expected_rle, f"RLE encoding for {chunk_name} is incorrect."


def test_archiver_artifacts_exist_and_work_on_dynamic_inputs():
    source = '/home/user/archiver.cpp'
    executable = '/home/user/archiver'

    assert os.path.isfile(source), f"Required source file {source} is missing."
    assert os.path.getsize(source) > 0, f"Required source file {source} is empty."
    assert os.path.isfile(executable), f"Required executable {executable} is missing."
    assert stat.S_ISREG(os.stat(executable).st_mode), f"{executable} is not a regular file."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{executable} is not a compiled ELF executable."

    token = secrets.token_hex(12)
    nested = os.path.join('/home/user/logs_archive', 'verification_' + token, 'deep', 'nested')
    os.makedirs(nested, exist_ok=False)

    matching_name = f'dynamic_{token}.log'
    matching_path = os.path.join(nested, matching_name)
    exact_name = f'exact_{token}.log'
    exact_path = os.path.join(nested, exact_name)
    wrong_ext_name = f'wrongext_{token}.dat'
    wrong_ext_path = os.path.join(nested, wrong_ext_name)

    # Randomized values and payload prevent a fixed set of precomputed outputs.
    run_a = secrets.randbelow(256)
    run_b = (run_a + 1 + secrets.randbelow(255)) % 256
    raw = bytes([run_a]) * 256 + os.urandom(4864)
    raw += bytes([run_b]) * 700 + os.urandom(4420)
    raw += os.urandom(2760)
    assert len(raw) == 13000

    exact_data = os.urandom(10240)
    wrong_ext_data = os.urandom(11000)
    with open(matching_path, 'wb') as f:
        f.write(raw)
    with open(exact_path, 'wb') as f:
        f.write(exact_data)
    with open(wrong_ext_path, 'wb') as f:
        f.write(wrong_ext_data)

    subprocess.run([executable], cwd='/home/user', check=True, timeout=30)

    assert not os.path.exists(matching_path), "A dynamically created matching nested .log was not deleted."
    assert os.path.exists(exact_path), "A .log of exactly 10,240 bytes was incorrectly processed."
    assert os.path.exists(wrong_ext_path), "A large file without the exact .log extension was incorrectly processed."
    with open(exact_path, 'rb') as f:
        assert f.read() == exact_data, "The exact-threshold .log was altered."
    with open(wrong_ext_path, 'rb') as f:
        assert f.read() == wrong_ext_data, "The non-.log file was altered."

    compressed_dir = '/home/user/compressed_logs'
    chunks = [raw[i:i + 5120] for i in range(0, len(raw), 5120)]
    assert len(chunks) == 3
    for index, chunk in enumerate(chunks):
        output = os.path.join(compressed_dir, f'{matching_name}.chunk{index}.rle')
        assert os.path.isfile(output), f"Dynamic output chunk {output} is missing."
        with open(output, 'rb') as f:
            assert f.read() == encode_rle(chunk), f"Dynamic output chunk {index} has incorrect RLE data."

    assert not os.path.exists(os.path.join(compressed_dir, f'{matching_name}.chunk3.rle')), \
        "The archiver created an extra chunk."
    assert not os.path.exists(os.path.join(compressed_dir, f'{exact_name}.chunk0.rle')), \
        "The exact-threshold .log incorrectly produced output."
    assert not os.path.exists(os.path.join(compressed_dir, f'{wrong_ext_name}.chunk0.rle')), \
        "The non-.log file incorrectly produced output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
