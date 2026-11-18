#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import os
import random
import re
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

SANITIZER = '/home/user/sanitizer'
SOURCE = '/home/user/sanitizer.c'
REBUILT = '/tmp/rebuilt_sanitizer'


@pytest.fixture(scope='session', autouse=True)
def compile_submitted_source():
    assert os.path.isfile(SOURCE), f"Sanitizer source {SOURCE} does not exist."
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', SOURCE, '-o', REBUILT],
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, f"sanitizer.c does not compile:\n{result.stderr.decode(errors='replace')}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def run_sanitizer(path, data):
    return subprocess.run([path], input=data, capture_output=True, timeout=5)


def test_sanitizer_exists_and_executable():
    sanitizer_path = '/home/user/sanitizer'
    assert os.path.isfile(sanitizer_path), f"Sanitizer executable {sanitizer_path} does not exist."
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer {sanitizer_path} is not executable."
    with open(sanitizer_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Sanitizer must be a compiled executable."


def test_sanitizer_source_exists():
    assert os.path.isfile(SOURCE), f"Sanitizer source {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"Sanitizer source {SOURCE} is empty."


def test_sanitizer_clean_corpus():
    sanitizer_path = '/home/user/sanitizer'
    clean_dir = '/app/corpora/clean/'

    clean_files = glob.glob(os.path.join(clean_dir, '*'))
    assert len(clean_files) > 0, "No files found in clean corpus."

    failed_files = []
    for filepath in clean_files:
        with open(filepath, 'rb') as f:
            input_data = f.read()

        result = subprocess.run(
            [sanitizer_path],
            input=input_data,
            capture_output=True
        )

        if result.returncode != 0:
            failed_files.append(f"{os.path.basename(filepath)} (crashed)")
            continue

        if result.stdout != input_data:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_sanitizer_evil_corpus():
    sanitizer_path = '/home/user/sanitizer'
    evil_dir = '/app/corpora/evil/'

    evil_files = glob.glob(os.path.join(evil_dir, '*'))
    assert len(evil_files) > 0, "No files found in evil corpus."

    failed_files = []
    for filepath in evil_files:
        with open(filepath, 'rb') as f:
            input_data = f.read()

        result = subprocess.run(
            [sanitizer_path],
            input=input_data,
            capture_output=True
        )

        if result.returncode != 0:
            pass

        if result.stdout.strip() != b"":
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def make_record(seq, obs, val):
    return f"[RECORD]\nSEQ:{seq}\nOBS:{obs}\nVAL:{val}\n[/RECORD]\n".encode()


def test_generated_hidden_adversarial_inputs():
    rng = random.SystemRandom()
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '
    valid = []
    for _ in range(24):
        seq = rng.randint(1, 2_000_000_000)
        length = rng.randint(1, 64)
        obs = ''.join(rng.choice(alphabet) for _ in range(length))
        if obs.strip() == '':
            obs = 'A' + obs[1:]
        forms = [
            f"{rng.randint(-100000, 100000)}.{rng.randint(0, 999999):06d}",
            f"{rng.randint(1, 9999)}e{rng.randint(-20, 20):+d}",
            f"-{rng.randint(0, 9999)}.{rng.randint(0, 9999):04d}",
        ]
        valid.append(make_record(seq, obs, rng.choice(forms)))

    token = ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(12))
    evil = [
        make_record(0, token, '1.0'),
        make_record(-rng.randint(1, 9999), token, '1.0'),
        make_record('12x', token, '1.0'),
        make_record(rng.randint(1, 9999), '', '1.0'),
        make_record(rng.randint(1, 9999), token + '!', '1.0'),
        make_record(rng.randint(1, 9999), 'A' * 65, '1.0'),
        make_record(rng.randint(1, 9999), token, 'not-a-float'),
        make_record(rng.randint(1, 9999), token, '1.2.3'),
        f"[RECORD]\nOBS:{token}\nSEQ:9\nVAL:1.0\n[/RECORD]\n".encode(),
        f"[RECORD]\nSEQ:9\nOBS:{token}\nVAL:1.0\n".encode(),
        f"[RECORD]\nSEQ:9\nOBS:{token}\nEXTRA:x\nVAL:1.0\n[/RECORD]\n".encode(),
        f"[RECORD ]\nSEQ:9\nOBS:{token}\nVAL:1.0\n[/RECORD]\n".encode(),
    ]

    for binary in (SANITIZER, REBUILT):
        for record in valid:
            result = run_sanitizer(binary, record)
            assert result.returncode == 0, f"{binary} crashed on a generated valid record"
            assert result.stdout == record, f"{binary} modified or rejected a generated valid record"
        combined = b''.join(valid)
        result = run_sanitizer(binary, combined)
        assert result.returncode == 0
        assert result.stdout == combined, f"{binary} failed a generated multi-record stream"
        for record in evil:
            result = run_sanitizer(binary, record)
            assert result.returncode == 0, f"{binary} crashed on generated malformed input"
            assert result.stdout == b'', f"{binary} accepted generated malformed input"


