#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/open_trace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static const char *target = "/home/user/mock_ssh/authorized_keys";
static const char *trace_path = "/tmp/key_open_trace";

static void record_open(const char *pathname, int flags, mode_t mode) {
    if (pathname == NULL || strcmp(pathname, target) != 0 || !(flags & O_CREAT))
        return;

    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%o\n", (unsigned int)(mode & 07777));
    int fd = (int)syscall(SYS_openat, AT_FDCWD, trace_path,
                          O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, buf, (size_t)len);
        syscall(SYS_close, fd);
    }
}

int open(const char *pathname, int flags, ...) {
    static int (*real_open)(const char *, int, ...) = NULL;
    if (!real_open)
        real_open = dlsym(RTLD_NEXT, "open");

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        record_open(pathname, flags, mode);
        return real_open(pathname, flags, mode);
    }
    return real_open(pathname, flags);
}

int open64(const char *pathname, int flags, ...) {
    static int (*real_open64)(const char *, int, ...) = NULL;
    if (!real_open64)
        real_open64 = dlsym(RTLD_NEXT, "open64");

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        record_open(pathname, flags, mode);
        return real_open64(pathname, flags, mode);
    }
    return real_open64(pathname, flags);
}

int openat(int dirfd, const char *pathname, int flags, ...) {
    static int (*real_openat)(int, const char *, int, ...) = NULL;
    if (!real_openat)
        real_openat = dlsym(RTLD_NEXT, "openat");

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        record_open(pathname, flags, mode);
        return real_openat(dirfd, pathname, flags, mode);
    }
    return real_openat(dirfd, pathname, flags);
}

int openat64(int dirfd, const char *pathname, int flags, ...) {
    static int (*real_openat64)(int, const char *, int, ...) = NULL;
    if (!real_openat64)
        real_openat64 = dlsym(RTLD_NEXT, "openat64");

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        record_open(pathname, flags, mode);
        return real_openat64(dirfd, pathname, flags, mode);
    }
    return real_openat64(dirfd, pathname, flags);
}
TRACE_EOF

if ! gcc -shared -fPIC -o /tmp/libopen_trace.so /tmp/open_trace.c -ldl; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import hashlib
import json
import base64
import pytest


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) >= 3, "Audit report must contain exactly 3 lines."

    # Derive the malicious key from the payload to ensure truth alignment
    payload_path = "/home/user/evidence/payload.b64"
    assert os.path.isfile(payload_path), "Evidence payload missing."
    with open(payload_path, "r") as f:
        b64_data = f.read().strip()

    decoded_json = base64.b64decode(b64_data).decode("utf-8")
    payload = json.loads(decoded_json)
    malicious_key = payload.get("key", "")

    expected_cwe = "CWE-732"
    expected_hash = hashlib.sha256(malicious_key.encode("utf-8")).hexdigest()

    assert lines[0] == malicious_key, "Line 1 of report is incorrect. Expected the malicious key."
    assert lines[1] == expected_cwe, f"Line 2 of report is incorrect. Expected {expected_cwe}."
    assert lines[2] == expected_hash, "Line 3 of report is incorrect. Expected SHA256 hash of the malicious key."


def test_permissions():
    mock_ssh_dir = "/home/user/mock_ssh"
    auth_keys_file = "/home/user/mock_ssh/authorized_keys"

    assert os.path.isdir(mock_ssh_dir), f"{mock_ssh_dir} directory missing."
    assert os.path.isfile(auth_keys_file), f"{auth_keys_file} file missing."

    dir_stat = os.stat(mock_ssh_dir)
    assert stat.S_IMODE(dir_stat.st_mode) == 0o700, f"Permissions for {mock_ssh_dir} must be exactly 0700."

    file_stat = os.stat(auth_keys_file)
    assert stat.S_IMODE(file_stat.st_mode) == 0o600, f"Permissions for {auth_keys_file} must be exactly 0600."


