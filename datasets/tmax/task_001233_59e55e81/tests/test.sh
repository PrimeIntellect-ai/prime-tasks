#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pathlib
import shutil
import stat
import struct
import subprocess
import tempfile
import threading
import time
import tomllib

import pytest

BINARY_PATH = "/home/user/safe_archiver/target/release/safe_archiver"
PROJECT_DIR = "/home/user/safe_archiver"
CLEAN_CORPUS_DIR = "/home/user/corpus/clean"
EVIL_CORPUS_DIR = "/home/user/corpus/evil"
LEGACY_PACKER = "/app/legacy_packer"
LEGACY_UNPACKER = "/app/legacy_unpacker"
MALICIOUS_MESSAGE = "MALICIOUS DIRECTORY DETECTED"


def run_archiver(root, archive, env=None, timeout=15):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        [BINARY_PATH, root, archive],
        capture_output=True,
        text=True,
        env=merged,
        timeout=timeout,
    )


def assert_malicious_result(result):
    assert result.returncode == 1, (
        f"malicious input returned {result.returncode}, expected exactly 1; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    lines = [line.strip() for line in (result.stdout + "\n" + result.stderr).splitlines()]
    assert MALICIOUS_MESSAGE in lines, (
        f"required message {MALICIOUS_MESSAGE!r} was not printed as a line; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def expected_regular_files(root):
    result = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(current, d))]
        for name in files:
            path = os.path.join(current, name)
            mode = os.lstat(path).st_mode
            if stat.S_ISREG(mode):
                rel = os.path.relpath(path, root).replace(os.sep, "/")
                with open(path, "rb") as f:
                    result[rel] = f.read()
    return result


def parse_archive(path):
    with open(path, "rb") as f:
        blob = f.read()
    assert blob[:4] == b"BKP1", "archive has incorrect magic"
    pos = 4
    entries = {}
    while pos < len(blob):
        assert len(blob) - pos >= 2, "truncated path length"
        path_len = struct.unpack_from("<H", blob, pos)[0]
        pos += 2
        assert len(blob) - pos >= path_len + 4, "truncated archive entry"
        raw_path = blob[pos:pos + path_len]
        pos += path_len
        try:
            rel = raw_path.decode("utf-8")
        except UnicodeDecodeError as exc:
            pytest.fail(f"non-UTF-8 archive path: {exc}")
        assert rel and not rel.startswith("/"), f"unsafe archive path {rel!r}"
        parts = pathlib.PurePosixPath(rel).parts
        assert ".." not in parts and "." not in parts, f"unsafe archive path {rel!r}"
        size = struct.unpack_from("<I", blob, pos)[0]
        pos += 4
        assert len(blob) - pos >= size + 32, f"truncated data/checksum for {rel!r}"
        data = blob[pos:pos + size]
        pos += size
        checksum = blob[pos:pos + 32]
        pos += 32
        assert checksum == hashlib.sha256(data).digest(), f"bad SHA-256 for {rel!r}"
        assert rel not in entries, f"duplicate archive path {rel!r}"
        entries[rel] = data
    assert pos == len(blob), "trailing or malformed archive bytes"
    return entries


def extracted_regular_files(root):
    result = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in files:
            path = os.path.join(current, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, "rb") as f:
                result[rel] = f.read()
    return result


