#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_art_tool.py
import glob
import os
import random
import shutil
import struct
import subprocess
import tempfile
import time

CPP = "/home/user/art_tool.cpp"
BIN = "/home/user/art_tool"
OUT = "/home/user/out_files"
LOG = "/home/user/cycle_log.txt"
REPO = "/home/user/repo"
LOCK_LOG = "/tmp/art_tool_lock_audit.log"


def reset_outputs():
    if os.path.lexists(OUT):
        if os.path.islink(OUT) or not os.path.isdir(OUT):
            os.unlink(OUT)
        else:
            shutil.rmtree(OUT)
    os.makedirs(OUT, exist_ok=True)
    if os.path.lexists(LOG):
        if os.path.isdir(LOG) and not os.path.islink(LOG):
            shutil.rmtree(LOG)
        else:
            os.unlink(LOG)


def write_part(path, entries):
    with open(path, "wb") as f:
        f.write(b"ART\0")
        for entry in entries:
            destination = entry["path"].encode("utf-8")
            f.write(struct.pack("<BH", entry["type"], len(destination)))
            f.write(destination)
            if entry["type"] == 0:
                data = entry["data"]
                encoded = bytes(byte ^ 0xAA for byte in data)
                f.write(struct.pack("<II", entry["offset"], len(encoded)))
                f.write(encoded)
            else:
                target = entry["target"].encode("utf-8")
                f.write(struct.pack("<H", len(target)))
                f.write(target)


def run_concurrently(paths, env=None, timeout=30):
    processes = [subprocess.Popen([BIN, path], env=env) for path in paths]
    deadline = time.monotonic() + timeout
    try:
        for process, path in zip(processes, paths):
            remaining = deadline - time.monotonic()
            assert remaining > 0, "Concurrent art_tool execution timed out"
            rc = process.wait(timeout=remaining)
            assert rc == 0, f"art_tool failed for {path} with exit status {rc}"
    except BaseException:
        for process in processes:
            if process.poll() is None:
                process.kill()
        for process in processes:
            try:
                process.wait(timeout=2)
            except Exception:
                pass
        raise


def run_one(path, env=None):
    completed = subprocess.run([BIN, path], env=env, timeout=20)
    assert completed.returncode == 0, f"art_tool failed for {path} with exit status {completed.returncode}"


def build_lock_auditor():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

static void record_lock(const char *kind, int fd) {
    const char *log = getenv("LOCK_AUDIT_FILE");
    if (!log) return;
    char procpath[64], target[4096], line[4200];
    snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(procpath, target, sizeof(target) - 1);
    if (n < 0) return;
    target[n] = '\0';
    int len = snprintf(line, sizeof(line), "%s %s\n", kind, target);
    int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (out >= 0) {
        if (len > 0) write(out, line, (size_t)len);
        close(out);
    }
}

int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = NULL;
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    int result = real_flock(fd, operation);
    if (result == 0 && (operation & LOCK_EX) && !(operation & LOCK_UN))
        record_lock("flock", fd);
    return result;
}

