#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_slog.py
import os
import re
import stat
import struct
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

HOME = Path('/home/user')


def assert_regular(path):
    path = Path(path)
    assert path.exists(), f'{path} does not exist.'
    assert path.is_file(), f'{path} is not a file.'
    assert stat.S_ISREG(path.lstat().st_mode), f'{path} is not a regular file.'


def check_original_state():
    extract_dir = HOME / 'extracted'
    assert extract_dir.exists(), f'Directory {extract_dir} does not exist.'
    assert extract_dir.is_dir(), f'{extract_dir} is not a directory.'

    expected_files = ['valid_log_A.txt', 'valid_log_B.txt']
    for fname in expected_files:
        fpath = extract_dir / fname
        assert fpath.exists(), f'Valid log file {fname} was not extracted to {extract_dir}.'
        assert fpath.is_file(), f'{fpath} is not a file.'

    extracted_contents = os.listdir(extract_dir)
    for item in extracted_contents:
        assert item in expected_files, (
            f'Unexpected file {item} found in {extract_dir}. '
            'Malicious files should not be extracted.'
        )

    expected_a = (
        b'[2023-10-25 10:00:00] INFO Server started.\n'
        b'Loading modules...\n'
        b'Done.\n'
        b'[2023-10-25 10:05:00] ERROR Disk usage high.\n'
        b'CRITICAL_SPACE_ERROR: Partition /dev/sda1 is at 99%.\n'
        b'Please clean up old logs immediately.\n'
        b'[2023-10-25 10:06:00] INFO Routine cleanup initiated.\n'
    )
    expected_b = (
        b'[2023-10-26 11:00:00] INFO User login.\n'
        b'[2023-10-26 11:15:00] WARNING Memory usage spike.\n'
        b'[2023-10-26 11:20:00] ERROR Another disk error.\n'
        b'CRITICAL_SPACE_ERROR: Failed to write to database.\n'
        b'Check storage backend.\n'
        b'[2023-10-26 11:25:00] INFO Retry successful.\n'
    )
    assert (extract_dir / 'valid_log_A.txt').read_bytes() == expected_a, 'valid_log_A.txt was not decompressed correctly.'
    assert (extract_dir / 'valid_log_B.txt').read_bytes() == expected_b, 'valid_log_B.txt was not decompressed correctly.'

    quarantine_path = HOME / 'quarantine.log'
    assert_regular(quarantine_path)
    lines = [line.strip() for line in quarantine_path.read_text().splitlines() if line.strip()]
    expected_quarantined = ['../../../etc/passwd', '/home/user/.bashrc_override']
    for expected in expected_quarantined:
        assert expected in lines, f"Malicious path '{expected}' is missing from {quarantine_path}."
    assert len(lines) == len(expected_quarantined), f'{quarantine_path} contains unexpected entries.'

    errors_path = HOME / 'critical_errors.txt'
    assert_regular(errors_path)
    content = errors_path.read_text()
    expected_error_1 = (
        '[2023-10-25 10:05:00] ERROR Disk usage high.\n'
        'CRITICAL_SPACE_ERROR: Partition /dev/sda1 is at 99%.\n'
        'Please clean up old logs immediately.'
    )
    expected_error_2 = (
        '[2023-10-26 11:20:00] ERROR Another disk error.\n'
        'CRITICAL_SPACE_ERROR: Failed to write to database.\n'
        'Check storage backend.'
    )
    assert expected_error_1 in content, f'First critical error block is missing or formatted incorrectly in {errors_path}.'
    assert expected_error_2 in content, f'Second critical error block is missing or formatted incorrectly in {errors_path}.'
    assert (expected_error_1 + '\n\n' + expected_error_2 in content or
            expected_error_2 + '\n\n' + expected_error_1 in content), (
        f'Critical errors in {errors_path} are not separated by a blank line as requested.'
    )
    assert content.rstrip('\n') == expected_error_1 + '\n\n' + expected_error_2, (
        f'{errors_path} contains missing, reordered, or additional content.'
    )


def discover_sources_and_artifacts():
    sources = []
    scripts = []
    elfs = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'extracted', '.git', '__pycache__'}]
        for name in files:
            p = Path(root) / name
            try:
                if p.is_symlink() or not p.is_file():
                    continue
                suffix = p.suffix.lower()
                if suffix in {'.cpp', '.cc', '.cxx'}:
                    sources.append(p)
                elif suffix == '.py':
                    scripts.append(('python3', p))
                elif suffix == '.sh':
                    scripts.append(('bash', p))
                mode = p.stat().st_mode
                if mode & 0o111:
                    with p.open('rb') as f:
                        if f.read(4) == b'\x7fELF':
                            elfs.append(p)
            except OSError:
                pass
    assert sources, 'No C++ source file was written under /home/user.'
    assert elfs, 'No compiled executable artifact was left under /home/user.'
    return sources[:50], scripts[:50]


def compile_sources(sources, build_dir):
    attempts = [[p] for p in sources]
    if len(sources) > 1:
        attempts.append(sources)
    binaries = []
    seen = set()
    for idx, group in enumerate(attempts):
        key = tuple(sorted(str(p) for p in group))
        if key in seen:
            continue
        seen.add(key)
        out = build_dir / f'candidate_{idx}'
        cmd = ['g++', '-std=c++17', '-O2', '-o', str(out)] + [str(p) for p in group]
        try:
            result = subprocess.run(cmd, cwd=HOME, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=30)
        except (subprocess.TimeoutExpired, OSError):
            continue
        if result.returncode == 0 and out.exists():
            binaries.append(out)
    assert binaries, 'The submitted C++ source could not be compiled.'
    return binaries


