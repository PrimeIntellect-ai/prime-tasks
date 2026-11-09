#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

TESTER = Path('/app/go_waf/waf-tester')
GO_DIR = Path('/app/go_waf')
C_DIR = Path('/app/c_scanner')


def assert_elf(path, expected_type=None):
    data = Path(path).read_bytes()[:20]
    assert len(data) >= 18 and data[:4] == b'\x7fELF', f'{path} is not an ELF artifact'
    endian = '<' if data[5] == 1 else '>'
    elf_type = struct.unpack(endian + 'H', data[16:18])[0]
    if expected_type is not None:
        assert elf_type == expected_type, f'{path} has unexpected ELF type {elf_type}'


def test_waf_tester_built():
    tester_path = '/app/go_waf/waf-tester'
    assert os.path.isfile(tester_path), f'Expected executable at {tester_path} is missing. Did you build the Go project?'
    assert os.access(tester_path, os.X_OK), f'File at {tester_path} is not executable.'
    assert_elf(tester_path)


def check_saved_results(corpus_dir, results_file, classification):
    assert os.path.isfile(results_file), f'Expected results file at {results_file} is missing.'
    with open(results_file, 'r') as f:
        results = json.load(f)
    assert isinstance(results, dict), f'{results_file} must contain a JSON object.'
    expected_files = {f for f in os.listdir(corpus_dir) if f.endswith('.json')}
    missing = [name for name in expected_files if name not in results]
    modified = [name for name in expected_files if name in results and results[name] != classification]
    extra = set(results) - expected_files
    errors = []
    if missing:
        errors.append(f'Missing {len(missing)} files in results: {missing}')
    if modified:
        errors.append(f'{len(modified)} files have the wrong classification: {modified}')
    if extra:
        errors.append(f'Unexpected files in results: {list(extra)}')
    assert not errors, ' | '.join(errors)


def test_clean_corpus_results():
    check_saved_results('/app/corpora/clean/', '/app/clean_results.json', 'CLEAN')


def test_evil_corpus_results():
    check_saved_results('/app/corpora/evil/', '/app/evil_results.json', 'EVIL')


def test_c_library_and_build_are_real():
    lib = C_DIR / 'libscanner.so'
    assert lib.is_file(), 'Expected /app/c_scanner/libscanner.so to exist.'

    # Rebuilding forces the repaired Makefile and scanner source to be usable.
    subprocess.run(
        ['make', '-B', 'libscanner.so'], cwd=C_DIR, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert_elf(lib, 3)  # ET_DYN shared object

    scanner = ctypes.CDLL(str(lib))
    fn = scanner.scan_payload
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_int
    assert fn(b'ordinary request body') == 0
    assert fn(b'prefix DROP TABLE accounts suffix') == 1
    assert fn(b'<script>alert(7)</script>') == 1
    assert fn(b'drop table and <Script> are harmless to this legacy scanner') == 0


def parse_semver(value):
    match = re.fullmatch(
        r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
        r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
        r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?', value
    )
    assert match, f'bad verifier semver fixture: {value}'
    return int(match[1]), int(match[2]), int(match[3]), None if match[4] is None else match[4].split('.')


def semver_cmp(left, right):
    a = parse_semver(left)
    b = parse_semver(right)
    if a[:3] != b[:3]:
        return -1 if a[:3] < b[:3] else 1
    ap, bp = a[3], b[3]
    if ap is None or bp is None:
        return 0 if ap is bp else (1 if ap is None else -1)
    for x, y in zip(ap, bp):
        if x == y:
            continue
        xn, yn = x.isdigit(), y.isdigit()
        if xn and yn:
            return -1 if int(x) < int(y) else 1
        if xn != yn:
            return -1 if xn else 1
        return -1 if x < y else 1
    return (len(ap) > len(bp)) - (len(ap) < len(bp))


def allowed_by_image_rule(version):
    return semver_cmp(version, '1.4.0') >= 0 and semver_cmp(version, '2.0.0-alpha') < 0


def run_dynamic_suite(binary):
    versions = [
        '0.9.9', '1.3.9', '1.4.0-alpha', '1.4.0-0', '1.4.0',
        '1.4.0+build.7', '1.4.1', '1.9.999', '1.99.2-rc.1',
        '2.0.0-0', '2.0.0-alpha', '2.0.0-alpha.1', '2.0.0-beta',
        '2.0.0', '2.1.0', '3.0.0'
    ]
    rng = random.SystemRandom()
    prereleases = [None, '0', 'alpha', 'alpha.1', 'beta', 'rc.2']
    for _ in range(35):
        major = rng.randrange(0, 4)
        minor = rng.randrange(0, 15)
        patch = rng.randrange(0, 30)
        pre = rng.choice(prereleases)
        versions.append(f'{major}.{minor}.{patch}' + (f'-{pre}' if pre else ''))

    with tempfile.TemporaryDirectory(prefix='waf-verifier-') as td:
        corpus = Path(td) / ('corpus-' + secrets.token_hex(6))
        corpus.mkdir()
        expected = {}
        for index, version in enumerate(versions):
            payloads = ['safe-' + secrets.token_hex(5)]
            if allowed_by_image_rule(version) and index % 3 == 0:
                payloads.append('before DROP TABLE audit_log after')
            if allowed_by_image_rule(version) and index % 5 == 0:
                payloads.append('x<script>alert(1)</script>y')
            for payload in payloads:
                filename = secrets.token_hex(8) + '.json'
                (corpus / filename).write_text(json.dumps({'version': version, 'payload': payload}))
                evil = (not allowed_by_image_rule(version)) or ('DROP TABLE' in payload) or ('<script>' in payload)
                expected[filename] = 'EVIL' if evil else 'CLEAN'

        output = Path(td) / ('output-' + secrets.token_hex(6) + '.json')
        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = str(C_DIR) + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        completed = subprocess.run(
            [str(binary), '-dir', str(corpus), '-out', str(output)],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=30
        )
        assert completed.returncode == 0, f'waf-tester failed:\n{completed.stdout}'
        assert output.is_file(), 'waf-tester did not create the requested output file'
        actual = json.loads(output.read_text())
        assert actual == expected, 'waf-tester produced incorrect classifications on generated requests'


def test_current_source_builds_links_scanner_and_handles_unseen_requests():
    config_source = (GO_DIR / 'internal/config/config.go').read_text()
    assert re.search(r'\bMaxPayloadSize\b', config_source), 'Existing MaxPayloadSize configuration property was removed.'

    with tempfile.TemporaryDirectory(prefix='go-build-') as td:
        rebuilt = Path(td) / 'waf-tester'
        env = os.environ.copy()
        env['CGO_ENABLED'] = '1'
        completed = subprocess.run(
            ['go', 'build', '-o', str(rebuilt), '.'], cwd=GO_DIR, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
        )
        assert completed.returncode == 0, f'Go source does not build (the import cycle may remain):\n{completed.stdout}'
        assert_elf(rebuilt)
        dynamic = subprocess.run(
            ['readelf', '-d', str(rebuilt)], check=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15
        ).stdout
        assert 'libscanner.so' in dynamic, 'Rebuilt Go CLI is not dynamically linked to libscanner.so.'
        run_dynamic_suite(rebuilt)

    # Also execute the specifically requested submitted artifact rather than only trusting its presence.
    run_dynamic_suite(TESTER)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
