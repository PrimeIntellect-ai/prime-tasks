#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SHIM_EOF' > /tmp/config_mgr_trace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <regex.h>
#include <stdarg.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static void trace_event(const char *tag, const char *path) {
    int fd = (int)syscall(SYS_openat, AT_FDCWD, "/tmp/config_mgr_trace.log",
                          O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    syscall(SYS_write, fd, tag, strlen(tag));
    if (path) syscall(SYS_write, fd, path, strlen(path));
    syscall(SYS_write, fd, "\n", 1);
    syscall(SYS_close, fd);
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fopen)(const char *, const char *);
    if (!real_fopen) real_fopen = dlsym(RTLD_NEXT, "fopen");
    FILE *result = real_fopen(path, mode);
    if (result && mode && mode[0] == 'r') trace_event("READ:", path);
    return result;
}

FILE *fopen64(const char *path, const char *mode) {
    static FILE *(*real_fopen64)(const char *, const char *);
    if (!real_fopen64) real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    FILE *result = real_fopen64(path, mode);
    if (result && mode && mode[0] == 'r') trace_event("READ:", path);
    return result;
}

FILE *freopen(const char *path, const char *mode, FILE *stream) {
    static FILE *(*real_freopen)(const char *, const char *, FILE *);
    if (!real_freopen) real_freopen = dlsym(RTLD_NEXT, "freopen");
    FILE *result = real_freopen(path, mode, stream);
    if (result && path && mode && mode[0] == 'r') trace_event("READ:", path);
    return result;
}

int open(const char *path, int flags, ...) {
    static int (*real_open)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    int result = (flags & O_CREAT) ? real_open(path, flags, mode) : real_open(path, flags);
    if (result >= 0 && (flags & O_ACCMODE) == O_RDONLY) trace_event("READ:", path);
    return result;
}

int open64(const char *path, int flags, ...) {
    static int (*real_open64)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    int result = (flags & O_CREAT) ? real_open64(path, flags, mode) : real_open64(path, flags);
    if (result >= 0 && (flags & O_ACCMODE) == O_RDONLY) trace_event("READ:", path);
    return result;
}

int openat(int dirfd, const char *path, int flags, ...) {
    static int (*real_openat)(int, const char *, int, ...);
    mode_t mode = 0;
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    int result = (flags & O_CREAT) ? real_openat(dirfd, path, flags, mode)
                                   : real_openat(dirfd, path, flags);
    if (result >= 0 && (flags & O_ACCMODE) == O_RDONLY) trace_event("READ:", path);
    return result;
}

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg) {
    static int (*real_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "pthread_create");
    trace_event("THREAD:", "pthread_create");
    return real_fn(thread, attr, start, arg);
}

int regcomp(regex_t *preg, const char *regex, int cflags) {
    static int (*real_fn)(regex_t *, const char *, int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "regcomp");
    trace_event("REGCOMP:", "regcomp");
    return real_fn(preg, regex, cflags);
}

int regexec(const regex_t *preg, const char *string, size_t nmatch,
            regmatch_t pmatch[], int eflags) {
    static int (*real_fn)(const regex_t *, const char *, size_t, regmatch_t[], int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "regexec");
    trace_event("REGEXEC:", "regexec");
    return real_fn(preg, string, nmatch, pmatch, eflags);
}
SHIM_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/config_mgr.c')
OUTPUT = Path('/home/user/active_config.csv')
BINARY = Path('/tmp/config_mgr_under_test')
TRACE = Path('/tmp/config_mgr_trace.log')
SHIM = Path('/tmp/config_mgr_trace.so')
EXPECTED_ORIGINAL = {'10.5.5.1,22', '10.5.5.1,8080', '192.168.1.200,3306'}


def read_rules():
    assert OUTPUT.is_file(), f'Output file not found: {OUTPUT}'
    lines = [line.strip() for line in OUTPUT.read_text(errors='replace').splitlines() if line.strip()]
    assert lines, 'The output file is empty.'
    return lines


def assert_original_jaccard():
    actual = set(read_rules())
    intersection = len(EXPECTED_ORIGINAL.intersection(actual))
    union = len(EXPECTED_ORIGINAL.union(actual))
    jaccard = intersection / union if union else 0.0
    assert jaccard >= 0.90, (
        f'Jaccard similarity is {jaccard:.4f}, but expected >= 0.90. '
        f'Expected rules: {EXPECTED_ORIGINAL}, Actual rules: {actual}'
    )


