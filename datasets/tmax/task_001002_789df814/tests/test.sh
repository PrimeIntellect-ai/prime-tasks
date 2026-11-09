#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import struct
import subprocess
import pytest

LIB_PATH = '/app/libwalparse-1.0/libwalparse.a'
AGENT_PATH = '/home/user/archiver'
SOURCE_PATH = '/home/user/archiver.cpp'
ORACLE_PATH = '/opt/oracle/wal_archiver'
MAGIC = 0x57414C21


def test_libwalparse_a_exists():
    assert os.path.isfile(LIB_PATH), "libwalparse.a was not built"


def test_archiver_source_exists():
    assert os.path.isfile(SOURCE_PATH), "/home/user/archiver.cpp is missing"


def test_archiver_executable_exists():
    assert os.path.isfile(AGENT_PATH), "/home/user/archiver executable is missing"
    assert os.access(AGENT_PATH, os.X_OK), "/home/user/archiver is not executable"


def test_archiver_is_not_reference_binary():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), \
        "Agent executable must not be a byte-identical copy of the reference binary"


def make_frame(page_id, data):
    # parse_wal_frame reads all integer fields directly on this little-endian host.
    return struct.pack('<I', MAGIC) + struct.pack('<I', page_id) + \
        struct.pack('<H', len(data)) + data


def expected_record(page_id, data):
    checksum = 0
    for byte in data:
        checksum ^= byte
    return struct.pack('<I', page_id) + bytes([checksum])


def test_known_valid_frames_produce_output():
    frames = [
        (2, b'\x01\x02\x03'),
        (3, b'ignored'),
        (0xFFFFFFFE, bytes(range(256))),
        (0, b''),
    ]
    input_data = b''.join(make_frame(page_id, data) for page_id, data in frames)
    expected = b''.join(
        expected_record(page_id, data)
        for page_id, data in frames
        if page_id % 2 == 0
    )

    proc = subprocess.run(
        [AGENT_PATH], input=input_data, capture_output=True, timeout=2
    )
    assert proc.stdout == expected


def generate_fuzz_case(rng):
    out = bytearray()
    expected = bytearray()

    # Always begin with a valid even frame so an implementation that merely
    # consumes stdin and emits nothing cannot pass.
    frame_count = rng.randint(4, 24)
    for index in range(frame_count):
        page_id = rng.getrandbits(32)
        if index == 0:
            page_id &= 0xFFFFFFFE
        data = rng.randbytes(rng.randint(0, 256))
        out.extend(make_frame(page_id, data))
        if page_id % 2 == 0:
            expected.extend(expected_record(page_id, data))

    # Exercise the required stop-on-error behavior after the valid prefix.
    tail_kind = rng.randrange(3)
    if tail_kind == 0:
        out.extend(b'BAD!')
        out.extend(rng.randbytes(rng.randint(0, 64)))
    elif tail_kind == 1:
        partial = make_frame(rng.getrandbits(32), rng.randbytes(rng.randint(1, 32)))
        out.extend(partial[:rng.randint(1, len(partial) - 1)])

    return bytes(out), bytes(expected)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"

    rng = random.Random(42)
    for i in range(500):
        input_data, expected = generate_fuzz_case(rng)

        oracle_proc = subprocess.run(
            [ORACLE_PATH], input=input_data, capture_output=True, timeout=2
        )
        agent_proc = subprocess.run(
            [AGENT_PATH], input=input_data, capture_output=True, timeout=2
        )

        assert oracle_proc.stdout == expected, \
            f"Reference mismatch on fuzz iteration {i}"

        if agent_proc.stdout != expected:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n"
                f"Input length: {len(input_data)}\n"
                f"Expected output length: {len(expected)}\n"
                f"Agent output length: {len(agent_proc.stdout)}\n"
                f"Expected output (hex): {expected.hex()}\n"
                f"Agent output (hex): {agent_proc.stdout.hex()}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