def test_authorized_keys_content():
    auth_keys_file = "/home/user/mock_ssh/authorized_keys"
    valid_hashes_file = "/home/user/evidence/valid_hashes.txt"

    assert os.path.isfile(auth_keys_file), f"{auth_keys_file} file missing."
    assert os.path.isfile(valid_hashes_file), f"{valid_hashes_file} file missing."

    with open(valid_hashes_file, "r") as f:
        valid_hashes = set(line.strip() for line in f if line.strip())

    with open(auth_keys_file, "r") as f:
        keys = [line.strip() for line in f if line.strip()]

    assert len(keys) == len(valid_hashes), "The number of keys in authorized_keys does not match the number of valid hashes."

    key_hashes = []
    for key in keys:
        key_hash = hashlib.sha256(key.encode("utf-8")).hexdigest()
        key_hashes.append(key_hash)
        assert key_hash in valid_hashes, f"Found a key in authorized_keys that does not match any valid hash: {key}"

    assert set(key_hashes) == valid_hashes, "authorized_keys must contain every valid key exactly once."


def test_rust_code_patch():
    main_rs_path = "/home/user/key_service/src/main.rs"
    assert os.path.isfile(main_rs_path), f"Rust source file missing at {main_rs_path}"

    with open(main_rs_path, "r") as f:
        content = f.read()

    assert "0o777" not in content, "The vulnerable 0o777 permission is still present in main.rs."
    assert "0o600" in content, "The secure 0o600 permission was not found in main.rs."
    assert "OpenOptionsExt" in content, "The code does not appear to use OpenOptionsExt to set permissions securely."


def test_rust_compilation():
    project_dir = "/home/user/key_service"
    assert os.path.isdir(project_dir), f"Rust project directory missing at {project_dir}"

    result = subprocess.run(
        ["cargo", "build"],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert result.returncode == 0, f"Rust project failed to compile:\n{result.stderr}"


def test_rust_file_open_behavior():
    main_rs = "/home/user/key_service/src/main.rs"
    executable = "/tmp/verified_key_service"
    auth_keys = "/home/user/mock_ssh/authorized_keys"
    trace_path = "/tmp/key_open_trace"
    expected_written = b"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... example@server\n"

    compile_result = subprocess.run(
        ["rustc", "--edition=2021", main_rs, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, f"src/main.rs failed direct compilation:\n{compile_result.stderr}"
    assert os.path.isfile(executable), "Compiled Rust executable was not produced."

    with open(auth_keys, "rb") as f:
        original_content = f.read()
    original_mode = stat.S_IMODE(os.stat(auth_keys).st_mode)

    if os.path.exists(trace_path):
        os.unlink(trace_path)
    os.unlink(auth_keys)

    result = None
    created_regular = False
    created_mode = None
    created_content = None
    traced_modes = []

    try:
        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/libopen_trace.so"
        result = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            preexec_fn=lambda: os.umask(0),
            timeout=30,
        )

        if os.path.lexists(auth_keys):
            created_regular = stat.S_ISREG(os.lstat(auth_keys).st_mode)
            if created_regular:
                created_mode = stat.S_IMODE(os.stat(auth_keys).st_mode)
                with open(auth_keys, "rb") as f:
                    created_content = f.read()

        if os.path.isfile(trace_path):
            with open(trace_path, "r") as f:
                traced_modes = [int(line.strip(), 8) for line in f if line.strip()]
    finally:
        if os.path.lexists(auth_keys):
            os.unlink(auth_keys)
        with open(auth_keys, "wb") as f:
            f.write(original_content)
        os.chmod(auth_keys, original_mode)

    assert result is not None and result.returncode == 0, f"Patched Rust program failed when executed:\n{result.stderr if result else ''}"
    assert created_regular, "The patched program did not create authorized_keys as a regular file."
    assert traced_modes, "The patched program did not create authorized_keys through an open operation with an explicit mode."
    assert all(mode == 0o600 for mode in traced_modes), f"authorized_keys was opened for creation with insecure mode(s): {traced_modes}"
    assert created_mode == 0o600, f"The patched program created authorized_keys with mode {created_mode!r}, not 0600."
    assert created_content == expected_written, "The patched program did not preserve its authorized_keys write behavior."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
