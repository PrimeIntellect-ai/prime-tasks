#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tarfile
import tempfile
from pathlib import Path

SOURCE = Path('/home/user/parser.c')
BINARY = Path('/home/user/parser')

LOCK_AUDIT_C = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

static int is_target(int fd) {
    const char *target = getenv("LOCK_TARGET");
    char procpath[64], actual[4096];
    ssize_t n;
    if (!target) return 0;
    snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
    n = readlink(procpath, actual, sizeof(actual) - 1);
    if (n < 0) return 0;
    actual[n] = '\0';
    return strcmp(actual, target) == 0;
}

static void record_event(const char *event) {
    const char *path = getenv("LOCK_AUDIT_LOG");
    int fd;
    if (!path) return;
    fd = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, event, strlen(event));
        syscall(SYS_write, fd, "\n", 1);
        syscall(SYS_close, fd);
    }
}

int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = NULL;
    int result;
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    result = real_flock(fd, operation);
    if (result == 0 && is_target(fd)) {
        if (operation & LOCK_UN) record_event("UNLOCK");
        else if (operation & LOCK_EX) record_event("EXCLUSIVE");
    }
    return result;
}

int fcntl(int fd, int cmd, ...) {
    static int (*real_fcntl)(int, int, ...) = NULL;
    va_list ap;
    void *arg;
    int result;
    if (!real_fcntl) real_fcntl = dlsym(RTLD_NEXT, "fcntl");
    va_start(ap, cmd);
    arg = va_arg(ap, void *);
    va_end(ap);
    result = real_fcntl(fd, cmd, arg);
    if (result == 0 && is_target(fd)) {
        int is_lock_cmd = (cmd == F_SETLK || cmd == F_SETLKW);
#ifdef F_OFD_SETLK
        is_lock_cmd = is_lock_cmd || cmd == F_OFD_SETLK || cmd == F_OFD_SETLKW;
#endif
        if (is_lock_cmd && arg) {
            struct flock *lock = (struct flock *)arg;
            if (lock->l_type == F_WRLCK) record_event("EXCLUSIVE");
            else if (lock->l_type == F_UNLCK) record_event("UNLOCK");
        }
    }
    return result;
}
'''


def build_lock_auditor(tmpdir):
    source = Path(tmpdir) / 'lockaudit.c'
    library = Path(tmpdir) / 'lockaudit.so'
    source.write_text(LOCK_AUDIT_C)
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', str(library), str(source), '-ldl'],
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, result.stderr
    return library


def exercise_parser(executable, lock_library):
    with tempfile.TemporaryDirectory(prefix='parser-case-') as td:
        root = Path(td)
        base = root / 'dataset'
        base.mkdir()

        token = secrets.token_hex(6)
        names = [f'{token}_first.dat', f'nested/{token}_second.bin', f'{token}_third.dat']
        sizes = [73 + secrets.randbelow(97), 211 + secrets.randbelow(149), 401 + secrets.randbelow(173)]
        for name, size in zip(names, sizes):
            path = base / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(os.urandom(size))

        failed = f'{token}_failed.dat'
        (base / failed).write_bytes(os.urandom(89))
        (base / 'ordinary_directory').mkdir()
        os.symlink('missing-target', base / 'broken-link')
        (base / 'loops').mkdir()
        os.symlink('loop2', base / 'loops' / 'loop1')
        os.symlink('loop1', base / 'loops' / 'loop2')

        records = [
            (11, 'SUCCESS', names[0]),
            (12, 'FAILED', failed),
            (13, 'SUCCESS', 'loops/loop1/fake.dat'),
            (14, 'SUCCESS', names[1]),
            (15, 'SUCCESS', 'broken-link'),
            (16, 'SUCCESS', 'ordinary_directory'),
            (17, 'SUCCESS', names[2]),
        ]
        log = base / 'transfer.log'
        with log.open('w') as f:
            for dataset_id, status, path in records:
                f.write(f'---RECORD---\nDatasetID: {dataset_id}\nStatus: {status}\nPath: {path}\n------------\n')

        output = root / 'summary.txt'
        audit_log = root / 'locks.txt'
        env = os.environ.copy()
        env.update({
            'LD_PRELOAD': str(lock_library),
            'LOCK_TARGET': str(output),
            'LOCK_AUDIT_LOG': str(audit_log),
        })
        result = subprocess.run(
            [str(executable), str(log), str(base), str(output)],
            text=True, capture_output=True, env=env, timeout=10
        )
        assert result.returncode == 0, (
            f'{executable} failed on a valid input: stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert output.is_file(), f'{executable} did not create its requested summary file'
        actual = [line.strip() for line in output.read_text().splitlines() if line.strip()]
        expected = [f'{name} {size}' for name, size in zip(names, sizes)]
        assert len(actual) == len(expected) and set(actual) == set(expected), (
            f'Expected dynamically derived lines {expected}, got {actual}'
        )

        events = audit_log.read_text().splitlines() if audit_log.exists() else []
        assert events.count('EXCLUSIVE') >= len(expected), (
            'The running program did not acquire an exclusive POSIX lock before each valid line'
        )
        assert events.count('UNLOCK') >= len(expected), (
            'The running program did not release its POSIX lock after each valid line'
        )


def test_valid_files_txt():
    txt_path = '/home/user/valid_files.txt'
    assert os.path.exists(txt_path), f'File {txt_path} does not exist.'
    with open(txt_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = {'data_alpha.dat 1024', 'data_beta.dat 2048'}
    actual_lines = set(lines)
    assert actual_lines == expected_lines, f'Expected lines {expected_lines}, but got {actual_lines}'


def test_parser_c_locking():
    assert SOURCE.exists(), f'Source file {SOURCE} does not exist.'
    content = SOURCE.read_text()
    has_lock = re.search(r'\b(flock|fcntl)\s*\(', content)
    assert has_lock, f'The C program {SOURCE} does not appear to use flock() or fcntl() for file locking.'


def test_parser_compiles_and_both_artifacts_run():
    assert SOURCE.is_file(), f'Source file {SOURCE} does not exist.'
    assert BINARY.is_file(), f'Compiled parser {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'{BINARY} is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', f'{BINARY} is not a compiled ELF executable.'

    with tempfile.TemporaryDirectory(prefix='parser-build-') as td:
        rebuilt = Path(td) / 'parser-rebuilt'
        compile_result = subprocess.run(
            ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-o', str(rebuilt), str(SOURCE)],
            text=True, capture_output=True, timeout=20
        )
        assert compile_result.returncode == 0, f'parser.c does not compile:\n{compile_result.stderr}'
        lock_library = build_lock_auditor(td)

        for executable in (rebuilt, BINARY):
            no_args = subprocess.run([str(executable)], capture_output=True, timeout=5)
            too_few = subprocess.run(
                [str(executable), '/tmp/log', '/tmp/base'], capture_output=True, timeout=5
            )
            assert no_args.returncode != 0 and too_few.returncode != 0, (
                f'{executable} does not enforce exactly three command-line arguments'
            )
            exercise_parser(executable, lock_library)


def test_clean_backup_tar():
    tar_path = '/home/user/clean_backup.tar'
    assert os.path.exists(tar_path), f'Backup tarball {tar_path} does not exist.'
    assert tarfile.is_tarfile(tar_path), f'File {tar_path} is not a valid tar file.'

    with tarfile.open(tar_path, 'r:') as tar:
        members = tar.getmembers()
        names = [member.name for member in members]
        expected_names = {'data_alpha.dat', 'data_beta.dat'}
        actual_names = set(names)
        assert actual_names == expected_names, f'Expected tarball contents {expected_names}, but got {actual_names}'
        assert len(members) == 2, 'Backup contains duplicate or extra archive members.'
        for member in members:
            assert member.isfile(), f'{member.name} is not stored as a regular file.'
            archived = tar.extractfile(member)
            assert archived is not None
            expected_path = Path('/home/user/dataset') / member.name
            assert expected_path.is_file(), f'Extracted source file {expected_path} is missing.'
            assert archived.read() == expected_path.read_bytes(), (
                f'Archived bytes for {member.name} do not match the extracted dataset file.'
            )


def test_archive_was_extracted():
    dataset = Path('/home/user/dataset')
    assert dataset.is_dir(), 'The dataset archive was not extracted to /home/user/dataset/.'
    assert (dataset / 'transfer.log').is_file(), 'The extracted transfer.log is missing.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
