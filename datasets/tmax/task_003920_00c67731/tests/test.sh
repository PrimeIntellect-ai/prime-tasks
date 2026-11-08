#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_submission.py
import hashlib
import os
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

import pytest

BASE = Path('/home/user/project_data')
RAW = BASE / 'raw'
PROCESSED = BASE / 'processed'
LOG = BASE / 'process.log'
MANIFEST = BASE / 'manifest.txt'


def strip_go_comments(text):
    out = []
    i = 0
    state = 'code'
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ''
        if state == 'code':
            if c == '/' and n == '/':
                state = 'line'
                out.extend('  ')
                i += 2
                continue
            if c == '/' and n == '*':
                state = 'block'
                out.extend('  ')
                i += 2
                continue
            if c == '"':
                state = 'string'
            elif c == '`':
                state = 'raw'
            elif c == "'":
                state = 'rune'
            out.append(c)
            i += 1
        elif state == 'line':
            if c == '\n':
                state = 'code'
                out.append(c)
            else:
                out.append(' ')
            i += 1
        elif state == 'block':
            if c == '*' and n == '/':
                state = 'code'
                out.extend('  ')
                i += 2
            else:
                out.append('\n' if c == '\n' else ' ')
                i += 1
        elif state in ('string', 'rune'):
            out.append(c)
            if c == '\\' and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
            else:
                if (state == 'string' and c == '"') or (state == 'rune' and c == "'"):
                    state = 'code'
                i += 1
        else:  # raw string
            out.append(c)
            if c == '`':
                state = 'code'
            i += 1
    return ''.join(out)


def candidate_directories():
    roots = [Path('/home/user'), Path('/workspace'), Path('/root')]
    found = {}
    skipped = {'.git', '.cache', 'go', 'pkg', 'vendor', 'node_modules', 'processed', 'raw'}
    for root in roots:
        if not root.exists():
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in skipped]
            go_files = [f for f in files if f.endswith('.go') and not f.endswith('_test.go')]
            if not go_files:
                continue
            paths = [Path(current) / f for f in go_files]
            text = '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in paths)
            if re.search(r'\bpackage\s+main\b', strip_go_comments(text)):
                found[Path(current)] = (paths, text)
    return found


def feature_score(text):
    code = strip_go_comments(text)
    checks = [
        re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_(])|\.\s*Go\s*\(', code),
        re.search(r'\.\s*(?:Flock|FcntlFlock)\s*\(', code),
        re.search(r'\.\s*Rename\s*\(', code),
        re.search(r'\.\s*(?:CreateTemp|TempFile)\s*\(', code) or '.tmp' in code,
        re.search(r'\bWaitGroup\b|\.\s*Wait\s*\(', code),
    ]
    return sum(bool(x) for x in checks)


def build_submission():
    candidates = candidate_directories()
    assert candidates, 'No Go source containing package main was found.'
    errors = []
    ordered = sorted(candidates.items(), key=lambda item: feature_score(item[1][1]), reverse=True)
    for directory, (paths, text) in ordered:
        binary = Path('/tmp/submission_program')
        try:
            binary.unlink(missing_ok=True)
            attempts = [
                ['go', 'build', '-o', str(binary), '.'],
                ['go', 'build', '-o', str(binary)] + [str(p) for p in paths],
            ]
            built = False
            last = ''
            for cmd in attempts:
                result = subprocess.run(cmd, cwd=directory, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        timeout=90)
                last = result.stdout
                if result.returncode == 0 and binary.is_file():
                    built = True
                    break
            if built:
                return binary, directory, text
            errors.append(f'{directory}: {last}')
        except (subprocess.TimeoutExpired, OSError) as exc:
            errors.append(f'{directory}: {exc}')
    pytest.fail('Could not compile the submitted Go program:\n' + '\n'.join(errors))


def rle_latin1(data):
    text = data.decode('iso-8859-1')
    out = []
    i = 0
    while i < len(text):
        j = i + 1
        while j < len(text) and text[j] == text[i]:
            j += 1
        count = j - i
        if count >= 3:
            out.append(text[i] + '*' + str(count))
        else:
            out.append(text[i] * count)
        i = j
    return ''.join(out).encode('utf-8')