def validate_clean_directory(root, trace_env=None):
    expected = expected_regular_files(root)
    with tempfile.TemporaryDirectory() as tmpdir:
        archive = os.path.join(tmpdir, "archive.bkp")
        result = run_archiver(root, archive, env=trace_env)
        assert result.returncode == 0, (
            f"clean input failed with {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(archive), "successful invocation did not create an archive"
        assert parse_archive(archive) == expected, "archive did not exactly preserve regular files"

        unpacked = os.path.join(tmpdir, "unpacked")
        os.mkdir(unpacked)
        unpack = subprocess.run(
            [LEGACY_UNPACKER, archive, unpacked], capture_output=True, timeout=15
        )
        assert unpack.returncode == 0, "legacy unpacker rejected the archive"
        assert extracted_regular_files(unpacked) == expected, (
            "legacy-unpacked files differ from the clean input"
        )


def build_mmap_tracer(directory):
    source = os.path.join(directory, "trace_mmap.c")
    library = os.path.join(directory, "trace_mmap.so")
    with open(source, "w") as f:
        f.write(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static void record_fd(int fd) {
    const char *prefix = getenv("MMAP_TRACE_PREFIX");
    const char *log = getenv("MMAP_TRACE_LOG");
    if (!prefix || !log || fd < 0) return;
    char proc[64], target[4096], line[4200];
    snprintf(proc, sizeof(proc), "/proc/self/fd/%d", fd);
    ssize_t n = syscall(SYS_readlink, proc, target, sizeof(target) - 1);
    if (n <= 0) return;
    target[n] = '\0';
    size_t plen = strlen(prefix);
    if (strncmp(target, prefix, plen) != 0 || (target[plen] != '/' && target[plen] != '\0')) return;
    int len = snprintf(line, sizeof(line), "%s\n", target);
    int out = syscall(SYS_openat, AT_FDCWD, log, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (out >= 0) {
        syscall(SYS_write, out, line, len);
        syscall(SYS_close, out);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED) record_fd(fd);
    return result;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t);
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    void *result = real_mmap64(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED) record_fd(fd);
    return result;
}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", source, "-o", library, "-ldl"],
        check=True,
        capture_output=True,
    )
    return library


def test_binary_exists_and_is_compiled_artifact():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "safe_archiver is not a compiled ELF binary"
    for reference in (LEGACY_PACKER, LEGACY_UNPACKER):
        assert not os.path.isfile(reference) or not shutil._samefile(BINARY_PATH, reference), (
            "submission is the legacy executable rather than the requested archiver"
        )
        if os.path.isfile(reference):
            with open(BINARY_PATH, "rb") as a, open(reference, "rb") as b:
                assert a.read() != b.read(), "submission is byte-identical to a legacy tool"


def test_rust_project_and_memmap_dependency():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), "Cargo.toml is missing"
    with open(cargo_toml, "rb") as f:
        manifest = tomllib.load(f)
    dependencies = manifest.get("dependencies", {})
    assert "memmap2" in dependencies, "memmap2 is not declared as a dependency"
    allowed = {"memmap2", "sha2"}
    assert set(dependencies).issubset(allowed), (
        f"disallowed direct dependencies: {sorted(set(dependencies) - allowed)}"
    )
    sources = []
    src_dir = os.path.join(PROJECT_DIR, "src")
    for current, _, files in os.walk(src_dir):
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(current, name), errors="replace") as f:
                    sources.append(f.read())
    joined = "\n".join(sources)
    assert "memmap2" in joined and ("Mmap" in joined or "map(" in joined), (
        "Rust source does not use memmap2"
    )


def test_provided_clean_corpus_exact_contents():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.skip("Clean corpus directory not found")
    clean_dirs = [
        os.path.join(CLEAN_CORPUS_DIR, d)
        for d in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isdir(os.path.join(CLEAN_CORPUS_DIR, d))
    ]
    assert clean_dirs, "clean corpus is empty"
    for clean_dir in clean_dirs:
        validate_clean_directory(clean_dir)


def test_dynamic_clean_archive_and_actual_mmap_usage():
    with tempfile.TemporaryDirectory() as tmpdir:
        root = os.path.join(tmpdir, "input")
        os.makedirs(os.path.join(root, "nested", "deeper"))
        files = {
            "root.bin": os.urandom(8193),
            "nested/note.txt": b"dynamic verifier content\n" + os.urandom(97),
            "nested/deeper/unicode-\u03bb.dat": os.urandom(32771),
        }
        for rel, data in files.items():
            path = os.path.join(root, *rel.split("/"))
            with open(path, "wb") as f:
                f.write(data)
        os.symlink("nested/note.txt", os.path.join(root, "safe-file-link"))
        os.symlink("nested/deeper", os.path.join(root, "safe-dir-link"))

        tracer = build_mmap_tracer(tmpdir)
        trace_log = os.path.join(tmpdir, "mmap.log")
        env = {
            "LD_PRELOAD": tracer,
            "MMAP_TRACE_PREFIX": os.path.realpath(root),
            "MMAP_TRACE_LOG": trace_log,
        }
        validate_clean_directory(root, trace_env=env)
        assert os.path.isfile(trace_log), "no input-file mmap calls were observed"
        with open(trace_log) as f:
            mapped = {os.path.realpath(line.strip()) for line in f if line.strip()}
        required = {
            os.path.realpath(os.path.join(root, *rel.split("/")))
            for rel, data in files.items() if data
        }
        assert required.issubset(mapped), (
            f"not every non-empty input file was memory-mapped; missing {sorted(required - mapped)}"
        )


