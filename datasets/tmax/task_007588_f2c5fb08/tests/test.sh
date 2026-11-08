#!/bin/bash
set -e
mkdir -p /logs/verifier

run_checks() {
    SRC=$(find /home/user -type f -name parser.cpp -print -quit)
    [ -n "$SRC" ] || { echo 'parser.cpp not found'; return 1; }

    ORIGINAL_BIN="$(dirname "$SRC")/parser"
    [ -f "$ORIGINAL_BIN" ] && [ -x "$ORIGINAL_BIN" ] || { echo 'Compiled parser executable not found beside parser.cpp'; return 1; }

    g++ -std=c++17 "$SRC" -o /tmp/submission_parser || return 1

    rm -rf /home/user/processed
    mkdir -p /home/user/processed
    rm -f /tmp/rename_trace /tmp/challenge_manifest.json

    python3 <<'PY' || return 1
import json
import os
import secrets
import struct

root = '/home/user/project_data'
tag = secrets.token_hex(8)
nested = os.path.join(root, 'dynamic_' + tag, 'deep')
os.makedirs(nested, exist_ok=True)

files = []
for index, directory in enumerate((root, nested)):
    name = f'challenge_{tag}_{index}.dat'
    payload = secrets.token_bytes(41 + index * 17) + b'\x00DYNAMIC\xff' + tag.encode()
    version = 37 + index
    path = os.path.join(directory, name)
    with open(path, 'wb') as f:
        f.write(b'DAT\x00' + bytes([version]) + struct.pack('<I', len(payload)) + payload)
    files.append({'name': name, 'payload_hex': payload.hex()})

critical1 = f'Context {tag}\n[CRITICAL] randomized failure {secrets.token_hex(6)}\ncontinuation {secrets.token_hex(5)}'
critical2 = f'prefix-[CRITICAL]-suffix {tag}\nsecond line {secrets.token_hex(5)}'
noncritical = f'ordinary record {tag}'
incomplete = f'[CRITICAL] incomplete {tag}'
log_path = os.path.join(nested, f'events_{tag}.log')
with open(log_path, 'w', encoding='utf-8') as f:
    f.write('[RECORD_START]\n' + noncritical + '\n[RECORD_END]\n')
    f.write('[RECORD_START]\n' + critical1 + '\n[RECORD_END]\n')
    f.write('[RECORD_START]\n' + critical2 + '\n[RECORD_END]\n')
    f.write('[RECORD_START]\n' + incomplete + '\n')

# Add another cycle to ensure the dynamically exercised traversal terminates.
cycle = os.path.join(nested, 'cycle_to_root')
if not os.path.lexists(cycle):
    os.symlink(root, cycle)

with open('/tmp/challenge_manifest.json', 'w', encoding='utf-8') as f:
    json.dump({
        'files': files,
        'critical': [critical1, critical2],
        'noncritical': noncritical,
        'incomplete': incomplete,
    }, f)
PY

    cat > /tmp/rename_trace.c <<'C'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static void fullpath(int dirfd, const char *path, char *out, size_t size) {
    if (!path) {
        snprintf(out, size, "(null)");
    } else if (path[0] == '/') {
        snprintf(out, size, "%s", path);
    } else {
        char base[PATH_MAX] = {0};
        if (dirfd == AT_FDCWD) {
            if (!getcwd(base, sizeof(base))) snprintf(base, sizeof(base), ".");
        } else {
            char proc[64];
            snprintf(proc, sizeof(proc), "/proc/self/fd/%d", dirfd);
            ssize_t n = readlink(proc, base, sizeof(base) - 1);
            if (n < 0) snprintf(base, sizeof(base), ".");
            else base[n] = '\0';
        }
        snprintf(out, size, "%s/%s", base, path);
    }
}

static void record_move(int oldfd, const char *oldpath, int newfd, const char *newpath, int rc) {
    if (rc != 0) return;
    char src[PATH_MAX * 2], dst[PATH_MAX * 2], line[PATH_MAX * 4 + 32];
    fullpath(oldfd, oldpath, src, sizeof(src));
    fullpath(newfd, newpath, dst, sizeof(dst));
    int n = snprintf(line, sizeof(line), "%s\t%s\t%d\n", src, dst, rc);
    int fd = open("/tmp/rename_trace", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        if (n > 0) write(fd, line, (size_t)n);
        close(fd);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    int rc = real_fn(oldpath, newpath);
    record_move(AT_FDCWD, oldpath, AT_FDCWD, newpath, rc);
    return rc;
}

int renameat(int oldfd, const char *oldpath, int newfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    int rc = real_fn(oldfd, oldpath, newfd, newpath);
    record_move(oldfd, oldpath, newfd, newpath, rc);
    return rc;
}

int renameat2(int oldfd, const char *oldpath, int newfd, const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    int rc;
    if (real_fn) rc = real_fn(oldfd, oldpath, newfd, newpath, flags);
    else rc = (int)syscall(SYS_renameat2, oldfd, oldpath, newfd, newpath, flags);
    record_move(oldfd, oldpath, newfd, newpath, rc);
    return rc;
}
C
    gcc -shared -fPIC /tmp/rename_trace.c -o /tmp/rename_trace.so -ldl || return 1

    (cd /home/user && timeout 15s env LD_PRELOAD=/tmp/rename_trace.so /tmp/submission_parser) || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os


def test_processed_dat_files():
    file1_path = "/home/user/processed/dat/file1.dat"
    file2_path = "/home/user/processed/dat/file2.dat"

    assert os.path.isfile(file1_path), f"Missing processed file: {file1_path}"
    with open(file1_path, "rb") as f:
        assert f.read() == b"HELLO", f"Incorrect content in {file1_path}"

    assert os.path.isfile(file2_path), f"Missing processed file: {file2_path}"
    with open(file2_path, "rb") as f:
        assert f.read() == b"TEST", f"Incorrect content in {file2_path}"


def test_critical_errors_log():
    log_path = "/home/user/processed/critical_errors.txt"
    assert os.path.isfile(log_path), f"Missing critical errors log: {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    record1 = "Warning: High memory usage\n[CRITICAL] Out of memory!\nPlease restart."
    record2 = "[CRITICAL] Database connection lost\nRetrying in 5 seconds..."

    assert record1 in content, "Missing or malformed first critical record in critical_errors.txt"
    assert record2 in content, "Missing or malformed second critical record in critical_errors.txt"

    assert "[RECORD_START]" not in content, "Found [RECORD_START] in critical_errors.txt, but markers should be excluded."
    assert "[RECORD_END]" not in content, "Found [RECORD_END] in critical_errors.txt, but markers should be excluded."

    assert "System booted" not in content, "Found non-critical record in critical_errors.txt."
    assert "User logged in" not in content, "Found non-critical record in critical_errors.txt."
    assert "Retry failed." not in content, "Found non-critical record in critical_errors.txt."


def manifest():
    with open('/tmp/challenge_manifest.json', encoding='utf-8') as f:
        return json.load(f)


def test_randomized_binary_headers_and_payloads():
    data = manifest()
    for item in data['files']:
        path = os.path.join('/home/user/processed/dat', item['name'])
        assert os.path.isfile(path), f'Missing dynamically generated output: {path}'
        with open(path, 'rb') as f:
            assert f.read() == bytes.fromhex(item['payload_hex'])


def test_randomized_multiline_records():
    data = manifest()
    path = '/home/user/processed/critical_errors.txt'
    with open(path, encoding='utf-8') as f:
        content = f.read()
    for record in data['critical']:
        assert content.count(record) == 1, 'A complete randomized critical record was missing, malformed, or duplicated'
    assert data['noncritical'] not in content
    assert data['incomplete'] not in content


def test_dat_outputs_were_published_by_atomic_rename():
    data = manifest()
    assert os.path.isfile('/tmp/rename_trace'), 'No successful rename operations were observed'
    moves = []
    with open('/tmp/rename_trace', encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) == 3 and parts[2] == '0':
                moves.append((os.path.normpath(parts[0]), os.path.normpath(parts[1])))

    output_dir = os.path.normpath('/home/user/processed/dat')
    for item in data['files']:
        destination = os.path.join(output_dir, item['name'])
        matching_sources = [src for src, dst in moves if dst == destination]
        assert matching_sources, f'{destination} was not atomically published with rename'
        assert any(os.path.dirname(src) == output_dir and src != destination for src in matching_sources), \
            f'Temporary file for {destination} was not created in the output directory'
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
