#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import stat
import struct
import pytest
from collections import defaultdict


def compute_hash(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    total_sum = 0
    for i in range(0, len(data) - (len(data) % 4), 4):
        val = struct.unpack('<I', data[i:i+4])[0]
        total_sum = (total_sum + val) & 0xFFFFFFFF

    rem = len(data) % 4
    if rem > 0:
        chunk = data[-rem:] + b'\x00' * (4 - rem)
        val = struct.unpack('<I', chunk)[0]
        total_sum = (total_sum + val) & 0xFFFFFFFF

    return total_sum ^ 0xDEADBEEF


def assert_original_fixture(blocks_dir):
    size = 1048576
    expected = {
        **{f"blockA_{i}.dat": 1 for i in range(4)},
        **{f"blockB_{i}.dat": 2 for i in range(3)},
        **{f"blockC_{i}.dat": 3 + i for i in range(3)},
    }

    actual = set(os.listdir(blocks_dir))
    assert actual == set(expected), (
        f"Block fixture was modified: expected {sorted(expected)}, got {sorted(actual)}"
    )

    inodes = set()
    for name, byte_value in expected.items():
        path = os.path.join(blocks_dir, name)
        info = os.lstat(path)
        assert stat.S_ISREG(info.st_mode), f"{name} is not a regular file"
        assert info.st_size == size, f"Unexpected size for {name}: {info.st_size}"
        assert info.st_nlink == 1, f"{name} was already hardlinked before verification"
        inode = (info.st_dev, info.st_ino)
        assert inode not in inodes, f"{name} shares an inode before the DEDUP command"
        inodes.add(inode)

        with open(path, 'rb') as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                assert chunk == bytes([byte_value]) * len(chunk), (
                    f"Unexpected content in {name}"
                )


def test_dedup_daemon_protocol_and_results():
    blocks_dir = "/data/blocks"
    wal_file = "/data/dedup.wal"

    # Ensure expectations cannot be weakened by deleting, replacing, or
    # pre-deduplicating the fixture before this verifier starts.
    assert_original_fixture(blocks_dir)

    # 1. Gather initial state of files
    files = [f for f in os.listdir(blocks_dir) if os.path.isfile(os.path.join(blocks_dir, f))]

    # Group by our own hash
    groups = defaultdict(list)
    for f in files:
        path = os.path.join(blocks_dir, f)
        h = compute_hash(path)
        groups[h].append(f)

    # Sort each group lexicographically
    for h in groups:
        groups[h].sort()

    # Calculate expected freed bytes
    expected_freed = 0
    for h, group in groups.items():
        if len(group) > 1:
            for f in group[1:]:
                expected_freed += os.path.getsize(os.path.join(blocks_dir, f))

    # 2. Connect to daemon and send command
    try:
        s = socket.create_connection(("127.0.0.1", 8888), timeout=5.0)
    except Exception as e:
        pytest.fail(f"Could not connect to daemon on port 8888: {e}")

    try:
        s.sendall(b"DEDUP /data/blocks\n")
        response = b""
        while b"\n" not in response:
            chunk = s.recv(1024)
            if not chunk:
                break
            response += chunk
    except Exception as e:
        pytest.fail(f"Error communicating with daemon: {e}")
    finally:
        s.close()

    # 3. Assert response
    expected_response = f"FREED {expected_freed}\n".encode()
    assert response == expected_response, f"Expected response {expected_response}, got {response}"

    # 4. Verify hardlinks
    for h, group in groups.items():
        if len(group) > 1:
            kept_file = os.path.join(blocks_dir, group[0])
            kept_inode = os.stat(kept_file).st_ino
            for f in group[1:]:
                replaced_file = os.path.join(blocks_dir, f)
                replaced_inode = os.stat(replaced_file).st_ino
                assert kept_inode == replaced_inode, f"File {f} is not hardlinked to {group[0]}"

    # 5. Verify WAL
    assert os.path.exists(wal_file), f"WAL file {wal_file} does not exist"

    with open(wal_file, 'rb') as f:
        wal_data = f.read()

    assert len(wal_data) % 134 == 0, f"WAL file size {len(wal_data)} is not a multiple of 134"

    entries = []
    for i in range(0, len(wal_data), 134):
        chunk = wal_data[i:i+134]
        magic = chunk[0:2]
        assert magic == b'\xda\x7a', f"Invalid magic bytes in WAL at offset {i}: {magic}"

        checksum = struct.unpack('<I', chunk[2:6])[0]
        kept_name = chunk[6:70].rstrip(b'\x00').decode('utf-8')
        replaced_name = chunk[70:134].rstrip(b'\x00').decode('utf-8')
        entries.append((checksum, kept_name, replaced_name))

    # Check that all expected replacements are in the WAL.
    # The WAL might contain basenames or full paths, handle both.
    for h, group in groups.items():
        if len(group) > 1:
            kept = group[0]
            for replaced in group[1:]:
                found = False
                for csum, k_name, r_name in entries:
                    if csum == h and (k_name == kept or k_name.endswith("/" + kept)) and (r_name == replaced or r_name.endswith("/" + replaced)):
                        found = True
                        break
                assert found, f"Replacement of {replaced} by {kept} not found in WAL"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
