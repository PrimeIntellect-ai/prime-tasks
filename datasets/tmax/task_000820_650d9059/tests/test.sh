#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import subprocess
import pytest

LEGACY_BIN = "/app/legacy_processor"
NEW_BIN = "/home/user/src/fast_processor"
SOURCE = "/home/user/src/fast_processor.c"
DATA_FILE = "/home/user/data/raw_payloads.bin"
HEX_TABLE = tuple(f"{i ^ 0x5A:02X}".encode("ascii") for i in range(256))


def expected_output(data):
    return b"".join(HEX_TABLE[b] for b in data)


def run_processor(path, data, timeout=15):
    return subprocess.run(
        [path], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=True, timeout=timeout
    )


@pytest.fixture(scope="session")
def rebuilt_bin():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."
    output = "/tmp/rebuilt_fast_processor"
    result = subprocess.run(
        ["gcc", "-O3", "-std=c11", SOURCE, "-o", output, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"fast_processor.c does not compile:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def test_anomalous_chunk():
    """Check that the anomalous chunk ID was correctly identified and written."""
    logs_dir = "/home/user/logs"
    anomalous_chunk_file = "/home/user/anomalous_chunk.txt"

    assert os.path.isfile(anomalous_chunk_file), f"{anomalous_chunk_file} does not exist."

    expected_chunk_id = None
    for filename in os.listdir(logs_dir):
        if filename.endswith(".log"):
            filepath = os.path.join(logs_dir, filename)
            with open(filepath, "r") as f:
                for line in f:
                    match = re.search(r"chunk_id=(\d+)\s+processing_time=(\d+)ms", line)
                    if match:
                        chunk_id = match.group(1)
                        proc_time = int(match.group(2))
                        if proc_time > 5000:
                            expected_chunk_id = chunk_id
                            break
        if expected_chunk_id:
            break

    assert expected_chunk_id is not None, "Could not find a chunk with processing_time > 5000ms in the logs."

    with open(anomalous_chunk_file, "r") as f:
        actual_chunk_id = f.read().strip()

    assert actual_chunk_id == expected_chunk_id, f"Expected chunk_id '{expected_chunk_id}', but got '{actual_chunk_id}' in {anomalous_chunk_file}."


def test_fast_processor_exists():
    """Check that fast_processor is an executable native binary."""
    assert os.path.isfile(NEW_BIN), f"Compiled binary {NEW_BIN} is missing."
    assert os.access(NEW_BIN, os.X_OK), f"Compiled binary {NEW_BIN} is not executable."
    with open(NEW_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_processor is not a compiled ELF executable."


def test_c_source_builds(rebuilt_bin):
    """Require the supplied C source to build into a native executable."""
    with open(rebuilt_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def test_equivalence():
    """Retain the original legacy equivalence checks."""
    for i in range(5):
        random_data = os.urandom(1000)

        try:
            p_legacy = run_processor(LEGACY_BIN, random_data)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"legacy_processor failed on random input {i}: {e}")

        try:
            p_new = run_processor(NEW_BIN, random_data)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"fast_processor failed on random input {i}: {e}")

        assert p_legacy.stdout == p_new.stdout, f"Output mismatch between legacy and fast processor on random input {i}."


def test_arbitrary_input_equivalence(rebuilt_bin):
    """Exercise boundary, binary, and unpredictable input sizes against derived answers."""
    cases = [
        b"",
        b"\x00",
        bytes(range(256)),
        os.urandom(999),
        os.urandom(1000),
        os.urandom(1001),
        os.urandom(4093),
        os.urandom(65537),
        os.urandom(180000 + int.from_bytes(os.urandom(2), "big") % 30001),
    ]

    for binary in (NEW_BIN, rebuilt_bin):
        for i, data in enumerate(cases):
            result = run_processor(binary, data)
            assert result.stdout == expected_output(data), f"Incorrect serialization from {binary} on case {i} ({len(data)} bytes)."
            assert result.stderr == b"", f"{binary} emitted unexpected standard error on case {i}."


def test_speedup(rebuilt_bin):
    """Check correctness on the benchmark payload and at least a 5x speedup."""
    assert os.path.isfile(DATA_FILE), f"Data file {DATA_FILE} is missing."
    with open(DATA_FILE, "rb") as f:
        data = f.read()
    expected = expected_output(data)

    t0 = time.perf_counter()
    subprocess.run([LEGACY_BIN], input=data, stdout=subprocess.DEVNULL, check=True, timeout=15)
    legacy_time = time.perf_counter() - t0

    t0 = time.perf_counter()
    new_result = subprocess.run(
        [NEW_BIN], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=True, timeout=15
    )
    new_time = time.perf_counter() - t0

    assert new_result.stdout == expected, "fast_processor produced incorrect output for the full benchmark payload."
    assert new_result.stderr == b"", "fast_processor emitted unexpected standard error for the benchmark payload."
    speedup = legacy_time / new_time
    assert speedup >= 5.0, f"Speedup threshold not met: achieved {speedup:.2f}x (legacy: {legacy_time:.3f}s, new: {new_time:.3f}s), expected >= 5.0x."

    t0 = time.perf_counter()
    rebuilt_result = subprocess.run(
        [rebuilt_bin], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=True, timeout=15
    )
    rebuilt_time = time.perf_counter() - t0

    assert rebuilt_result.stdout == expected, "The executable rebuilt from fast_processor.c produced incorrect benchmark output."
    assert rebuilt_result.stderr == b"", "The executable rebuilt from fast_processor.c emitted unexpected standard error."
    rebuilt_speedup = legacy_time / rebuilt_time
    assert rebuilt_speedup >= 5.0, f"Rebuilt C processor speedup threshold not met: achieved {rebuilt_speedup:.2f}x (legacy: {legacy_time:.3f}s, rebuilt: {rebuilt_time:.3f}s), expected >= 5.0x."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
