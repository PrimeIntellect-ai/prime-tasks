#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import pathlib
import subprocess
import tempfile
import uuid

import pytest

ROOT = pathlib.Path('/home/user/bashwaf')
LIB = ROOT / 'libeval.so'
WAF = ROOT / 'waf.sh'
WRAPPER = ROOT / 'ffi_wrapper.py'
EVALUATOR = ROOT / 'evaluator.go'
RESULTS = ROOT / 'scan_results.log'
ORIGINAL_EXPECTED = 'req_001: CLEAN\nreq_002: MALICIOUS\nreq_003: ERROR'


def test_libeval_so_exists():
    lib_path = '/home/user/bashwaf/libeval.so'
    assert os.path.isfile(lib_path), f'Expected shared library {lib_path} to exist, but it is missing.'


def test_scan_results_content():
    results_path = '/home/user/bashwaf/scan_results.log'
    assert os.path.isfile(results_path), f'Expected {results_path} to exist.'

    with open(results_path, 'r') as f:
        content = f.read().strip()

    expected_content = 'req_001: CLEAN\nreq_002: MALICIOUS\nreq_003: ERROR'
    assert content == expected_content, (
        f'Contents of {results_path} do not match the expected output.\n'
        f'Expected:\n{expected_content}\nGot:\n{content}'
    )


def test_waf_sh_initialization_checks_retained():
    waf_path = '/home/user/bashwaf/waf.sh'
    assert os.path.isfile(waf_path), f'Expected {waf_path} to exist.'

    with open(waf_path, 'r') as f:
        content = f.read()

    assert 'Starting BashWAF...' in content, "Original initialization check 'Starting BashWAF...' is missing from waf.sh"
    assert 'Initializing engine...' in content, "Original initialization check 'Initializing engine...' is missing from waf.sh"


def classification(payload):
    if 'MALICIOUS' in payload:
        return 1
    if 'INVALID' in payload:
        return 2
    return 0


def probe_library(path, payloads):
    probe = r'''
import ctypes, json, sys
from concurrent.futures import ThreadPoolExecutor
lib = ctypes.CDLL(sys.argv[1])
fn = lib.EvaluatePayload
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_int
payloads = json.loads(sys.argv[2])
def call(value):
    return int(fn(value.encode('utf-8')))
with ThreadPoolExecutor(max_workers=8) as pool:
    print(json.dumps(list(pool.map(call, payloads))))
'''
    proc = subprocess.run(
        ['python3', '-c', probe, str(path), json.dumps(payloads)],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout) == [classification(p) for p in payloads]


def test_go_source_builds_and_both_libraries_execute_without_deadlock(tmp_path):
    assert EVALUATOR.is_file(), 'evaluator.go from the PR is missing'
    assert WRAPPER.is_file(), 'ffi_wrapper.py from the PR is missing'
    assert LIB.read_bytes()[:4] == b'\x7fELF', 'libeval.so is not an ELF shared library'

    metadata = subprocess.run(
        ['go', 'version', '-m', str(LIB)], text=True, capture_output=True, timeout=10
    )
    assert metadata.returncode == 0 and 'go1.' in metadata.stdout, (
        'libeval.so does not contain Go build metadata and was not built as the required Go library'
    )

    rebuilt = tmp_path / 'libeval_rebuilt.so'
    build = subprocess.run(
        ['go', 'build', '-buildmode=c-shared', '-o', str(rebuilt), str(EVALUATOR)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=90,
    )
    assert build.returncode == 0, f'evaluator.go does not build as a C-shared library:\n{build.stderr}'

    nonce = uuid.uuid4().hex
    payloads = []
    for i in range(8):
        payloads.extend([
            f'PUSH {i} PUSH {i + 1} ADD POP {nonce}',
            f'PUSH {i} MALICIOUS_{nonce}_{i}',
            f'INVALID_{nonce}_{i} OPCODE',
        ])
    probe_library(LIB, payloads)
    probe_library(rebuilt, payloads)


def test_ffi_wrapper_propagates_derived_codes():
    nonce = uuid.uuid4().hex
    cases = [
        (f'PUSH 17 PUSH 25 ADD POP {nonce}', 0),
        (f'PUSH 9 MALICIOUS_SYSCALL_{nonce}', 1),
        (f'INVALID_{nonce} OPCODE', 2),
    ]
    for payload, expected in cases:
        proc = subprocess.run(
            ['python3', str(WRAPPER), payload],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert proc.returncode == expected, (
            f'ffi_wrapper.py returned {proc.returncode} for {payload!r}; expected {expected}. '
            f'stderr: {proc.stderr}'
        )


def test_waf_executes_wrapper_and_maps_dynamic_return_codes(tmp_path):
    assert os.access(WAF, os.X_OK), 'waf.sh must be executable so it can be run as ./waf.sh'

    missing_arg = subprocess.run(
        [str(WAF)], cwd=ROOT, text=True, capture_output=True, timeout=10
    )
    assert missing_arg.returncode == 1
    assert 'Starting BashWAF...' in missing_arg.stdout
    assert 'Usage: ./waf.sh <payload_file>' in missing_arg.stdout

    nonce = uuid.uuid4().hex
    rows = [
        (f'clean_{nonce}', f'PUSH 41 PUSH 1 ADD POP {nonce}', 'CLEAN'),
        (f'bad_{nonce}', f'PUSH 99 MALICIOUS_SYSCALL_{nonce}', 'MALICIOUS'),
        (f'error_{nonce}', f'INVALID_{nonce} OPCODE', 'ERROR'),
        (f'clean2_{nonce}', f'PUSH 3 POP {nonce}', 'CLEAN'),
    ]
    payload_file = tmp_path / 'dynamic_payloads.txt'
    payload_file.write_text(''.join(f'{ident}|{payload}\n' for ident, payload, _ in rows))
    RESULTS.write_text('sentinel: MUST_BE_TRUNCATED\n')

    proc = subprocess.run(
        [str(WAF), str(payload_file)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert proc.returncode == 0, proc.stderr
    assert 'Starting BashWAF...' in proc.stdout
    assert 'Initializing engine...' in proc.stdout
    expected = '\n'.join(f'{ident}: {status}' for ident, _, status in rows)
    assert RESULTS.read_text().strip() == expected

    # Restore and independently re-check the required final result using the shipped input.
    restore = subprocess.run(
        [str(WAF), str(ROOT / 'payloads.txt')],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert restore.returncode == 0, restore.stderr
    assert RESULTS.read_text().strip() == ORIGINAL_EXPECTED
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
