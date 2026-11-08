#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -f /tmp/out_legacy.bin /tmp/out_fast.bin

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shutil
import struct
import subprocess
import tempfile
import time
import zlib
from collections import Counter


def generate_test_data(*dirs):
    for d in dirs:
        os.makedirs(d, exist_ok=True)

    # Generate the same 10,000 dummy artifacts in each directory.
    for _ in range(10000):
        major = random.randint(0, 5)
        minor = random.randint(0, 20)
        patch = random.randint(0, 50)
        fname = f"artifact_{major}.{minor}.{patch}.bin"
        data = os.urandom(random.randint(10, 500))
        for d in dirs:
            with open(os.path.join(d, fname), "wb") as f:
                f.write(data)


def expected_archive(input_dir, min_v):
    minimum = tuple(map(int, min_v.split(".")))
    pattern = re.compile(r"artifact_(\d+)\.(\d+)\.(\d+)\.bin")
    names = []

    for name in os.listdir(input_dir):
        match = pattern.match(name)
        if match and tuple(map(int, match.groups())) > minimum:
            names.append(name)
    names.sort()

    output = bytearray(b"ARTF01")
    output.extend(struct.pack("<I", len(names)))
    for name in names:
        with open(os.path.join(input_dir, name), "rb") as f:
            data = f.read()
        encoded_name = name.encode("ascii")
        output.extend(struct.pack("<H", len(encoded_name)))
        output.extend(encoded_name)
        output.extend(struct.pack("<I", len(data)))
        output.extend(data)
        output.extend(struct.pack("<I", zlib.crc32(data) & 0xffffffff))
    return bytes(output)


def get_md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def test_files_exist_and_build():
    src_dir = "/home/user/src"
    c_file = os.path.join(src_dir, "fast_packer.c")
    makefile = os.path.join(src_dir, "Makefile")
    fast_bin = os.path.join(src_dir, "fast_packer")

    assert os.path.isfile(c_file), f"Missing C source file at {c_file}"
    assert os.path.isfile(makefile), f"Missing Makefile at {makefile}"

    # Ensure 'make all' actually creates the submitted executable.
    if os.path.lexists(fast_bin):
        os.remove(fast_bin)
    result = subprocess.run(["make", "-C", src_dir, "all"], capture_output=True, text=True)
    assert result.returncode == 0, f"Make failed with error:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(fast_bin), f"Binary {fast_bin} was not created by 'make all'"
    assert os.access(fast_bin, os.X_OK), f"Binary {fast_bin} is not executable"
    with open(fast_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_packer is not a compiled ELF executable"


def test_correctness_and_speedup():
    root = tempfile.mkdtemp(prefix="packer_eval_")
    try:
        fast_input = os.path.join(root, "fast_input")
        legacy_input = os.path.join(root, "legacy_input")
        out_fast = os.path.join(root, "fast_result.bin")
        out_legacy = os.path.join(root, "legacy_result.bin")
        min_v = "2.5.0"

        generate_test_data(fast_input, legacy_input)

        # Derive the answer before executing either submitted or legacy code.
        # No oracle output file exists when fast_packer runs.
        expected = expected_archive(fast_input, min_v)
        expected_md5 = hashlib.md5(expected).hexdigest()

        fast_bin = "/home/user/src/fast_packer"
        t0 = time.perf_counter()
        res_fast = subprocess.run(
            [fast_bin, fast_input, min_v, out_fast],
            capture_output=True,
            text=True,
            timeout=60,
        )
        t_fast = time.perf_counter() - t0
        assert res_fast.returncode == 0, f"Fast packer failed to run:\n{res_fast.stderr}"
        assert os.path.isfile(out_fast), "Fast packer did not produce output"
        with open(out_fast, "rb") as f:
            fast_bytes = f.read()
        assert fast_bytes == expected, "Fast packer output does not match the derived archive format"
        md5_fast = get_md5(out_fast)
        assert md5_fast == expected_md5

        # Run the legacy tool only after fast_packer's output has already been
        # fully checked, and use a separate but identical input directory.
        t0 = time.perf_counter()
        res_legacy = subprocess.run(
            ["/app/legacy_packer", legacy_input, min_v, out_legacy],
            capture_output=True,
            text=True,
            timeout=120,
        )
        t_legacy = time.perf_counter() - t0
        assert res_legacy.returncode == 0, f"Legacy packer failed to run:\n{res_legacy.stderr}"
        assert os.path.isfile(out_legacy), "Legacy packer did not produce output"
        with open(out_legacy, "rb") as f:
            legacy_bytes = f.read()
        assert legacy_bytes == expected, "Legacy output disagrees with the derived expected archive"

        md5_legacy = get_md5(out_legacy)
        assert md5_legacy == md5_fast, (
            f"Output mismatch! Legacy MD5: {md5_legacy}, Fast MD5: {md5_fast}"
        )

        speedup = t_legacy / t_fast
        assert speedup >= 3.0, (
            f"Performance requirement failed: Speedup {speedup:.2f}x is less than required 3.0x"
        )
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_verification_log_exists_and_contains_hashes():
    log_file = "/home/user/verification.log"
    assert os.path.exists(log_file), f"Missing verification log at {log_file}"
    assert os.path.isfile(log_file), f"{log_file} is not a regular file"
    with open(log_file, "r", errors="replace") as f:
        contents = f.read()
    hashes = re.findall(r"(?i)(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])", contents)
    assert len(hashes) >= 2, "verification.log must contain MD5 hashes for both tool outputs"
    counts = Counter(h.lower() for h in hashes)
    assert any(count >= 2 for count in counts.values()), (
        "verification.log must contain matching MD5 hashes for the legacy and fast outputs"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
