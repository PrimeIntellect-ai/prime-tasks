#!/bin/bash
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/link_trace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void resolve_path(const char *path, int dirfd, char *out, size_t size) {
    char joined[PATH_MAX];
    char base[PATH_MAX];
    char fdpath[64];
    ssize_t n;

    if (!path) {
        snprintf(out, size, "(null)");
        return;
    }
    if (path[0] == '/') {
        if (!realpath(path, out))
            snprintf(out, size, "%s", path);
        return;
    }
    if (dirfd == AT_FDCWD) {
        if (!getcwd(base, sizeof(base))) {
            snprintf(out, size, "%s", path);
            return;
        }
    } else {
        snprintf(fdpath, sizeof(fdpath), "/proc/self/fd/%d", dirfd);
        n = readlink(fdpath, base, sizeof(base) - 1);
        if (n < 0) {
            snprintf(out, size, "%s", path);
            return;
        }
        base[n] = '\0';
    }
    snprintf(joined, sizeof(joined), "%s/%s", base, path);
    if (!realpath(joined, out))
        snprintf(out, size, "%s", joined);
}

static void record_link(const char *oldpath, int olddirfd,
                        const char *newpath, int newdirfd) {
    const char *log_path = getenv("TRACE_LINK_LOG");
    char old_abs[PATH_MAX], new_abs[PATH_MAX], line[PATH_MAX * 2 + 4];
    int fd, len;

    if (!log_path || !*log_path)
        return;
    resolve_path(oldpath, olddirfd, old_abs, sizeof(old_abs));
    resolve_path(newpath, newdirfd, new_abs, sizeof(new_abs));
    len = snprintf(line, sizeof(line), "%s\t%s\n", old_abs, new_abs);
    if (len <= 0)
        return;
    fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        write(fd, line, (size_t)len);
        close(fd);
    }
}

int link(const char *oldpath, const char *newpath) {
    static int (*real_link)(const char *, const char *);
    int rc;
    if (!real_link)
        real_link = dlsym(RTLD_NEXT, "link");
    rc = real_link(oldpath, newpath);
    if (rc == 0)
        record_link(oldpath, AT_FDCWD, newpath, AT_FDCWD);
    return rc;
}

int linkat(int olddirfd, const char *oldpath, int newdirfd,
           const char *newpath, int flags) {
    static int (*real_linkat)(int, const char *, int, const char *, int);
    int rc;
    if (!real_linkat)
        real_linkat = dlsym(RTLD_NEXT, "linkat");
    rc = real_linkat(olddirfd, oldpath, newdirfd, newpath, flags);
    if (rc == 0)
        record_link(oldpath, olddirfd, newpath, newdirfd);
    return rc;
}
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid


def test_backup_directory_and_contents():
    backup_dir = "/home/user/backup"
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    for i in range(1, 51):
        num_str = f"{i:02d}"
        backup_file = os.path.join(backup_dir, f"doc_{num_str}.md")

        assert os.path.isfile(backup_file), f"Backup file {backup_file} is missing."

        with open(backup_file, "r") as f:
            content = f.read()

        assert f"ID: {num_str}" in content, f"Original ID missing in backup {backup_file}."
        assert "State: WORK_IN_PROGRESS" in content, f"State was modified in backup {backup_file}!"
        assert f"Location: /home/user/docs/doc_{num_str}.md" in content, f"Location was modified in backup {backup_file}!"


def test_docs_directory_renamed_and_edited():
    docs_dir = "/home/user/docs"

    for i in range(1, 51):
        num_str = f"{i:02d}"
        old_file = os.path.join(docs_dir, f"doc_{num_str}.md")
        new_file = os.path.join(docs_dir, f"rel_{num_str}.md")

        assert not os.path.exists(old_file), f"Old file {old_file} still exists. It should have been renamed."
        assert os.path.isfile(new_file), f"New file {new_file} is missing."

        with open(new_file, "r") as f:
            content = f.read()

        assert f"ID: {num_str}" in content, f"ID missing in {new_file}."
        assert "State: RELEASED" in content, f"State not correctly updated to RELEASED in {new_file}."
        assert f"Location: {new_file}" in content, f"Location not correctly updated in {new_file}."


