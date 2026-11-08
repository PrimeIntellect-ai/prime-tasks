#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/waf_project')
PARSER = PROJECT / 'src/parser.c'
MOCK = PROJECT / 'tests/mock_request.c'
MAIN = PROJECT / 'tests/main.c'
HEADER = PROJECT / 'include/waf.h'
PIPELINE = PROJECT / 'ci_pipeline.sh'
BINARY = PROJECT / 'tests/run_tests'
TARBALL = Path('/home/user/deployment.tar.gz')


def run(cmd, *, cwd=PROJECT, env=None, timeout=30):
    return subprocess.run(cmd, cwd=str(cwd), env=env, capture_output=True,
                          text=True, timeout=timeout)


def asan_env():
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
    return env


def test_mock_request_c_exists_and_content():
    assert MOCK.is_file(), f'File {MOCK} does not exist'
    content = MOCK.read_text()
    assert '"POST"' in content, f'{MOCK} missing POST method literal'
    assert '"/login"' in content, f'{MOCK} missing /login uri literal'
    assert '"X-Malicious"' in content, f'{MOCK} missing X-Malicious header_name literal'
    assert '"<script>alert(1)</script>"' in content, f'{MOCK} missing XSS payload literal'

    harness = Path('/tmp/check_mock.c')
    harness.write_text(r'''
#include "waf.h"
#include <string.h>
extern void setup_mock_request(HttpRequest *req);
int main(void) {
    HttpRequest req = {(char*)1, (char*)1, (char*)1, (char*)1};
    setup_mock_request(&req);
    if (!req.method || strcmp(req.method, "POST")) return 1;
    if (!req.uri || strcmp(req.uri, "/login")) return 2;
    if (!req.header_name || strcmp(req.header_name, "X-Malicious")) return 3;
    if (!req.header_value || strcmp(req.header_value, "<script>alert(1)</script>")) return 4;
    return 0;
}
''')
    output = Path('/tmp/check_mock')
    result = run(['/usr/bin/gcc', '-fsanitize=address', '-g',
                  str(MOCK), str(harness), '-o', str(output), '-I./include'])
    assert result.returncode == 0, result.stderr
    result = run([str(output)], env=asan_env())
    assert result.returncode == 0, result.stderr


def test_parser_c_patched_fixed_and_behavioral():
    assert PARSER.is_file(), f'File {PARSER} does not exist'
    content = PARSER.read_text()
    assert 'strdup' in content and 'temp_val' in content, f'{PARSER} does not appear to have the patch applied'
    assert 'free(' in content, f'{PARSER} does not contain a call to free()'

    harness = Path('/tmp/check_parser.c')
    harness.write_text(r'''
#include "waf.h"
#include <stdlib.h>
#include <string.h>

static int dup_calls;
static int free_calls;
void *__real_free;

char *__wrap_strdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (!p) return NULL;
    memcpy(p, s, n);
    dup_calls++;
    return p;
}
void __real_free(void *p);
void __wrap_free(void *p) {
    if (p) free_calls++;
    __real_free(p);
}

int main(void) {
    HttpRequest blocked = {"POST", "/login", "X-Malicious", "<script>alert(1)</script>"};
    HttpRequest allowed = {"GET", "/", "Accept", "text/plain"};
    if (analyze_request(&blocked) != 1) return 10;
    if (dup_calls != 1 || free_calls != 1) return 11;
    if (analyze_request(&allowed) != 0) return 12;
    if (dup_calls != 2 || free_calls != 2) return 13;
    return 0;
}
''')
    output = Path('/tmp/check_parser')
    result = run(['/usr/bin/gcc', '-fsanitize=address', '-g', str(PARSER),
                  str(harness), '-o', str(output), '-I./include',
                  '-Wl,--wrap=strdup', '-Wl,--wrap=free'])
    assert result.returncode == 0, result.stderr
    result = run([str(output)], env=asan_env())
    assert result.returncode == 0, f'Parser behavior/allocation test failed: {result.stderr}'


