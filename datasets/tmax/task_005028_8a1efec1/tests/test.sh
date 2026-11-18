#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat > /tmp/disk_nav_audit.c <<'AUDIT_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/types.h>
#include <unistd.h>

static void audit_log(const char *text) {
    const char *path = getenv("DISK_NAV_AUDIT_LOG");
    int saved = errno;
    int fd;
    if (!path || !*path) return;
    fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        (void)write(fd, text, strlen(text));
        close(fd);
    }
    errno = saved;
}

pid_t fork(void) {
    static pid_t (*real_fork)(void);
    pid_t result;
    char line[128];
    int saved;
    if (!real_fork) real_fork = dlsym(RTLD_NEXT, "fork");
    result = real_fork();
    saved = errno;
    if (result > 0) {
        snprintf(line, sizeof(line), "F\t%ld\t%ld\n", (long)getpid(), (long)result);
        audit_log(line);
    }
    errno = saved;
    return result;
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *);
    int result, saved;
    char line[4096];
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    result = real_rename(oldpath, newpath);
    saved = errno;
    if (result == 0) {
        snprintf(line, sizeof(line), "R\t%s\t%s\n", oldpath, newpath);
        audit_log(line);
    }
    errno = saved;
    return result;
}

int flock(int fd, int operation) {
    static int (*real_flock)(int, int);
    int result, saved;
    char line[128];
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    result = real_flock(fd, operation);
    saved = errno;
    if (result == 0 && (operation & LOCK_EX)) {
        snprintf(line, sizeof(line), "L\t%ld\t%d\n", (long)getpid(), fd);
        audit_log(line);
    }
    errno = saved;
    return result;
}

int fcntl(int fd, int cmd, ...) {
    static int (*real_fcntl)(int, int, ...);
    va_list ap;
    unsigned long arg = 0;
    int has_arg = 1;
    int result, saved;
    char line[128];

    if (!real_fcntl) real_fcntl = dlsym(RTLD_NEXT, "fcntl");
    if (cmd == F_GETFD || cmd == F_GETFL || cmd == F_GETOWN) has_arg = 0;
#ifdef F_GETSIG
    if (cmd == F_GETSIG) has_arg = 0;
#endif
#ifdef F_GETLEASE
    if (cmd == F_GETLEASE) has_arg = 0;
#endif
#ifdef F_GETPIPE_SZ
    if (cmd == F_GETPIPE_SZ) has_arg = 0;
#endif
#ifdef F_GET_SEALS
    if (cmd == F_GET_SEALS) has_arg = 0;
#endif

    if (has_arg) {
        va_start(ap, cmd);
        arg = va_arg(ap, unsigned long);
        va_end(ap);
        result = real_fcntl(fd, cmd, arg);
    } else {
        result = real_fcntl(fd, cmd);
    }
    saved = errno;

    if (result == 0 && (cmd == F_SETLK || cmd == F_SETLKW)) {
        struct flock *lock = (struct flock *)arg;
        if (lock && lock->l_type == F_WRLCK) {
            snprintf(line, sizeof(line), "L\t%ld\t%d\n", (long)getpid(), fd);
            audit_log(line);
        }
    }
    errno = saved;
    return result;
}
AUDIT_EOF

cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import pwd
import re
import subprocess
import uuid


def test_c_source_exists_and_contains_required_functions():
    source_file = "/home/user/disk_nav.c"
    assert os.path.isfile(source_file), f"Source file {source_file} does not exist."
    with open(source_file, "r") as f:
        content = f.read()
    assert re.search(r'\b(flock|fcntl)\b', content), "Source file must contain 'flock' or 'fcntl' for file locking."
    assert re.search(r'\brename\b', content), "Source file must contain 'rename' for atomic file update."
    assert re.search(r'\bfork\b', content), "Source file must contain 'fork' for process creation."


def test_compiled_binary_exists():
    binary_file = "/home/user/disk_nav"
    assert os.path.isfile(binary_file), f"Compiled binary {binary_file} does not exist."
    assert os.access(binary_file, os.X_OK), f"Compiled binary {binary_file} is not executable."


def test_storage_root_structure():
    expected_files = {
        "/home/user/storage_root/file_A.dat": 2000,
        "/home/user/storage_root/dir1/file_B.dat": 5000,
        "/home/user/storage_root/dir1/file_C.dat": 100,
        "/home/user/storage_root/dir2/sub/file_D.dat": 8000,
    }
    for filepath, expected_size in expected_files.items():
        assert os.path.isfile(filepath), f"Required test file {filepath} does not exist."
        actual_size = os.path.getsize(filepath)
        assert actual_size == expected_size, f"File {filepath} has size {actual_size}, expected {expected_size}."