def rle(data):
    out = bytearray()
    i = 0
    while i < len(data):
        value = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == value and count < 255:
            count += 1
        out.extend((count, value))
        i += count
    out.extend((0, 0))
    return bytes(out)


def write_archive(path, entries):
    with open(path, 'wb') as f:
        f.write(b'SLOG')
        f.write(struct.pack('<I', len(entries)))
        for name, data in entries:
            encoded = name.encode('ascii')
            f.write(struct.pack('<H', len(encoded)))
            f.write(encoded)
            f.write(rle(data))


def dynamic_test(binaries, scripts):
    token = uuid.uuid4().hex
    case_root = Path('/tmp') / ('slog_case_' + token)
    extract_dir = case_root / 'output'
    quarantine = case_root / 'quarantine.txt'
    relative_escape = case_root / ('escape_' + token + '.txt')
    absolute_escape = Path('/tmp') / ('slog_absolute_' + token + '.txt')

    name_a = 'alpha_' + token[:8] + '.txt'
    name_b = 'beta_' + token[8:16] + '.txt'
    name_other = 'notes_' + token[16:24] + '.dat'
    malicious_rel = '../' + relative_escape.name
    malicious_abs = str(absolute_escape)

    log_a = (
        '[2041-02-03 04:05:06] INFO generated case ' + token + '\n'
        'ordinary continuation\n'
        '[2041-02-03 04:06:07] ERROR generated disk event\n'
        'CRITICAL_SPACE_ERROR: volume ' + token[:12] + ' is full\n'
        'first requested action\n'
        '[2041-02-03 04:07:08] INFO recovered\n'
    ).encode()
    log_b = (
        '[2042-03-04 05:06:07] WARNING another generated case\n'
        '[2042-03-04 05:07:08] ERROR backend failure\n'
        'details before marker\n'
        'CRITICAL_SPACE_ERROR: backend ' + token[12:24] + '\n'
        'second requested action\n'
        '[2042-03-04 05:08:09] INFO retry complete\n'
    ).encode()
    other = ('CRITICAL_SPACE_ERROR in a non-txt file ' + token + '\n').encode()

    expected_block_a = (
        '[2041-02-03 04:06:07] ERROR generated disk event\n'
        'CRITICAL_SPACE_ERROR: volume ' + token[:12] + ' is full\n'
        'first requested action'
    )
    expected_block_b = (
        '[2042-03-04 05:07:08] ERROR backend failure\n'
        'details before marker\n'
        'CRITICAL_SPACE_ERROR: backend ' + token[12:24] + '\n'
        'second requested action'
    )
    expected_critical = expected_block_a + '\n\n' + expected_block_b

    entries = [
        (name_a, log_a),
        (malicious_rel, b'escape-relative-' + token.encode()),
        (name_other, other),
        (malicious_abs, b'escape-absolute-' + token.encode()),
        (name_b, log_b),
    ]

    archive = HOME / 'server_logs.slog'
    config = HOME / 'slog_config.ini'
    critical = HOME / 'critical_errors.txt'

    def reset_case():
        shutil.rmtree(case_root, ignore_errors=True)
        case_root.mkdir(parents=True)
        for p in (relative_escape, absolute_escape):
            try:
                p.unlink()
            except FileNotFoundError:
                pass
        try:
            critical.unlink()
        except FileNotFoundError:
            pass
        write_archive(archive, entries)
        config.write_text(f'extract_dir={extract_dir}\nquarantine_log={quarantine}\n')

    def assess():
        assert extract_dir.is_dir(), 'The configured extraction directory was not created.'
        actual_names = sorted(p.name for p in extract_dir.iterdir())
        expected_names = sorted([name_a, name_b, name_other])
        assert actual_names == expected_names, 'Valid files were missing or unexpected files were extracted.'
        for name, expected in ((name_a, log_a), (name_b, log_b), (name_other, other)):
            p = extract_dir / name
            assert_regular(p)
            assert p.read_bytes() == expected, f'{name} was not RLE-decompressed correctly.'
        assert not relative_escape.exists(), 'A ../ archive entry escaped the extraction directory.'
        assert not absolute_escape.exists(), 'An absolute archive entry was written.'
        assert_regular(quarantine)
        qlines = [line for line in quarantine.read_text().splitlines() if line]
        assert qlines == [malicious_rel, malicious_abs], 'The dynamic quarantine log is incomplete or contains extra entries.'
        assert_regular(critical)
        result = critical.read_text()
        assert result.rstrip('\n') == expected_critical, 'Critical entries were not parsed exactly or extra content was emitted.'

    helpers = [None] + scripts + [('binary', b) for b in binaries]
    failures = []
    for primary in binaries:
        for helper in helpers:
            if helper == ('binary', primary):
                continue
            reset_case()
            try:
                first = subprocess.run([str(primary)], cwd=HOME, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, timeout=12)
                if first.returncode != 0:
                    raise AssertionError(f'extractor exited with status {first.returncode}')
                if helper is not None:
                    kind, path = helper
                    cmd = [str(path)] if kind == 'binary' else [kind, str(path)]
                    second = subprocess.run(cmd, cwd=HOME, stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE, timeout=12)
                    if second.returncode != 0:
                        raise AssertionError(f'helper exited with status {second.returncode}')
                assess()
                return
            except (AssertionError, OSError, subprocess.TimeoutExpired) as exc:
                failures.append(str(exc))
    raise AssertionError('No compiled submitted C++ implementation passed the generated archive test. ' +
                         ('Last failure: ' + failures[-1] if failures else ''))


check_original_state()
sources, scripts = discover_sources_and_artifacts()
with tempfile.TemporaryDirectory(prefix='slog_build_') as td:
    binaries = compile_sources(sources, Path(td))
    dynamic_test(binaries, scripts)
PY_EOF

if python3 /tmp/verify_slog.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
