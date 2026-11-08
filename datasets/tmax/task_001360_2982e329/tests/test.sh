#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'WRAP_EOF' > /tmp/verify_interpose.c
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/file.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdlib.h>
#include <unistd.h>

static void mark_call(char c) {
    const char *path = getenv("VERIFY_CALL_MARKER");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        (void)write(fd, &c, 1);
        close(fd);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    mark_call('M');
    return (void *)syscall(SYS_mmap, addr, length, prot, flags, fd, offset);
}

int flock(int fd, int operation) {
    mark_call('L');
    return (int)syscall(SYS_flock, fd, operation);
}

int fcntl(int fd, int cmd, ...) {
    long arg = 0;
    switch (cmd) {
        case F_GETFD:
        case F_GETFL:
        case F_GETOWN:
#ifdef F_GETSIG
        case F_GETSIG:
#endif
#ifdef F_GETLEASE
        case F_GETLEASE:
#endif
            break;
        default: {
            va_list ap;
            va_start(ap, cmd);
            arg = va_arg(ap, long);
            va_end(ap);
            break;
        }
    }
    if (cmd == F_SETLK || cmd == F_SETLKW)
        mark_call('F');
    return (int)syscall(SYS_fcntl, fd, cmd, arg);
}
WRAP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import time


def xor_checksum(data):
    value = 0
    for byte in data:
        value ^= byte
    return value


