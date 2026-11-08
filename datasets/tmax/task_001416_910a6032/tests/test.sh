#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/polyglot-sanitizer')
CLI_PATH = PROJECT / 'bin/sanitizer_cli'
BUILD_PATH = PROJECT / 'build.sh'
C_SOURCE = PROJECT / 'c_src/filter.c'
RUST_PROJECT = PROJECT / 'rust_src'
ORACLE_PATH = Path('/app/sanitizer_oracle')
CLEAN_CORPUS = Path('/app/corpus/clean')
EVIL_CORPUS = Path('/app/corpus/evil')


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def find_filter_library():
    candidates = []
    for path in PROJECT.rglob('libfilter.so'):
        if path.is_file():
            result = run(['nm', '-D', str(path)], text=True)
            if result.returncode == 0 and 'validate_and_check' in result.stdout:
                candidates.append(path)
    assert candidates, 'No libfilter.so exporting validate_and_check was produced'
    return candidates[0]


def assert_elf(path):
    assert path.is_file(), f'Missing artifact: {path}'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF binary'


def compare_program(program, path):
    oracle = run([str(ORACLE_PATH), str(path)], timeout=5)
    actual = run([str(program), str(path)], timeout=5)
    if oracle.returncode == 0:
        assert actual.returncode == 0, f'{path.name}: expected exit 0, got {actual.returncode}'
        assert actual.stdout == oracle.stdout, f'{path.name}: stdout differs from oracle'
    else:
        assert oracle.returncode == 1
        assert actual.returncode == 1, f'{path.name}: invalid input must exit 1, got {actual.returncode}'
        assert actual.stdout == b'', f'{path.name}: invalid input produced stdout'


def generated_cases(directory):
    cases = [
        b'',
        b'ordinary ASCII text',
        'Unicode: café Ελληνικά 日本語 😀'.encode(),
        b'prefix<script>suffix',
        b'prefix exec(command) suffix',
        b'\xff', b'\x80', b'\xc2', b'\xe2\x82', b'\xf0\x9f\x92',
        b'abc\xe2\x28\xa1xyz', b'abc\xf0\x28\x8c\xbcxyz',
        b'<' + b'a' * 4095, b'e' + b'a' * 4095,
        ('line\n' * 1000).encode(),
    ]
    state = 0x6D2B79F5
    for index in range(80):
        data = bytearray()
        length = 1 + (index * 37) % 257
        for _ in range(length):
            state ^= (state << 13) & 0xffffffff
            state ^= state >> 17
            state ^= (state << 5) & 0xffffffff
            data.append(1 + (state % 255))  # avoid NUL because the supplied oracle prints with printf("%s")
        if index % 11 == 0 and len(data) >= 8:
            pos = len(data) // 3
            data[pos:pos + 8] = b'<script>'
        elif index % 13 == 0 and len(data) >= 5:
            pos = len(data) // 2
            data[pos:pos + 5] = b'exec('
        cases.append(bytes(data))

    paths = []
    for i, data in enumerate(cases):
        path = Path(directory) / f'case_{i:03d}.bin'
        path.write_bytes(data)
        paths.append(path)
    return paths


