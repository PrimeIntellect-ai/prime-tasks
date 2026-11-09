#!/bin/bash
set +e
mkdir -p /logs/verifier
python3 <<'PY'
import os
import random
import shutil
import stat
import subprocess
import tempfile

SRC = '/home/user/archiver.c'
EXE = '/home/user/archiver'
CONF = '/home/user/backup.conf'
ARCHIVE = '/home/user/archive.bin'
ORIGINALS = {
    '/home/user/log1.dat': b'AAAAABBBCCCDDDDDDDDD',
    '/home/user/log2.dat': b'XXYYYZZ',
    '/home/user/log3.dat': b'E' * 260 + b'F' * 10,
}
ORIGINAL_CONF = b'/home/user/log1.dat\n/home/user/log2.dat\n/home/user/log3.dat\n'
ORIGINAL_ARCHIVE = (
    b'\x05A\x03B\x03C\x09D'
    b'\x02X\x03Y\x02Z'
    b'\xffE\x05E\x0aF'
)

WRAPPER = r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>

struct mapping { void *addr; size_t len; char path[512]; int active; };
static struct mapping maps[256];

static void fd_path(int fd, char *out, size_t n) {
    char link[64];
    long r;
    snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
    r = syscall(SYS_readlinkat, AT_FDCWD, link, out, n - 1);
    if (r < 0) snprintf(out, n, "?");
    else out[r] = 0;
}

static void emit(const char *line) {
    const char *p = getenv("ARCHIVER_TRACE");
    int fd;
    if (!p) return;
    fd = syscall(SYS_openat, AT_FDCWD, p, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, line, strlen(line));
        syscall(SYS_close, fd);
    }
}

int flock(int fd, int op) {
    static int (*real_flock)(int, int);
    char path[512], line[700];
    int rc, saved;
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    fd_path(fd, path, sizeof(path));
    rc = real_flock(fd, op);
    saved = errno;
    snprintf(line, sizeof(line), "F\t%s\t%d\t%d\n", path, op, rc);
    emit(line);
    errno = saved;
    return rc;
}

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    char path[512], line[800];
    void *result;
    int i, saved;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    fd_path(fd, path, sizeof(path));
    result = real_mmap(addr, len, prot, flags, fd, off);
    saved = errno;
    if (result != MAP_FAILED) {
        for (i = 0; i < 256; i++) if (!maps[i].active) {
            maps[i].addr = result;
            maps[i].len = len;
            snprintf(maps[i].path, sizeof(maps[i].path), "%s", path);
            maps[i].active = 1;
            break;
        }
    }
    snprintf(line, sizeof(line), "M\t%s\t%zu\t%d\t%d\t%lld\t%d\n",
             path, len, prot, flags, (long long)off, result != MAP_FAILED);
    emit(line);
    errno = saved;
    return result;
}

void *mmap64(void *addr, size_t len, int prot, int flags, int fd, off64_t off) {
    return mmap(addr, len, prot, flags, fd, (off_t)off);
}

int munmap(void *addr, size_t len) {
    static int (*real_munmap)(void *, size_t);
    char path[512] = "?", line[700];
    int i, rc, saved, found = -1;
    if (!real_munmap) real_munmap = dlsym(RTLD_NEXT, "munmap");
    for (i = 0; i < 256; i++) if (maps[i].active && maps[i].addr == addr) {
        snprintf(path, sizeof(path), "%s", maps[i].path);
        found = i;
        break;
    }
    rc = real_munmap(addr, len);
    saved = errno;
    if (rc == 0 && found >= 0) maps[found].active = 0;
    snprintf(line, sizeof(line), "U\t%s\t%zu\t%d\n", path, len, rc);
    emit(line);
    errno = saved;
    return rc;
}