def test_go_program_and_outputs():
    binary, source_dir, source = build_submission()
    code = strip_go_comments(source)

    # Keep the behavioral checks and also require source constructs implementing
    # the explicitly requested concurrency, synchronization, and atomic writes.
    assert re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_(])|\.\s*Go\s*\(', code), \
        'The Go source does not launch work in goroutines.'
    assert re.search(r'\.\s*(?:Flock|FcntlFlock)\s*\(', code), \
        'The Go source does not use OS-level file locking.'
    assert re.search(r'\.\s*Rename\s*\(', code), \
        'The Go source does not atomically rename temporary output files.'
    assert re.search(r'\.\s*(?:CreateTemp|TempFile)\s*\(', code) or '.tmp' in code, \
        'The Go source does not create or name temporary output files.'
    assert re.search(r'\bWaitGroup\b|\.\s*Wait\s*\(', code), \
        'The Go source does not wait for concurrent processing to finish.'

    # Add unpredictable inputs so pre-created fixed artifacts cannot pass.
    for i in range(8):
        body = bytearray()
        seed = os.urandom(32)
        for j in range(5000):
            b = seed[j % len(seed)]
            body.extend(bytes([b]) * (1 + ((j + i) % 6)))
            body.extend(bytes([(b + j + i + 1) & 0xff]))
        (RAW / f'audit_{i:02d}.dat').write_bytes(bytes(body))
    large = bytes(range(32, 256)) * 18000
    (RAW / 'audit_large.dat').write_bytes(large)

    expected = {}
    for path in RAW.iterdir():
        if path.is_file() and path.suffix == '.dat':
            expected[path.stem + '.rle'] = rle_latin1(path.read_bytes())

    # Preserve the original fixed-content assertions.
    fixed = {
        'file1.rle': 'Hel*3o Wörld!*3'.encode('utf-8'),
        'file2.rle': 'a*4b*4c*4D*4'.encode('utf-8'),
        'file3.rle': 'Just a nôrmal file.*3'.encode('utf-8'),
    }
    for name, content in fixed.items():
        assert expected.get(name) == content

    PROCESSED.mkdir(parents=True, exist_ok=True)
    for entry in PROCESSED.iterdir():
        if entry.is_dir():
            shutil.rmtree(entry)
        else:
            entry.unlink()
    LOG.unlink(missing_ok=True)
    MANIFEST.unlink(missing_ok=True)

    partial = []
    stop = threading.Event()

    def watch_outputs():
        seen_sizes = {}
        while not stop.is_set():
            try:
                for path in PROCESSED.iterdir():
                    if path.suffix != '.rle' or not path.is_file():
                        continue
                    data = path.read_bytes()
                    wanted = expected.get(path.name)
                    if wanted is None or data != wanted:
                        partial.append((path.name, len(data), None if wanted is None else len(wanted)))
                        return
                    old = seen_sizes.get(path.name)
                    if old is not None and old != len(data):
                        partial.append((path.name, old, len(data)))
                        return
                    seen_sizes[path.name] = len(data)
            except FileNotFoundError:
                pass
            time.sleep(0.0005)

    watcher = threading.Thread(target=watch_outputs, daemon=True)
    watcher.start()
    try:
        run = subprocess.run([str(binary)], cwd=source_dir, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             timeout=60)
    finally:
        stop.set()
        watcher.join(timeout=2)

    assert run.returncode == 0, f'Compiled program failed:\n{run.stdout}'
    assert not partial, f'A partial or unexpected final .rle file became visible: {partial[0]}'

    actual_names = {p.name for p in PROCESSED.iterdir() if p.is_file()}
    assert actual_names == set(expected), f'Wrong processed file set: {actual_names}'
    for name, wanted in expected.items():
        path = PROCESSED / name
        assert path.is_file(), f'Processed file {path} is missing.'
        assert path.read_bytes() == wanted, f'Incorrect content in {path}.'
    assert not list(PROCESSED.glob('*.tmp')), 'Temporary files remain after processing.'

    assert LOG.is_file(), f'Log file {LOG} is missing.'
    lines = [line.strip() for line in LOG.read_text(encoding='utf-8').splitlines() if line.strip()]
    expected_log = {f'PROCESSED: {name}' for name in expected}
    assert set(lines) == expected_log, f'Incorrect log entries: {lines}'
    assert len(lines) == len(expected_log), 'The log contains duplicate or extra entries.'
    assert {'PROCESSED: file1.rle', 'PROCESSED: file2.rle', 'PROCESSED: file3.rle'} <= set(lines)

    assert MANIFEST.is_file(), f'Manifest file {MANIFEST} is missing.'
    expected_manifest = [
        f'{hashlib.sha256(expected[name]).hexdigest()}  {name}'
        for name in sorted(expected)
    ]
    manifest_lines = [line.strip() for line in MANIFEST.read_text(encoding='utf-8').splitlines() if line.strip()]
    assert manifest_lines == expected_manifest, \
        f'Incorrect manifest. Expected {expected_manifest}, got {manifest_lines}'
TEST_EOF

if python3 -m pytest /tmp/test_submission.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
