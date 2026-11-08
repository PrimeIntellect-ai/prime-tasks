#!/bin/bash
set -e
mkdir -p /logs/verifier

AUDIT_DIR="$(mktemp -d /tmp/bdoc-verifier.XXXXXX)"
trap 'rm -rf "$AUDIT_DIR"' EXIT

cat > "$AUDIT_DIR/flock_audit.c" <<'C_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static int (*real_flock)(int, int) = NULL;

int flock(int fd, int operation) {
    if (!real_flock) {
        real_flock = (int (*)(int, int))dlsym(RTLD_NEXT, "flock");
        if (!real_flock) _exit(125);
    }

    int result = real_flock(fd, operation);
    if (result == 0) {
        const char *log_path = getenv("BDOC_FLOCK_AUDIT_LOG");
        if (log_path && *log_path) {
            char link_path[64];
            char target[PATH_MAX];
            char line[PATH_MAX + 96];
            snprintf(link_path, sizeof(link_path), "/proc/self/fd/%d", fd);
            ssize_t n = readlink(link_path, target, sizeof(target) - 1);
            if (n >= 0) target[n] = '\0';
            else snprintf(target, sizeof(target), "<unreadable>");

            int len = snprintf(line, sizeof(line), "%ld %d %s\n",
                               (long)getpid(), operation, target);
            int out = (int)syscall(SYS_openat, AT_FDCWD, log_path,
                                   O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (out >= 0) {
                syscall(SYS_write, out, line, (size_t)len);
                syscall(SYS_close, out);
            }
        }
    }
    return result;
}
C_EOF

gcc -shared -fPIC -O2 -o "$AUDIT_DIR/flock_audit.so" "$AUDIT_DIR/flock_audit.c" -ldl
export BDOC_AUDIT_DIR="$AUDIT_DIR"
export BDOC_AUDIT_SO="$AUDIT_DIR/flock_audit.so"

cat << 'TEST_EOF' > "$AUDIT_DIR/test_final_state.py"
import collections
import os
import re
import secrets
import shutil
import struct
import subprocess
import time

COMPILED = '/home/user/compiled_docs.md'
SOURCE = '/home/user/bdoc_parser.cpp'
EXECUTABLE = '/home/user/bdoc_parser'
AUDIT_DIR = os.environ['BDOC_AUDIT_DIR']
AUDIT_SO = os.environ['BDOC_AUDIT_SO']


def test_final_docs_exists_and_correct():
    final_docs_path = '/home/user/final_docs.md'
    assert os.path.exists(final_docs_path), f"The file {final_docs_path} does not exist. Did you create it?"
    assert os.path.isfile(final_docs_path), f"The path {final_docs_path} is not a regular file."

    expected_content = """# API Reference

Endpoints are RESTful and use JSON payloads.
---
# Architecture

The system uses a monolithic design with modular components.
---
# Authentication

JWT tokens are required in the Authorization header.
---
# Deployment

Use the provided Docker Compose file to deploy the stack.
---"""

    with open(final_docs_path, 'r') as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), (
        f"The content of {final_docs_path} does not match the expected sorted markdown output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{content}"
    )


def test_cpp_parser_exists_and_uses_flock():
    assert os.path.exists(SOURCE), f"The C++ source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"The path {SOURCE} is not a regular file."

    with open(SOURCE, 'r') as f:
        content = f.read()

    assert 'flock' in content, "The C++ program must use flock() to ensure thread-safe appends."
    assert 'LOCK_EX' in content, "The C++ program must use LOCK_EX with flock()."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"The executable {EXECUTABLE} does not exist. Did you compile the C++ program?"
    assert os.path.isfile(EXECUTABLE), f"The path {EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The compiled parser must be an ELF executable."


def _write_bdoc(path, title, content):
    title_bytes = title.encode('ascii')
    content_bytes = content.encode('ascii')
    with open(path, 'wb') as f:
        f.write(b'BDOC')
        f.write(struct.pack('<I', len(title_bytes)))
        f.write(title_bytes)
        f.write(struct.pack('<I', len(content_bytes)))
        f.write(content_bytes)