def test_verify_program_compiles_and_operates_with_mmap_and_locking():
    verify_c_path = "/home/user/verify.c"
    verify_path = "/home/user/verify"
    assert os.path.isfile(verify_c_path), f"Missing C source file: {verify_c_path}"

    with open(verify_c_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "mmap" in content, "The program must use mmap to read hashes.bin"
    has_flock = "flock" in content
    has_fcntl = "F_SETLK" in content or "F_SETLKW" in content
    assert has_flock or has_fcntl, "The program must use file locking (flock or fcntl) before writing to the log"

    result = subprocess.run(
        ["gcc", "-std=c11", verify_c_path, "-o", verify_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"verify.c did not compile:\n{result.stderr}"
    assert os.path.isfile(verify_path), f"Missing compiled program: {verify_path}"
    assert os.access(verify_path, os.X_OK), f"Compiled program is not executable: {verify_path}"

    home = "/home/user"
    src_path = os.path.join(home, "src")
    hashes_path = os.path.join(home, "hashes.bin")
    log_path = os.path.join(home, "verified.log")
    backup = tempfile.mkdtemp(prefix="verifier-backup-", dir=home)
    saved_src = os.path.join(backup, "src")
    saved_hashes = os.path.join(backup, "hashes.bin")
    saved_log = os.path.join(backup, "verified.log")
    had_src = os.path.lexists(src_path)
    had_hashes = os.path.lexists(hashes_path)
    had_log = os.path.lexists(log_path)

    if had_src:
        os.rename(src_path, saved_src)
    if had_hashes:
        os.rename(hashes_path, saved_hashes)
    if had_log:
        os.rename(log_path, saved_log)

    marker = os.path.join(backup, "calls")
    token = secrets.token_hex(5)
    good_names = [f"ok_{token}_a.c", f"ok_{token}_b.c"]
    bad_name = f"bad_{token}.c"
    contents = {
        good_names[0]: secrets.token_bytes(71),
        good_names[1]: secrets.token_bytes(113),
        bad_name: secrets.token_bytes(89),
    }

    try:
        os.mkdir(src_path)
        for name, data in contents.items():
            with open(os.path.join(src_path, name), "wb") as f:
                f.write(data)

        with open(hashes_path, "wb") as f:
            for name in good_names:
                f.write(struct.pack("<31sB", name.encode(), xor_checksum(contents[name])))
            f.write(struct.pack("<31sB", bad_name.encode(), xor_checksum(contents[bad_name]) ^ 0xA5))

        sentinel = "preexisting-entry.c\n"
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(sentinel)

        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/verify_interpose.so"
        env["VERIFY_CALL_MARKER"] = marker

        lock_fd = os.open(log_path, os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        fcntl.lockf(lock_fd, fcntl.LOCK_EX)
        proc = subprocess.Popen(
            [verify_path], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        time.sleep(0.5)

        with open(log_path, "r", encoding="utf-8") as f:
            assert f.read() == sentinel, "verify wrote to verified.log without first acquiring the exclusive lock"

        exited_while_contended = proc.poll() is not None
        fcntl.lockf(lock_fd, fcntl.LOCK_UN)
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

        if exited_while_contended:
            stdout, stderr = proc.communicate(timeout=2)
            if os.path.exists(marker):
                os.unlink(marker)
            proc = subprocess.Popen(
                [verify_path], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )

        stdout, stderr = proc.communicate(timeout=5)
        assert proc.returncode == 0, f"verify failed on generated records: {stderr.decode(errors='replace')}"

        assert os.path.isfile(marker), "verify did not invoke the required mmap/locking APIs"
        calls = open(marker, "rb").read()
        assert b"M" in calls, "The compiled program did not call mmap while reading hashes.bin"
        assert b"L" in calls or b"F" in calls, "The compiled program did not call flock or a fcntl locking operation"

        with open(log_path, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines[0] == "preexisting-entry.c", "verify must append rather than truncate verified.log"
        assert set(lines[1:]) == set(good_names), f"verify logged incorrect generated records: {lines}"
        assert bad_name not in lines, "verify logged a file whose derived checksum was intentionally invalid"
    finally:
        if os.path.isdir(src_path):
            shutil.rmtree(src_path)
        elif os.path.lexists(src_path):
            os.unlink(src_path)
        if os.path.lexists(hashes_path):
            os.unlink(hashes_path)
        if os.path.lexists(log_path):
            os.unlink(log_path)
        if had_src:
            os.rename(saved_src, src_path)
        if had_hashes:
            os.rename(saved_hashes, hashes_path)
        if had_log:
            os.rename(saved_log, log_path)
        shutil.rmtree(backup, ignore_errors=True)


def test_verified_log_contents():
    log_path = "/home/user/verified.log"
    assert os.path.isfile(log_path), f"Missing log file: {log_path}"

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert set(lines) == {"main.c", "utils.c"}, f"verified.log should contain exactly main.c and utils.c, got: {lines}"


def test_src_files_modified_correctly():
    src_dir = "/home/user/src"

    main_c = os.path.join(src_dir, "main.c")
    utils_c = os.path.join(src_dir, "utils.c")
    bad_c = os.path.join(src_dir, "bad.c")

    assert os.path.isfile(main_c), f"Missing extracted file: {main_c}"
    assert os.path.isfile(utils_c), f"Missing extracted file: {utils_c}"
    assert os.path.isfile(bad_c), f"Missing extracted file: {bad_c}"

    with open(main_c, "r", encoding="utf-8") as f:
        main_content = f.read()
    assert "MODERN_API_CALL" in main_content, "main.c should have MODERN_API_CALL"
    assert "DEPRECATED_API_CALL" not in main_content, "main.c should not have DEPRECATED_API_CALL"

    with open(utils_c, "r", encoding="utf-8") as f:
        utils_content = f.read()
    assert "MODERN_API_CALL" in utils_content, "utils.c should have MODERN_API_CALL"
    assert "DEPRECATED_API_CALL" not in utils_content, "utils.c should not have DEPRECATED_API_CALL"

    with open(bad_c, "r", encoding="utf-8") as f:
        bad_content = f.read()
    assert "DEPRECATED_API_CALL" in bad_content, "bad.c should still have DEPRECATED_API_CALL (it was corrupted)"
    assert "MODERN_API_CALL" not in bad_content, "bad.c should not have MODERN_API_CALL"
TEST_EOF

if gcc -shared -fPIC /tmp/verify_interpose.c -o /tmp/verify_interpose.so && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
