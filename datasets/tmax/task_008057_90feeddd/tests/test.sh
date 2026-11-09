#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
import tempfile

PROJECT = "/home/user/forensics_tool"
CARVER = os.path.join(PROJECT, "carver")
EVIDENCE = "/home/user/data/evidence.bin"
EXPECTED = "FLAG{F0r3ns1cs_M4st3r_X0R}"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=5, **kwargs)


def make_evidence(path, payload, prefix=b"\x10\x20\x30", trailing=b"\x77"):
    encoded = bytes(b ^ 0x42 for b in payload)
    with open(path, "wb") as f:
        f.write(struct.pack("<HI", 0x5A5A, len(payload)))
        f.write(prefix + b"\xff" + encoded + trailing)


def test_00_clean_build_succeeds():
    result = run(["make", "clean"], cwd=PROJECT)
    assert result.returncode == 0, result.stdout + result.stderr
    result = run(["make"], cwd=PROJECT)
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(CARVER), "The 'carver' executable was not built."
    with open(CARVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "carver is not a compiled ELF executable."


def test_extracted_flag():
    flag_path = "/home/user/extracted_flag.txt"
    assert os.path.isfile(flag_path), f"{flag_path} does not exist."
    with open(flag_path, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, "The extracted flag is incorrect."


def test_test_runner_script():
    script_path = "/home/user/test_runner.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

    result = run([script_path])
    assert result.returncode == 0, f"test_runner.sh failed with return code {result.returncode}."

    with open(EVIDENCE, "rb") as f:
        original = f.read()
    try:
        make_evidence(EVIDENCE, b"FLAG{deliberately_wrong}", b"\x01\x02\x03")
        result = run([script_path])
        assert result.returncode == 1, "test_runner.sh does not reject incorrect carver output."
    finally:
        with open(EVIDENCE, "wb") as f:
            f.write(original)


def test_executable_exists():
    assert os.path.isfile(CARVER), "The 'carver' executable was not built."
    st = os.stat(CARVER)
    assert bool(st.st_mode & stat.S_IXUSR), f"{CARVER} is not executable."


def test_makefile_fixed():
    makefile_path = os.path.join(PROJECT, "Makefile")
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "decoder.o" in content, "Makefile does not reference decoder.o."

    lines = content.splitlines()
    carver_target_found = False
    for i, line in enumerate(lines):
        if line.startswith("carver:"):
            assert "decoder.o" in line, "Makefile 'carver' target does not depend on decoder.o."
            assert i + 1 < len(lines) and "decoder.o" in lines[i + 1], "Makefile 'carver' target does not link decoder.o."
            carver_target_found = True
            break
    assert carver_target_found, "Makefile does not contain a 'carver' target."


def test_decoder_h_fixed():
    decoder_h_path = os.path.join(PROJECT, "decoder.h")
    with open(decoder_h_path, "r") as f:
        content = f.read()
    compact = content.replace(" ", "").replace("\t", "").replace("\n", "")
    assert "__attribute__((packed))" in compact, "decoder.h struct EvidenceHeader is missing __attribute__((packed))."


def test_decoder_c_fixed():
    decoder_c_path = os.path.join(PROJECT, "decoder.c")
    with open(decoder_c_path, "r") as f:
        content = f.read()

    assert "i <= len" not in content, "decoder.c still contains the off-by-one bug (i <= len)."
    assert "i < len" in content, "decoder.c does not contain the fixed loop boundary (i < len)."
    assert "left = mid;" not in content, "decoder.c still contains the convergence bug (left = mid;)."
    assert "right = mid;" not in content, "decoder.c still contains the convergence bug (right = mid;)."
    assert "left = mid + 1" in content or "left=mid+1" in content.replace(" ", ""), "decoder.c does not properly increment left in binary search."
    assert "right = mid - 1" in content or "right=mid-1" in content.replace(" ", ""), "decoder.c does not properly decrement right in binary search."


def test_decoder_functions_on_independent_inputs():
    harness = r'''
#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include "decoder.h"

int main(void) {
    uint8_t a[] = {0xff};
    uint8_t b[] = {0x10, 0xff, 0x20};
    uint8_t c[] = {0x10, 0x20, 0x30, 0xff, 0x01, 0x02, 0x03, 0x04, 0x05};
    uint8_t d[] = {0x01, 0x02, 0x03, 0x04};
    if (find_sync_offset(a, sizeof(a)) != 1) return 10;
    if (find_sync_offset(b, sizeof(b)) != 2) return 11;
    if (find_sync_offset(c, sizeof(c)) != 4) return 12;
    if (find_sync_offset(d, sizeof(d)) != -1) return 13;

    long page = sysconf(_SC_PAGESIZE);
    uint8_t *mem = mmap(NULL, (size_t)page * 2, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return 20;
    if (mprotect(mem + page, (size_t)page, PROT_NONE) != 0) return 21;
    uint8_t *src = mem + page - 4;
    src[0] = 1; src[1] = 2; src[2] = 3; src[3] = 4;
    char out[5] = {9, 9, 9, 9, 9};
    extract_payload(src, 0, 4, out);
    if ((uint8_t)out[0] != (1 ^ 0x42) || (uint8_t)out[1] != (2 ^ 0x42) ||
        (uint8_t)out[2] != (3 ^ 0x42) || (uint8_t)out[3] != (4 ^ 0x42) ||
        out[4] != '\0') return 22;
    munmap(mem, (size_t)page * 2);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "harness.c")
        binary = os.path.join(td, "harness")
        with open(source, "w") as f:
            f.write(harness)
        result = run([
            "gcc", "-std=c11", "-Wall", "-Werror", "-I", PROJECT,
            source, os.path.join(PROJECT, "decoder.c"), "-o", binary
        ])
        assert result.returncode == 0, result.stdout + result.stderr
        result = run([binary])
        assert result.returncode == 0, f"decoder function harness failed with {result.returncode}: {result.stderr}"


def test_carver_output():
    result = run([CARVER, EVIDENCE])
    assert result.returncode == 0, "carver executable failed to run."
    assert EXPECTED in result.stdout, "carver output did not contain the correct decoded flag."
    assert result.stdout.strip() == EXPECTED, "carver emitted unexpected output."


def test_carver_on_generated_evidence_files():
    cases = [
        (b"FLAG{A1}", b"", b"\x11"),
        (b"FLAG{different_payload_29}", b"\x01\x15\x7e", b"\x00\xaa"),
        (b"PAYLOAD-without-fixed-flag", bytes(range(1, 18)), b"\x10\x20\x30"),
    ]
    with tempfile.TemporaryDirectory() as td:
        for index, (payload, prefix, trailing) in enumerate(cases):
            path = os.path.join(td, f"evidence-{index}.bin")
            make_evidence(path, payload, prefix, trailing)
            result = run([CARVER, path])
            assert result.returncode == 0, result.stdout + result.stderr
            assert result.stdout == payload.decode("ascii") + "\n", \
                f"wrong output for generated evidence case {index}: {result.stdout!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
