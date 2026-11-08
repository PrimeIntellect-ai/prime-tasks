#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

EXPECTED_CALLS = [(1, 15), (2, 25), (3, 35)]
EXPECTED_OUTPUT = b"Total: 170\n"

INTERPOSER_SOURCE = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

typedef int (*real_create_t)(pthread_t *, const pthread_attr_t *,
                             void *(*)(void *), void *);

struct start_ctx {
    void *(*start)(void *);
    void *arg;
};

static void log_event(char event) {
    const char *path = getenv("CHECK_THREAD_AUDIT");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        char line[2] = {event, '\n'};
        (void)write(fd, line, sizeof(line));
        close(fd);
    }
}

static void *wrapped_start(void *opaque) {
    struct start_ctx *ctx = (struct start_ctx *)opaque;
    void *(*start)(void *) = ctx->start;
    void *arg = ctx->arg;
    free(ctx);
    log_event('S');
    return start(arg);
}

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg) {
    static real_create_t real_create;
    if (!real_create)
        real_create = (real_create_t)dlsym(RTLD_NEXT, "pthread_create");
    if (!real_create) return EAGAIN;

    struct start_ctx *ctx = malloc(sizeof(*ctx));
    if (!ctx) return ENOMEM;
    ctx->start = start;
    ctx->arg = arg;

    int rc = real_create(thread, attr, wrapped_start, ctx);
    if (rc == 0)
        log_event('C');
    else
        free(ctx);
    return rc;
}
'''


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=15, **kwargs)


def build_interposer(directory):
    source = os.path.join(directory, "thread_audit.c")
    library = os.path.join(directory, "thread_audit.so")
    with open(source, "w") as f:
        f.write(INTERPOSER_SOURCE)
    run(["gcc", "-shared", "-fPIC", "-O2", source, "-o", library, "-ldl", "-pthread"])
    return library


def assert_real_pthread_binary(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF executable."

    symbols = run(["nm", "-D", path], stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT).stdout.decode("utf-8", "replace")
    assert re.search(r"\bU\s+pthread_create(?:@|\s|$)", symbols), \
        f"{path} does not call the real POSIX pthread_create function."


def execute_and_check_threads(path, interposer, audit_path):
    if os.path.exists(audit_path):
        os.unlink(audit_path)
    env = os.environ.copy()
    env["LD_PRELOAD"] = interposer
    env["CHECK_THREAD_AUDIT"] = audit_path
    result = run([path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    assert result.stdout == EXPECTED_OUTPUT, \
        f"{path} produced {result.stdout!r}, expected {EXPECTED_OUTPUT!r}."
    assert result.stderr == b"", f"{path} wrote unexpected stderr: {result.stderr!r}"

    with open(audit_path, "r") as f:
        events = [line.strip() for line in f if line.strip()]
    assert events.count("C") >= 3, f"{path} successfully created fewer than three POSIX threads."
    assert events.count("S") >= 3, f"Fewer than three worker threads in {path} actually started."


def test_check_go_patched():
    path = "/home/user/check.go"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "go worker(1, 15, &wg, ch)" in content, "check.go does not contain the patched worker(1, 15...) call."
    assert "go worker(2, 25, &wg, ch)" in content, "check.go does not contain the patched worker(2, 25...) call."
    assert "go worker(3, 35, &wg, ch)" in content, "check.go does not contain the patched worker(3, 35...) call."

    calls = [(int(a), int(b)) for a, b in re.findall(
        r"\bgo\s+worker\(\s*(\d+)\s*,\s*(\d+)\s*,", content)]
    assert calls == EXPECTED_CALLS, f"Unexpected worker calls in patched check.go: {calls!r}"
    derived = sum(worker_id * value for worker_id, value in calls)
    assert EXPECTED_OUTPUT == f"Total: {derived}\n".encode()


def test_check_c_exists_and_uses_pthreads():
    path = "/home/user/check.c"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "pthread_create" in content, "check.c does not contain 'pthread_create'. You must use POSIX threads."


def test_check_bin_is_compiled_and_executable():
    path = "/home/user/check_bin"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_deploy_ready_log_content():
    path = "/home/user/deploy_ready.log"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "Total: 170", f"Expected 'Total: 170' in {path}, but got '{content}'"
    with open(path, "rb") as f:
        assert f.read() == EXPECTED_OUTPUT, "deploy_ready.log is not the exact redirected program output."


def test_source_compiles_and_both_executables_run_real_threads():
    with tempfile.TemporaryDirectory(prefix="verify_check_") as directory:
        rebuilt = os.path.join(directory, "check_rebuilt")
        run(["gcc", "-std=c11", "-O2", "-pthread", "/home/user/check.c", "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        interposer = build_interposer(directory)

        assert_real_pthread_binary(rebuilt)
        execute_and_check_threads(rebuilt, interposer, os.path.join(directory, "rebuilt.audit"))

        assert_real_pthread_binary("/home/user/check_bin")
        execute_and_check_threads("/home/user/check_bin", interposer,
                                  os.path.join(directory, "submitted.audit"))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
