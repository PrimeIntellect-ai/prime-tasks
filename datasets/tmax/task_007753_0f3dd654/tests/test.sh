#!/bin/bash
mkdir -p /logs/verifier

if (
set -e

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_extract_drops_cpp_exists():
    assert os.path.isfile('/home/user/extract_drops.cpp'), "The C++ source file /home/user/extract_drops.cpp does not exist."

def test_mmap_used_in_cpp():
    with open('/home/user/extract_drops.cpp', 'r') as f:
        content = f.read()
    assert re.search(r'\bmmap\s*\(', content), "The C++ program does not appear to use mmap() as required."

def test_dropped_objects_txt_exists():
    assert os.path.isfile('/home/user/dropped_objects.txt'), "The output file /home/user/dropped_objects.txt does not exist."

def test_dropped_objects_content():
    expected_ids = [12, 404, 777, 999]

    with open('/home/user/dropped_objects.txt', 'r') as f:
        lines = f.read().strip().split('\n')

    lines = [line.strip() for line in lines if line.strip()]
    assert len(lines) == len(expected_ids), f"Expected {len(expected_ids)} unique DROP Object IDs, but found {len(lines)}."

    for i, expected_id in enumerate(expected_ids):
        try:
            actual_id = int(lines[i])
        except ValueError:
            assert False, f"Line {i+1} in dropped_objects.txt is not a valid integer: '{lines[i]}'."
        assert actual_id == expected_id, f"Expected Object ID {expected_id} at line {i+1}, but got {actual_id}. Ensure output is sorted and unique."
TEST_EOF

# Preserve all original final-state assertions.
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

# Compile the submitted source using the command required by the instruction.
g++ -O3 /home/user/extract_drops.cpp -o /home/user/extract_drops

# Install a small mmap interposer so verification can confirm that the executed
# program successfully maps WAL files rather than merely mentioning mmap.
cat << 'HOOK_EOF' > /tmp/mmap_audit.c
#define _GNU_SOURCE
#define _LARGEFILE64_SOURCE
#include <sys/mman.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void record_mapping(int fd, void *result) {
    if (fd < 0 || result == MAP_FAILED) return;

    char link_name[64];
    char path[PATH_MAX + 1];
    int n = snprintf(link_name, sizeof(link_name), "/proc/self/fd/%d", fd);
    if (n <= 0 || n >= (int)sizeof(link_name)) return;

    ssize_t count = readlink(link_name, path, PATH_MAX);
    if (count <= 0) return;
    path[count] = '\0';

    const char *prefix = "/home/user/wal_archive/";
    size_t plen = strlen(prefix);
    size_t pathlen = strlen(path);
    if (strncmp(path, prefix, plen) != 0 || pathlen < 4 || strcmp(path + pathlen - 4, ".wal") != 0) return;

    const char *log_path = getenv("MMAP_AUDIT_LOG");
    if (!log_path) return;
    int out = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (out >= 0) {
        write(out, path, pathlen);
        write(out, "\n", 1);
        close(out);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    if (!real_mmap) { errno = ENOSYS; return MAP_FAILED; }
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    record_mapping(fd, result);
    return result;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t);
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    if (!real_mmap64) { errno = ENOSYS; return MAP_FAILED; }
    void *result = real_mmap64(addr, length, prot, flags, fd, offset);
    record_mapping(fd, result);
    return result;
}
HOOK_EOF
gcc -shared -fPIC /tmp/mmap_audit.c -o /tmp/mmap_audit.so -ldl

# Replace the fixed fixture with fresh, unpredictable valid WAL files. The
# expected result is retained in a root-only file and is derived from the data.
python3 << 'PY_EOF'
import json
import os
import secrets
import shutil
import struct

archive = '/home/user/wal_archive'
shutil.rmtree(archive)
os.makedirs(archive, mode=0o755)

def distinct_id(used, high=False):
    while True:
        if high:
            value = 0x80000000 + secrets.randbelow(0x80000000)
        else:
            value = 1 + secrets.randbelow(0x7fffffff)
        if value not in used:
            used.add(value)
            return value

used = set()
ids = [distinct_id(used, high=(i in (1, 4))) for i in range(6)]
distractors = [distinct_id(used, high=(i == 1)) for i in range(4)]
base_ts = secrets.randbits(48)

def write_wal(path, records):
    with open(path, 'wb') as f:
        f.write(b'WALv1\0\0\0')
        for ts, op, obj_id, payload in records:
            f.write(struct.pack('<QBII', ts, op, obj_id, len(payload)))
            f.write(payload)

write_wal(os.path.join(archive, 'case_a.wal'), [
    (base_ts + 1, 1, distractors[0], b'insert-data'),
    (base_ts + 2, 3, ids[4], b''),
    (base_ts + 3, 2, distractors[1], b'update' * 31),
    (base_ts + 4, 3, ids[0], b'reason\x00with\x00nul'),
    (base_ts + 5, 3, ids[4], b'duplicate'),
])
write_wal(os.path.join(archive, 'case_b.wal'), [
    (base_ts + 6, 3, ids[2], secrets.token_bytes(257)),
    (base_ts + 7, 1, distractors[2], b''),
    (base_ts + 8, 3, ids[1], b'x'),
])
write_wal(os.path.join(archive, 'case_c.wal'), [
    (base_ts + 9, 2, distractors[3], b'z' * 4097),
    (base_ts + 10, 3, ids[5], b''),
    (base_ts + 11, 3, ids[3], b'last'),
])
# A non-WAL extension must not contribute its DROP record.
write_wal(os.path.join(archive, 'ignore.bin'), [
    (base_ts + 12, 3, distinct_id(used), b'not a wal file')
])

with open('/tmp/expected_drop_ids.json', 'w') as f:
    json.dump(sorted(ids), f)
os.chmod('/tmp/expected_drop_ids.json', 0o600)
PY_EOF

rm -f /home/user/dropped_objects.txt
: > /tmp/mmap_audit.log
chmod 666 /tmp/mmap_audit.log

timeout 20s runuser -u user -- env \
    LD_PRELOAD=/tmp/mmap_audit.so \
    MMAP_AUDIT_LOG=/tmp/mmap_audit.log \
    /home/user/extract_drops

python3 << 'VERIFY_EOF'
import json
import os

output = '/home/user/dropped_objects.txt'
assert os.path.isfile(output), 'The executed program did not create dropped_objects.txt.'
with open('/tmp/expected_drop_ids.json') as f:
    expected = json.load(f)
with open(output) as f:
    lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]
assert len(lines) == len(expected), f'Expected {len(expected)} unique DROP Object IDs, but found {len(lines)}.'
try:
    actual = [int(line) for line in lines]
except ValueError as exc:
    raise AssertionError(f'dropped_objects.txt contains a non-integer line: {exc}')
assert actual == expected, f'Executed program produced {actual}, expected sorted unique IDs {expected}.'

with open('/tmp/mmap_audit.log') as f:
    mapped = {os.path.basename(line.strip()) for line in f if line.strip()}
required = {'case_a.wal', 'case_b.wal', 'case_c.wal'}
assert required <= mapped, f'The executed program did not successfully mmap every WAL fixture; observed mappings: {sorted(mapped)}'
VERIFY_EOF
) ; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