def test_master_clean_log_exists():
    log_path = '/home/user/master_clean.log'
    assert os.path.isfile(log_path), f"Final output file {log_path} is missing."
    assert os.path.getsize(log_path) > 0, f"Final output file {log_path} is empty."


record_re = re.compile(
    rb'\A\[RECORD\]\nSEQ:([0-9]+)\nOBS:([A-Za-z0-9 ]{1,64})\n'
    rb'VAL:[+-]?(?:(?:[0-9]+(?:\.[0-9]*)?)|(?:\.[0-9]+))(?:[eE][+-]?[0-9]+)?\n'
    rb'\[/RECORD\]\n\Z'
)


def valid_record_bytes(record):
    match = record_re.fullmatch(record)
    return match is not None and int(match.group(1)) > 0


def split_canonical_records(data):
    lines = data.splitlines(keepends=True)
    if len(lines) % 5 != 0:
        return None
    records = [b''.join(lines[i:i + 5]) for i in range(0, len(lines), 5)]
    if not all(valid_record_bytes(record) for record in records):
        return None
    return records


def test_extraction_decoder_and_master_integration():
    raw_root = Path('/app/raw_data')
    selected = []
    for path in raw_root.rglob('*.tar.gz'):
        mode = path.stat().st_mode
        if mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            selected.append(path)
    selected.sort()
    assert selected, "No executable .tar.gz archives found."

    expected_files = {}
    for archive in selected:
        with tarfile.open(archive, 'r:gz') as tf:
            for member in tf.getmembers():
                if member.isfile():
                    name = member.name
                    while name.startswith('./'):
                        name = name[2:]
                    assert name and not name.startswith('/') and '..' not in Path(name).parts
                    expected_files[name] = tf.extractfile(member).read()

    extracted_root = Path('/home/user/extracted')
    assert extracted_root.is_dir(), "Extraction directory is missing."
    for name, expected_data in expected_files.items():
        destination = extracted_root / name
        assert destination.is_file(), f"Archive member {name} was not extracted."
        assert destination.read_bytes() == expected_data, f"Extracted archive member {name} has wrong contents."

    expected_dat_names = sorted(name for name in expected_files if name.endswith('.dat'))
    actual_dat_names = sorted(str(p.relative_to(extracted_root)) for p in extracted_root.rglob('*.dat'))
    assert actual_dat_names == expected_dat_names, "Extracted .dat files do not match the selected executable archives."

    expected_records = []
    with tempfile.TemporaryDirectory() as td:
        temp_root = Path(td)
        for name in expected_dat_names:
            path = temp_root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected_files[name])
            decoded = subprocess.run(
                ['/app/decoder.bin', str(path)], capture_output=True, timeout=5
            )
            assert decoded.returncode == 0, f"Decoder failed for archive member {name}."
            records = split_canonical_records(decoded.stdout)
            assert records is not None, f"Decoder produced an unexpected record format for {name}."
            expected_records.extend(records)

    master = Path('/home/user/master_clean.log').read_bytes()
    actual_records = split_canonical_records(master)
    assert actual_records is not None, "master_clean.log contains malformed, altered, or partial records."
    assert collections.Counter(actual_records) == collections.Counter(expected_records), \
        "master_clean.log does not contain exactly the sanitized decoder output for all extracted .dat files."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
