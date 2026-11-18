#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/reader_trace.c
#define _GNU_SOURCE
#define _LARGEFILE64_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

static void trace_msg(const char *kind, long value) {
    const char *path = getenv("SAFE_READER_TRACE");
    if (!path) return;
    char buf[128];
    int n = snprintf(buf, sizeof(buf), "%s %ld\n", kind, value);
    int fd = (int)syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, buf, (size_t)n);
        syscall(SYS_close, fd);
    }
}

static int no_arg_cmd(int cmd) {
    return cmd == F_GETFD || cmd == F_GETFL || cmd == F_GETOWN;
}

int fcntl(int fd, int cmd, ...) {
    static int (*real_fcntl)(int, int, ...) = NULL;
    if (!real_fcntl) real_fcntl = dlsym(RTLD_NEXT, "fcntl");

    long arg = 0;
    int rc;
    if (no_arg_cmd(cmd)) {
        rc = real_fcntl(fd, cmd);
    } else {
        va_list ap;
        va_start(ap, cmd);
        arg = va_arg(ap, long);
        va_end(ap);
        rc = real_fcntl(fd, cmd, arg);
    }

    if (rc == 0 && (cmd == F_SETLK || cmd == F_SETLKW)) {
        struct flock *lock = (struct flock *)arg;
        if (lock && cmd == F_SETLKW && lock->l_type == F_RDLCK)
            trace_msg("RDLOCK", cmd);
        if (lock && lock->l_type == F_UNLCK)
            trace_msg("UNLOCK", cmd);
    }
    return rc;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED) trace_msg("MMAP", (long)length);
    return result;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t) = NULL;
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    void *result = real_mmap64(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED) trace_msg("MMAP", (long)length);
    return result;
}

int munmap(void *addr, size_t length) {
    static int (*real_munmap)(void *, size_t) = NULL;
    if (!real_munmap) real_munmap = dlsym(RTLD_NEXT, "munmap");
    int rc = real_munmap(addr, length);
    if (rc == 0) trace_msg("MUNMAP", (long)length);
    return rc;
}
TRACE_EOF

if ! gcc -shared -fPIC -O2 -o /tmp/reader_trace.so /tmp/reader_trace.c -ldl; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import gzip
import os
import shutil
import subprocess
import tarfile
import time
import uuid


def test_active_path_txt():
    path = '/home/user/active_path.txt'
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == '/home/user/live_config.bin', f"Expected '/home/user/live_config.bin' in {path}, got '{content}'"


def test_safe_reader_cpp():
    path = '/home/user/safe_reader.cpp'
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, 'r') as f:
        content = f.read()
    for keyword in ['mmap', 'fcntl', 'F_SETLKW', 'F_RDLCK']:
        assert keyword in content, f"Keyword '{keyword}' not found in {path}"


def test_safe_reader_executable():
    path = '/home/user/safe_reader'
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{path} is not a compiled executable."


def test_package_backup_sh():
    path = '/home/user/package_backup.sh'
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_safe_reader_behavior_and_syscalls(tmp_path):
    reader = '/home/user/safe_reader'
    payload = b'\x00binary\xffpayload\n' + os.urandom(257)
    data_path = tmp_path / 'input.bin'
    data_path.write_bytes(payload)
    trace_path = tmp_path / 'trace.log'

    env = os.environ.copy()
    env['LD_PRELOAD'] = '/tmp/reader_trace.so'
    env['SAFE_READER_TRACE'] = str(trace_path)
    result = subprocess.run([reader, str(data_path)], capture_output=True, env=env, timeout=5)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert result.stdout == payload, 'safe_reader did not reproduce the complete binary file.'

    trace = trace_path.read_text()
    assert 'RDLOCK ' in trace, 'safe_reader did not acquire a blocking shared fcntl lock.'
    assert f'MMAP {len(payload)}' in trace, 'safe_reader did not mmap the entire file.'
    assert f'MUNMAP {len(payload)}' in trace, 'safe_reader did not unmap the mapped file.'
    assert 'UNLOCK ' in trace, 'safe_reader did not explicitly release its file lock.'

    no_args = subprocess.run([reader], capture_output=True, timeout=5)
    two_args = subprocess.run([reader, str(data_path), str(data_path)], capture_output=True, timeout=5)
    missing = subprocess.run([reader, str(tmp_path / 'missing.bin')], capture_output=True, timeout=5)
    assert no_args.returncode != 0, 'safe_reader must reject zero arguments.'
    assert two_args.returncode != 0, 'safe_reader must reject more than one argument.'
    assert missing.returncode != 0, 'safe_reader must report failure for a missing file.'


