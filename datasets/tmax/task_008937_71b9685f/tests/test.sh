#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import subprocess
import tarfile
import uuid
import pytest

DUMPS_DIR = "/home/user/dumps"
SCANNER_C = "/home/user/scanner.c"
OLD_FILES_TXT = "/home/user/old_files.txt"
ARCHIVE_PATH = "/home/user/old_dumps.tar.gz"
SCANNER_BIN = "/tmp/submitted_scanner"
MMAP_LOG = "/tmp/scanner_mmap.log"
MMAP_AUDIT_SO = "/tmp/mmap_audit.so"

EXPECTED_OLD = {
    "dump_01.bin": (1650000000, 1024),
    "dump_03.bin": (1500000000, 512),
    "dump_05.bin": (1699999999, 4096),
}
EXPECTED_NEW = {
    "dump_02.bin": (1750000000, 2048),
    "dump_04.bin": (1700000000, 1024),
}
EXPECTED_OLD_FILES = set(EXPECTED_OLD)
EXPECTED_NEW_FILES = set(EXPECTED_NEW)
MAGIC = 0xDEADBEEF
CUTOFF = 1700000000


def parse_dump_bytes(data, label):
    assert len(data) >= 16, f"Fail: {label} is shorter than its 16-byte header"
    magic, timestamp, payload_size = struct.unpack("<IIQ", data[:16])
    assert magic == MAGIC, f"Fail: {label} has an invalid magic number"
    assert len(data) == 16 + payload_size, (
        f"Fail: {label} has {len(data) - 16} payload bytes but its header declares {payload_size}"
    )
    return timestamp, payload_size


def test_scanner_c_exists_and_uses_mmap():
    assert os.path.isfile(SCANNER_C), f"Fail: {SCANNER_C} does not exist"
    with open(SCANNER_C, "r", encoding="utf-8") as f:
        content = f.read()
    assert "mmap" in content, f"Fail: {SCANNER_C} does not seem to use mmap (missing 'mmap' keyword)"
    assert "<sys/mman.h>" in content, f"Fail: {SCANNER_C} does not include <sys/mman.h>"


def test_old_files_txt_content():
    assert os.path.isfile(OLD_FILES_TXT), f"Fail: {OLD_FILES_TXT} does not exist"
    with open(OLD_FILES_TXT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_paths = {os.path.join(DUMPS_DIR, fname) for fname in EXPECTED_OLD_FILES}
    actual_paths = set(lines)
    assert len(lines) == len(expected_paths), (
        f"Fail: {OLD_FILES_TXT} should contain exactly {len(expected_paths)} lines, found {len(lines)}"
    )
    assert actual_paths == expected_paths, (
        f"Fail: {OLD_FILES_TXT} does not contain the correct absolute paths. "
        f"Expected {expected_paths}, got {actual_paths}"
    )


def test_remaining_files_in_dumps_dir():
    assert os.path.isdir(DUMPS_DIR), f"Fail: {DUMPS_DIR} does not exist"
    actual_files = set(os.listdir(DUMPS_DIR))
    assert actual_files == EXPECTED_NEW_FILES, (
        f"Fail: {DUMPS_DIR} should contain exactly {EXPECTED_NEW_FILES}, but contains {actual_files}"
    )

    for name, expected in EXPECTED_NEW.items():
        path = os.path.join(DUMPS_DIR, name)
        with open(path, "rb") as f:
            data = f.read()
        timestamp, payload_size = parse_dump_bytes(data, path)
        assert (timestamp, payload_size) == expected, (
            f"Fail: remaining file {name} has header values {(timestamp, payload_size)}, expected {expected}"
        )
        assert timestamp >= CUTOFF, f"Fail: old dump {name} was not removed"


def test_archive_exists_and_contains_old_files_with_valid_contents():
    assert os.path.isfile(ARCHIVE_PATH), f"Fail: {ARCHIVE_PATH} does not exist"
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"Fail: {ARCHIVE_PATH} is not a valid tar archive"

    try:
        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            bin_members = [m for m in tar.getmembers() if m.name.endswith(".bin")]
            archived_basenames = [os.path.basename(m.name) for m in bin_members]

            assert set(archived_basenames) == EXPECTED_OLD_FILES, (
                f"Fail: Archive contains incorrect files. Expected {EXPECTED_OLD_FILES}, "
                f"got {set(archived_basenames)}"
            )
            assert len(archived_basenames) == len(EXPECTED_OLD_FILES), (
                "Fail: Archive contains duplicate or extra .bin members"
            )

            for member in bin_members:
                name = os.path.basename(member.name)
                assert member.isfile(), f"Fail: archived member {member.name} is not a regular file"
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Fail: could not read archived member {member.name}"
                data = extracted.read()
                timestamp, payload_size = parse_dump_bytes(data, f"archive member {member.name}")
                assert (timestamp, payload_size) == EXPECTED_OLD[name], (
                    f"Fail: archived file {name} has header values {(timestamp, payload_size)}, "
                    f"expected {EXPECTED_OLD[name]}"
                )
                assert timestamp < CUTOFF, f"Fail: archive member {name} is not old"
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"Fail: Could not read {ARCHIVE_PATH} as a gzipped tarball. Error: {e}")


