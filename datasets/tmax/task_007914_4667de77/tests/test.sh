#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'AUDIT_EOF' > /tmp/mmap_audit.c
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

void *__real_mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int __real_munmap(void *addr, size_t length);

static void audit_line(const char *format, void *addr, size_t length, off_t offset, int fd) {
    const char *log_path = getenv("MMAP_AUDIT_LOG");
    if (!log_path) return;

    int log_fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (log_fd < 0) return;

    if (fd >= 0) {
        char link_path[64];
        char target[PATH_MAX];
        snprintf(link_path, sizeof(link_path), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link_path, target, sizeof(target) - 1);
        if (n >= 0) {
            target[n] = '\0';
            dprintf(log_fd, format, addr, length, (long long)offset, target);
        }
    } else {
        dprintf(log_fd, format, addr, length, (long long)offset, "-");
    }
    close(log_fd);
}

void *__wrap_mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    void *result = __real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED)
        audit_line("M %p %zu %lld %s\n", result, length, offset, fd);
    return result;
}

int __wrap_munmap(void *addr, size_t length) {
    int result = __real_munmap(addr, length);
    if (result == 0)
        audit_line("U %p %zu %lld %s\n", addr, length, 0, -1);
    return result;
}
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path


def test_to_archive_txt_content():
    path = "/home/user/to_archive.txt"
    assert os.path.exists(path), f"File {path} is missing."

    expected_content = (
        "[ARCHIVE_ME] Warning: CPU temperature reached 90C!!!!!\n"
        "[ARCHIVE_ME] Critical Error: Memory leak detected in thread 00000000.\n"
        "[ARCHIVE_ME] Shutdown        complete.\n"
    )

    with open(path, "r") as f:
        content = f.read()

    assert content == expected_content, f"Content of {path} does not match the expected filtered new lines."


def test_to_archive_is_the_derived_increment():
    old = Path("/home/user/log_v1.txt").read_bytes()
    current = Path("/home/user/log_v2.txt").read_bytes()
    assert current.startswith(old), "The current log no longer contains the previous log as a prefix."
    expected = b"".join(
        line for line in current[len(old):].splitlines(keepends=True)
        if b"[ARCHIVE_ME]" in line
    )
    assert Path("/home/user/to_archive.txt").read_bytes() == expected


def test_archive_z_content():
    path = "/home/user/archive.z"
    assert os.path.exists(path), f"File {path} is missing."

    expected_content = (
        "[ARCHIVE_ME] Warning: CPU temperature reached 90C*5!\n"
        "[ARCHIVE_ME] Critical Error: Memory leak detected in thread *80.\n"
        "[ARCHIVE_ME] Shutdown*8 complete.\n"
    )

    with open(path, "r") as f:
        content = f.read()

    assert content == expected_content, f"Content of {path} does not match the expected compressed output."


def test_mmap_compress_c_exists_and_uses_mmap():
    path = "/home/user/mmap_compress.c"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "mmap" in content, f"File {path} does not seem to use mmap."
    assert "munmap" in content, f"File {path} does not seem to use munmap."


def rle(data):
    output = bytearray()
    i = 0
    while i < len(data):
        j = i + 1
        while j < len(data) and data[j] == data[i]:
            j += 1
        count = j - i
        if count >= 4:
            output.extend(b"*" + str(count).encode("ascii") + data[i:i + 1])
        else:
            output.extend(data[i:j])
        i = j
    return bytes(output)


def test_source_compiles_runs_rle_and_actually_maps_input():
    source = Path("/home/user/mmap_compress.c")
    assert source.is_file(), "mmap_compress.c must be a regular source file."

    obj = "/tmp/submission_mmap_compress.o"
    audit_obj = "/tmp/mmap_audit.o"
    executable = "/tmp/submission_mmap_compress"
    subprocess.run(
        ["gcc", "-std=c11", "-O2", "-c", str(source), "-o", obj],
        check=True, timeout=20
    )
    subprocess.run(
        ["gcc", "-std=c11", "-O2", "-c", "/tmp/mmap_audit.c", "-o", audit_obj],
        check=True, timeout=20
    )
    subprocess.run(
        ["gcc", obj, audit_obj, "-Wl,--wrap=mmap", "-Wl,--wrap=munmap", "-o", executable],
        check=True, timeout=20
    )

    input_path = Path("/home/user/to_archive.txt")
    output_path = Path("/home/user/archive.z")
    original_input = input_path.read_bytes()
    original_output = output_path.read_bytes()
    token = secrets.token_hex(24).encode("ascii")
    cases = [
        b"[ARCHIVE_ME] " + token + b"!!!!!\n" + b" " * (7 + secrets.randbelow(10)) + b"end\n",
        b"prefix" + b"a" * (4 + secrets.randbelow(30)) + b"***" + b"." * (10 + secrets.randbelow(20)) + b"\n",
        token[::-1] + b"\n" * (4 + secrets.randbelow(8)) + b"0" * (8 + secrets.randbelow(25)) + b" xyz\n",
    ]

    try:
        for number, payload in enumerate(cases):
            audit_log = Path(f"/tmp/mmap_audit_{number}.log")
            audit_log.unlink(missing_ok=True)
            input_path.write_bytes(payload)
            output_path.unlink(missing_ok=True)

            env = os.environ.copy()
            env["MMAP_AUDIT_LOG"] = str(audit_log)
            subprocess.run([executable], cwd="/home/user", env=env, check=True, timeout=10)

            assert output_path.is_file(), "The compiled program did not create /home/user/archive.z."
            assert output_path.read_bytes() == rle(payload), "The compiled program produced incorrect RLE output."
            assert audit_log.is_file(), "No mmap audit information was produced."

            mappings = []
            unmapped = set()
            for line in audit_log.read_text().splitlines():
                fields = line.split(maxsplit=4)
                if fields and fields[0] == "M" and len(fields) == 5:
                    mappings.append((fields[1], int(fields[2]), int(fields[3]), fields[4]))
                elif fields and fields[0] == "U" and len(fields) >= 3:
                    unmapped.add(fields[1])

            valid = [m for m in mappings
                     if m[3] == "/home/user/to_archive.txt"
                     and m[2] == 0 and m[1] >= len(payload)]
            assert valid, "The program did not mmap the complete /home/user/to_archive.txt input."
            assert any(m[0] in unmapped for m in valid), "The input mapping was not passed to munmap()."
    finally:
        input_path.write_bytes(original_input)
        output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