int close(int fd) {
    static int (*real_close)(int);
    char path[512], line[700];
    int rc, saved;
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");
    fd_path(fd, path, sizeof(path));
    rc = real_close(fd);
    saved = errno;
    snprintf(line, sizeof(line), "C\t%s\t%d\n", path, rc);
    emit(line);
    errno = saved;
    return rc;
}
'''

def run_checked(argv, env=None):
    result = subprocess.run(argv, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=15)
    assert result.returncode == 0, (
        f'{argv[0]} exited with {result.returncode}: '
        + result.stderr.decode('utf-8', 'replace'))

def rle(data):
    out = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        out.extend((count, data[i]))
        i += count
    return bytes(out)

def assert_original_inputs():
    for path, expected in ORIGINALS.items():
        with open(path, 'rb') as f:
            assert f.read() == expected, f'{path} was modified'
    with open(CONF, 'rb') as f:
        assert f.read() == ORIGINAL_CONF, f'{CONF} was modified'

# Preserve the original verifier's source, fixed-output, and input-integrity checks.
assert os.path.exists(SRC), f'Source file {SRC} does not exist'
with open(SRC, 'r', encoding='utf-8', errors='ignore') as f:
    source_content = f.read()
assert 'mmap' in source_content, f"Source file {SRC} does not contain 'mmap'"
assert 'flock' in source_content, f"Source file {SRC} does not contain 'flock'"
assert os.path.exists(ARCHIVE), f'Output file {ARCHIVE} does not exist'
with open(ARCHIVE, 'rb') as f:
    assert f.read() == ORIGINAL_ARCHIVE, 'Initial archive does not match the required RLE data'
assert_original_inputs()

# The demanded compiled artifact must exist, be executable, and be an ELF program.
st = os.stat(EXE)
assert stat.S_ISREG(st.st_mode), f'{EXE} is not a regular file'
assert os.access(EXE, os.X_OK), f'{EXE} is not executable'
with open(EXE, 'rb') as f:
    assert f.read(4) == b'\x7fELF', f'{EXE} is not an ELF executable'

work = tempfile.mkdtemp(prefix='archiver_verify_', dir='/home/user')
trace = os.path.join(work, 'trace.log')
preload_c = os.path.join(work, 'trace.c')
preload_so = os.path.join(work, 'trace.so')
rebuilt = os.path.join(work, 'rebuilt_archiver')
original_conf_bytes = open(CONF, 'rb').read()
original_file_bytes = {p: open(p, 'rb').read() for p in ORIGINALS}

try:
    with open(preload_c, 'w') as f:
        f.write(WRAPPER)
    run_checked(['gcc', '-shared', '-fPIC', '-O2', preload_c, '-o', preload_so, '-ldl'])
    # Also require the submitted C source to compile successfully.
    run_checked(['gcc', SRC, '-o', rebuilt])

    rng = random.SystemRandom()
    values = rng.sample(range(1, 255), 12)
    datasets = [
        bytes([values[0]]) * rng.randint(256, 600)
        + bytes([values[1]]) * rng.randint(1, 40)
        + bytes([values[2]]) * rng.randint(256, 520),
        bytes([values[3]]) * rng.randint(1, 20)
        + bytes([values[4]]) * rng.randint(30, 120)
        + bytes([values[5]]) * rng.randint(1, 20),
        bytes([values[6], values[7], values[8], 0, 10, values[9]])
        + bytes([values[10]]) * rng.randint(260, 400)
        + bytes([values[11]]),
    ]
    paths = []
    for i, data in enumerate(datasets):
        path = os.path.join(work, f'input_{i}_{rng.randrange(1 << 30)}.bin')
        with open(path, 'wb') as f:
            f.write(data)
        paths.append(path)
    with open(CONF, 'w') as f:
        for path in paths:
            f.write(path + '\n')

    expected = b''.join(rle(data) for data in datasets)
    with open(ARCHIVE, 'wb') as f:
        f.write(os.urandom(97))

    env = os.environ.copy()
    env['LD_PRELOAD'] = preload_so
    env['ARCHIVER_TRACE'] = trace
    run_checked([EXE], env=env)
    with open(ARCHIVE, 'rb') as f:
        assert f.read() == expected, 'Executable failed randomized configuration/RLE test'

    assert os.path.exists(trace), 'No mmap/flock trace was produced by the executable'
    events = []
    with open(trace, 'r', errors='replace') as f:
        for line in f:
            events.append(line.rstrip('\n').split('\t'))

    # For every configured file require successful shared-lock, read-only whole-file
    # mmap, munmap, unlock, and close operations in that order.
    for path, data in zip(paths, datasets):
        state = 0
        for e in events:
            if len(e) < 2 or e[1] != path:
                continue
            if state == 0 and e[0] == 'F' and int(e[2]) == 1 and int(e[3]) == 0:
                state = 1
            elif state == 1 and e[0] == 'M' and int(e[2]) == len(data) and (int(e[3]) & 1) and not (int(e[3]) & 2) and int(e[5]) == 0 and int(e[6]) == 1:
                state = 2
            elif state == 2 and e[0] == 'U' and int(e[2]) == len(data) and int(e[3]) == 0:
                state = 3
            elif state == 3 and e[0] == 'F' and int(e[2]) == 8 and int(e[3]) == 0:
                state = 4
            elif state == 4 and e[0] == 'C' and int(e[2]) == 0:
                state = 5
                break
        assert state == 5, f'Missing required lock/mmap/munmap/unlock/close sequence for {path}'

    # Ensure the submitted source itself implements the same generalized behavior.
    with open(ARCHIVE, 'wb') as f:
        f.write(os.urandom(83))
    run_checked([rebuilt])
    with open(ARCHIVE, 'rb') as f:
        assert f.read() == expected, 'Recompiled source failed randomized configuration/RLE test'
finally:
    with open(CONF, 'wb') as f:
        f.write(original_conf_bytes)
    for path, data in original_file_bytes.items():
        with open(path, 'wb') as f:
            f.write(data)
    shutil.rmtree(work, ignore_errors=True)

# Re-run the demanded artifact on the real configuration and retain the original
# final-state assertions.
if os.path.exists(ARCHIVE):
    os.unlink(ARCHIVE)
run_checked([EXE])
assert_original_inputs()
assert os.path.exists(ARCHIVE), f'Output file {ARCHIVE} does not exist after execution'
with open(ARCHIVE, 'rb') as f:
    assert f.read() == ORIGINAL_ARCHIVE, 'Final archive does not match the required RLE data'
PY
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
