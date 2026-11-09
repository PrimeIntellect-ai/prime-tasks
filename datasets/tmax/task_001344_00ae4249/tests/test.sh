#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import random
import re
import string
import subprocess
import time
import uuid

SOURCE = "/home/user/detect_zipslip.c"
LOG = "/home/user/restore_requests.log"
ALERTS = "/home/user/alerts.csv"
BINARY = "/tmp/detect_zipslip_test"
HOOK = "/tmp/lock_hook.so"
MARKER = "/tmp/lock_marker"


def test_c_source_code_exists_and_uses_locking():
    assert os.path.exists(SOURCE), f"The C source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"The path {SOURCE} is not a file."

    with open(SOURCE, "r") as f:
        content = f.read()

    has_flock = "flock" in content
    has_fcntl = "fcntl" in content
    assert has_flock or has_fcntl, (
        f"The C source code in {SOURCE} must use file locking (flock or fcntl)."
    )


def test_alerts_csv_content():
    assert os.path.exists(ALERTS), f"The output file {ALERTS} does not exist."
    assert os.path.isfile(ALERTS), f"The path {ALERTS} is not a file."

    expected_content = """ID,FILE
REQ002,../../etc/passwd
REQ005,a/b/c/../../../../tmp/hacked
REQ006,/var/log/syslog
"""

    with open(ALERTS, "r") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().split("\n")]
    expected_lines = [line.strip() for line in expected_content.strip().split("\n")]
    assert actual_lines == expected_lines, (
        f"The content of {ALERTS} does not match the expected output.\n"
        f"Expected:\n{expected_content}\nActual:\n{actual_content}"
    )


def test_alerts_csv_no_duplicate_headers():
    if os.path.exists(ALERTS):
        with open(ALERTS, "r") as f:
            content = f.read()
        header_count = content.count("ID,FILE")
        assert header_count == 1, (
            f"The header 'ID,FILE' should appear exactly once in {ALERTS}, "
            f"found {header_count} times."
        )


def is_attack(path):
    if path.startswith("/"):
        return True
    depth = 0
    for component in path.split("/"):
        if component == "..":
            depth -= 1
        elif component not in ("", "."):
            depth += 1
        if depth < 0:
            return True
    return False


def write_log(records):
    with open(LOG, "w") as f:
        for record_id, path in records:
            f.write(
                "BEGIN_RECORD\n"
                f"ID: {record_id}\n"
                f"BASE: /restore/{record_id}\n"
                f"FILE: {path}\n"
                "END_RECORD\n\n"
            )


def expected_csv(records, include_header=True):
    result = "ID,FILE\n" if include_header else ""
    for record_id, path in records:
        if is_attack(path):
            result += f"{record_id},{path}\n"
    return result


def make_records(paths):
    prefix = uuid.uuid4().hex[:10].upper()
    return [(f"{prefix}{i}", path) for i, path in enumerate(paths)]


def compile_lock_hook():
    hook_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

static void mark_lock(void) {
    const char *path = getenv("LOCK_MARKER");
    if (!path) return;
    int fd = (int)syscall(SYS_openat, AT_FDCWD, path,
                          O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        const char byte = '1';
        syscall(SYS_write, fd, &byte, 1);
        syscall(SYS_close, fd);
    }
}

int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = 0;
    if (!real_flock)
        real_flock = (int (*)(int, int))dlsym(RTLD_NEXT, "flock");
    if ((operation & LOCK_EX) == LOCK_EX)
        mark_lock();
    return real_flock(fd, operation);
}

