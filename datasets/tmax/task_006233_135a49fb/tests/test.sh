#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess

import pytest

SOURCE = "/home/user/extract.c"
EXECUTABLE = "/home/user/extract"
WAL = "/home/user/wiki.wal"
CSV = "/home/user/docs.csv"
COMPILED_SOURCE = "/tmp/extract_from_source"
MMAP_AUDIT_C = "/tmp/mmap_audit.c"
MMAP_AUDIT_SO = "/tmp/mmap_audit.so"
MMAP_LOG = "/tmp/mmap_audit.log"

EXPECTED_ORIGINAL = (
    "DocID,Text\n"
    "101,API Documentation Final\n"
    "102,User Guide V2 Final\n"
    "103,Internal Developer Notes\n"
    "104,Archived System Architecture\n"
)

MMAP_AUDIT_SOURCE = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

static void record_mapping(int fd) {
    char procpath[64];
    char target[4096];
    const char *logpath;
    ssize_t n;
    int out;

    if (fd < 0) return;
    snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
    n = readlink(procpath, target, sizeof(target) - 1);
    if (n < 0) return;
    target[n] = '\0';
    if (strcmp(target, "/home/user/wiki.wal") != 0) return;

    logpath = getenv("MMAP_AUDIT_LOG");
    if (!logpath) return;
    out = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out >= 0) {
        write(out, target, strlen(target));
        write(out, "\n", 1);
        close(out);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    void *result;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    result = real_mmap(addr, length, prot, flags, fd, offset);
    record_mapping(fd);
    return result;
}
'''


def normalized(text):
    return [line.strip() for line in text.strip().splitlines()]


def assert_csv(expected):
    assert os.path.isfile(CSV), f"Output file {CSV} is missing."
    with open(CSV, "r", encoding="utf-8") as f:
        actual = f.read()
    assert normalized(actual) == normalized(expected), (
        f"Content of {CSV} does not match expected output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def rle_encode(text):
    raw = text.encode("ascii")
    encoded = bytearray()
    i = 0
    while i < len(raw):
        count = 1
        while i + count < len(raw) and raw[i + count] == raw[i] and count < 255:
            count += 1
        encoded.extend((count, raw[i]))
        i += count
    return bytes(encoded)


def make_wal(records):
    data = bytearray()
    for doc_id, text in records:
        payload = rle_encode(text)
        data += b"DOC5" + struct.pack("<II", doc_id, len(payload)) + payload
    return bytes(data)


def expected_csv(records):
    latest = {}
    for doc_id, text in records:
        latest[doc_id] = text
    lines = ["DocID,Text"]
    lines.extend(f"{doc_id},{latest[doc_id]}" for doc_id in sorted(latest))
    return "\n".join(lines) + "\n"


def run_and_check(program, expected):
    if os.path.exists(CSV):
        os.unlink(CSV)
    if os.path.exists(MMAP_LOG):
        os.unlink(MMAP_LOG)

    env = os.environ.copy()
    env["LD_PRELOAD"] = MMAP_AUDIT_SO
    env["MMAP_AUDIT_LOG"] = MMAP_LOG
    result = subprocess.run(
        [program], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_csv(expected)
    assert os.path.isfile(MMAP_LOG), f"{program} did not mmap {WAL}."
    with open(MMAP_LOG, "r", encoding="utf-8") as f:
        mappings = f.read().splitlines()
    assert WAL in mappings, f"{program} did not mmap {WAL}."


def test_extract_c_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."


def test_extract_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_docs_csv_content_and_program_behavior():
    with open(WAL, "rb") as f:
        original_wal = f.read()
    original_docs = None
    if os.path.isfile(CSV):
        with open(CSV, "rb") as f:
            original_docs = f.read()

    try:
        with open(MMAP_AUDIT_C, "w", encoding="utf-8") as f:
            f.write(MMAP_AUDIT_SOURCE)
        helper = subprocess.run(
            ["gcc", "-shared", "-fPIC", MMAP_AUDIT_C, "-o", MMAP_AUDIT_SO, "-ldl"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert helper.returncode == 0, f"Failed to build mmap audit helper: {helper.stderr}"

        build = subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", COMPILED_SOURCE],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert build.returncode == 0, (
            f"Source file does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
        )

        # Preserve the original exact-content assertion, but first require the
        # submitted executable to generate that content from the supplied WAL.
        with open(WAL, "wb") as f:
            f.write(original_wal)
        run_and_check(EXECUTABLE, EXPECTED_ORIGINAL)

        # Exercise both the submitted executable and a fresh build of the source
        # on verifier-generated data, including later updates and a run over 255.
        base = 1000 + secrets.randbelow(1000000)
        token = secrets.token_hex(10)
        records = [
            (base + 19, "Early " + token),
            (base + 2, "Guide " + token),
            (base + 31, "Z" * 260 + " End " + token),
            (base + 19, "Final " + token + " Version"),
            (base + 7, "Single Document " + token),
            (base + 2, "Updated Guide " + token),
        ]
        dynamic_wal = make_wal(records)
        dynamic_expected = expected_csv(records)

        with open(WAL, "wb") as f:
            f.write(dynamic_wal)
        run_and_check(EXECUTABLE, dynamic_expected)

        with open(WAL, "wb") as f:
            f.write(dynamic_wal)
        run_and_check(COMPILED_SOURCE, dynamic_expected)
    finally:
        with open(WAL, "wb") as f:
            f.write(original_wal)
        if original_docs is None:
            if os.path.exists(CSV):
                os.unlink(CSV)
        else:
            with open(CSV, "wb") as f:
                f.write(original_docs)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