def test_provided_evil_corpus_exact_failure():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.skip("Evil corpus directory not found")
    evil_dirs = [
        os.path.join(EVIL_CORPUS_DIR, d)
        for d in os.listdir(EVIL_CORPUS_DIR)
        if os.path.isdir(os.path.join(EVIL_CORPUS_DIR, d))
    ]
    assert evil_dirs, "evil corpus is empty"
    for evil_dir in evil_dirs:
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_archiver(evil_dir, os.path.join(tmpdir, "archive.bkp"))
            assert_malicious_result(result)


def test_dynamic_malicious_symlink_cases():
    cases = ["absolute", "relative", "self_cycle", "two_cycle", "outside_dir", "broken_outside"]
    for case in cases:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = os.path.join(tmpdir, "root")
            outside = os.path.join(tmpdir, "outside")
            os.mkdir(root)
            os.mkdir(outside)
            with open(os.path.join(root, "ordinary.txt"), "wb") as f:
                f.write(os.urandom(64))
            with open(os.path.join(outside, "secret"), "wb") as f:
                f.write(os.urandom(64))

            if case == "absolute":
                os.symlink("/etc/passwd", os.path.join(root, "link"))
            elif case == "relative":
                os.symlink("../outside/secret", os.path.join(root, "link"))
            elif case == "self_cycle":
                os.symlink("loop", os.path.join(root, "loop"))
            elif case == "two_cycle":
                os.symlink("b", os.path.join(root, "a"))
                os.symlink("a", os.path.join(root, "b"))
            elif case == "outside_dir":
                os.symlink(outside, os.path.join(root, "linked-directory"))
            elif case == "broken_outside":
                os.symlink("../../nonexistent-outside-target", os.path.join(root, "link"))

            result = run_archiver(root, os.path.join(tmpdir, "archive.bkp"))
            assert_malicious_result(result)


def test_symlink_swap_race_never_archives_outside_data():
    with tempfile.TemporaryDirectory() as tmpdir:
        root = os.path.join(tmpdir, "root")
        staging = os.path.join(tmpdir, "staging")
        os.mkdir(root)
        os.mkdir(staging)
        safe_data = b"SAFE-RACE-DATA-" + os.urandom(128)
        secret_data = b"OUTSIDE-SECRET-" + os.urandom(256)
        secret = os.path.join(tmpdir, "secret")
        with open(secret, "wb") as f:
            f.write(secret_data)
        with open(os.path.join(root, "stable.txt"), "wb") as f:
            f.write(b"stable")
        with open(os.path.join(root, "flip"), "wb") as f:
            f.write(safe_data)

        stop = threading.Event()

        def swapper():
            counter = 0
            while not stop.is_set():
                candidate = os.path.join(staging, f"candidate-{counter % 2}")
                try:
                    if os.path.lexists(candidate):
                        os.unlink(candidate)
                    os.symlink(secret, candidate)
                    os.replace(candidate, os.path.join(root, "flip"))
                    with open(candidate, "wb") as f:
                        f.write(safe_data)
                    os.replace(candidate, os.path.join(root, "flip"))
                except FileNotFoundError:
                    pass
                counter += 1

        thread = threading.Thread(target=swapper, daemon=True)
        thread.start()
        try:
            for attempt in range(25):
                archive = os.path.join(tmpdir, f"race-{attempt}.bkp")
                result = run_archiver(root, archive, timeout=15)
                if result.returncode == 1:
                    assert_malicious_result(result)
                    continue
                assert result.returncode == 0, (
                    f"race input returned unexpected code {result.returncode}"
                )
                entries = parse_archive(archive)
                assert entries.get("stable.txt") == b"stable"
                assert set(entries).issubset({"stable.txt", "flip"})
                if "flip" in entries:
                    assert entries["flip"] == safe_data, (
                        "archive captured data through an outside symlink during a race"
                    )
                assert secret_data not in entries.values(), "outside secret was archived"
        finally:
            stop.set()
            thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