def test_inodes_are_split():
    backup_dir = "/home/user/backup"
    docs_dir = "/home/user/docs"

    for i in range(1, 51):
        num_str = f"{i:02d}"
        backup_file = os.path.join(backup_dir, f"doc_{num_str}.md")
        new_file = os.path.join(docs_dir, f"rel_{num_str}.md")

        if os.path.isfile(backup_file) and os.path.isfile(new_file):
            stat_backup = os.stat(backup_file)
            stat_new = os.stat(new_file)
            assert stat_backup.st_ino != stat_new.st_ino, (
                f"Inodes match for {backup_file} and {new_file}! "
                "The program edited the hard link in-place, ruining the snapshot."
            )


def test_c_artifact_executes_and_performs_snapshot_workflow():
    source = "/home/user/doc_manager.c"
    executable = "/home/user/doc_manager"
    trace_library = "/tmp/link_trace.so"
    trace_log = "/tmp/doc_manager_links.log"

    assert os.path.isfile(source), f"Required C source {source} is missing."
    assert os.path.isfile(executable), f"Required executable {executable} is missing."
    mode = os.stat(executable).st_mode
    assert mode & stat.S_IXUSR, f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable."

    syntax = subprocess.run(
        ["gcc", "-fsyntax-only", source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert syntax.returncode == 0, f"{source} is not valid C source:\n{syntax.stderr}"
    assert os.path.isfile(trace_library), "Verifier link tracing library was not built."

    held = f"/tmp/doc_manager_previous_{uuid.uuid4().hex}"
    os.makedirs(held)
    shutil.move("/home/user/docs", os.path.join(held, "docs"))
    if os.path.lexists("/home/user/backup"):
        shutil.move("/home/user/backup", os.path.join(held, "backup"))
    os.makedirs("/home/user/docs")

    originals = {}
    nonce = uuid.uuid4().hex
    for i in range(1, 51):
        num_str = f"{i:02d}"
        path = f"/home/user/docs/doc_{num_str}.md"
        content = (
            f"ID: {num_str}\n"
            "State: WORK_IN_PROGRESS\n"
            f"Location: /home/user/docs/doc_{num_str}.md\n\n"
            f"Documentation content for item {num_str}...\n"
            f"Verification nonce: {nonce}-{num_str}\n"
        )
        originals[num_str] = content
        with open(path, "w") as f:
            f.write(content)

    if os.path.exists(trace_log):
        os.unlink(trace_log)
    env = os.environ.copy()
    env["LD_PRELOAD"] = trace_library
    env["TRACE_LINK_LOG"] = trace_log
    result = subprocess.run(
        [executable],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Executing {executable} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isdir("/home/user/backup"), "Execution did not create /home/user/backup."
    observed_links = set()
    if os.path.isfile(trace_log):
        with open(trace_log) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t", 1)
                if len(parts) == 2:
                    observed_links.add(tuple(parts))

    for i in range(1, 51):
        num_str = f"{i:02d}"
        old_path = f"/home/user/docs/doc_{num_str}.md"
        backup_path = f"/home/user/backup/doc_{num_str}.md"
        new_path = f"/home/user/docs/rel_{num_str}.md"

        assert (old_path, backup_path) in observed_links, (
            f"Execution did not create the required hard-link snapshot "
            f"from {old_path} to {backup_path}."
        )
        assert not os.path.exists(old_path), f"Execution left old file {old_path}."
        assert os.path.isfile(backup_path), f"Execution did not create {backup_path}."
        assert os.path.isfile(new_path), f"Execution did not create {new_path}."

        with open(backup_path) as f:
            backup_content = f.read()
        with open(new_path) as f:
            active_content = f.read()

        assert backup_content == originals[num_str], f"Backup content changed in {backup_path}."
        expected_active = originals[num_str].replace(
            "State: WORK_IN_PROGRESS", "State: RELEASED"
        ).replace(old_path, new_path)
        assert active_content == expected_active, f"Active content is incorrect in {new_path}."
        assert os.stat(backup_path).st_ino != os.stat(new_path).st_ino, (
            f"Execution failed to isolate edits for {new_path}."
        )
TEST_EOF

if gcc -shared -fPIC -o /tmp/link_trace.so /tmp/link_trace.c -ldl >/tmp/link_trace_build.log 2>&1 && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
