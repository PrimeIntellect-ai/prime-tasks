#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import uuid
import subprocess
import pytest


def wait_until(predicate, message, timeout=4.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    assert predicate(), message


def read_text(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def write_config(path, value):
    encoded = value.encode("ascii")
    assert len(encoded) < 64
    with open(path, "r+b", buffering=0) as f:
        f.seek(0)
        f.write(encoded + b"\0" + b"\0" * (255 - len(encoded)))
        f.flush()
        os.fsync(f.fileno())


def build_audit_library():
    source = r'''
#define _GNU_SOURCE
#include <sys/inotify.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void audit_line(const char *line) {
    const char *path = getenv("WATCHER_AUDIT_FILE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    size_t n = 0;
    while (line[n]) n++;
    (void)write(fd, line, n);
    close(fd);
}

int inotify_add_watch(int fd, const char *pathname, uint32_t mask) {
    int result = (int)syscall(SYS_inotify_add_watch, fd, pathname, mask);
    char line[1024];
    snprintf(line, sizeof(line), "INOTIFY\t%s\tmask=%u\n",
             pathname ? pathname : "(null)", (unsigned)mask);
    audit_line(line);
    return result;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    void *result = (void *)syscall(SYS_mmap, addr, length, prot, flags, fd, offset);
    char procpath[64];
    char target[768];
    char line[1024];
    snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(procpath, target, sizeof(target) - 1);
    if (n < 0) {
        target[0] = '\0';
    } else {
        target[n] = '\0';
    }
    snprintf(line, sizeof(line), "MMAP\t%s\tlen=%zu\tprot=%d\toffset=%lld\n",
             target, length, prot, (long long)offset);
    audit_line(line);
    return result;
}
'''
    c_path = "/tmp/watcher_audit.c"
    so_path = "/tmp/libwatcher_audit.so"
    with open(c_path, "w") as f:
        f.write(source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", c_path, "-o", so_path],
        capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"Could not build audit library: {result.stderr}"
    return so_path


def test_watcher_functionality():
    cpp_file = "/home/user/config_watcher.cpp"
    executable = "/home/user/watcher"
    app_config = "/home/user/app_config.bin"
    symlink = "/home/user/active_env"
    log_file = "/home/user/watcher.log"
    audit_file = "/tmp/watcher_api_audit.log"

    assert os.path.isfile(cpp_file), f"Source code {cpp_file} not found."

    with open(cpp_file, "r", errors="replace") as f:
        source = f.read()
    required_source_patterns = {
        "inotify_add_watch": r"\binotify_add_watch\s*\(",
        "IN_MODIFY": r"\bIN_MODIFY\b",
        "mmap": r"\bmmap\s*\(",
        "munmap": r"\bmunmap\s*\(",
        "std::ofstream": r"\b(?:std::)?ofstream\b",
    }
    for description, pattern in required_source_patterns.items():
        assert re.search(pattern, source), f"Source does not use required mechanism: {description}"

    # Preserve the original fallback compilation behavior.
    if not os.path.isfile(executable):
        compile_result = subprocess.run(
            ["g++", "-std=c++17", cpp_file, "-o", executable],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"Compilation failed: {compile_result.stderr}"

    assert os.path.isfile(executable), f"Executable {executable} not found."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    assert os.path.isfile(app_config), f"Config file {app_config} not found."

    # Rebuild the demanded executable from the submitted source so the tested binary
    # cannot be unrelated to config_watcher.cpp.
    compile_result = subprocess.run(
        ["g++", "-std=c++17", cpp_file, "-o", executable],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Compilation failed: {compile_result.stderr}"
    assert os.path.isfile(executable), f"Executable {executable} not found."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."

    audit_library = build_audit_library()

    if os.path.exists(log_file):
        os.remove(log_file)
    if os.path.lexists(symlink):
        os.unlink(symlink)
    if os.path.exists(audit_file):
        os.remove(audit_file)

    env = os.environ.copy()
    env["LD_PRELOAD"] = audit_library
    env["WATCHER_AUDIT_FILE"] = audit_file

    process = subprocess.Popen([executable], env=env)
    random_paths = []
    try:
        wait_until(
            lambda: process.poll() is None and
                    "INOTIFY\t/home/user/app_config.bin\t" in read_text(audit_file),
            "Watcher did not establish an inotify watch on app_config.bin.",
        )

        # Original fixed trigger 1 and assertions.
        write_config(app_config, "/home/user/env_v1")
        wait_until(
            lambda: os.path.islink(symlink) and os.readlink(symlink) == "/home/user/env_v1",
            f"Symlink {symlink} was not created after first modification.",
        )
        assert os.path.islink(symlink), f"Symlink {symlink} was not created after first modification."
        target1 = os.readlink(symlink)
        assert target1 == "/home/user/env_v1", f"Symlink points to wrong target: {target1}"

        # Original fixed trigger 2 and assertions.
        write_config(app_config, "/home/user/env_v2")
        fixed_expected = "/home/user/env_v1\n/home/user/env_v2\n"
        wait_until(
            lambda: os.path.islink(symlink)
                    and os.readlink(symlink) == "/home/user/env_v2"
                    and read_text(log_file) == fixed_expected,
            "Watcher did not complete the second fixed update.",
        )
        assert os.path.islink(symlink), f"Symlink {symlink} is missing after second modification."
        target2 = os.readlink(symlink)
        assert target2 == "/home/user/env_v2", f"Symlink points to wrong target after update: {target2}"

        assert os.path.isfile(log_file), f"Log file {log_file} was not created."
        with open(log_file, "r") as f:
            log_content = f.read()
        expected_log = "/home/user/env_v1\n/home/user/env_v2\n"
        assert log_content.strip() == expected_log.strip(), \
            f"Log file content mismatch. Expected:\n{expected_log}\nGot:\n{log_content}"

        # Exercise unpredictable values derived by the verifier.
        expected_paths = ["/home/user/env_v1", "/home/user/env_v2"]
        for _ in range(3):
            value = "/tmp/watcher_env_" + uuid.uuid4().hex
            os.makedirs(value)
            random_paths.append(value)
            expected_paths.append(value)
            write_config(app_config, value)
            expected_now = "".join(path + "\n" for path in expected_paths)
            wait_until(
                lambda value=value, expected_now=expected_now:
                    os.path.islink(symlink)
                    and os.readlink(symlink) == value
                    and read_text(log_file) == expected_now,
                f"Watcher did not process unpredictable path {value!r}.",
            )
            assert os.readlink(symlink) == value

        final_expected = "".join(path + "\n" for path in expected_paths)
        assert read_text(log_file) == final_expected
        assert process.poll() is None, "Watcher exited instead of running continuously."

        audit = read_text(audit_file)
        inotify_lines = [line for line in audit.splitlines() if line.startswith("INOTIFY\t")]
        assert any(
            line.startswith("INOTIFY\t/home/user/app_config.bin\t")
            and (int(line.rsplit("mask=", 1)[1]) & 0x2)
            for line in inotify_lines
        ), "The watcher did not request IN_MODIFY for app_config.bin."

        mmap_lines = [line for line in audit.splitlines()
                      if line.startswith("MMAP\t/home/user/app_config.bin\t")]
        valid_maps = []
        for line in mmap_lines:
            length = int(re.search(r"\tlen=(\d+)", line).group(1))
            prot = int(re.search(r"\tprot=(\d+)", line).group(1))
            offset = int(re.search(r"\toffset=(-?\d+)", line).group(1))
            if length == 256 and (prot & 1) and not (prot & 2) and offset == 0:
                valid_maps.append(line)
        assert len(valid_maps) >= len(expected_paths), \
            "Each processed modification must read app_config.bin through a 256-byte read-only mmap."

    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)
        for path in random_paths:
            try:
                os.rmdir(path)
            except OSError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