int fcntl(int fd, int cmd, ...) {
    static int (*real_fcntl)(int, int, ...) = 0;
    if (!real_fcntl)
        real_fcntl = (int (*)(int, int, ...))dlsym(RTLD_NEXT, "fcntl");

    if (cmd == F_GETFD || cmd == F_GETFL || cmd == F_GETOWN
#ifdef F_GETSIG
        || cmd == F_GETSIG
#endif
#ifdef F_GETLEASE
        || cmd == F_GETLEASE
#endif
#ifdef F_GETPIPE_SZ
        || cmd == F_GETPIPE_SZ
#endif
    ) {
        return real_fcntl(fd, cmd);
    }

    va_list ap;
    va_start(ap, cmd);
    uintptr_t arg = va_arg(ap, uintptr_t);
    va_end(ap);

    int lock_command = (cmd == F_SETLK || cmd == F_SETLKW);
#ifdef F_OFD_SETLK
    lock_command = lock_command || cmd == F_OFD_SETLK || cmd == F_OFD_SETLKW;
#endif
    if (lock_command) {
        struct flock *lock = (struct flock *)arg;
        if (lock && lock->l_type == F_WRLCK)
            mark_lock();
    }
    return real_fcntl(fd, cmd, arg);
}
'''
    with open("/tmp/lock_hook.c", "w") as f:
        f.write(hook_source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", HOOK,
         "/tmp/lock_hook.c", "-ldl"],
        text=True, capture_output=True
    )
    assert result.returncode == 0, f"Failed to build locking test helper:\n{result.stderr}"


def test_program_compiles_executes_parses_and_locks():
    compile_result = subprocess.run(
        ["gcc", "-O2", "-o", BINARY, SOURCE],
        text=True, capture_output=True
    )
    assert compile_result.returncode == 0, (
        f"The submitted C program does not compile with gcc:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    nonce = "".join(random.choice(string.ascii_lowercase) for _ in range(10))
    first_records = make_records([
        f"safe/{nonce}/file.txt",
        f"../outside/{nonce}",
        f"one/./two/../{nonce}",
        f"a//b/../../{nonce}",
        f"a/b/../../../escaped-{nonce}",
        f"/absolute/{nonce}",
        f"x/y/../../z/{nonce}",
    ])
    write_log(first_records)
    if os.path.exists(ALERTS):
        os.unlink(ALERTS)

    run = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8
    )
    assert run.returncode == 0, (
        f"The compiled program failed when executed:\n{run.stderr}"
    )
    assert os.path.isfile(ALERTS), "The executed program did not create alerts.csv."
    with open(ALERTS, "r") as f:
        first_actual = f.read()
    first_expected = expected_csv(first_records)
    assert first_actual == first_expected, (
        "The executed program did not correctly parse dynamically generated records.\n"
        f"Expected:\n{first_expected}\nActual:\n{first_actual}"
    )

    second_records = make_records([
        f"folder/{nonce}/../ok.bin",
        f"../../secret-{nonce}",
        f"././normal-{nonce}",
        f"p/q/r/../../../../escape-{nonce}",
    ])
    write_log(second_records)
    before = first_actual
    compile_lock_hook()
    if os.path.exists(MARKER):
        os.unlink(MARKER)

    lock_fd = os.open(ALERTS, os.O_RDWR)
    proc = None
    try:
        # Hold both BSD flock and POSIX record locks so either permitted locking
        # implementation must wait before modifying the CSV.
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.lockf(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

        env = os.environ.copy()
        env["LD_PRELOAD"] = HOOK
        env["LOCK_MARKER"] = MARKER
        proc = subprocess.Popen(
            [BINARY], cwd="/home/user", env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        deadline = time.time() + 3
        while time.time() < deadline and not os.path.exists(MARKER):
            if proc.poll() is not None:
                break
            time.sleep(0.03)

        assert os.path.exists(MARKER), (
            "The running program did not attempt an exclusive flock/fcntl lock."
        )
        assert proc.poll() is None, (
            "The program did not wait for the existing exclusive lock."
        )
        with open(ALERTS, "r") as f:
            assert f.read() == before, (
                "alerts.csv was modified while another process held an exclusive lock."
            )
    finally:
        try:
            fcntl.lockf(lock_fd, fcntl.LOCK_UN)
        finally:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)

    stdout, stderr = proc.communicate(timeout=8)
    assert proc.returncode == 0, f"Program failed after lock release:\n{stderr}"

    expected_after = before + expected_csv(second_records, include_header=False)
    with open(ALERTS, "r") as f:
        actual_after = f.read()
    assert actual_after == expected_after, (
        "The program did not append the correct dynamic findings after lock release.\n"
        f"Expected:\n{expected_after}\nActual:\n{actual_after}"
    )
    assert actual_after.count("ID,FILE") == 1, (
        "The program added a duplicate CSV header when appending."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
