#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import stat
import struct
import subprocess
import tempfile

import pytest

FIXTURES = {
    "/home/user/storage_pool/backups/db_dump.blob": [
        (1690000000, "old_data1.bin", b"A", 500000),
        (1710000000, "new_data1.bin", b"B", 600000),
    ],
    "/home/user/storage_pool/misc/logs.blob": [
        (1705000000, "log_A.txt", b"C", 800000),
        (1699999999, "log_B.txt", b"D", 400000),
        (1720000000, "log_C.txt", b"E", 200000),
    ],
    "/home/user/storage_pool/misc/tiny.blob": [
        (1710000000, "tiny.bin", b"F", 1000),
    ],
    "/home/user/storage_pool/backups/archive.dat": [
        (1710000000, "dat.bin", b"G", 2000000),
    ],
}


def assert_original_fixtures_intact():
    for filepath, chunks in FIXTURES.items():
        try:
            mode = os.lstat(filepath).st_mode
        except FileNotFoundError:
            pytest.fail(f"Original fixture is missing: {filepath}")
        assert stat.S_ISREG(mode), f"Original fixture is not a regular file: {filepath}"

        expected_size = sum(32 + payload_size for _, _, _, payload_size in chunks)
        assert os.path.getsize(filepath) == expected_size, f"Original fixture size changed: {filepath}"

        with open(filepath, "rb") as f:
            for timestamp, filename, fill_byte, payload_size in chunks:
                expected_header = struct.pack(
                    "<4s Q I 16s",
                    b"BLOB",
                    timestamp,
                    payload_size,
                    filename.encode("ascii"),
                )
                assert f.read(32) == expected_header, f"Original fixture header changed: {filepath}"

                remaining = payload_size
                while remaining:
                    amount = min(65536, remaining)
                    data = f.read(amount)
                    assert data == fill_byte * amount, f"Original fixture payload changed: {filepath}"
                    remaining -= amount

            assert f.read(1) == b"", f"Original fixture has trailing data: {filepath}"


def parse_blob_file(filepath):
    """Yields (timestamp, chunk_data) for each chunk in the blob file."""
    with open(filepath, 'rb') as f:
        while True:
            header = f.read(32)
            if not header:
                break
            if len(header) < 32:
                pytest.fail(f"File {filepath} has an incomplete header.")

            magic, timestamp, payload_size, filename = struct.unpack("<4s Q I 16s", header)
            if magic != b"BLOB":
                pytest.fail(f"File {filepath} has invalid magic bytes: {magic}")

            payload = f.read(payload_size)
            if len(payload) < payload_size:
                pytest.fail(f"File {filepath} has an incomplete payload.")

            yield timestamp, header + payload


def get_expected_files_and_sizes():
    # Expectations may safely be derived from the pool only after proving that
    # the original agent-writable fixtures are still present and unchanged.
    assert_original_fixtures_intact()

    storage_pool = "/home/user/storage_pool"
    target_files = []
    total_original_bytes = 0
    total_compacted_bytes = 0
    expected_compacted_contents = {}

    for root, _, files in os.walk(storage_pool):
        for file in files:
            if file.endswith(".blob"):
                filepath = os.path.join(root, file)
                size = os.path.getsize(filepath)
                if size > 1048576:
                    target_files.append(file)
                    total_original_bytes += size

                    compacted_content = bytearray()
                    for timestamp, chunk_data in parse_blob_file(filepath):
                        if timestamp > 1700000000:
                            compacted_content.extend(chunk_data)

                    expected_compacted_contents[file] = bytes(compacted_content)
                    total_compacted_bytes += len(compacted_content)

    return expected_compacted_contents, total_original_bytes, total_compacted_bytes


