#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/observe_rotate.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static const char *secret = "/home/user/secret.key";
static int secret_fds[32];
static int n_fds;
static FILE *secret_streams[32];
static int n_streams;

static void event(char c) {
    const char *p = getenv("ROTATE_TRACE");
    if (!p) return;
    int fd = syscall(SYS_openat, AT_FDCWD, p, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, &c, 1);
        syscall(SYS_close, fd);
    }
}

static int tracked_fd(int fd) {
    for (int i = 0; i < n_fds; i++) if (secret_fds[i] == fd) return 1;
    return 0;
}

static int tracked_stream(FILE *f) {
    for (int i = 0; i < n_streams; i++) if (secret_streams[i] == f) return 1;
    return 0;
}

int stat(const char *path, struct stat *st) {
    static int (*real_stat)(const char *, struct stat *);
    if (!real_stat) real_stat = dlsym(RTLD_NEXT, "stat");
    if (path && strcmp(path, secret) == 0) event('S');
    return real_stat(path, st);
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fopen)(const char *, const char *);
    if (!real_fopen) real_fopen = dlsym(RTLD_NEXT, "fopen");
    FILE *f = real_fopen(path, mode);
    if (f && path && strcmp(path, secret) == 0 && n_streams < 32)
        secret_streams[n_streams++] = f;
    return f;
}

int open(const char *path, int flags, ...) {
    static int (*real_open)(const char *, int, ...);
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    int fd = real_open(path, flags, mode);
    if (fd >= 0 && path && strcmp(path, secret) == 0 && n_fds < 32)
        secret_fds[n_fds++] = fd;
    return fd;
}

int open64(const char *path, int flags, ...) {
    static int (*real_open64)(const char *, int, ...);
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    int fd = real_open64(path, flags, mode);
    if (fd >= 0 && path && strcmp(path, secret) == 0 && n_fds < 32)
        secret_fds[n_fds++] = fd;
    return fd;
}

int openat(int dirfd, const char *path, int flags, ...) {
    static int (*real_openat)(int, const char *, int, ...);
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    int fd = real_openat(dirfd, path, flags, mode);
    if (fd >= 0 && path && strcmp(path, secret) == 0 && n_fds < 32)
        secret_fds[n_fds++] = fd;
    return fd;
}

ssize_t read(int fd, void *buf, size_t count) {
    static ssize_t (*real_read)(int, void *, size_t);
    if (!real_read) real_read = dlsym(RTLD_NEXT, "read");
    ssize_t r = real_read(fd, buf, count);
    if (tracked_fd(fd) && r > 0) event('R');
    return r;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    static size_t (*real_fread)(void *, size_t, size_t, FILE *);
    if (!real_fread) real_fread = dlsym(RTLD_NEXT, "fread");
    size_t r = real_fread(ptr, size, nmemb, stream);
    if (tracked_stream(stream) && r > 0) event('R');
    return r;
}

char *fgets(char *s, int size, FILE *stream) {
    static char *(*real_fgets)(char *, int, FILE *);
    if (!real_fgets) real_fgets = dlsym(RTLD_NEXT, "fgets");
    char *r = real_fgets(s, size, stream);
    if (tracked_stream(stream) && r) event('R');
    return r;
}

ssize_t getline(char **lineptr, size_t *n, FILE *stream) {
    static ssize_t (*real_getline)(char **, size_t *, FILE *);
    if (!real_getline) real_getline = dlsym(RTLD_NEXT, "getline");
    ssize_t r = real_getline(lineptr, n, stream);
    if (tracked_stream(stream) && r > 0) event('R');
    return r;
}

int fgetc(FILE *stream) {
    static int (*real_fgetc)(FILE *);
    if (!real_fgetc) real_fgetc = dlsym(RTLD_NEXT, "fgetc");
    int r = real_fgetc(stream);
    if (tracked_stream(stream) && r != EOF) event('R');
    return r;
}
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import pytest

SECRET_KEY_PATH = '/home/user/secret.key'
SOURCE_PATH = '/home/user/src/rotate.c'
BIN_ROTATE_PATH = '/home/user/bin/rotate'
ROTATE_LOG_PATH = '/home/user/rotate.log'
EXPECTED_SECRET = 'super_secret_rotation_key_99'
EXPECTED_LOG = 'Credential rotated securely\n'
REBUILT_PATH = '/tmp/rotate_rebuilt'
HOOK_PATH = '/tmp/observe_rotate.so'

@pytest.fixture(scope='session', autouse=True)
def compile_and_validate_artifacts():
    assert os.path.isfile(SOURCE_PATH), f'{SOURCE_PATH} does not exist or is not a regular file.'
    with open(SOURCE_PATH, 'r') as f:
        assert f.read().strip(), f'{SOURCE_PATH} is empty.'

    hook = subprocess.run(
        ['gcc', '-shared', '-fPIC', '/tmp/observe_rotate.c', '-ldl', '-o', HOOK_PATH],
        capture_output=True, text=True)
    assert hook.returncode == 0, f'Could not build verifier instrumentation: {hook.stderr}'

    built = subprocess.run(
        ['gcc', SOURCE_PATH, '-o', REBUILT_PATH], capture_output=True, text=True)
    assert built.returncode == 0, f'{SOURCE_PATH} does not compile with gcc: {built.stderr}'
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)


