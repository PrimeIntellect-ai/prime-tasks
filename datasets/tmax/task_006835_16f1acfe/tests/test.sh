#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tarfile
import tempfile
import uuid

import gzip
import pytest

SOURCE = "/home/user/filter_logs.c"
EXECUTABLE = "/home/user/filter_logs"
NEEDLE = b"ARCHIVE_ME"

HOOK_SOURCE = r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdlib.h>
#include <unistd.h>

static void record_mapping(int fd) {
    static __thread int busy = 0;
    char procpath[64];
    char target[PATH_MAX + 1];
    const char *logpath;
    ssize_t n;
    int out;

    if (busy || fd < 0)
        return;
    busy = 1;
    logpath = getenv("MMAP_AUDIT_LOG");
    if (logpath != NULL) {
        int len = snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
        if (len > 0 && (size_t)len < sizeof(procpath)) {
            n = readlink(procpath, target, PATH_MAX);
            if (n > 0) {
                target[n] = '\0';
                out = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
                if (out >= 0) {
                    write(out, target, (size_t)n);
                    write(out, "\n", 1);
                    close(out);
                }
            }
        }
    }
    busy = 0;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
    void *result;
    if (real_mmap == NULL)
        real_mmap = dlsym(RTLD_NEXT, "mmap");
    if (real_mmap == NULL)
        return MAP_FAILED;
    result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED)
        record_mapping(fd);
    return result;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t) = NULL;
    void *result;
    if (real_mmap64 == NULL)
        real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    if (real_mmap64 == NULL)
        return MAP_FAILED;
    result = real_mmap64(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED)
        record_mapping(fd);
    return result;
}
'''


def test_c_source_exists():
    assert os.path.isfile(SOURCE), "/home/user/filter_logs.c is missing."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled native executable."


def build_mmap_hook(directory):
    source_path = os.path.join(directory, "mmap_audit.c")
    library_path = os.path.join(directory, "mmap_audit.so")
    with open(source_path, "w") as f:
        f.write(HOOK_SOURCE)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", source_path, "-o", library_path, "-ldl"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f"Could not build mmap audit helper: {result.stderr.decode(errors='replace')}"
    return library_path


def exercise_filter(executable, hook, require_mmap):
    with tempfile.TemporaryDirectory(prefix="filter-logs-test-") as directory:
        token = uuid.uuid4().hex.encode()
        cases = {
            "plain.log": b"ordinary log " + token + b" without the marker",
            "middle.log": token + b" before " + NEEDLE + b" after",
            "binary.log": b"abc\x00def" + NEEDLE + b"\x00tail" + token,
            "boundary.log": b"x" * 4093 + NEEDLE + token,
            "near.log": b"ARCHIVE_M and ARCHIVE_MEE are not exact matches " + token,
            "empty.log": b"",
        }
        paths = []
        expected = []
        nonempty_paths = []
        for name, payload in cases.items():
            path = os.path.abspath(os.path.join(directory, name))
            with open(path, "wb") as f:
                f.write(payload)
            paths.append(path)
            if payload:
                nonempty_paths.append(path)
            if NEEDLE in payload:
                expected.append(path)

        error_directory = os.path.join(directory, "not_a_file.log")
        os.mkdir(error_directory)
        missing = os.path.join(directory, "missing.log")
        inputs = paths + [error_directory, missing]
        random.SystemRandom().shuffle(inputs)

        mmap_log = os.path.join(directory, "mmap_calls.txt")
        env = os.environ.copy()
        env["LD_PRELOAD"] = hook
        env["MMAP_AUDIT_LOG"] = mmap_log
        result = subprocess.run(
            [executable],
            input=("\n".join(inputs) + "\n").encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{executable} failed while processing valid and invalid input paths: "
            f"{result.stderr.decode(errors='replace')}"
        )
        try:
            output_lines = [line for line in result.stdout.decode().splitlines() if line]
        except UnicodeDecodeError as exc:
            pytest.fail(f"{executable} produced non-text output: {exc}")

        assert len(output_lines) == len(expected), (
            f"{executable} produced an incorrect number of matching paths: {output_lines}"
        )
        assert set(output_lines) == set(expected), (
            f"{executable} did not correctly identify files containing {NEEDLE!r}. "
            f"Expected {set(expected)}, got {set(output_lines)}"
        )
        assert all(os.path.isabs(line) for line in output_lines), "Filter output paths must be absolute."

        if require_mmap:
            assert os.path.isfile(mmap_log), "The submitted C program did not make any observable mmap calls."
            with open(mmap_log, "r", errors="replace") as f:
                mapped = {os.path.realpath(line.strip()) for line in f if line.strip()}
            required = {os.path.realpath(path) for path in nonempty_paths}
            assert required <= mapped, (
                "The submitted C program did not mmap every non-empty input file before scanning it. "
                f"Missing mappings for: {required - mapped}"
            )


def test_program_behavior_and_mmap_usage():
    with tempfile.TemporaryDirectory(prefix="filter-build-") as build_dir:
        hook = build_mmap_hook(build_dir)
        rebuilt = os.path.join(build_dir, "filter_logs_from_source")
        result = subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"The submitted C source does not compile: {result.stderr.decode(errors='replace')}"
        )
        exercise_filter(rebuilt, hook, require_mmap=True)
        exercise_filter(EXECUTABLE, hook, require_mmap=False)


def test_archived_list_contents():
    list_path = "/home/user/archived_list.txt"
    assert os.path.isfile(list_path), f"{list_path} is missing."

    with open(list_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_files = {
        "/home/user/logs/app1/error.log",
        "/home/user/logs/app2/crash.log",
        "/home/user/logs/db/corruption.log"
    }

    actual_files = set(lines)
    assert actual_files == expected_files, f"Contents of {list_path} do not match expected files. Expected {expected_files}, got {actual_files}."
    assert len(lines) == len(expected_files), f"Duplicates found or incorrect number of lines in {list_path}."
    assert all(os.path.isabs(line) for line in lines), f"All paths in {list_path} must be absolute."


def test_tarball_exists_and_valid():
    tar_path = "/home/user/cold_storage.tar.gz"
    assert os.path.isfile(tar_path), f"{tar_path} is missing."

    try:
        with gzip.open(tar_path, "rb") as f:
            f.read(1)
    except Exception as e:
        pytest.fail(f"{tar_path} is not a valid gzip file: {e}")


def test_tarball_contents():
    tar_path = "/home/user/cold_storage.tar.gz"
    assert os.path.isfile(tar_path), f"{tar_path} is missing."

    expected_files = {
        "/home/user/logs/app1/error.log",
        "/home/user/logs/app2/crash.log",
        "/home/user/logs/db/corruption.log"
    }
    expected_files_stripped = {f.lstrip("/") for f in expected_files}

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            members = tar.getmembers()
            names = [member.name for member in members]
            actual_files_stripped = {name.lstrip("/") for name in names}

            assert actual_files_stripped == expected_files_stripped, (
                f"Tarball contents do not match expected files. "
                f"Expected {expected_files_stripped}, got {actual_files_stripped}."
            )
            assert len(members) == len(expected_files), "Tarball contains duplicate or additional members."

            by_name = {member.name.lstrip("/"): member for member in members}
            for original in expected_files:
                archive_name = original.lstrip("/")
                member = by_name[archive_name]
                assert member.isfile(), f"Archive member {member.name} is not a regular file."
                archived_file = tar.extractfile(member)
                assert archived_file is not None, f"Could not read archive member {member.name}."
                archived_payload = archived_file.read()
                with open(original, "rb") as f:
                    original_payload = f.read()
                assert archived_payload == original_payload, (
                    f"Archive payload for {original} does not match the original file."
                )
    except (AssertionError, pytest.fail.Exception):
        raise
    except Exception as e:
        pytest.fail(f"Failed to read tarball contents: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
