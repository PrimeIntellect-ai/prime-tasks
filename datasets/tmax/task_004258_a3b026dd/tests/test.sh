#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import cv2
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

SOURCE = "/home/user/dataset_filter.c"
EXECUTABLE = "/home/user/dataset_filter"


@pytest.fixture(scope="session", autouse=True)
def compile_submission():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    subprocess.run(["gcc", "-O2", SOURCE, "-o", EXECUTABLE], check=True)
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."


def make_valid(payload):
    checksum = 0
    for byte in payload:
        checksum ^= byte
    return b"DSF2" + struct.pack("<I", len(payload)) + payload + bytes([checksum])


def test_pulse_count():
    pulse_file = "/home/user/pulse_count.txt"
    assert os.path.isfile(pulse_file), f"File {pulse_file} does not exist."
    with open(pulse_file, "r") as f:
        content = f.read().strip()
    assert content == "27", f"Expected pulse count to be 27, but got {content}."

    capture = cv2.VideoCapture("/app/experiment_video.mp4")
    assert capture.isOpened(), "Could not open experiment video."
    expected = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        height, width = gray.shape
        center = gray[height // 2 - 5:height // 2 + 5,
                      width // 2 - 5:width // 2 + 5]
        assert center.shape == (10, 10)
        if float(center.mean()) > 200.0:
            expected += 1
    capture.release()
    assert int(content) == expected, (
        f"Pulse count {content} does not match analysis of the video ({expected})."
    )


def test_dataset_filter_executable():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."


def test_dataset_filter_clean_corpus():
    clean_in = "/app/corpus/clean"
    with tempfile.TemporaryDirectory() as clean_out:
        clean_manifest = os.path.join(clean_out, "manifest.txt")
        result = subprocess.run(
            [EXECUTABLE, clean_in, clean_out, clean_manifest],
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, f"dataset_filter failed on clean corpus: {result.stderr}"

        expected_files = set(os.listdir(clean_in))
        actual_files = set(os.listdir(clean_out)) - {"manifest.txt"}
        missing = expected_files - actual_files
        assert not missing, (
            f"{len(missing)} of {len(expected_files)} clean files modified/rejected: {missing}"
        )
        for name in expected_files:
            with open(os.path.join(clean_in, name), "rb") as fin, \
                 open(os.path.join(clean_out, name), "rb") as fout:
                assert fin.read() == fout.read(), f"Clean file {name} was modified during copy."


def test_dataset_filter_evil_corpus():
    evil_in = "/app/corpus/evil"
    with tempfile.TemporaryDirectory() as evil_out:
        evil_manifest = os.path.join(evil_out, "manifest.txt")
        result = subprocess.run(
            [EXECUTABLE, evil_in, evil_out, evil_manifest],
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, f"dataset_filter failed on evil corpus: {result.stderr}"

        actual_files = set(os.listdir(evil_out)) - {"manifest.txt"}
        expected_files = set(os.listdir(evil_in))
        assert not actual_files, (
            f"{len(actual_files)} of {len(expected_files)} evil files bypassed: {actual_files}"
        )


def build_audit_library(directory):
    source = Path(directory) / "audit.c"
    library = Path(directory) / "audit.so"
    source.write_text(r'''#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static __thread int busy;

static void emit(const char *fmt, ...) {
    if (busy) return;
    busy = 1;
    const char *path = getenv("DATASET_AUDIT_LOG");
    if (path) {
        char buf[PATH_MAX * 2 + 32];
        va_list ap;
        va_start(ap, fmt);
        int n = vsnprintf(buf, sizeof(buf), fmt, ap);
        va_end(ap);
        if (n > 0) {
            int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (fd >= 0) {
                size_t amount = (size_t)n < sizeof(buf) ? (size_t)n : sizeof(buf) - 1;
                write(fd, buf, amount);
                close(fd);
            }
        }
    }
    busy = 0;
}

static void fd_path(int fd, char *out, size_t size) {
    char proc[64];
    snprintf(proc, sizeof(proc), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(proc, out, size - 1);
    if (n < 0) out[0] = '\0';
    else out[n] = '\0';
}

static void at_path(int dirfd, const char *path, char *out, size_t size) {
    if (path[0] == '/') {
        snprintf(out, size, "%s", path);
        return;
    }
    char base[PATH_MAX];
    if (dirfd == AT_FDCWD) {
        if (!getcwd(base, sizeof(base))) base[0] = '\0';
    } else {
        fd_path(dirfd, base, sizeof(base));
    }
    snprintf(out, size, "%s/%s", base, path);
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_fn)(void *, size_t, int, int, int, off_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "mmap");
    void *result = real_fn(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED && fd >= 0) {
        char path[PATH_MAX];
        fd_path(fd, path, sizeof(path));
        emit("M\t%s\n", path);
    }
    return result;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_fn)(void *, size_t, int, int, int, off64_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "mmap64");
    void *result = real_fn(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED && fd >= 0) {
        char path[PATH_MAX];
        fd_path(fd, path, sizeof(path));
        emit("M\t%s\n", path);
    }
    return result;
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    char old_abs[PATH_MAX], new_abs[PATH_MAX];
    at_path(AT_FDCWD, oldpath, old_abs, sizeof(old_abs));
    at_path(AT_FDCWD, newpath, new_abs, sizeof(new_abs));
    int result = real_fn(oldpath, newpath);
    if (result == 0) emit("R\t%s\t%s\n", old_abs, new_abs);
    return result;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    char old_abs[PATH_MAX], new_abs[PATH_MAX];
    at_path(olddirfd, oldpath, old_abs, sizeof(old_abs));
    at_path(newdirfd, newpath, new_abs, sizeof(new_abs));
    int result = real_fn(olddirfd, oldpath, newdirfd, newpath);
    if (result == 0) emit("R\t%s\t%s\n", old_abs, new_abs);
    return result;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd,
              const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    char old_abs[PATH_MAX], new_abs[PATH_MAX];
    at_path(olddirfd, oldpath, old_abs, sizeof(old_abs));
    at_path(newdirfd, newpath, new_abs, sizeof(new_abs));
    int result = real_fn(olddirfd, oldpath, newdirfd, newpath, flags);
    if (result == 0) emit("R\t%s\t%s\n", old_abs, new_abs);
    return result;
}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", str(source), "-o", str(library), "-ldl"],
        check=True
    )
    return str(library)


def test_randomized_recursive_validation_manifest_mmap_and_atomic_writes():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix=f"input_{token}_") as input_dir, \
         tempfile.TemporaryDirectory(prefix=f"output_{token}_") as output_dir, \
         tempfile.TemporaryDirectory(prefix=f"meta_{token}_") as meta_dir:
        nested_a = Path(input_dir) / f"level_{secrets.token_hex(3)}"
        nested_b = nested_a / f"deeper_{secrets.token_hex(3)}"
        nested_b.mkdir(parents=True)

        valid = {}
        locations = {}
        specs = [
            (Path(input_dir), secrets.token_hex(5) + ".bin", os.urandom(37)),
            (nested_a, secrets.token_hex(5) + ".raw", os.urandom(513)),
            (nested_b, secrets.token_hex(5) + ".dat", os.urandom(4097)),
            (nested_b, secrets.token_hex(5), b""),
        ]
        for parent, name, payload in specs:
            data = make_valid(payload)
            path = parent / name
            path.write_bytes(data)
            valid[name] = data
            locations[name] = str(path.resolve())

        malformed = {
            secrets.token_hex(5) + ".bad": b"DSF3" + struct.pack("<I", 1) + b"A\x41",
            secrets.token_hex(5) + ".bad": b"DSF2" + struct.pack("<I", 0xffffffff) + b"x",
            secrets.token_hex(5) + ".bad": b"DSF2" + struct.pack("<I", 20) + b"short",
            secrets.token_hex(5) + ".bad": make_valid(b"payload") + b"trailing",
            secrets.token_hex(5) + ".bad": b"DSF2" + struct.pack("<I", 4) + b"abcd\x00",
            secrets.token_hex(5) + ".bad": b"DSF2" + struct.pack("<I", 0),
            secrets.token_hex(5) + ".bad": os.urandom(3),
        }
        for index, (name, data) in enumerate(malformed.items()):
            parent = [Path(input_dir), nested_a, nested_b][index % 3]
            (parent / name).write_bytes(data)

        manifest = str(Path(meta_dir) / "manifest.txt")
        audit_log = str(Path(meta_dir) / "audit.log")
        audit_library = build_audit_library(meta_dir)
        env = os.environ.copy()
        env["LD_PRELOAD"] = audit_library
        env["DATASET_AUDIT_LOG"] = audit_log

        result = subprocess.run(
            [EXECUTABLE, input_dir, output_dir, manifest],
            capture_output=True, text=True, timeout=30, env=env
        )
        assert result.returncode == 0, result.stderr

        output_names = set(os.listdir(output_dir))
        assert output_names == set(valid), (
            f"Expected only randomized valid files, got {output_names}"
        )
        for name, expected_data in valid.items():
            assert (Path(output_dir) / name).read_bytes() == expected_data

        assert os.path.isfile(manifest), "Manifest was not created."
        with open(manifest, "r") as handle:
            lines = [line.rstrip("\n") for line in handle]
        expected_lines = sorted(f"{name} {len(data)}" for name, data in valid.items())
        assert sorted(lines) == expected_lines, (
            f"Manifest contents are incorrect: {lines}"
        )

        audit_lines = Path(audit_log).read_text().splitlines() if os.path.exists(audit_log) else []
        mapped = {
            os.path.realpath(line.split("\t", 1)[1])
            for line in audit_lines if line.startswith("M\t")
        }
        for name, input_path in locations.items():
            assert os.path.realpath(input_path) in mapped, f"Valid input {name} was not read using mmap."

        renames = []
        for line in audit_lines:
            fields = line.split("\t")
            if len(fields) == 3 and fields[0] == "R":
                renames.append((os.path.normpath(fields[1]), os.path.normpath(fields[2])))
        for name in valid:
            final_path = os.path.normpath(os.path.join(output_dir, name))
            matching = [(old, new) for old, new in renames if new == final_path]
            assert matching, f"No successful atomic rename produced {name}."
            assert any(
                old != new and os.path.dirname(old) == os.path.normpath(output_dir)
                for old, new in matching
            ), f"{name} was not renamed from a temporary file in the output directory."


def test_exact_argument_count():
    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, "in")
        output_dir = os.path.join(root, "out")
        manifest = os.path.join(root, "manifest")
        os.mkdir(input_dir)
        os.mkdir(output_dir)
        bad_argv = [
            [EXECUTABLE],
            [EXECUTABLE, input_dir],
            [EXECUTABLE, input_dir, output_dir],
            [EXECUTABLE, input_dir, output_dir, manifest, "extra"],
        ]
        for argv in bad_argv:
            result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
            assert result.returncode != 0, f"Accepted invalid argument count: {len(argv) - 1}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
