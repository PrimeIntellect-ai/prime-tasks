#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import struct
import subprocess


def test_complete_task_and_dynamic_extraction():
    c_file = '/home/user/extract_metadata.c'
    executable = '/home/user/extract_metadata'
    archive = '/home/user/legacy_archive.bin'
    raw_file = '/home/user/raw_metadata.txt'
    csv_file = '/home/user/clean_metadata.csv'
    manifest_file = '/home/user/manifest.txt'

    # Preserve the original source assertion.
    assert os.path.exists(c_file), f"File {c_file} is missing."
    with open(c_file, 'r') as f:
        content = f.read()
    assert 'mmap' in content, f"The C program {c_file} must use 'mmap'."

    # The requested compiled artifact must already exist and be an executable ELF.
    assert os.path.isfile(executable), f"Compiled program {executable} is missing."
    assert os.access(executable, os.X_OK), f"Compiled program {executable} is not executable."
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{executable} is not a compiled ELF executable."

    # Preserve the original output assertions.
    assert os.path.exists(raw_file), f"File {raw_file} is missing."
    expected_raw = [
        "ID:1001|DATE:20231015|STATUS:A",
        "ID:1002|DATE:20231016|STATUS:B",
        "ID:1003|DATE:20231017|STATUS:C",
    ]
    with open(raw_file, 'r') as f:
        actual_raw = [line.strip() for line in f.readlines() if line.strip()]
    assert actual_raw == expected_raw, \
        f"Content of {raw_file} is incorrect. Expected {expected_raw}, got {actual_raw}."

    assert os.path.exists(csv_file), f"File {csv_file} is missing."
    expected_csv = [
        "1001,20231015,A",
        "1002,20231016,B",
        "1003,20231017,C",
    ]
    with open(csv_file, 'r') as f:
        actual_csv = [line.strip() for line in f.readlines() if line.strip()]
    assert actual_csv == expected_csv, \
        f"Content of {csv_file} is incorrect. Expected {expected_csv}, got {actual_csv}."

    assert os.path.exists(manifest_file), f"File {manifest_file} is missing."
    with open(csv_file, 'rb') as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()
    with open(manifest_file, 'r') as f:
        manifest_content = f.read().strip()
    assert expected_hash in manifest_content, \
        f"Manifest {manifest_file} does not contain the correct hash {expected_hash} for {csv_file}."
    assert "clean_metadata.csv" in manifest_content, \
        f"Manifest {manifest_file} does not contain the filename 'clean_metadata.csv'."
    expected_manifest_line = f"{expected_hash}  clean_metadata.csv"
    assert manifest_content == expected_manifest_line or manifest_content == f"{expected_hash} *clean_metadata.csv", \
        f"Manifest format is incorrect. Expected '{expected_manifest_line}', got '{manifest_content}'."

    # Recompile the submitted source so the behavioral test exercises that source.
    compile_result = subprocess.run(
        ['gcc', '-O2', c_file, '-o', executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, \
        f"Failed to compile {c_file}:\n{compile_result.stderr}"

    # Interpose mmap and record only a successful mapping of the archive itself.
    hook_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

typedef void *(*mmap_fn)(void *, size_t, int, int, int, off_t);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static mmap_fn real_mmap = NULL;
    if (!real_mmap)
        real_mmap = (mmap_fn)dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED && fd >= 0) {
        char procpath[64];
        char target[PATH_MAX];
        snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(procpath, target, sizeof(target) - 1);
        if (n >= 0) {
            target[n] = '\0';
            if (strcmp(target, "/home/user/legacy_archive.bin") == 0) {
                const char *marker = getenv("MMAP_MARKER");
                if (marker) {
                    int out = open(marker, O_WRONLY | O_CREAT | O_TRUNC, 0600);
                    if (out >= 0) {
                        write(out, "mapped\n", 7);
                        close(out);
                    }
                }
            }
        }
    }
    return result;
}
'''
    hook_c = '/tmp/verify_mmap_hook.c'
    hook_so = '/tmp/verify_mmap_hook.so'
    with open(hook_c, 'w') as f:
        f.write(hook_source)
    hook_compile = subprocess.run(
        ['gcc', '-shared', '-fPIC', hook_c, '-o', hook_so, '-ldl'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert hook_compile.returncode == 0, hook_compile.stderr

    original_archive = open(archive, 'rb').read()
    original_raw = open(raw_file, 'rb').read()
    marker = f"/tmp/mmap_marker_{secrets.token_hex(12)}"

    try:
        rng = random.SystemRandom()
        metadata_payloads = []
        records = []
        for i in range(5):
            ident = str(rng.randrange(200000, 999999))
            date = f"{rng.randrange(2024, 2035):04d}{rng.randrange(1, 13):02d}{rng.randrange(1, 29):02d}"
            status = chr(ord('A') + rng.randrange(26))
            payload = f"ID:{ident}|DATE:{date}|STATUS:{status}".encode('ascii')
            metadata_payloads.append(payload)
            records.append((2, payload))
            records.append((1, secrets.token_bytes(rng.randrange(1, 48))))
        rng.shuffle(records)
        expected_dynamic = [payload for record_type, payload in records if record_type == 2]

        with open(archive, 'wb') as f:
            for record_type, payload in records:
                f.write(struct.pack('<III', 0xBACCBACC, record_type, len(payload)))
                f.write(payload)
        if os.path.exists(raw_file):
            os.remove(raw_file)
        if os.path.exists(marker):
            os.remove(marker)

        env = os.environ.copy()
        env['LD_PRELOAD'] = hook_so
        env['MMAP_MARKER'] = marker
        run_result = subprocess.run(
            [executable],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )

        assert os.path.exists(marker), \
            "The submitted program did not mmap /home/user/legacy_archive.bin."
        assert os.path.exists(raw_file), \
            "Executing the submitted program did not create raw_metadata.txt."
        with open(raw_file, 'rb') as f:
            dynamic_output = f.read()
        expected_output = b''.join(payload + b'\n' for payload in expected_dynamic)
        assert dynamic_output == expected_output, \
            f"Program failed on verifier-generated archive data. stderr: {run_result.stderr.decode(errors='replace')}"
    finally:
        with open(archive, 'wb') as f:
            f.write(original_archive)
        with open(raw_file, 'wb') as f:
            f.write(original_raw)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
