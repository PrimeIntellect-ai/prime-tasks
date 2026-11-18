#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import ctypes
import json
import os
import shutil
import struct
import subprocess
import tempfile
import time
from pathlib import Path

APP = Path('/app')


def malicious(data):
    return b'<script>' in data or b'DROP TABLE' in data


def fnv1a(data):
    h = 1469598103934665603
    for b in data:
        h ^= b
        h = (h * 1099511628211) & 0xffffffffffffffff
    return h


def check_library(path):
    class ScanResult(ctypes.Structure):
        _fields_ = [
            ('is_safe', ctypes.c_int),
            ('threat_score', ctypes.c_double),
            ('file_hash', ctypes.c_char * 32),
        ]

    assert ctypes.sizeof(ScanResult) == 48
    assert ScanResult.is_safe.offset == 0
    assert ScanResult.threat_score.offset == 8
    assert ScanResult.file_hash.offset == 16

    lib = ctypes.CDLL(str(path))
    scan = lib.scan_content
    scan.argtypes = [ctypes.c_void_p, ctypes.c_int]
    scan.restype = ScanResult

    cases = [
        b'', b'ordinary content', b'<script>', b'x<script>y',
        b'DROP TABLE', b'SELECT DROP TABLE users',
        b'<scrip', b'drop table', b'A\x00<script>B',
        b'A\x00DROP TABLE B', b'<scriptX>', b'DROP  TABLE',
    ]
    for i in range(80):
        prefix = bytes(((i * 17 + j * 29) & 255) for j in range(i % 31))
        suffix = bytes(((i * 11 + j * 7) & 255) for j in range((i * 3) % 37))
        token = (b'<script>' if i % 3 == 0 else
                 b'DROP TABLE' if i % 3 == 1 else b'harmless')
        cases.append(prefix + token + suffix)

    for data in cases:
        buf = ctypes.create_string_buffer(data, len(data) + 1)
        result = scan(ctypes.cast(buf, ctypes.c_void_p), len(data))
        expected_safe = not malicious(data)
        assert result.is_safe == int(expected_safe), \
            f'{path} misclassified {data!r}'
        expected_score = 0.0 if expected_safe else 0.99
        assert abs(result.threat_score - expected_score) < 1e-12, \
            f'{path} returned wrong threat_score for {data!r}'
        assert result.file_hash == b'', f'{path} did not return an empty file_hash'


