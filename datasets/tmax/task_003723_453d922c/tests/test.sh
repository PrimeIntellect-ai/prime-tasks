#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/workspace"
AUTH_LOG_PATH = os.path.join(WORKSPACE_DIR, "auth.log")
COMPROMISED_IPS_PATH = os.path.join(WORKSPACE_DIR, "compromised_ips.txt")
SECURE_READER_C = os.path.join(WORKSPACE_DIR, "secure_reader.c")
SECURE_READER_EXE = os.path.join(WORKSPACE_DIR, "secure_reader")
SECRET_PATH = os.path.join(WORKSPACE_DIR, "new_secret.txt")
VERIFIED_SECRET_PATH = os.path.join(WORKSPACE_DIR, "verified_secret.txt")
EXPECTED_HASH = "2abf9b2d87a2a07cb63a4365b210202fc0e6760ba2502ef893fcff5afcc42fc8"
AUDIT_SO = "/tmp/seccomp_audit.so"
REBUILT_EXE = "/tmp/rebuilt_secure_reader"


def test_compromised_ips_content():
    assert os.path.isfile(COMPROMISED_IPS_PATH), f"File {COMPROMISED_IPS_PATH} does not exist."

    expected_ips = set()
    if os.path.isfile(AUTH_LOG_PATH):
        with open(AUTH_LOG_PATH, "r") as f:
            for line in f:
                if "password=hunter2" in line:
                    match = re.search(r"src_ip=([0-9\.]+)", line)
                    if match:
                        expected_ips.add(match.group(1))

    expected_ips_sorted = sorted(expected_ips)
    with open(COMPROMISED_IPS_PATH, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips_sorted, (
        f"Expected IPs {expected_ips_sorted}, but got {actual_ips} in {COMPROMISED_IPS_PATH}"
    )


def test_verified_secret_content():
    assert os.path.isfile(VERIFIED_SECRET_PATH), f"File {VERIFIED_SECRET_PATH} does not exist."
    assert os.path.isfile(SECRET_PATH), f"Original secret file {SECRET_PATH} does not exist."

    with open(SECRET_PATH, "rb") as f:
        expected_secret = f.read()
    with open(VERIFIED_SECRET_PATH, "rb") as f:
        actual_secret = f.read()

    assert hashlib.sha256(expected_secret).hexdigest() == EXPECTED_HASH, "new_secret.txt was modified"
    assert actual_secret == expected_secret, (
        f"Content of {VERIFIED_SECRET_PATH} does not match {SECRET_PATH}"
    )


def test_secure_reader_c_source():
    assert os.path.isfile(SECURE_READER_C), f"Source file {SECURE_READER_C} does not exist."
    with open(SECURE_READER_C, "r") as f:
        source_code = f.read()

    assert "PR_SET_SECCOMP" in source_code, f"PR_SET_SECCOMP not found in {SECURE_READER_C}"
    assert "SECCOMP_MODE_STRICT" in source_code, f"SECCOMP_MODE_STRICT not found in {SECURE_READER_C}"


def test_secure_reader_executable_exists():
    assert os.path.isfile(SECURE_READER_EXE), f"Executable {SECURE_READER_EXE} does not exist."
    assert os.access(SECURE_READER_EXE, os.X_OK), f"File {SECURE_READER_EXE} is not executable."
    with open(SECURE_READER_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SECURE_READER_EXE} is not a compiled ELF executable"


def build_audit_library():
    if os.path.isfile(AUDIT_SO):
        return
    audit_c = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <linux/seccomp.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

static int strict_enabled = 0;

static void audit_byte(char value) {
    const char *text = getenv("SECCOMP_AUDIT_FD");
    if (text && *text) {
        int fd = atoi(text);
        syscall(SYS_write, fd, &value, 1);
    }
}

int prctl(int option, ...) {
    va_list ap;
    unsigned long arg2, arg3, arg4, arg5;
    va_start(ap, option);
    arg2 = va_arg(ap, unsigned long);
    arg3 = va_arg(ap, unsigned long);
    arg4 = va_arg(ap, unsigned long);
    arg5 = va_arg(ap, unsigned long);
    va_end(ap);

    if (option == PR_SET_SECCOMP && arg2 == SECCOMP_MODE_STRICT) {
        strict_enabled = 1;
        audit_byte('S');
        return 0;
    }
    return (int)syscall(SYS_prctl, option, arg2, arg3, arg4, arg5);
}

ssize_t write(int fd, const void *buf, size_t count) {
    static ssize_t (*real_write)(int, const void *, size_t) = NULL;
    if (fd == STDOUT_FILENO && !strict_enabled)
        audit_byte('B');
    if (!real_write)
        real_write = dlsym(RTLD_NEXT, "write");
    return real_write(fd, buf, count);
}
'''
    path = "/tmp/seccomp_audit.c"
    with open(path, "w") as f:
        f.write(audit_c)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", path, "-o", AUDIT_SO, "-ldl"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Could not build seccomp audit helper: {result.stderr}"


def run_with_seccomp_audit(executable, secret_path):
    build_audit_library()
    read_fd, write_fd = os.pipe()
    env = os.environ.copy()
    env["LD_PRELOAD"] = AUDIT_SO
    env["SECCOMP_AUDIT_FD"] = str(write_fd)
    proc = subprocess.Popen(
        [executable, secret_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        pass_fds=(write_fd,),
    )
    os.close(write_fd)
    try:
        stdout, stderr = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        os.close(read_fd)
        raise AssertionError(f"{executable} timed out")
    audit = os.read(read_fd, 4096)
    os.close(read_fd)
    return proc.returncode, stdout, stderr, audit


def assert_reader_behavior(executable):
    with open(SECRET_PATH, "rb") as f:
        expected_secret = f.read()

    returncode, stdout, stderr, audit = run_with_seccomp_audit(executable, SECRET_PATH)
    assert returncode == 0, f"Expected success for the valid secret, got exit code {returncode}: {stderr!r}"
    assert stdout == expected_secret, f"Valid secret output was incorrect: {stdout!r}"
    assert b"S" in audit, "The executable did not invoke prctl(PR_SET_SECCOMP, SECCOMP_MODE_STRICT)"
    assert b"B" not in audit, "The executable wrote to stdout before enabling strict seccomp"

    invalid_values = [os.urandom(37), b"BadSecret123-" + os.urandom(11), expected_secret + b"tampered"]
    for value in invalid_values:
        with tempfile.NamedTemporaryFile(mode="wb", delete=False) as tmp:
            tmp.write(value)
            tmp_path = tmp.name
        try:
            result = subprocess.run([executable, tmp_path], capture_output=True, timeout=5)
            assert result.returncode == 1, (
                f"Expected exit code 1 for a bad hash, but got {result.returncode}"
            )
            assert result.stdout == b"", "A rejected secret must not be written to stdout"
            assert result.stderr, "A rejected secret must print an error to stderr"
        finally:
            os.remove(tmp_path)

    for args in ([], [SECRET_PATH, SECRET_PATH]):
        result = subprocess.run([executable] + args, capture_output=True, timeout=5)
        assert result.returncode != 0, "The executable must accept exactly one command-line argument"
        assert result.stdout == b"", "Invalid invocation must not output a secret"


def test_secure_reader_behavior_and_seccomp():
    assert_reader_behavior(SECURE_READER_EXE)


def test_source_builds_and_has_same_required_behavior():
    result = subprocess.run(
        ["gcc", SECURE_READER_C, "-o", REBUILT_EXE, "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"secure_reader.c failed to compile: {result.stderr}"
    assert_reader_behavior(REBUILT_EXE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
