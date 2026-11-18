#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

ROOT = Path('/home/user/analyzer')
BINARY = ROOT / 'loganalyzer'


def test_alerts_sorted_txt():
    path = ROOT / 'alerts_sorted.txt'
    assert path.is_file(), f'File {path} does not exist.'

    with path.open() as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        '/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaUNIONSELECT',
        "/login.php?user=admin'UNION+SELECT+1,2,3--",
        '/search?q=UNION+SELECT+password+FROM+users',
    ]
    assert lines == expected_lines, f'Contents of {path} do not match the expected sorted, deduplicated output.'


def test_parser_c_fixed():
    path = ROOT / 'parser.c'
    assert path.is_file(), f'File {path} does not exist.'
    content = path.read_text()

    unsafe_sscanf_pattern = r'sscanf\s*\([^,]+,\s*"[^"]*%s[^"]*"\s*,'
    assert not re.search(unsafe_sscanf_pattern, content), "parser.c still contains an unbounded sscanf with '%s'."

    # Compile the submitted parser with AddressSanitizer and exercise a URI far
    # larger than the original 64-byte stack buffer, while still fitting the
    # 1024-byte output buffer used by the Go program.
    harness = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"

int main(void) {
    char uri[901];
    char req[930];
    char out[1024];
    memset(uri, 'a', 900);
    uri[0] = '/';
    memcpy(uri + 20, "UNIONSELECT", 11);
    uri[900] = '\0';
    snprintf(req, sizeof(req), "GET %s HTTP/1.1", uri);
    memset(out, 0, sizeof(out));
    parse_uri(req, out);
    if (strcmp(uri, out) != 0) {
        fprintf(stderr, "long URI was not parsed intact\n");
        return 2;
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = Path(td) / 'parser_harness.c'
        executable = Path(td) / 'parser_harness'
        harness_path.write_text(harness)
        build = subprocess.run(
            ['gcc', '-fsanitize=address', '-fno-omit-frame-pointer', '-g',
             '-I', str(ROOT), str(harness_path), str(path), '-o', str(executable)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30,
        )
        assert build.returncode == 0, f'parser.c failed to compile with the harness:\n{build.stderr}'
        run = subprocess.run(
            [str(executable)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15,
            env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0:halt_on_error=1'},
        )
        assert run.returncode == 0, f'parser failed the long-URI memory-safety test:\n{run.stderr}'


def test_main_go_fixed():
    path = ROOT / 'main.go'
    assert path.is_file(), f'File {path} does not exist.'
    content = path.read_text()

    has_mutex = 'Mutex' in content and '.Lock()' in content and '.Unlock()' in content
    has_channel = 'chan ' in content and '<-' in content
    has_sync_map = 'sync.Map' in content
    assert has_mutex or has_channel or has_sync_map, 'main.go does not appear to use synchronization (Mutex, Channel, or sync.Map) to fix the data race.'


def test_module_and_build_with_race_detector(tmp_path):
    gomod = ROOT / 'go.mod'
    assert gomod.is_file(), 'go.mod does not exist.'
    assert re.search(r'(?m)^\s*module\s+security/loganalyzer\s*$', gomod.read_text()), \
        'go.mod does not declare module security/loganalyzer.'

    race_binary = tmp_path / 'loganalyzer-race'
    build = subprocess.run(
        ['go', 'build', '-race', '-o', str(race_binary), '.'], cwd=ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120,
        env={**os.environ, 'CGO_ENABLED': '1'},
    )
    assert build.returncode == 0, f'The submitted project does not build with the race detector:\n{build.stderr}'
    exercise_analyzer(race_binary)


def exercise_analyzer(binary):
    nonce = uuid.uuid4().hex
    malicious = [f'/{nonce}/item/{i}?q=UNION+SELECT+{i}' for i in range(700)]
    long_uri = '/' + nonce + '/UNIONSELECT/' + ('x' * 820)
    malicious.append(long_uri)
    benign = [f'/{nonce}/benign/{i}' for i in range(180)]

    requests = []
    for uri in malicious + benign:
        requests.append(f'GET {uri} HTTP/1.1')

    # Interleave the lines deterministically to create sustained concurrent appends.
    requests = requests[::2] + requests[1::2]
    with tempfile.TemporaryDirectory() as td:
        Path(td, 'requests.log').write_text('\n'.join(requests) + '\n')
        run = subprocess.run(
            [str(binary)], cwd=td, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=45,
        )

    assert run.returncode == 0, f'analyzer crashed or failed on adversarial input:\n{run.stderr}'
    assert 'WARNING: DATA RACE' not in run.stderr, f'Go race detector found a concurrency bug:\n{run.stderr}'
    actual = [line.strip() for line in run.stdout.splitlines() if line.strip()]
    assert sorted(actual) == sorted(malicious), \
        'analyzer output was incomplete, duplicated, corrupted, or incorrect on generated inputs'


def test_binary_exists_and_runs():
    assert BINARY.is_file(), f'Compiled binary {BINARY} does not exist. Did you build the Go project?'
    assert os.access(BINARY, os.X_OK), f'File {BINARY} is not executable.'
    with BINARY.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'loganalyzer is not a compiled ELF binary.'
    exercise_analyzer(BINARY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