def test_ci_pipeline_build_test_and_package():
    assert PIPELINE.is_file(), f'File {PIPELINE} does not exist'
    assert os.access(PIPELINE, os.X_OK), f'File {PIPELINE} is not executable'

    original_parser = PARSER.read_bytes()
    original_main = MAIN.read_bytes()
    original_mock = MOCK.read_bytes()
    original_header = HEADER.read_bytes()

    # A real pipeline must compile parser.c rather than reuse a fabricated binary.
    try:
        PARSER.write_bytes(original_parser + b'\n#error verifier_forced_compile_failure\n')
        BINARY.unlink(missing_ok=True)
        TARBALL.unlink(missing_ok=True)
        result = run([str(PIPELINE)], env=asan_env())
        assert result.returncode != 0, 'CI pipeline ignored a compiler failure'
        assert not BINARY.exists(), 'CI pipeline produced/reused run_tests despite compiler failure'
        assert not TARBALL.exists(), 'CI pipeline packaged despite compiler failure'
    finally:
        PARSER.write_bytes(original_parser)
        BINARY.unlink(missing_ok=True)
        TARBALL.unlink(missing_ok=True)

    # It must execute the newly built test binary and stop before packaging on failure.
    try:
        MAIN.write_text('int main(void) { return 37; }\n')
        result = run([str(PIPELINE)], env=asan_env())
        assert result.returncode != 0, 'CI pipeline did not propagate a test failure'
        assert not TARBALL.exists(), 'CI pipeline packaged after a failing test'
    finally:
        MAIN.write_bytes(original_main)
        BINARY.unlink(missing_ok=True)
        TARBALL.unlink(missing_ok=True)

    result = run([str(PIPELINE)], env=asan_env())
    assert result.returncode == 0, f'CI pipeline failed: stdout={result.stdout}\nstderr={result.stderr}'

    assert PARSER.read_bytes() == original_parser
    assert MAIN.read_bytes() == original_main
    assert MOCK.read_bytes() == original_mock
    assert HEADER.read_bytes() == original_header

    assert BINARY.is_file(), f'Binary {BINARY} does not exist'
    assert os.access(BINARY, os.X_OK), f'Binary {BINARY} is not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'tests/run_tests is not an ELF binary'

    linked = run(['/usr/bin/ldd', str(BINARY)], cwd=PROJECT)
    assert linked.returncode == 0, linked.stderr
    assert 'libasan' in linked.stdout, 'tests/run_tests was not linked with AddressSanitizer'

    result = run([str(BINARY)], env=asan_env())
    assert result.returncode == 0, f'Binary failed or ASan detected a leak: {result.stderr}'
    assert 'Test passed: Request blocked.' in result.stdout

    # Independently perform the required build from the submitted sources.
    independent = Path('/tmp/independent_run_tests')
    result = run(['/usr/bin/gcc', '-fsanitize=address', '-g',
                  'src/parser.c', 'tests/mock_request.c', 'tests/main.c',
                  '-o', str(independent), '-I./include'])
    assert result.returncode == 0, result.stderr
    result = run([str(independent)], env=asan_env())
    assert result.returncode == 0, f'Independent ASan build failed: {result.stderr}'

    assert TARBALL.is_file(), f'Tarball {TARBALL} does not exist'
    expected_files = set()
    expected_dirs = {'src', 'include'}
    for top in ('src', 'include'):
        root = PROJECT / top
        for current, dirs, files in os.walk(root):
            rel_dir = Path(current).relative_to(PROJECT).as_posix()
            expected_dirs.add(rel_dir)
            for name in files:
                expected_files.add((Path(rel_dir) / name).as_posix())

    with tarfile.open(TARBALL, 'r:gz') as tar:
        members = tar.getmembers()
        assert members, 'Deployment archive is empty'
        seen_files = set()
        seen_dirs = set()
        for member in members:
            name = member.name.rstrip('/')
            while name.startswith('./'):
                name = name[2:]
            assert name and not name.startswith('/') and '..' not in Path(name).parts
            assert Path(name).parts[0] in {'src', 'include'}, f'Unexpected archive member: {member.name}'
            assert member.isfile() or member.isdir(), f'Archive contains non-file member: {member.name}'
            if member.isdir():
                seen_dirs.add(name)
            else:
                assert name not in seen_files, f'Duplicate archive member: {name}'
                seen_files.add(name)
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == (PROJECT / name).read_bytes(), f'Packaged {name} differs from repository'

        assert seen_files == expected_files, f'Archive files differ: expected {expected_files}, got {seen_files}'
        assert seen_dirs <= expected_dirs, f'Unexpected archive directories: {seen_dirs - expected_dirs}'
        assert 'src/parser.c' in seen_files
        assert 'include/waf.h' in seen_files

        parser_member = next(m for m in members if m.name.rstrip('/').lstrip('./') == 'src/parser.c')
        packaged_parser = tar.extractfile(parser_member).read().decode('utf-8', errors='ignore')
        assert 'free(' in packaged_parser, 'free() not found in packaged parser.c'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