def run_program(with_trace=True):
    env = os.environ.copy()
    if with_trace:
        env['LD_PRELOAD'] = str(SHIM)
    result = subprocess.run(
        ['timeout', '20', str(BINARY)], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, (
        f'Compiled processor failed with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_complete_configuration_pipeline():
    assert SOURCE.is_file(), f'Required C source not found: {SOURCE}'
    source = SOURCE.read_text(errors='replace')

    assert re.search(r'#\s*include\s*[<\"]regex\.h[>\"]', source), 'config_mgr.c must include <regex.h>.'
    assert re.search(r'\bregcomp\s*\(', source) and re.search(r'\bregexec\s*\(', source), \
        'config_mgr.c must compile and execute a POSIX regular expression.'
    assert re.search(r'#\s*include\s*[<\"]pthread\.h[>\"]', source), 'config_mgr.c must include <pthread.h>.'
    assert re.search(r'\bpthread_create\s*\(', source) and re.search(r'\bpthread_join\s*\(', source), \
        'config_mgr.c must create and join worker threads.'
    assert re.search(r'\b(?:hash\w*|fnv\w*|djb\w*|bucket\w*)\s*\(', source, re.I), \
        'No hash-table/hash-function implementation was found.'

    shim_build = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-o', str(SHIM), '/tmp/config_mgr_trace.c', '-ldl', '-pthread'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert shim_build.returncode == 0, f'Failed to build verifier tracing shim: {shim_build.stderr}'

    build = subprocess.run(
        ['gcc', '-O2', '-o', str(BINARY), str(SOURCE), '-pthread'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert build.returncode == 0, f'config_mgr.c does not compile with pthreads:\n{build.stderr}'

    OUTPUT.unlink(missing_ok=True)
    TRACE.unlink(missing_ok=True)
    run_program(with_trace=True)
    assert_original_jaccard()

    trace_text = TRACE.read_text(errors='replace') if TRACE.exists() else ''
    assert 'THREAD:pthread_create' in trace_text, 'The processor did not create any pthread worker.'
    assert 'REGCOMP:regcomp' in trace_text and 'REGEXEC:regexec' in trace_text, \
        'The processor did not use POSIX regex while processing the transcript.'

    transcript_paths = []
    for line in trace_text.splitlines():
        if not line.startswith('READ:'):
            continue
        raw = line[5:]
        path = Path(raw) if os.path.isabs(raw) else Path('/home/user') / raw
        try:
            data = path.read_bytes()
        except (OSError, ValueError):
            continue
        sample = data[:100000].decode(errors='ignore').lower()
        if all(token in sample for token in ('add', 'rule', 'ip', 'port')):
            transcript_paths.append(path.resolve())

    transcript_paths = sorted(set(transcript_paths))
    assert transcript_paths, 'The executed C program did not read a textual command transcript.'

    rng = random.Random(913742)
    ips = ['10.20.0.9', '10.20.0.10', '172.31.4.2', '192.0.2.7', '198.51.100.3']
    ports = [22, 53, 80, 443, 8080, 12000]
    state = set()
    commands = []
    for _ in range(34):
        key = (rng.choice(ips), rng.choice(ports))
        action = rng.choice(['Add', 'Remove'])
        commands.append(f'{action} rule for IP {key[0]} on port {key[1]}')
        if action == 'Add':
            state.add(key)
        else:
            state.discard(key)
    for key in [('10.20.0.9', 443), ('198.51.100.3', 12000), ('10.20.0.9', 443)]:
        commands.append(f'Add rule for IP {key[0]} on port {key[1]}')
        state.add(key)

    custom_transcript = '.\n'.join(commands) + '.\n'
    expected_lines = [f'{ip},{port}' for ip, port in sorted(state, key=lambda item: (item[0], item[1]))]
    backups = {path: path.read_bytes() for path in transcript_paths}

    try:
        for path in transcript_paths:
            path.write_text(custom_transcript)
        OUTPUT.unlink(missing_ok=True)
        run_program(with_trace=False)
        actual_lines = read_rules()
        assert actual_lines == expected_lines, (
            'Processor failed the independently generated conflict/deduplication transcript '
            'or did not sort by IP and numeric port.\n'
            f'Expected: {expected_lines}\nActual: {actual_lines}'
        )
    finally:
        for path, data in backups.items():
            path.write_bytes(data)

    OUTPUT.unlink(missing_ok=True)
    run_program(with_trace=False)
    assert_original_jaccard()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
