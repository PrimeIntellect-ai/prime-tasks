#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import pytest

CPP_PATH = "/home/user/process.cpp"
CSV_PATH = "/home/user/high_values.csv"
BIN_PATH = "/home/user/dataset/measurements.bin"


def test_cpp_file_exists_and_uses_mmap():
    """Verify that the C++ source file exists and uses mmap."""
    assert os.path.isfile(CPP_PATH), f"C++ source file missing at {CPP_PATH}"

    with open(CPP_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert "mmap" in content, "The C++ program must use memory-mapped I/O (mmap)."


def test_csv_output_exists():
    """Verify that the output CSV file exists."""
    assert os.path.isfile(CSV_PATH), f"Output CSV file missing at {CSV_PATH}"


def test_csv_contents():
    """Verify that the output CSV contains the correct header and records."""
    if not os.path.isfile(CSV_PATH):
        pytest.fail(f"File {CSV_PATH} does not exist.")

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "The CSV file is empty."
    assert lines[0] == "id,timestamp,value", "The CSV header is incorrect."

    expected_lines = ["id,timestamp,value"]
    for i in range(800, 1000):
        val = float(i * 0.1)
        expected_lines.append(f"{i},{1600000000 + i},{val:.2f}")

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i + 1}: expected '{expected}', got '{actual}'"


def test_z_compile_run_on_unseen_input_and_map_entire_file(tmp_path):
    """Compile and execute the submitted program on verifier-generated records."""
    executable = tmp_path / "process_under_test"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

    rng = random.SystemRandom()
    values = [79.75, 80.0, 80.25, 95.25, -3.25, 120.75, 79.25]
    records = []
    for i in range(43):
        record_id = rng.randrange(1, 2**32)
        timestamp = rng.randrange(1_700_000_000, 2**63)
        value = values[i % len(values)]
        records.append((record_id, timestamp, value))

    os.makedirs(os.path.dirname(BIN_PATH), exist_ok=True)
    with open(BIN_PATH, "wb") as f:
        for record_id, timestamp, value in records:
            f.write(struct.pack("<IQf", record_id, timestamp, value))

    hook_source = tmp_path / "mmap_hook.c"
    hook_library = tmp_path / "mmap_hook.so"
    mmap_log = tmp_path / "mmap.log"
    hook_source.write_text(r'''
#define _GNU_SOURCE
#define _LARGEFILE64_SOURCE
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

static void record_mapping(int fd, size_t length, long long offset, void *result) {
    if (result == MAP_FAILED || fd < 0) return;
    const char *target = getenv("VERIFY_MMAP_TARGET");
    const char *log_path = getenv("VERIFY_MMAP_LOG");
    if (!target || !log_path) return;
    struct stat target_stat, fd_stat;
    if (stat(target, &target_stat) != 0 || fstat(fd, &fd_stat) != 0) return;
    if (target_stat.st_dev != fd_stat.st_dev || target_stat.st_ino != fd_stat.st_ino) return;
    int out = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out < 0) return;
    char buffer[128];
    int count = snprintf(buffer, sizeof(buffer), "%lld %zu\n", offset, length);
    if (count > 0) write(out, buffer, (size_t)count);
    close(out);
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    record_mapping(fd, length, (long long)offset, result);
    return result;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t) = NULL;
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    void *result = real_mmap64(addr, length, prot, flags, fd, offset);
    record_mapping(fd, length, (long long)offset, result);
    return result;
}
''', encoding="utf-8")

    hook_result = subprocess.run(
        ["gcc", "-shared", "-fPIC", str(hook_source), "-ldl", "-o", str(hook_library)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert hook_result.returncode == 0, f"Failed to build mmap monitor:\n{hook_result.stderr}"

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    env = os.environ.copy()
    env["LD_PRELOAD"] = str(hook_library)
    env["VERIFY_MMAP_TARGET"] = BIN_PATH
    env["VERIFY_MMAP_LOG"] = str(mmap_log)
    run_result = subprocess.run(
        [str(executable)],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, f"Program failed:\n{run_result.stderr}"
    assert os.path.isfile(CSV_PATH), "Program did not generate /home/user/high_values.csv"

    expected = ["id,timestamp,value"]
    for record_id, timestamp, value in records:
        stored_value = struct.unpack("<f", struct.pack("<f", value))[0]
        if stored_value >= 80.0:
            expected.append(f"{record_id},{timestamp},{stored_value:.2f}")

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, "Program output is incorrect for verifier-generated binary records"

    assert mmap_log.is_file(), "The program did not mmap measurements.bin"
    intervals = []
    for line in mmap_log.read_text(encoding="utf-8").splitlines():
        offset_text, length_text = line.split()
        start = int(offset_text)
        length = int(length_text)
        if start >= 0 and length > 0:
            intervals.append((start, start + length))

    file_size = os.path.getsize(BIN_PATH)
    covered_until = 0
    for start, end in sorted(intervals):
        if start > covered_until:
            break
        covered_until = max(covered_until, end)
    assert covered_until >= file_size, "mmap calls did not cover the complete measurements.bin file"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