def test_safe_reader_waits_for_writer_lock(tmp_path):
    reader = '/home/user/safe_reader'
    data_path = tmp_path / 'locked.bin'
    initial = b'old-data-' + os.urandom(32)
    updated = b'new-data-' + os.urandom(32)
    data_path.write_bytes(initial)

    with open(data_path, 'r+b', buffering=0) as locked:
        fcntl.lockf(locked, fcntl.LOCK_EX)
        proc = subprocess.Popen([reader, str(data_path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.35)
        assert proc.poll() is None, 'safe_reader did not wait for an exclusive POSIX writer lock.'
        locked.seek(0)
        locked.truncate()
        locked.write(updated)
        os.fsync(locked.fileno())
        fcntl.lockf(locked, fcntl.LOCK_UN)

    stdout, stderr = proc.communicate(timeout=5)
    assert proc.returncode == 0, stderr.decode(errors='replace')
    assert stdout == updated, 'safe_reader read stale or corrupted data across the writer lock.'


def test_backup_execution_and_artifacts():
    script_path = '/home/user/package_backup.sh'
    reader_path = '/home/user/safe_reader'
    active_path = '/home/user/active_path.txt'
    token = uuid.uuid4().hex
    target_path = f'/home/user/verifier_config_{token}.bin'
    invocation_log = f'/tmp/reader_invocation_{token}'
    saved_reader = f'/tmp/safe_reader_real_{token}'
    payload = b'DATA_' + os.urandom(333) + b'\x00\xff\n'

    with open(active_path, 'rb') as f:
        original_active = f.read()
    shutil.copy2(reader_path, saved_reader)

    try:
        with open(target_path, 'wb') as f:
            f.write(payload)
        with open(active_path, 'w') as f:
            f.write(target_path + '\n')

        os.unlink(reader_path)
        with open(reader_path, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write(f"printf '%s\\0' \"$@\" > {invocation_log!r}\n")
            f.write(f'exec {saved_reader!r} "$@"\n')
        os.chmod(reader_path, 0o755)

        for artifact in ['/home/user/snapshot.gz', '/home/user/snapshot.tar', '/home/user/latest_backup.link']:
            if os.path.lexists(artifact):
                os.unlink(artifact)

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Script {script_path} failed with return code {result.returncode}. stderr: {result.stderr}"
        assert os.path.isfile(invocation_log), 'package_backup.sh did not execute /home/user/safe_reader.'
        with open(invocation_log, 'rb') as f:
            assert f.read() == os.fsencode(target_path) + b'\0', 'safe_reader was not called with the path from active_path.txt.'

        link_path = '/home/user/latest_backup.link'
        assert os.path.islink(link_path), f"{link_path} is not a symbolic link."
        target = os.readlink(link_path)
        assert target in ['/home/user/snapshot.tar', 'snapshot.tar'], f"{link_path} points to {target}, expected /home/user/snapshot.tar or snapshot.tar"

        tar_path = '/home/user/snapshot.tar'
        assert os.path.isfile(tar_path), f"{tar_path} does not exist."
        with tarfile.open(tar_path, 'r') as tar:
            members = tar.getnames()
            assert 'snapshot.gz' in members or '/home/user/snapshot.gz' in members or any(m.endswith('snapshot.gz') for m in members), 'snapshot.gz not found in tar archive.'
            gz_member = next(m for m in tar.getmembers() if m.name.endswith('snapshot.gz'))
            f_gz = tar.extractfile(gz_member)
            assert f_gz is not None, 'Failed to extract snapshot.gz from tar.'
            with gzip.GzipFile(fileobj=f_gz, mode='rb') as gz:
                content = gz.read()

        assert content.startswith(b'DATA_') or content.startswith(b'INIT_DATA'), 'Content of snapshot.gz does not match expected format.'
        assert content == payload, 'The packaged snapshot is not the exact content read from the configured target file.'
    finally:
        if os.path.lexists(reader_path):
            os.unlink(reader_path)
        if os.path.exists(saved_reader):
            shutil.move(saved_reader, reader_path)
        with open(active_path, 'wb') as f:
            f.write(original_active)
        if os.path.exists(target_path):
            os.unlink(target_path)
        if os.path.exists(invocation_log):
            os.unlink(invocation_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
