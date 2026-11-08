#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import shutil
import struct
import subprocess

SOURCE = "/home/user/processor.c"
BINARY = "/tmp/processor_under_test"
DATASET = "/home/user/dataset.bin"
GZIP_DATASET = "/home/user/dataset.bin.gz"
CHUNKS = "/home/user/chunks"
LOG = "/home/user/extraction_log.csv"
MMAP_MARKER = "/tmp/processor_mmap_calls"
PRELOAD_SOURCE = "/tmp/mmap_trace.c"
PRELOAD_LIBRARY = "/tmp/mmap_trace.so"


def compile_artifacts():
    assert os.path.exists(SOURCE), f"C source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."

    with open(SOURCE, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "mmap" in content, f"The C source file {SOURCE} does not appear to use 'mmap'."

    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"processor.c did not compile:\n{result.stderr}"

    tracer = r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>

static void record_call(int fd, size_t length, off_t offset) {
    const char *marker = getenv("MMAP_TRACE_FILE");
    if (!marker || fd < 0) return;

    char linkname[64];
    char path[PATH_MAX + 1];
    snprintf(linkname, sizeof(linkname), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(linkname, path, PATH_MAX);
    if (n < 0) return;
    path[n] = '\0';

    int out = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out < 0) return;
    char line[PATH_MAX + 128];
    int used = snprintf(line, sizeof(line), "%zu %lld %s\n",
                        length, (long long)offset, path);
    if (used > 0) write(out, line, (size_t)used);
    close(out);
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    record_call(fd, length, offset);
    return (void *)syscall(SYS_mmap, addr, length, prot, flags, fd, offset);
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    record_call(fd, length, (off_t)offset);
    return (void *)syscall(SYS_mmap, addr, length, prot, flags, fd, (off_t)offset);
}
'''
    with open(PRELOAD_SOURCE, "w") as f:
        f.write(tracer)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", PRELOAD_SOURCE, "-o", PRELOAD_LIBRARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"Failed to build mmap tracer:\n{result.stderr}"


def clean_outputs():
    if os.path.isdir(CHUNKS):
        shutil.rmtree(CHUNKS)
    elif os.path.lexists(CHUNKS):
        os.unlink(CHUNKS)
    if os.path.lexists(LOG):
        os.unlink(LOG)
    if os.path.exists(MMAP_MARKER):
        os.unlink(MMAP_MARKER)


def run_processor():
    clean_outputs()
    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD_LIBRARY
    env["MMAP_TRACE_FILE"] = MMAP_MARKER
    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Compiled processor failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(MMAP_MARKER), "The processor did not call mmap."
    with open(MMAP_MARKER, "r", errors="replace") as f:
        calls = [line.strip().split(" ", 2) for line in f if line.strip()]
    mapped_dataset = any(
        len(parts) == 3
        and int(parts[0]) > 0
        and parts[2] == DATASET
        for parts in calls
    )
    assert mapped_dataset, "The processor did not mmap /home/user/dataset.bin."


def assert_outputs(records):
    assert os.path.exists(CHUNKS), f"Directory {CHUNKS} does not exist."
    assert os.path.isdir(CHUNKS), f"{CHUNKS} is not a directory."

    for timestamp, payload in records:
        filename = f"chunk_{timestamp}.dat"
        filepath = os.path.join(CHUNKS, filename)
        assert os.path.exists(filepath), f"Expected chunk file {filepath} is missing."
        assert os.path.isfile(filepath), f"{filepath} is not a file."
        with open(filepath, "rb") as f:
            content = f.read()
        assert len(content) == len(payload), (
            f"File {filename} has incorrect size. Expected {len(payload)}, got {len(content)}."
        )
        assert content == payload, f"File {filename} content does not match the expected payload."

    assert os.path.exists(LOG), f"Log file {LOG} is missing."
    with open(LOG, "r") as f:
        content = f.read().strip().splitlines()
    data_rows = [
        line.strip() for line in content
        if line.strip() and line.strip() != "Timestamp,PayloadSize"
    ]
    expected_rows = [f"{timestamp},{len(payload)}" for timestamp, payload in records]
    assert data_rows == expected_rows, (
        f"Extraction log data does not match expected output. Got: {data_rows}"
    )


def write_dataset(records):
    with open(DATASET, "wb") as f:
        for timestamp, payload in records:
            f.write(struct.pack("<IQI", 0x5A5A5A5A, timestamp, len(payload)))
            f.write(payload)


def test_compiled_processor_parses_with_mmap():
    compile_artifacts()

    assert os.path.isfile(DATASET), f"Decompressed file {DATASET} is missing."
    with gzip.open(GZIP_DATASET, "rb") as f:
        expected_uncompressed = f.read()
    with open(DATASET, "rb") as f:
        actual_uncompressed = f.read()
    assert actual_uncompressed == expected_uncompressed, (
        "dataset.bin is not the decompressed content of dataset.bin.gz."
    )

    original_records = [
        (1680000000, b"A" * 1024),
        (1680000060, b"B" * 2048),
        (1680000120, b"C" * 512),
        (1680000180, b"D" * 4096),
    ]
    run_processor()
    assert_outputs(original_records)

    base = secrets.randbelow(1_000_000_000) + 2_000_000_000
    dynamic_records = [
        (base, secrets.token_bytes(37)),
        (base + 17, secrets.token_bytes(913)),
        (base + 44, secrets.token_bytes(2057)),
    ]
    write_dataset(dynamic_records)
    run_processor()
    assert_outputs(dynamic_records)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
