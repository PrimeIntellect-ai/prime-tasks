#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import pytest

def test_compromised_user():
    path = "/home/user/compromised_user.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "mallory", f"Expected 'mallory', found '{content}'"

def test_string_address():
    bin_path = "/home/user/fw_updater"
    assert os.path.isfile(bin_path), f"Missing binary: {bin_path}"

    with open(bin_path, "rb") as f:
        data = f.read()

    target = b"ALGO: NONE"
    offset = data.find(target)
    assert offset != -1, f"String '{target.decode()}' not found in binary"

    # Parse ELF64 Program Headers to find the virtual address
    # e_phoff is at 0x20, e_phentsize at 0x36, e_phnum at 0x38
    e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
    e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
    e_phnum = struct.unpack_from('<H', data, 0x38)[0]

    vaddr = None
    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from('<IIQQQQQQ', data, ph_offset)
        if p_type == 1:  # PT_LOAD
            if p_offset <= offset < p_offset + p_filesz:
                vaddr = p_vaddr + (offset - p_offset)
                break

    assert vaddr is not None, "Could not map string offset to a virtual address"
    expected_hex = hex(vaddr)

    ans_path = "/home/user/string_address.txt"
    assert os.path.isfile(ans_path), f"Missing file: {ans_path}"
    with open(ans_path, "r") as f:
        ans_content = f.read().strip().lower()

    # allow for zero padding like 0x040201a vs 0x40201a
    ans_int = int(ans_content, 16)
    expected_int = int(expected_hex, 16)
    assert ans_int == expected_int, f"Incorrect address. Expected {expected_hex}, found {ans_content}"

def test_malicious_manifest():
    path = "/home/user/malicious.manifest"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 3, "Manifest must have at least 3 lines to reach the rule line"
    assert lines[1] == "ALGO: NONE", f"Line 2 must be exactly 'ALGO: NONE', found '{lines[1]}'"
    assert lines[2] == "ALLOW PORT 9999", f"Line 3 must be exactly 'ALLOW PORT 9999', found '{lines[2]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
