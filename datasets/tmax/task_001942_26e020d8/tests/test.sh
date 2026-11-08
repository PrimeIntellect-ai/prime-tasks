#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
from pathlib import PurePosixPath

SIGNATURE = b"\xDE\xAD\xBE\xEF\xCF\xFA\xED\xFE"
NULLS = b"\x00" * 8

EXPECTED = {
    "libalpha.so": b"head data " + NULLS + b" tail data\n",
    "libbeta.so": b"head data \x01\x02\x03\x04 tail data\n",
    "libgamma.so": b"random " + NULLS + b" more " + NULLS + b" end\n",
    "libdelta.so": b"clean \xAA\xBB\xCC end\n",
}


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def manifest_targets():
    result = []
    with open("/home/user/manifest.raw", encoding="utf-8") as f:
        for line in f:
            fields = [field.strip() for field in line.rstrip("\n").split("|")]
            if len(fields) == 4 and fields[3] == "NEEDS_PATCH":
                result.append(fields[0])
    return result


def test_targets_file():
    targets_path = "/home/user/targets.txt"
    assert os.path.isfile(targets_path), f"{targets_path} does not exist."
    with open(targets_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert "libalpha.so" in lines, "libalpha.so is missing from targets.txt"
    assert "libgamma.so" in lines, "libgamma.so is missing from targets.txt"
    assert len(lines) == 2, f"targets.txt should contain exactly 2 lines, found {len(lines)}"
    assert lines == manifest_targets(), "targets.txt does not exactly match the manifest selection"


def test_binaries_patched():
    for name in ("libalpha.so", "libgamma.so"):
        path = f"/home/user/artifacts/{name}"
        assert os.path.isfile(path), f"{path} does not exist."
        content = read_bytes(path)
        assert SIGNATURE not in content, f"Deprecated signature still found in {name}"
        assert content == EXPECTED[name], f"{name} was not modified only at signature locations"

    assert read_bytes("/home/user/artifacts/libalpha.so").count(NULLS) >= 1
    assert read_bytes("/home/user/artifacts/libgamma.so").count(NULLS) >= 2


def test_unpatched_binaries_untouched():
    for name in ("libbeta.so", "libdelta.so"):
        path = f"/home/user/artifacts/{name}"
        assert os.path.isfile(path)
        content = read_bytes(path)
        assert SIGNATURE not in content
        assert content == EXPECTED[name], f"Unselected artifact {name} was changed"


def build_mmap_auditor():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static int is_probe_fd(int fd) {
    char linkpath[64], actual[PATH_MAX];
    const char *wanted = getenv("MMAP_AUDIT_PROBE");
    if (!wanted) return 0;
    snprintf(linkpath, sizeof(linkpath), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(linkpath, actual, sizeof(actual)-1);
    if (n < 0) return 0;
    actual[n] = 0;
    return strcmp(actual, wanted) == 0;
}

static void record(char code) {
    const char *path = getenv("MMAP_AUDIT_LOG");
    if (!path) return;
    int fd = open(path, O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, &code, 1);
        syscall(SYS_write, fd, "\n", 1);
        close(fd);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t off) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    if (is_probe_fd(fd)) {
        struct stat st;
        if (fstat(fd, &st) == 0 && off == 0 && length == (size_t)st.st_size &&
            (prot & PROT_READ) && (prot & PROT_WRITE) && (flags & MAP_SHARED)) record('M');
        else record('B');
    }
    return real_mmap(addr, length, prot, flags, fd, off);
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t off) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t);
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    if (is_probe_fd(fd)) {
        struct stat st;
        if (fstat(fd, &st) == 0 && off == 0 && length == (size_t)st.st_size &&
            (prot & PROT_READ) && (prot & PROT_WRITE) && (flags & MAP_SHARED)) record('M');
        else record('B');
    }
    return real_mmap64(addr, length, prot, flags, fd, off);
}

ssize_t write(int fd, const void *buf, size_t count) {
    static ssize_t (*real_write)(int, const void *, size_t);
    if (!real_write) real_write = dlsym(RTLD_NEXT, "write");
    if (is_probe_fd(fd)) record('W');
    return real_write(fd, buf, count);
}

ssize_t pwrite(int fd, const void *buf, size_t count, off_t off) {
    static ssize_t (*real_pwrite)(int, const void *, size_t, off_t);
    if (!real_pwrite) real_pwrite = dlsym(RTLD_NEXT, "pwrite");
    if (is_probe_fd(fd)) record('W');
    return real_pwrite(fd, buf, count, off);
}