int fcntl(int fd, int cmd, ...) {
    static int (*real_fcntl)(int, int, ...) = NULL;
    if (!real_fcntl) real_fcntl = dlsym(RTLD_NEXT, "fcntl");
    va_list ap;
    va_start(ap, cmd);
    int result;
    if (cmd == F_GETFD || cmd == F_GETFL || cmd == F_GETOWN) {
        result = real_fcntl(fd, cmd);
    } else if (cmd == F_SETLK || cmd == F_SETLKW || cmd == F_GETLK) {
        struct flock *lock = va_arg(ap, struct flock *);
        result = real_fcntl(fd, cmd, lock);
        if (result == 0 && (cmd == F_SETLK || cmd == F_SETLKW) &&
            lock && lock->l_type == F_WRLCK)
            record_lock("fcntl", fd);
    } else {
        long arg = va_arg(ap, long);
        result = real_fcntl(fd, cmd, arg);
    }
    va_end(ap);
    return result;
}
'''
    src = "/tmp/lock_audit.c"
    lib = "/tmp/lock_audit.so"
    with open(src, "w", encoding="utf-8") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", src, "-o", lib, "-ldl"],
        check=True,
        timeout=30,
    )
    return lib


# Preserve the original source and binary assertions.
assert os.path.isfile(CPP), f"C++ source code {CPP} is missing."
assert os.path.isfile(BIN), f"Compiled binary {BIN} is missing."
assert os.access(BIN, os.X_OK), f"Binary {BIN} is not executable."
with open(CPP, "r", encoding="utf-8") as f:
    source_content = f.read()
assert "<fcntl.h>" in source_content or "<sys/file.h>" in source_content, \
    "C++ source does not include <fcntl.h> or <sys/file.h> for file locking."
assert ("flock" in source_content or "F_SETLKW" in source_content or
        "F_SETLK" in source_content), \
    "C++ source does not contain 'flock' or 'F_SETLKW'/'F_SETLK' for file locking."

# Exercise the submitted executable concurrently on unpredictable archives.
lock_lib = build_lock_auditor()
env = os.environ.copy()
env["LD_PRELOAD"] = lock_lib
env["LOCK_AUDIT_FILE"] = LOCK_LOG
if os.path.exists(LOCK_LOG):
    os.unlink(LOCK_LOG)
reset_outputs()
with tempfile.TemporaryDirectory(prefix="art_parts_") as generated_repo:
    nonce = os.urandom(8).hex()
    destination = f"concurrent_{nonce}.bin"
    count = 24
    chunk_size = 65536
    expected_chunks = [os.urandom(chunk_size) for _ in range(count)]
    indexes = list(range(count))
    random.SystemRandom().shuffle(indexes)
    part_paths = []
    for sequence, index in enumerate(indexes):
        part = os.path.join(generated_repo, f"chunk_{sequence}.part")
        write_part(part, [{
            "type": 0,
            "path": destination,
            "offset": index * chunk_size,
            "data": expected_chunks[index],
        }])
        part_paths.append(part)

    run_concurrently(part_paths, env=env)
    result_path = os.path.join(OUT, destination)
    assert os.path.isfile(result_path), "Concurrent extraction did not create its destination file"
    with open(result_path, "rb") as f:
        actual = f.read()
    assert actual == b"".join(expected_chunks), "Concurrent chunk extraction produced corrupt data"

    assert os.path.isfile(LOCK_LOG), "No executed POSIX locking operation was observed"
    with open(LOCK_LOG, "r", encoding="utf-8", errors="replace") as f:
        lock_records = f.read().splitlines()
    assert any(line.endswith(" " + result_path) for line in lock_records), \
        "art_tool did not obtain an exclusive POSIX lock on the destination file"

# Exercise symlink creation and cycle detection through the executable.
reset_outputs()
with tempfile.TemporaryDirectory(prefix="art_links_") as generated_repo:
    nonce = os.urandom(6).hex()
    data_name = f"data_{nonce}"
    a, b, c = (f"a_{nonce}", f"b_{nonce}", f"c_{nonce}")
    valid = f"valid_{nonce}"
    archive = os.path.join(generated_repo, "links.part")
    write_part(archive, [
        {"type": 0, "path": data_name, "offset": 0, "data": b"dynamic target"},
        {"type": 1, "path": a, "target": b},
        {"type": 1, "path": b, "target": c},
        {"type": 1, "path": c, "target": a},
        {"type": 1, "path": valid, "target": data_name},
    ])
    run_one(archive, env=env)
    assert os.path.islink(os.path.join(OUT, a))
    assert os.path.islink(os.path.join(OUT, b))
    assert not os.path.lexists(os.path.join(OUT, c)), "A generated cyclic symlink was created"
    assert os.path.islink(os.path.join(OUT, valid))
    assert os.readlink(os.path.join(OUT, valid)) == data_name
    assert os.path.isfile(LOG), "Cycle log was not created for a generated cycle"
    with open(LOG, "r", encoding="utf-8") as f:
        assert c in f.read().splitlines(), "Rejected generated symlink was not logged"

# Restore the supplied repository deterministically, then execute every .part
# concurrently as promised by the instruction.
os.makedirs(REPO, exist_ok=True)
for old_part in glob.glob(os.path.join(REPO, "*.part")):
    os.unlink(old_part)
write_part(os.path.join(REPO, "part1.part"), [
    {"type": 0, "path": "file1.txt", "offset": 0, "data": b"Hello World! "},
    {"type": 1, "path": "linkA", "target": "linkB"},
])
write_part(os.path.join(REPO, "part2.part"), [
    {"type": 0, "path": "file1.txt", "offset": 13, "data": b"This is a test."},
    {"type": 1, "path": "linkB", "target": "linkC"},
])
write_part(os.path.join(REPO, "part3.part"), [
    {"type": 1, "path": "linkC", "target": "linkA"},
    {"type": 1, "path": "valid_link", "target": "file1.txt"},
])
original_parts = sorted(glob.glob(os.path.join(REPO, "*.part")))
reset_outputs()
run_concurrently(original_parts, env=env)
with open(os.path.join(OUT, "file1.txt"), "rb") as f:
    assert f.read() == b"Hello World! This is a test.", \
        "Concurrent execution over the supplied .part files corrupted file1.txt"
assert os.path.islink(os.path.join(OUT, "valid_link"))
assert os.readlink(os.path.join(OUT, "valid_link")) == "file1.txt"

# Run in deterministic order so the original final-state assertions remain valid.
reset_outputs()
for part in original_parts:
    run_one(part, env=env)

target_file = os.path.join(OUT, "file1.txt")
assert os.path.isfile(target_file), f"Extracted file {target_file} is missing."
with open(target_file, "rb") as f:
    content = f.read()
expected_content = b"Hello World! This is a test."
assert content == expected_content, \
    f"File content mismatch. Expected {expected_content}, got {content}"

valid_link = os.path.join(OUT, "valid_link")
assert os.path.islink(valid_link), f"Symlink {valid_link} is missing or not a symlink."
assert os.readlink(valid_link) == "file1.txt", \
    f"Symlink {valid_link} does not point to 'file1.txt'."

cycle_links = ["linkA", "linkB", "linkC"]
existing_links = []
missing_links = []
for link in cycle_links:
    link_path = os.path.join(OUT, link)
    if os.path.islink(link_path):
        existing_links.append(link)
    else:
        missing_links.append(link)
assert len(missing_links) >= 1, \
    "A cycle was created! None of the cyclic symlinks were prevented."
assert len(missing_links) == 1, \
    f"Expected exactly 1 symlink to be rejected to break the cycle, but {len(missing_links)} are missing: {missing_links}"
assert os.path.isfile(LOG), f"Cycle log file {LOG} is missing."
with open(LOG, "r", encoding="utf-8") as f:
    log_content = f.read().strip().splitlines()
rejected_link = missing_links[0]
assert any(rejected_link in line for line in log_content), \
    f"Cycle log does not contain the rejected symlink '{rejected_link}'."
PY_EOF

if python3 /tmp/verify_art_tool.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