def test_00_build_pipeline_and_artifacts():
    assert BUILD_PATH.is_file(), f'Build script not found at {BUILD_PATH}'
    assert C_SOURCE.is_file(), f'C implementation not found at {C_SOURCE}'
    assert (RUST_PROJECT / 'src/main.rs').is_file(), 'Rust implementation is missing'
    assert (RUST_PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing'

    if CLI_PATH.exists() or CLI_PATH.is_symlink():
        CLI_PATH.unlink()
    for old_lib in PROJECT.rglob('libfilter.so'):
        if old_lib.is_file() or old_lib.is_symlink():
            old_lib.unlink()
    shutil.rmtree(RUST_PROJECT / 'target', ignore_errors=True)

    result = run(['bash', str(BUILD_PATH)], cwd=str(PROJECT), text=True, timeout=180)
    assert result.returncode == 0, f'build.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'

    assert CLI_PATH.is_file(), f'Compiled binary not found at {CLI_PATH}'
    assert os.access(CLI_PATH, os.X_OK), f'Binary at {CLI_PATH} is not executable'
    assert_elf(CLI_PATH)
    assert CLI_PATH.read_bytes() != ORACLE_PATH.read_bytes(), 'Submission is byte-identical to the reference oracle'

    library = find_filter_library()
    assert_elf(library)
    header = run(['readelf', '-h', str(library)], text=True)
    assert header.returncode == 0 and 'DYN (Shared object file)' in header.stdout, 'libfilter.so is not a shared library'

    dynamic = run(['readelf', '-d', str(CLI_PATH)], text=True)
    assert dynamic.returncode == 0, dynamic.stderr
    assert 'Shared library: [libfilter.so]' in dynamic.stdout, 'sanitizer_cli is not dynamically linked to libfilter.so'
    linked = run(['ldd', str(CLI_PATH)], text=True)
    assert linked.returncode == 0, linked.stderr
    filter_lines = [line for line in linked.stdout.splitlines() if 'libfilter.so' in line]
    assert filter_lines and all('not found' not in line for line in filter_lines), 'libfilter.so cannot be resolved at runtime'


def test_01_cli_binary_exists():
    assert CLI_PATH.is_file(), f'Compiled binary not found at {CLI_PATH}'
    assert os.access(CLI_PATH, os.X_OK), f'Binary at {CLI_PATH} is not executable'
    assert_elf(CLI_PATH)


def test_02_original_corpora_with_exact_exit_contract():
    evil_files = [p for p in EVIL_CORPUS.iterdir() if p.is_file()]
    clean_files = [p for p in CLEAN_CORPUS.iterdir() if p.is_file()]

    for path in evil_files:
        result = run([str(CLI_PATH), str(path)], timeout=5)
        assert result.returncode == 1, f'{path.name}: evil input returned {result.returncode}, not 1'
        assert result.stdout == b'', f'{path.name}: evil input produced stdout'

    for path in clean_files:
        oracle_result = run([str(ORACLE_PATH), str(path)], timeout=5)
        cli_result = run([str(CLI_PATH), str(path)], timeout=5)
        assert cli_result.returncode == 0, f'{path.name}: clean input rejected with {cli_result.returncode}'
        assert cli_result.stdout == oracle_result.stdout, f'{path.name}: stdout mismatch'


def test_03_generated_oracle_cases():
    with tempfile.TemporaryDirectory() as directory:
        for path in generated_cases(directory):
            compare_program(CLI_PATH, path)


def test_04_c_implementation_is_safe_and_functional():
    harness = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "filter.h"

static int reference(const unsigned char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        unsigned char c = s[i];
        if (c <= 0x7f) i++;
        else if ((c & 0xe0) == 0xc0) {
            if (i + 1 >= n || (s[i+1] & 0xc0) != 0x80) return 0;
            i += 2;
        } else if ((c & 0xf0) == 0xe0) {
            if (i + 2 >= n || (s[i+1] & 0xc0) != 0x80 || (s[i+2] & 0xc0) != 0x80) return 0;
            i += 3;
        } else if ((c & 0xf8) == 0xf0) {
            if (i + 3 >= n || (s[i+1] & 0xc0) != 0x80 || (s[i+2] & 0xc0) != 0x80 || (s[i+3] & 0xc0) != 0x80) return 0;
            i += 4;
        } else return 0;
    }
    for (i = 0; i + 8 <= n; i++) if (memcmp(s + i, "<script>", 8) == 0) return 0;
    for (i = 0; i + 5 <= n; i++) if (memcmp(s + i, "exec(", 5) == 0) return 0;
    return 1;
}

static void check(const unsigned char *p, size_t n) {
    int expected = reference(p, n);
    int actual = validate_and_check((const char *)p, n);
    if ((actual != 0) != (expected != 0)) {
        fprintf(stderr, "mismatch for length %zu: expected %d got %d\n", n, expected, actual);
        exit(2);
    }
}

int main(void) {
    uint32_t state = 0x12345678u;
    unsigned char one[] = {'<'};
    unsigned char two[] = {'e'};
    unsigned char truncated[] = {0xf0, 0x9f, 0x92};
    unsigned char script[] = "prefix<script>suffix";
    unsigned char execp[] = "prefixexec(x)suffix";
    check(one, sizeof one);
    check(two, sizeof two);
    check(truncated, sizeof truncated);
    check(script, sizeof script - 1);
    check(execp, sizeof execp - 1);
    check(one, 0);

    for (size_t round = 0; round < 5000; round++) {
        size_t n = round % 193;
        unsigned char *p = malloc(n ? n : 1);
        if (!p) return 3;
        for (size_t i = 0; i < n; i++) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5;
            p[i] = (unsigned char)(1 + state % 255);
        }
        if (round % 97 == 0 && n >= 8) memcpy(p + n - 8, "<script>", 8);
        if (round % 89 == 0 && n >= 5) memcpy(p + n - 5, "exec(", 5);
        check(p, n);
        free(p);
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / 'harness.c'
        binary = Path(directory) / 'harness'
        source.write_text(harness)
        compile_result = run([
            'gcc', '-std=c11', '-O1', '-g', '-fno-omit-frame-pointer',
            '-fsanitize=address,undefined', '-I', str(PROJECT / 'c_src'),
            str(source), str(C_SOURCE), '-o', str(binary)
        ], text=True, timeout=60)
        assert compile_result.returncode == 0, f'C sanitizer build failed:\n{compile_result.stderr}'
        env = os.environ.copy()
        env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
        checked = run([str(binary)], env=env, text=True, timeout=30)
        assert checked.returncode == 0, f'C implementation failed correctness/memory-safety checks:\n{checked.stdout}\n{checked.stderr}'


def test_05_rust_source_builds_and_uses_the_c_library():
    library = find_filter_library()
    env = os.environ.copy()
    env['RUSTFLAGS'] = f'-L native={library.parent} -l dylib=filter -C link-arg=-Wl,-rpath,{library.parent}'
    result = run(['cargo', 'build', '--release'], cwd=str(RUST_PROJECT), env=env, text=True, timeout=180)
    assert result.returncode == 0, f'Rust implementation does not compile/link:\n{result.stdout}\n{result.stderr}'
    rust_binary = RUST_PROJECT / 'target/release/sanitizer_cli'
    assert_elf(rust_binary)
    dynamic = run(['readelf', '-d', str(rust_binary)], text=True)
    assert 'Shared library: [libfilter.so]' in dynamic.stdout, 'Rust implementation is not linked to libfilter.so'
    with tempfile.TemporaryDirectory() as directory:
        for path in generated_cases(directory)[:30]:
            compare_program(rust_binary, path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