def _run_concurrent_batch(executable, label):
    token = secrets.token_hex(12)
    input_dir = os.path.join(AUDIT_DIR, label + '-inputs-' + token)
    os.mkdir(input_dir)
    audit_log = os.path.join(AUDIT_DIR, label + '-flock-' + token + '.log')
    open(audit_log, 'wb').close()
    open(COMPILED, 'wb').close()

    expected = []
    paths = []
    for i in range(32):
        title = f"Verifier {token} {i:03d}"
        fragment = secrets.token_hex(24)
        content = (f"dynamic-{i:03d}-{fragment}-" * 3000) + f"end-{token}-{i}"
        path = os.path.join(input_dir, f'{i:03d}.bdoc')
        _write_bdoc(path, title, content)
        paths.append(path)
        expected.append(f"# {title}\n\n{content}\n---\n")

    env = os.environ.copy()
    env['LD_PRELOAD'] = AUDIT_SO
    env['BDOC_FLOCK_AUDIT_LOG'] = audit_log
    processes = [subprocess.Popen([executable, path], env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                 for path in paths]
    deadline = time.monotonic() + 30
    failures = []
    for process in processes:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            process.kill()
            failures.append('timeout')
            continue
        try:
            stdout, stderr = process.communicate(timeout=remaining)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
            failures.append('timeout')
            continue
        if process.returncode != 0:
            failures.append(f"pid {process.pid}: rc={process.returncode}, stderr={stderr.decode(errors='replace')}")
    assert not failures, f"Parser executions failed: {failures}"

    with open(COMPILED, 'r', encoding='ascii', newline='') as f:
        actual = f.read()
    block_pattern = re.compile(r'# [^\n]+\n\n.*?\n---\n', re.DOTALL)
    blocks = block_pattern.findall(actual)
    assert ''.join(blocks) == actual, "Concurrent parser output contains malformed or interleaved Markdown blocks."
    assert collections.Counter(blocks) == collections.Counter(expected), (
        "The parser did not decode and append every dynamically generated .bdoc file exactly once."
    )

    events = collections.defaultdict(list)
    with open(audit_log, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.rstrip('\n').split(' ', 2)
            assert len(parts) == 3, f"Malformed flock audit record: {line!r}"
            pid, operation, target = int(parts[0]), int(parts[1]), parts[2]
            events[pid].append((operation, target))

    for process in processes:
        own_events = events[process.pid]
        exclusive_positions = [i for i, (op, target) in enumerate(own_events)
                               if (op & 2) and target == COMPILED]
        unlock_positions = [i for i, (op, target) in enumerate(own_events)
                            if (op & 8) and target == COMPILED]
        assert exclusive_positions, f"Parser pid {process.pid} never acquired LOCK_EX on {COMPILED}."
        assert unlock_positions, f"Parser pid {process.pid} never unlocked {COMPILED}."
        assert exclusive_positions[0] < unlock_positions[-1], (
            f"Parser pid {process.pid} did not unlock after acquiring its exclusive lock."
        )


def test_parser_behavior_and_concurrent_locking():
    rebuilt = os.path.join(AUDIT_DIR, 'rebuilt_bdoc_parser')
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE, '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        "bdoc_parser.cpp could not be compiled:\n" + compile_result.stderr
    )

    existed = os.path.exists(COMPILED)
    backup = os.path.join(AUDIT_DIR, 'compiled_docs.backup')
    old_stat = None
    if existed:
        old_stat = os.stat(COMPILED)
        shutil.copyfile(COMPILED, backup)

    try:
        _run_concurrent_batch(EXECUTABLE, 'submitted-executable')
        _run_concurrent_batch(rebuilt, 'rebuilt-source')
    finally:
        if existed:
            shutil.copyfile(backup, COMPILED)
            os.chmod(COMPILED, old_stat.st_mode)
            os.chown(COMPILED, old_stat.st_uid, old_stat.st_gid)
        elif os.path.exists(COMPILED):
            os.unlink(COMPILED)
TEST_EOF

if python3 -m pytest "$AUDIT_DIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