def test_output_report_correctness():
    report_file = "/home/user/large_files_report.txt"
    assert os.path.isfile(report_file), f"Output report {report_file} does not exist."
    with open(report_file, "r") as f:
        lines = f.read().splitlines()
    actual_lines = sorted([line.strip() for line in lines if line.strip()])
    expected_lines = [
        "5000 /home/user/storage_root/dir1/file_B.dat",
        "8000 /home/user/storage_root/dir2/sub/file_D.dat"
    ]
    assert actual_lines == sorted(expected_lines), f"Report contents are incorrect. Expected {expected_lines}, got {actual_lines}."


def _drop_to_user():
    account = pwd.getpwnam("user")
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def _make_file(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.truncate(size)
    os.chmod(path, 0o644)


def test_binary_on_generated_tree_with_required_process_and_update_operations():
    token = uuid.uuid4().hex
    base = f"/home/user/disk_nav_verify_{token}"
    target = os.path.join(base, "input tree")
    output = os.path.join(base, "generated report.txt")
    audit = os.path.join(base, "audit.log")
    threshold = 3071

    os.makedirs(target, mode=0o777)
    os.chmod(base, 0o777)
    os.chmod(target, 0o755)

    sizes = {}
    def add(relative, size):
        path = os.path.join(target, relative)
        _make_file(path, size)
        sizes[path] = size

    # The parent and every required top-level child have reportable work.
    add("parent equal.bin", threshold)
    add("parent small.bin", threshold - 1)
    for index in range(4):
        dirname = f"direct_{index}_{token[:6]}"
        add(os.path.join(dirname, f"large {index}.dat"), threshold + 101 + index)
        add(os.path.join(dirname, "small.dat"), 17 + index)
        add(os.path.join(dirname, "nested", f"deep {index}.dat"), threshold + 900 + index)
    os.makedirs(os.path.join(target, f"direct_0_{token[:6]}", "empty"), exist_ok=True)

    # A read-only existing destination cannot be opened for writing by the
    # unprivileged run, but can be replaced atomically through its directory.
    with open(output, "w") as f:
        f.write("old report must be replaced\n")
    os.chmod(output, 0o444)
    with open(audit, "w"):
        pass
    os.chmod(audit, 0o666)

    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/libdisk_nav_audit.so"
    env["DISK_NAV_AUDIT_LOG"] = audit
    process = subprocess.Popen(
        ["/home/user/disk_nav", target, output, str(threshold)],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        preexec_fn=_drop_to_user,
    )
    stdout, stderr = process.communicate(timeout=20)
    assert process.returncode == 0, f"Generated scan failed ({process.returncode}): stdout={stdout!r}, stderr={stderr!r}"

    expected = sorted(f"{size} {path}" for path, size in sizes.items() if size >= threshold)
    assert os.path.isfile(output), "The generated report was not created."
    with open(output) as f:
        actual = sorted(line.rstrip("\n") for line in f if line.rstrip("\n"))
    assert actual == expected, f"Generated report mismatch. Expected {expected}, got {actual}."

    with open(audit) as f:
        records = [line.rstrip("\n").split("\t") for line in f if line.strip()]

    root_forks = [int(r[2]) for r in records if len(r) == 3 and r[0] == "F" and int(r[1]) == process.pid]
    assert len(set(root_forks)) >= 4, "The initial process did not fork a worker for every direct subdirectory."

    locking_pids = {int(r[1]) for r in records if len(r) == 3 and r[0] == "L"}
    assert process.pid in locking_pids, "The parent did not acquire an exclusive lock for its report write."
    assert len(set(root_forks) & locking_pids) >= 4, "Each direct-subdirectory worker must acquire an exclusive lock while logging."

    renames = [r for r in records if len(r) == 3 and r[0] == "R"]
    matching = []
    for _, old, new in renames:
        old_abs = os.path.abspath(old)
        new_abs = os.path.abspath(new)
        if new_abs == os.path.abspath(output):
            matching.append(old_abs)
    assert matching, "No successful rename installed the generated output report."
    assert any(old != os.path.abspath(output) and os.path.dirname(old) == os.path.dirname(os.path.abspath(output)) for old in matching), \
        "The report must be renamed from a distinct temporary file in the output directory."


def test_binary_rejects_incorrect_argument_counts():
    binary = "/home/user/disk_nav"
    too_few = subprocess.run([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    too_many = subprocess.run([binary, "/tmp", "/tmp/out", "1", "extra"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert too_few.returncode != 0, "The program must reject too few arguments."
    assert too_many.returncode != 0, "The program must reject extra arguments."
TEST_EOF

if gcc -shared -fPIC -O2 -Wall /tmp/disk_nav_audit.c -o /tmp/libdisk_nav_audit.so -ldl \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