def test_speedup_and_correctness():
    # Restore files exactly as the original verifier did.
    for d in [APP / 'safe', APP / 'quarantine']:
        d.mkdir(exist_ok=True)
        for p in list(d.iterdir()):
            target = APP / 'uploads' / p.name
            assert not target.exists(), f'Duplicate upload name while restoring: {p.name}'
            shutil.move(str(p), str(target))

    uploads = APP / 'uploads'
    upload_files = sorted(p for p in uploads.iterdir() if p.is_file())
    uploads_count = len(os.listdir(uploads))
    assert uploads_count == 20000, \
        f'Expected 20000 files in /app/uploads, but found {uploads_count}.'
    assert len(upload_files) == 20000, 'All upload entries must be regular files.'

    assert (APP / 'slow_organizer.py').is_file(), '/app/slow_organizer.py is missing.'
    assert (APP / 'fast_organizer.py').is_file(), '/app/fast_organizer.py is missing.'
    assert (APP / 'scanner.c').is_file(), '/app/scanner.c is missing.'
    assert (APP / 'libscanner.so').is_file(), '/app/libscanner.so is missing.'

    fast_source = (APP / 'fast_organizer.py').read_text(errors='replace')
    for marker in ('ctypes', 'CDLL', 'Structure', 'scan_content', 'libscanner.so'):
        assert marker in fast_source, f'fast_organizer.py is missing required ctypes element: {marker}'

    lib_path = APP / 'libscanner.so'
    assert lib_path.read_bytes()[:4] == b'\x7fELF', 'libscanner.so is not an ELF shared library.'
    symbols = subprocess.run(
        ['nm', '-D', str(lib_path)], check=True, capture_output=True, text=True
    ).stdout
    assert 'scan_content' in symbols, 'libscanner.so does not export scan_content.'

    # Verify the exact struct layout declared by scanner.c.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        abi_c = td / 'abi.c'
        abi_c.write_text(r'''
#include <stddef.h>
#include <stdio.h>
#define main scanner_submission_main
#include "/app/scanner.c"
#undef main
int main(void) {
    printf("%zu %zu %zu %zu %zu\n",
        sizeof(struct ScanResult),
        offsetof(struct ScanResult, is_safe),
        offsetof(struct ScanResult, threat_score),
        offsetof(struct ScanResult, file_hash),
        sizeof(((struct ScanResult *)0)->file_hash));
    return 0;
}
''')
        abi_exe = td / 'abi'
        subprocess.run(['gcc', '-O3', str(abi_c), '-o', str(abi_exe)], check=True)
        layout = subprocess.run([str(abi_exe)], check=True, capture_output=True, text=True).stdout.strip()
        assert layout == '48 0 8 16 32', f'Incorrect ScanResult ABI: {layout}'

        # Compile the submitted C source itself with the required optimization and test it.
        rebuilt = td / 'rebuilt_scanner.so'
        subprocess.run(
            ['gcc', '-O3', '-shared', '-fPIC', '/app/scanner.c', '-o', str(rebuilt)],
            check=True,
        )
        check_library(rebuilt)

    # Also test the submitted shared object directly on independently derived cases.
    check_library(lib_path)

    expected_data = {p.name: p.read_bytes() for p in upload_files}
    expected_safe = {name for name, data in expected_data.items() if not malicious(data)}
    expected_quarantine = set(expected_data) - expected_safe
    expected_hashes = collections.Counter(fnv1a(data) for data in expected_data.values())

    # Run and retain the original baseline timing and aggregate assertions.
    start_slow = time.perf_counter()
    subprocess.run(['python3', '/app/slow_organizer.py'], check=True, cwd='/app', timeout=180)
    slow_duration = time.perf_counter() - start_slow
    assert (APP / 'slow_results.json').is_file(), '/app/slow_results.json was not generated.'
    with open(APP / 'slow_results.json') as f:
        slow_res = json.load(f)

    # Remove the baseline answer before the submitted script runs.
    os.unlink(APP / 'slow_results.json')
    for p in (APP / 'results.json', Path('/tmp/scanner_call_audit.bin')):
        if p.exists():
            p.unlink()

    # Replace libscanner.so temporarily with an ABI-compatible auditing implementation.
    # This proves the Python wrapper actually loads and invokes the required library once
    # for each upload, rather than producing counts or moves without using ctypes.
    original_lib = lib_path.read_bytes()
    original_mode = lib_path.stat().st_mode
    spy_source = Path('/tmp/scanner_audit.c')
    spy_lib = Path('/tmp/libscanner_audit.so')
    spy_source.write_text(r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ScanResult {
    int is_safe;
    double threat_score;
    char file_hash[32];
};

static uint64_t hashes[1000000];
static uint64_t call_count = 0;

static int contains(const unsigned char *s, int n, const char *needle, int m) {
    if (!s || n < m) return 0;
    for (int i = 0; i <= n - m; ++i)
        if (memcmp(s + i, needle, (size_t)m) == 0) return 1;
    return 0;
}

struct ScanResult scan_content(const char *content, int length) {
    struct ScanResult r;
    memset(&r, 0, sizeof(r));
    uint64_t h = UINT64_C(1469598103934665603);
    if (length < 0) length = 0;
    for (int i = 0; i < length; ++i) {
        h ^= (unsigned char)content[i];
        h *= UINT64_C(1099511628211);
    }
    if (call_count < 1000000) hashes[call_count] = h;
    ++call_count;
    int bad = contains((const unsigned char *)content, length, "<script>", 8) ||
              contains((const unsigned char *)content, length, "DROP TABLE", 10);
    r.is_safe = bad ? 0 : 1;
    r.threat_score = bad ? 0.99 : 0.0;
    return r;
}

__attribute__((destructor)) static void write_audit(void) {
    const char *path = getenv("SCAN_AUDIT_PATH");
    if (!path) return;
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fwrite(&call_count, sizeof(call_count), 1, f);
    uint64_t n = call_count < 1000000 ? call_count : 1000000;
    fwrite(hashes, sizeof(uint64_t), (size_t)n, f);
    fclose(f);
}
''')
    subprocess.run(['gcc', '-O3', '-shared', '-fPIC', str(spy_source), '-o', str(spy_lib)], check=True)
    shutil.copyfile(spy_lib, lib_path)

    env = os.environ.copy()
    env['SCAN_AUDIT_PATH'] = '/tmp/scanner_call_audit.bin'
    try:
        start_fast = time.perf_counter()
        subprocess.run(
            ['python3', '/app/fast_organizer.py'], check=True, cwd='/app', env=env, timeout=180
        )
        fast_duration = time.perf_counter() - start_fast
    finally:
        lib_path.write_bytes(original_lib)
        os.chmod(lib_path, original_mode)

    # Restore the baseline result only after fast_organizer has exited, preserving the
    # original verifier's checks without exposing the aggregate oracle during execution.
    with open(APP / 'slow_results.json', 'w') as f:
        json.dump(slow_res, f)

    assert Path('/tmp/scanner_call_audit.bin').is_file(), \
        'fast_organizer.py did not load and invoke /app/libscanner.so.'
    audit = Path('/tmp/scanner_call_audit.bin').read_bytes()
    assert len(audit) >= 8, 'Invalid scanner call audit.'
    call_count = struct.unpack_from('<Q', audit, 0)[0]
    assert call_count == 20000, f'Expected exactly 20000 scan_content calls, found {call_count}.'
    assert len(audit) == 8 + 8 * call_count, 'Incomplete scanner call audit.'
    actual_hashes = collections.Counter(struct.unpack_from(f'<{call_count}Q', audit, 8))
    assert actual_hashes == expected_hashes, \
        'scan_content was not called with the contents of every uploaded file.'

    speedup = slow_duration / fast_duration

    assert (APP / 'slow_results.json').is_file(), '/app/slow_results.json was not generated.'
    assert (APP / 'results.json').is_file(), '/app/results.json was not generated.'
    with open(APP / 'slow_results.json') as f:
        slow_res_after = json.load(f)
    with open(APP / 'results.json') as f:
        fast_res = json.load(f)

    assert slow_res_after['safe_count'] == fast_res['safe_count'], \
        f"Safe counts do not match. Slow: {slow_res_after['safe_count']}, Fast: {fast_res['safe_count']}"
    assert slow_res_after['quarantine_count'] == fast_res['quarantine_count'], \
        f"Quarantine counts do not match. Slow: {slow_res_after['quarantine_count']}, Fast: {fast_res['quarantine_count']}"
    assert fast_res['safe_count'] == len(expected_safe)
    assert fast_res['quarantine_count'] == len(expected_quarantine)

    safe_names = set(os.listdir(APP / 'safe'))
    quarantine_names = set(os.listdir(APP / 'quarantine'))
    assert safe_names == expected_safe, 'One or more individual files were placed in the wrong safe directory.'
    assert quarantine_names == expected_quarantine, \
        'One or more individual files were placed in the wrong quarantine directory.'
    assert not os.listdir(uploads), 'Processed files remain in /app/uploads.'

    # Confirm files were moved without changing their contents.
    for name in expected_safe:
        assert (APP / 'safe' / name).read_bytes() == expected_data[name]
    for name in expected_quarantine:
        assert (APP / 'quarantine' / name).read_bytes() == expected_data[name]

    safe_dir_count = len(os.listdir(APP / 'safe'))
    quarantine_dir_count = len(os.listdir(APP / 'quarantine'))
    assert safe_dir_count == fast_res['safe_count'], \
        f"Files were not moved to /app/safe correctly. Expected {fast_res['safe_count']}, found {safe_dir_count}."
    assert quarantine_dir_count == fast_res['quarantine_count'], \
        f"Files were not moved to /app/quarantine correctly. Expected {fast_res['quarantine_count']}, found {quarantine_dir_count}."

    assert speedup >= 5.0, \
        f'Speedup was {speedup:.2f}x, which is less than the required 5.0x threshold.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