int ftruncate(int fd, off_t length) {
    static int (*real_ftruncate)(int, off_t);
    if (!real_ftruncate) real_ftruncate = dlsym(RTLD_NEXT, "ftruncate");
    if (is_probe_fd(fd)) record('W');
    return real_ftruncate(fd, length);
}
'''
    src = "/tmp/mmap_auditor.c"
    so = "/tmp/mmap_auditor.so"
    with open(src, "w") as f:
        f.write(source)
    subprocess.run(["gcc", "-shared", "-fPIC", "-O2", src, "-ldl", "-o", so], check=True)
    return so


def test_c_program_exists_and_uses_mmap():
    patcher_c_path = "/home/user/patcher.c"
    assert os.path.isfile(patcher_c_path), f"{patcher_c_path} does not exist."
    with open(patcher_c_path, "r") as f:
        content = f.read()
    assert "mmap" in content, "The C program does not appear to use mmap."

    patcher_bin_path = "/home/user/patcher"
    assert os.path.isfile(patcher_bin_path), f"{patcher_bin_path} does not exist."
    assert os.access(patcher_bin_path, os.X_OK), "patcher is not executable"

    fresh_patcher = "/tmp/submitted_patcher"
    subprocess.run(["gcc", "-O2", "-Wall", "-Wextra", patcher_c_path, "-o", fresh_patcher], check=True)

    auditor = build_mmap_auditor()
    probe_name = ".verifier_mmap_probe.bin"
    probe_path = f"/home/user/artifacts/{probe_name}"
    list_path = "/tmp/verifier_targets.txt"
    log_path = "/tmp/mmap_audit.log"
    original_artifacts = {name: read_bytes(f"/home/user/artifacts/{name}") for name in EXPECTED}
    probe_original = b"prefix" + SIGNATURE + b"middle" + SIGNATURE + b"suffix"
    probe_expected = b"prefix" + NULLS + b"middle" + NULLS + b"suffix"

    try:
        with open(probe_path, "wb") as f:
            f.write(probe_original)
        with open(list_path, "w") as f:
            f.write(probe_name + "\n")
        if os.path.exists(log_path):
            os.unlink(log_path)

        env = os.environ.copy()
        env.update({
            "LD_PRELOAD": auditor,
            "MMAP_AUDIT_PROBE": probe_path,
            "MMAP_AUDIT_LOG": log_path,
        })
        result = subprocess.run([fresh_patcher, list_path], env=env, timeout=10,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, f"freshly compiled patcher failed: {result.stderr.decode(errors='replace')}"
        assert read_bytes(probe_path) == probe_expected, "patcher did not perform exact replacement on verifier input"
        assert os.path.isfile(log_path), "no mmap operation on the probe file was observed"
        events = read_bytes(log_path).splitlines()
        assert b"M" in events, "probe was not mapped whole-file with MAP_SHARED and PROT_READ|PROT_WRITE"
        assert b"B" not in events, "probe was mapped with incorrect mmap parameters"
        assert b"W" not in events, "probe was modified using write/pwrite/truncation instead of mapped memory"
        for name, before in original_artifacts.items():
            assert read_bytes(f"/home/user/artifacts/{name}") == before, "patcher changed a file not in its supplied list"
    finally:
        if os.path.exists(probe_path):
            os.unlink(probe_path)


def normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return str(PurePosixPath(name))


def test_incremental_backup():
    tar_path = "/home/user/patch_incremental.tar"
    snapshot_path = "/home/user/backup_snapshot.snar"
    assert os.path.isfile(tar_path), f"{tar_path} does not exist."
    assert os.path.isfile(snapshot_path) and os.path.getsize(snapshot_path) > 0, "incremental snapshot is missing or empty"

    with tarfile.open(tar_path, "r") as tar:
        members = tar.getmembers()
        names = [m.name for m in members]

        file_names = [name for name in names if not name.endswith('/') and name != 'artifacts']
        assert any("libalpha.so" in name for name in file_names), "libalpha.so missing from incremental backup"
        assert any("libgamma.so" in name for name in file_names), "libgamma.so missing from incremental backup"
        assert not any("libbeta.so" in name for name in file_names), "libbeta.so should not be in the incremental backup"
        assert not any("libdelta.so" in name for name in file_names), "libdelta.so should not be in the incremental backup"

        regular = {normalized_member_name(m.name): m for m in members if m.isfile()}
        assert set(regular) == {"artifacts/libalpha.so", "artifacts/libgamma.so"}, \
            f"incremental backup has unexpected regular files: {sorted(regular)}"
        for archive_name, member in regular.items():
            artifact_name = PurePosixPath(archive_name).name
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == EXPECTED[artifact_name], f"backup payload for {artifact_name} is incorrect"

        assert any(m.type == tarfile.GNUTYPE_DUMPDIR for m in members), \
            "archive lacks GNU incremental dump-directory metadata"


def test_backup_contents_logged():
    log_path = "/home/user/backup_contents.txt"
    tar_path = "/home/user/patch_incremental.tar"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()

    assert "libalpha.so" in content, "libalpha.so missing from backup_contents.txt"
    assert "libgamma.so" in content, "libgamma.so missing from backup_contents.txt"
    assert "libbeta.so" not in content, "libbeta.so should not be in backup_contents.txt"

    actual_listing = subprocess.run(["tar", "-tf", tar_path], check=True,
                                    stdout=subprocess.PIPE, text=True).stdout
    assert content == actual_listing, "backup_contents.txt is not the actual tar listing"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