def run_binary(binary, args=(), trace=False):
    env = os.environ.copy()
    trace_path = None
    if trace:
        fd, trace_path = tempfile.mkstemp(prefix='rotate_trace_')
        os.close(fd)
        env['LD_PRELOAD'] = HOOK_PATH
        env['ROTATE_TRACE'] = trace_path
    result = subprocess.run([binary, *args], capture_output=True, text=True, env=env)
    events = ''
    if trace_path is not None:
        with open(trace_path, 'r') as f:
            events = f.read()
        os.remove(trace_path)
    return result, events


def remove_log():
    if os.path.lexists(ROTATE_LOG_PATH):
        os.remove(ROTATE_LOG_PATH)


def assert_success(binary, require_trace=False):
    remove_log()
    result, events = run_binary(binary, trace=require_trace)
    assert result.returncode == 0, f'{binary} failed with stderr: {result.stderr}'
    assert os.path.isfile(ROTATE_LOG_PATH), f'{binary} did not create {ROTATE_LOG_PATH}'
    with open(ROTATE_LOG_PATH, 'r') as f:
        assert f.read() == EXPECTED_LOG
    if require_trace:
        assert 'S' in events, f'{binary} did not call stat on the secret file.'
        assert 'R' in events, f'{binary} did not read data from the secret file.'


def test_secret_key_file():
    assert os.path.exists(SECRET_KEY_PATH), f'{SECRET_KEY_PATH} does not exist.'
    assert os.path.isfile(SECRET_KEY_PATH), f'{SECRET_KEY_PATH} is not a file.'
    with open(SECRET_KEY_PATH, 'r') as f:
        content = f.read().strip()
    assert content == EXPECTED_SECRET, f'Secret key content is incorrect. Expected {EXPECTED_SECRET}, got {content}'
    mode = stat.S_IMODE(os.stat(SECRET_KEY_PATH).st_mode)
    assert mode == 0o600, f'Permissions of {SECRET_KEY_PATH} are not 0600. Got {oct(mode)}'


def test_bin_rotate_executable():
    assert os.path.exists(BIN_ROTATE_PATH), f'{BIN_ROTATE_PATH} does not exist.'
    assert os.path.isfile(BIN_ROTATE_PATH), f'{BIN_ROTATE_PATH} is not a file.'
    assert os.access(BIN_ROTATE_PATH, os.X_OK), f'{BIN_ROTATE_PATH} is not executable.'
    with open(BIN_ROTATE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{BIN_ROTATE_PATH} is not a compiled ELF executable.'


def test_rotate_log_file():
    assert os.path.exists(ROTATE_LOG_PATH), f'{ROTATE_LOG_PATH} does not exist.'
    assert os.path.isfile(ROTATE_LOG_PATH), f'{ROTATE_LOG_PATH} is not a file.'
    with open(ROTATE_LOG_PATH, 'r') as f:
        content = f.read()
    assert content == EXPECTED_LOG, f'Log file content is incorrect. Expected {EXPECTED_LOG!r}, got {content!r}'


@pytest.mark.parametrize('binary', [BIN_ROTATE_PATH, REBUILT_PATH])
def test_success_calls_stat_and_reads_secret(binary):
    os.chmod(SECRET_KEY_PATH, 0o600)
    assert_success(binary, require_trace=True)


@pytest.mark.parametrize('binary', [BIN_ROTATE_PATH, REBUILT_PATH])
@pytest.mark.parametrize('bad_mode', [0o644, 0o400, 0o660])
def test_dynamic_security_check(binary, bad_mode):
    os.chmod(SECRET_KEY_PATH, bad_mode)
    remove_log()
    result, _ = run_binary(binary)
    assert result.returncode == 1, f'{binary} should exit 1 for mode {oct(bad_mode)}, got {result.returncode}.'
    assert 'Insecure file' in result.stderr, f"{binary} should print 'Insecure file' to stderr, got: {result.stderr}"
    assert not os.path.exists(ROTATE_LOG_PATH), f'{ROTATE_LOG_PATH} should not be created for insecure permissions.'


@pytest.mark.parametrize('binary', [BIN_ROTATE_PATH, REBUILT_PATH])
def test_rejects_command_line_secret(binary):
    os.chmod(SECRET_KEY_PATH, 0o600)
    remove_log()
    result, _ = run_binary(binary, ['not_the_file_secret'])
    assert result.returncode != 0, f'{binary} accepted a command-line secret argument.'
    assert not os.path.exists(ROTATE_LOG_PATH), f'{binary} rotated credentials despite receiving an argument.'


def test_restore_required_final_state():
    with open(SECRET_KEY_PATH, 'w') as f:
        f.write(EXPECTED_SECRET)
    os.chmod(SECRET_KEY_PATH, 0o600)
    assert_success(BIN_ROTATE_PATH, require_trace=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    chmod 0600 /home/user/secret.key 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
