#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import secrets
import string
import subprocess
from pathlib import Path

import pytest

LIB_DIR = Path('/app/libsemver-v1.0.0')
SO_PATH = LIB_DIR / 'libsemver.so'
FILTER_PATH = Path('/home/user/version_filter')


def run_filter(input_path, output_path, *, env=None, timeout=15):
    if output_path.exists():
        output_path.unlink()
    result = subprocess.run(
        [str(FILTER_PATH), str(input_path), str(output_path)],
        capture_output=True,
        text=True,
        env=env,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f'version_filter failed with return code {result.returncode}.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert output_path.is_file(), f'Output file {output_path} was not created.'
    return output_path.read_bytes()


def test_libsemver_so_built_and_makefile_fixed():
    assert SO_PATH.is_file(), f'Expected shared library {SO_PATH} was not built.'

    result = subprocess.run(
        ['make', 'clean', 'shared'],
        cwd=LIB_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        'make clean shared failed; the Makefile does not correctly build the shared library.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert SO_PATH.is_file(), f'Expected shared library {SO_PATH} was not built.'
    assert SO_PATH.read_bytes()[:4] == b'\x7fELF', 'libsemver.so is not an ELF shared library.'
    lib = ctypes.CDLL(str(SO_PATH))
    assert getattr(lib, 'semver_parse', None) is not None, 'libsemver.so does not export semver_parse.'


def test_version_filter_executable_exists():
    assert FILTER_PATH.is_file(), f'Executable {FILTER_PATH} does not exist.'
    assert os.access(FILTER_PATH, os.X_OK), f'File {FILTER_PATH} is not executable.'


def test_version_filter_clean_corpus():
    clean_in = Path('/app/corpus/clean/good_versions.txt')
    clean_out = Path('/tmp/clean_out.txt')
    actual = run_filter(clean_in, clean_out)
    assert actual.splitlines() == clean_in.read_bytes().splitlines(), (
        'Clean corpus was modified or not fully preserved.'
    )


def test_version_filter_evil_corpus():
    evil_in = Path('/app/corpus/evil/bad_versions.txt')
    evil_out = Path('/tmp/evil_out.txt')
    actual = run_filter(evil_in, evil_out)
    actual_lines = [line for line in actual.splitlines() if line.strip()]
    assert len(actual_lines) == 0, (
        f'Evil corpus bypassed the filter. {len(actual_lines)} evil lines were accepted.'
    )


def build_oracle():
    source = Path('/tmp/semver_oracle.c')
    binary = Path('/tmp/semver_oracle')
    source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include "semver.h"

int main(void) {
    char *line = NULL;
    size_t cap = 0;
    ssize_t n = getline(&line, &cap, stdin);
    if (n < 0) return 2;
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = '\0';
    semver_t version = {0};
    int result = semver_parse(line, &version);
    if (result == 0) semver_free(&version);
    free(line);
    return result == 0 ? 0 : 1;
}
''')
    result = subprocess.run(
        [
            'gcc', '-O2', '-I', str(LIB_DIR), str(source),
            '-L', str(LIB_DIR), '-Wl,-rpath,' + str(LIB_DIR),
            '-lsemver', '-o', str(binary),
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'Could not compile semver oracle: {result.stderr}'
    return binary


def oracle_accepts(oracle, line):
    try:
        result = subprocess.run(
            [str(oracle)], input=line + b'\n', capture_output=True, timeout=3
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def build_audit_library():
    source = Path('/tmp/semver_audit.c')
    library = Path('/tmp/semver_audit.so')
    source.write_text(r'''
#define _GNU_SOURCE
#include <link.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

static int log_fd = -1;

unsigned int la_version(unsigned int version) {
    log_fd = open("/tmp/semver_audit.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    return LAV_CURRENT;
}

unsigned int la_objopen(struct link_map *map, Lmid_t lmid, uintptr_t *cookie) {
    (void)lmid;
    *cookie = (uintptr_t)map;
    if (log_fd >= 0 && map->l_name && strstr(map->l_name, "/app/libsemver-v1.0.0/libsemver.so"))
        write(log_fd, "OBJECT libsemver.so\n", 20);
    return LA_FLG_BINDTO | LA_FLG_BINDFROM;
}

uintptr_t la_symbind64(Elf64_Sym *sym, unsigned int ndx, uintptr_t *refcook,
                       uintptr_t *defcook, unsigned int *flags, const char *name) {
    (void)ndx; (void)refcook; (void)defcook; (void)flags;
    if (log_fd >= 0 && name && strcmp(name, "semver_parse") == 0)
        write(log_fd, "SYMBOL semver_parse\n", 20);
    return sym->st_value;
}
''')
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', str(source), '-o', str(library)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'Could not compile runtime audit library: {result.stderr}'
    return library


def test_randomized_inputs_match_libsemver_and_library_is_used():
    oracle = build_oracle()
    rng = random.SystemRandom()

    valid_candidates = []
    for _ in range(30):
        major, minor, patch = (rng.randrange(0, 1000000) for _ in range(3))
        token = secrets.token_hex(rng.randrange(2, 10))
        choice = rng.randrange(4)
        if choice == 0:
            value = f'{major}.{minor}.{patch}'
        elif choice == 1:
            value = f'{major}.{minor}.{patch}-alpha.{rng.randrange(0, 10000)}'
        elif choice == 2:
            value = f'{major}.{minor}.{patch}+build.{token}'
        else:
            value = f'{major}.{minor}.{patch}-rc.{rng.randrange(0, 100)}+{token}'
        valid_candidates.append(value.encode())

    malformed = []
    alphabet = string.ascii_letters + string.digits + '._-+[]!@/'
    for _ in range(45):
        value = ''.join(rng.choice(alphabet) for _ in range(rng.randrange(1, 80)))
        malformed.append(value.encode())
    malformed.extend([
        f'{rng.randrange(1,999)}.{rng.randrange(1,999)}'.encode(),
        f'{rng.randrange(1,999)}..{rng.randrange(1,999)}'.encode(),
        f'-{rng.randrange(1,999)}.2.3'.encode(),
        ('A' * rng.randrange(120000, 180000) + '.0.0').encode(),
        b'',
    ])

    lines = valid_candidates + malformed
    rng.shuffle(lines)
    accepted = [line for line in lines if oracle_accepts(oracle, line)]
    rejected = [line for line in lines if line not in accepted]
    assert accepted, 'Oracle unexpectedly accepted no generated inputs.'
    assert rejected, 'Oracle unexpectedly rejected no generated inputs.'

    nonce = secrets.token_hex(12)
    input_path = Path(f'/tmp/generated-{nonce}.txt')
    output_path = Path(f'/tmp/generated-out-{nonce}.txt')
    input_path.write_bytes(b''.join(line + b'\n' for line in lines))
    expected = b''.join(line + b'\n' for line in lines if oracle_accepts(oracle, line))

    actual = run_filter(input_path, output_path, timeout=20)
    assert actual == expected, (
        'version_filter output did not match results independently derived by calling libsemver.'
    )

    audit_library = build_audit_library()
    audit_log = Path('/tmp/semver_audit.log')
    if audit_log.exists():
        audit_log.unlink()
    env = os.environ.copy()
    env['LD_AUDIT'] = str(audit_library)
    audited_output = Path(f'/tmp/generated-audited-out-{nonce}.txt')
    actual = run_filter(input_path, audited_output, env=env, timeout=20)
    assert actual == expected, 'Audited execution produced incorrect output.'
    log = audit_log.read_text(errors='replace') if audit_log.exists() else ''
    assert 'OBJECT libsemver.so' in log, 'version_filter did not load the required libsemver.so.'
    assert 'SYMBOL semver_parse' in log, 'version_filter did not bind/call libsemver semver_parse.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