def test_compiled_scanner_parses_unseen_files_and_really_maps_them():
    subprocess.run(
        ["gcc", "-O2", SCANNER_C, "-o", SCANNER_BIN],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    audit_source = r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/syscall.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

typedef void *(*mmap_fn)(void *, size_t, int, int, int, off_t);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static mmap_fn real_mmap = NULL;
    if (!real_mmap)
        real_mmap = (mmap_fn)dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);

    if (fd >= 0) {
        char linkpath[64];
        char target[PATH_MAX];
        int n = snprintf(linkpath, sizeof(linkpath), "/proc/self/fd/%d", fd);
        ssize_t got = readlink(linkpath, target, sizeof(target) - 1);
        if (n > 0 && got > 0) {
            target[got] = '\0';
            if (strstr(target, "/home/user/dumps/") == target) {
                const char *logpath = getenv("MMAP_AUDIT_LOG");
                if (logpath) {
                    int out = syscall(SYS_openat, AT_FDCWD, logpath,
                                      O_WRONLY | O_CREAT | O_APPEND, 0600);
                    if (out >= 0) {
                        syscall(SYS_write, out, target, (size_t)got);
                        syscall(SYS_write, out, "\n", 1);
                        syscall(SYS_close, out);
                    }
                }
            }
        }
    }
    return result;
}
'''
    with open("/tmp/mmap_audit.c", "w", encoding="utf-8") as f:
        f.write(audit_source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/mmap_audit.c", "-o", MMAP_AUDIT_SO, "-ldl"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    token = uuid.uuid4().hex
    probe_specs = {
        f"probe_old_a_{token}.bin": (MAGIC, CUTOFF - 1, 37),
        f"probe_old_b_{token}.bin": (MAGIC, 123456789, 83),
        f"probe_new_{token}.bin": (MAGIC, CUTOFF + 98765, 51),
        f"probe_bad_magic_{token}.bin": (0x12345678, CUTOFF - 100, 29),
    }
    truncated_name = f"probe_truncated_{token}.bin"
    created = []
    original_list = None

    try:
        with open(OLD_FILES_TXT, "rb") as f:
            original_list = f.read()

        for name, (magic, timestamp, size) in probe_specs.items():
            path = os.path.join(DUMPS_DIR, name)
            with open(path, "wb") as f:
                f.write(struct.pack("<IIQ", magic, timestamp, size))
                f.write(os.urandom(size))
            created.append(path)

        truncated_path = os.path.join(DUMPS_DIR, truncated_name)
        with open(truncated_path, "wb") as f:
            f.write(os.urandom(9))
        created.append(truncated_path)

        if os.path.exists(MMAP_LOG):
            os.unlink(MMAP_LOG)
        env = os.environ.copy()
        env["LD_PRELOAD"] = MMAP_AUDIT_SO
        env["MMAP_AUDIT_LOG"] = MMAP_LOG
        result = subprocess.run(
            [SCANNER_BIN], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"Fail: compiled scanner exited with {result.returncode}. stderr: {result.stderr}"
        )

        with open(OLD_FILES_TXT, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        expected = {
            os.path.join(DUMPS_DIR, f"probe_old_a_{token}.bin"),
            os.path.join(DUMPS_DIR, f"probe_old_b_{token}.bin"),
        }
        assert len(lines) == len(expected) and set(lines) == expected, (
            "Fail: the compiled scanner did not derive the correct result for unseen valid, "
            "new, invalid-magic, and truncated dump files"
        )

        assert os.path.isfile(MMAP_LOG), "Fail: no mmap activity on dump files was observed"
        with open(MMAP_LOG, "r", encoding="utf-8", errors="replace") as f:
            mapped_paths = set(line.strip() for line in f if line.strip())
        required_mapped = {
            os.path.join(DUMPS_DIR, f"probe_old_a_{token}.bin"),
            os.path.join(DUMPS_DIR, f"probe_new_{token}.bin"),
        }
        assert required_mapped <= mapped_paths, (
            f"Fail: scanner did not mmap the unseen dump files; observed mappings: {mapped_paths}"
        )
    finally:
        for path in created:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        if original_list is not None:
            with open(OLD_FILES_TXT, "wb") as f:
                f.write(original_list)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
