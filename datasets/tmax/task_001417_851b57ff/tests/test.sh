#!/bin/bash
mkdir -p /logs/verifier

cat << 'MMAP_EOF' > /tmp/mmap_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static void record_if_target(int fd) {
    const char *dev_s = getenv("MMAP_AUDIT_DEV");
    const char *ino_s = getenv("MMAP_AUDIT_INO");
    const char *marker = getenv("MMAP_AUDIT_MARKER");
    struct stat st;

    if (!dev_s || !ino_s || !marker || fd < 0 || fstat(fd, &st) != 0)
        return;

    if ((unsigned long long)st.st_dev == strtoull(dev_s, NULL, 10) &&
        (unsigned long long)st.st_ino == strtoull(ino_s, NULL, 10)) {
        int out = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (out >= 0) {
            (void)write(out, "1", 1);
            close(out);
        }
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap)
        real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED)
        record_if_target(fd);
    return result;
}

#ifdef __USE_LARGEFILE64
void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t);
    if (!real_mmap64)
        real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    void *result = real_mmap64(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED)
        record_if_target(fd);
    return result;
}
#endif
MMAP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/oracle_parser"
AGENT_PATH = "/home/user/log_parser"
SOURCE_PATH = "/home/user/log_parser.c"
AUDIT_LIBRARY = "/tmp/mmap_audit.so"
DELIMITER = b"\xF0\x0D\xBB\x11"

# The reference must have been available to the agent as promised, but it must
# not remain callable while the submitted executable is under test.
assert os.path.isfile(ORACLE_PATH), "Oracle parser missing."
if os.path.isfile(AGENT_PATH):
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), \
        "The submitted executable is byte-identical to the reference binary."
os.unlink(ORACLE_PATH)


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), "The executable /home/user/log_parser is missing."
    assert os.access(AGENT_PATH, os.X_OK), "/home/user/log_parser is not executable."


def test_source_code_exists_and_uses_mmap():
    assert os.path.isfile(SOURCE_PATH), "The source file /home/user/log_parser.c is missing."
    with open(SOURCE_PATH, "r") as f:
        content = f.read()
    assert "mmap" in content, "The source code does not appear to use mmap as required."


def expected_output(data):
    count = 0
    output = bytearray()
    i = 0
    while i < len(data):
        if data[i:i + 4] == DELIMITER:
            output.extend(b"[LOG_SPLIT]\n")
            count += 1
            i += 4
        else:
            output.append(data[i])
            i += 1
    output.extend(b"\nEOF_CHUNKS: " + str(count).encode("ascii") + b"\n")
    return bytes(output)


def generate_random_input(length):
    if length == 0:
        return b""

    data = bytearray(os.urandom(length))
    num_injections = length // 1000
    for _ in range(num_injections):
        if length >= 4:
            idx = random.randint(0, length - 4)
            data[idx:idx + 4] = DELIMITER
    return bytes(data)


def run_agent(input_path, require_mmap):
    st = os.stat(input_path)
    fd, marker = tempfile.mkstemp(prefix="mmap-marker-")
    os.close(fd)
    os.unlink(marker)

    env = os.environ.copy()
    env["LD_PRELOAD"] = AUDIT_LIBRARY
    env["MMAP_AUDIT_DEV"] = str(st.st_dev)
    env["MMAP_AUDIT_INO"] = str(st.st_ino)
    env["MMAP_AUDIT_MARKER"] = marker

    try:
        proc = subprocess.run(
            [AGENT_PATH, input_path],
            capture_output=True,
            env=env,
            timeout=10,
        )
        if require_mmap:
            assert os.path.isfile(marker) and os.path.getsize(marker) > 0, \
                "The executable did not mmap the input file."
        return proc
    finally:
        if os.path.exists(marker):
            os.remove(marker)


def test_fuzz_equivalence():
    assert not os.path.exists(ORACLE_PATH), "Oracle remained accessible during verification."

    edge_cases = [
        b"",
        DELIMITER,
        DELIMITER + DELIMITER,
        b"A" * 100,
        b"A" * 10 + DELIMITER + b"B" * 10,
        DELIMITER + b"A" * 10,
        b"A" * 10 + DELIMITER,
    ]

    random.seed(42)
    for _ in range(50):
        length = random.randint(10, 50000)
        edge_cases.append(generate_random_input(length))

    for i, data in enumerate(edge_cases):
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(data)
            tmp_path = tmp.name

        try:
            agent_proc = run_agent(tmp_path, require_mmap=(len(data) > 0))
            expected = expected_output(data)

            assert agent_proc.returncode == 0, f"Return code mismatch on test case {i}"
            assert agent_proc.stdout == expected, \
                f"Output mismatch on test case {i}. Length of input: {len(data)}"
            assert agent_proc.stderr == b"", f"Stderr mismatch on test case {i}"
        finally:
            os.remove(tmp_path)
TEST_EOF

if gcc -shared -fPIC -O2 /tmp/mmap_audit.c -o /tmp/mmap_audit.so -ldl \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