def run_script(input_path, output_path, memory_limit=None, timeout=60):
    script = "/home/user/compact_blobs.py"
    assert os.path.isfile(script), f"Required script {script} is missing."
    assert not os.path.islink(script), f"Required script {script} must be a regular file."

    preexec_fn = None
    if memory_limit is not None:
        def apply_limit():
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))
        preexec_fn = apply_limit

    result = subprocess.run(
        ["python3", script, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=preexec_fn,
    )
    assert result.returncode == 0, (
        f"compact_blobs.py failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )


def test_original_fixtures_intact():
    assert_original_fixtures_intact()


def test_compact_script_behavior_and_streaming():
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "generated.blob")
        output_path = os.path.join(tmpdir, "generated-output.blob")

        chunks = [
            (1699999999, b"old.bin", os.urandom(137)),
            (1700000000, b"edge.bin", os.urandom(251)),
            (1700000001, b"new.bin", os.urandom(4099)),
            (1800000000, b"empty.bin", b""),
        ]
        expected = bytearray()
        with open(input_path, "wb") as f:
            for timestamp, filename, payload in chunks:
                header = struct.pack("<4s Q I 16s", b"BLOB", timestamp, len(payload), filename)
                f.write(header)
                f.write(payload)
                if timestamp > 1700000000:
                    expected.extend(header)
                    expected.extend(payload)

        run_script(input_path, output_path)
        assert os.path.isfile(output_path), "compact_blobs.py did not create its requested output file."
        with open(output_path, "rb") as f:
            assert f.read() == bytes(expected), "compact_blobs.py failed generated behavioral inputs."

        # A retained payload larger than the process memory allowance ensures
        # that payload copying is performed incrementally rather than loaded in full.
        large_input = os.path.join(tmpdir, "large.blob")
        large_output = os.path.join(tmpdir, "large-output.blob")
        large_size = 80 * 1024 * 1024
        old_payload = 1024 * 1024
        old_header = struct.pack("<4s Q I 16s", b"BLOB", 1600000000, old_payload, b"old-large.bin")
        keep_header = struct.pack("<4s Q I 16s", b"BLOB", 1800000000, large_size, b"keep-large.bin")

        with open(large_input, "wb") as f:
            f.write(old_header)
            block = b"X" * 65536
            for _ in range(old_payload // len(block)):
                f.write(block)
            f.write(keep_header)
            f.seek(large_size - 1, os.SEEK_CUR)
            f.write(b"\x00")

        run_script(large_input, large_output, memory_limit=64 * 1024 * 1024)
        assert os.path.getsize(large_output) == 32 + large_size, "Streaming-test output has the wrong size."
        with open(large_output, "rb") as f:
            assert f.read(32) == keep_header, "Streaming-test output did not preserve the retained header."
            remaining = large_size
            while remaining:
                amount = min(1024 * 1024, remaining)
                assert f.read(amount) == b"\x00" * amount, "Streaming-test output corrupted payload data."
                remaining -= amount
            assert f.read(1) == b"", "Streaming-test output has trailing data."


def test_compacted_pool_directory_exists():
    assert os.path.isdir("/home/user/compacted_pool"), "/home/user/compacted_pool directory is missing."


def test_compacted_files_correctness():
    expected_contents, _, _ = get_expected_files_and_sizes()
    compacted_pool = "/home/user/compacted_pool"

    assert os.path.isdir(compacted_pool), "Compacted pool directory missing."

    actual_files = set(os.listdir(compacted_pool))
    expected_files = set(expected_contents.keys())

    assert actual_files == expected_files, f"Expected files {expected_files} in compacted_pool, but found {actual_files}."

    for filename, expected_data in expected_contents.items():
        filepath = os.path.join(compacted_pool, filename)
        with open(filepath, 'rb') as f:
            actual_data = f.read()
        assert actual_data == expected_data, f"The compacted file {filename} does not contain the exact expected valid chunks."


def test_reclaimed_space_report():
    report_path = "/home/user/reclaimed_space.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    _, expected_original, expected_compacted = get_expected_files_and_sizes()

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected_content = f"{expected_original} {expected_compacted}"
    assert content == expected_content, f"Expected report content '{expected_content}', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
