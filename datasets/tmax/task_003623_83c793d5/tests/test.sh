#!/bin/bash
set +e
mkdir -p /logs/verifier

run_checks() (
set -e

cat << 'AUDIT_EOF' > /tmp/rotate_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static char audit_path[4096];

__attribute__((constructor)) static void init_audit(void) {
    const char *p = getenv("ROTATE_AUDIT");
    if (p) {
        strncpy(audit_path, p, sizeof(audit_path) - 1);
        audit_path[sizeof(audit_path) - 1] = '\0';
    }
}

static void audit_log(const char *fmt, ...) {
    if (!audit_path[0]) return;
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n <= 0) return;
    if (n > (int)sizeof(buf)) n = sizeof(buf);
    int fd = syscall(SYS_openat, AT_FDCWD, audit_path,
                     O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, buf, (size_t)n);
        syscall(SYS_close, fd);
    }
}

int pipe(int fds[2]) {
    static int (*real_pipe)(int[2]);
    if (!real_pipe) real_pipe = dlsym(RTLD_NEXT, "pipe");
    int rc = real_pipe(fds);
    audit_log("PIPE pid=%ld rc=%d\n", (long)getpid(), rc);
    return rc;
}

int pipe2(int fds[2], int flags) {
    static int (*real_pipe2)(int[2], int);
    if (!real_pipe2) real_pipe2 = dlsym(RTLD_NEXT, "pipe2");
    int rc = real_pipe2(fds, flags);
    audit_log("PIPE pid=%ld rc=%d\n", (long)getpid(), rc);
    return rc;
}

pid_t fork(void) {
    static pid_t (*real_fork)(void);
    if (!real_fork) real_fork = dlsym(RTLD_NEXT, "fork");
    pid_t parent = getpid();
    pid_t rc = real_fork();
    if (rc == 0)
        audit_log("FORK_CHILD pid=%ld parent=%ld\n", (long)getpid(), (long)parent);
    else
        audit_log("FORK_PARENT pid=%ld child=%ld rc=%ld\n",
                  (long)parent, (long)rc, (long)rc);
    return rc;
}

int execve(const char *pathname, char *const argv[], char *const envp[]) {
    static int (*real_execve)(const char *, char *const[], char *const[]);
    if (!real_execve) real_execve = dlsym(RTLD_NEXT, "execve");
    int empty = envp != NULL && envp[0] == NULL;
    int target = pathname != NULL && strcmp(pathname, "/home/user/legacy_auth") == 0;
    audit_log("EXEC pid=%ld empty=%d target=%d\n", (long)getpid(), empty, target);
    return real_execve(pathname, argv, envp);
}
AUDIT_EOF

gcc -shared -fPIC -O2 /tmp/rotate_audit.c -o /tmp/librotate_audit.so -ldl

test -f /home/user/rotate_cred.cpp
test -f /home/user/rotate_cred
test -x /home/user/rotate_cred
readelf -h /home/user/rotate_cred >/dev/null

g++ -O2 /home/user/rotate_cred.cpp -o /tmp/rotate_cred_from_source -lcrypto

cat << 'HELPER_EOF' > /tmp/check_rotation.py
import hashlib
import os
import re
import sys

NEW_PASSWORD = "Nova_Core_77X!"
SALT = "S@lt_90210_X"
expected_hash = hashlib.sha256((NEW_PASSWORD + SALT).encode()).hexdigest()

def check_outputs():
    with open("/home/user/auth_config.txt", "r") as f:
        assert f.read().strip() == expected_hash
    with open("/home/user/rotation_log.txt", "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]
    assert lines == [
        "SALT=" + SALT,
        "HASH=" + expected_hash,
        "RESULT=Access Granted",
    ]

def check_audit(path):
    with open(path, "r") as f:
        lines = f.read().splitlines()

    pipes = {}
    children = {}
    execs = []
    for line in lines:
        m = re.fullmatch(r"PIPE pid=(\d+) rc=(-?\d+)", line)
        if m and int(m.group(2)) == 0:
            pid = int(m.group(1))
            pipes[pid] = pipes.get(pid, 0) + 1
            continue
        m = re.fullmatch(r"FORK_CHILD pid=(\d+) parent=(\d+)", line)
        if m:
            children[int(m.group(1))] = int(m.group(2))
            continue
        m = re.fullmatch(r"EXEC pid=(\d+) empty=([01]) target=([01])", line)
        if m:
            execs.append(tuple(map(int, m.groups())))

    valid = False
    for pid, empty, target in execs:
        parent = children.get(pid)
        if empty == 1 and target == 1 and parent is not None and pipes.get(parent, 0) >= 2:
            valid = True
            break
    assert valid, "No forked child execve'd legacy_auth with an empty environment after creating stdin/stdout pipes"

check_outputs()
check_audit(sys.argv[1])
HELPER_EOF

run_and_check() {
    local program="$1"
    local audit="$2"
    printf '%064d\n' 0 > /home/user/auth_config.txt
    rm -f /home/user/rotation_log.txt "$audit"
    ROTATE_AUDIT="$audit" LD_PRELOAD=/tmp/librotate_audit.so timeout 10s "$program"
    python3 /tmp/check_rotation.py "$audit"
}

# Compile and exercise the submitted source, then independently exercise the
# executable the instruction required at its final path.
run_and_check /tmp/rotate_cred_from_source /tmp/source_audit.$$
run_and_check /home/user/rotate_cred /tmp/binary_audit.$$

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import re

def test_auth_config_updated():
    path = "/home/user/auth_config.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    expected_hash = hashlib.sha256(b"Nova_Core_77X!S@lt_90210_X").hexdigest()

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == expected_hash, f"File {path} does not contain the expected hash. Found: {content}"

def test_rotation_log_contents():
    path = "/home/user/rotation_log.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    expected_hash = hashlib.sha256(b"Nova_Core_77X!S@lt_90210_X").hexdigest()
    expected_lines = [
        "SALT=S@lt_90210_X",
        f"HASH={expected_hash}",
        "RESULT=Access Granted"
    ]

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f"Expected 3 lines in {path}, found {len(lines)}"
    assert lines[0] == expected_lines[0], f"Expected first line to be '{expected_lines[0]}', found '{lines[0]}'"
    assert lines[1] == expected_lines[1], f"Expected second line to be '{expected_lines[1]}', found '{lines[1]}'"
    assert lines[2] == expected_lines[2], f"Expected third line to be '{expected_lines[2]}', found '{lines[2]}'"

def test_cpp_files_exist():
    cpp_path = "/home/user/rotate_cred.cpp"
    bin_path = "/home/user/rotate_cred"

    assert os.path.exists(cpp_path), f"Source file {cpp_path} does not exist."
    assert os.path.exists(bin_path), f"Compiled binary {bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"Binary {bin_path} is not executable."

def test_source_uses_required_process_apis():
    with open("/home/user/rotate_cred.cpp", "r") as f:
        source = f.read()
    assert re.search(r"\bfork\s*\(", source), "Source does not call fork()"
    assert re.search(r"\bexecve\s*\(", source), "Source does not call execve()"
    assert re.search(r"\bpipe2?\s*\(", source), "Source does not create pipes"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
)

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
