#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import codecs
import glob
import os
import re
import subprocess
import tarfile
from pathlib import Path

import pytest

ROOT = Path('/app/project_files')
LOG = ROOT / 'logs' / 'system.log'
FILTERED = ROOT / 'logs' / 'filtered_system.log'
SOURCE = ROOT / 'packer.c'
OPTIMIZED = ROOT / 'optimized.bin'
PACKER = Path('/tmp/verified_packer')


def config():
    result = subprocess.run(
        ['tesseract', str(ROOT / 'settings_scan.png'), 'stdout'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, result.stderr
    encoding_match = re.search(r'ENCODING\s*=\s*([A-Za-z0-9_-]+)', result.stdout, re.I)
    threshold_match = re.search(r'THRESHOLD\s*=\s*(\d+)', result.stdout, re.I)
    assert encoding_match and threshold_match, f'Could not read configuration from image: {result.stdout!r}'
    encoding = codecs.lookup(encoding_match.group(1)).name
    threshold = int(threshold_match.group(1))
    assert threshold == 4500
    return encoding, threshold


def blocks(text):
    return [part.strip() for part in text.split('---') if part.strip()]


def expected_filtered_blocks():
    encoding, threshold = config()
    original = LOG.read_bytes().decode(encoding)
    selected = []
    for block in blocks(original):
        matches = re.findall(r'^Duration:\s*(\d+)ms\s*$', block, re.M)
        assert len(matches) == 1, f'Invalid source log block: {block!r}'
        if int(matches[0]) >= threshold:
            selected.append(block)
    assert selected
    return selected


def test_archives_organized():
    corrupted_dir = ROOT / 'corrupted'
    extracted_dir = ROOT / 'extracted'
    archives_dir = ROOT / 'archives'

    corrupted_files = glob.glob(str(corrupted_dir / '*.tar.gz'))
    assert len(corrupted_files) == 2, f'Expected 2 corrupted archives in {corrupted_dir}/, found {len(corrupted_files)}.'
    assert {Path(p).name for p in corrupted_files} == {'archive4.tar.gz', 'archive5.tar.gz'}

    extracted_items = os.listdir(extracted_dir)
    assert len(extracted_items) >= 3, f'Expected contents from 3 valid archives in {extracted_dir}/, found {len(extracted_items)} items.'

    remaining = {p.name for p in archives_dir.glob('*.tar.gz')}
    assert remaining == {'archive1.tar.gz', 'archive2.tar.gz', 'archive3.tar.gz'}

    for i in range(1, 4):
        archive = archives_dir / f'archive{i}.tar.gz'
        result = subprocess.run(['tar', '-tzf', str(archive)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        assert result.returncode == 0, f'{archive.name} is not a valid archive: {result.stderr!r}'
        with tarfile.open(archive, 'r:gz') as tf:
            regular = [m for m in tf.getmembers() if m.isfile()]
            assert [m.name.lstrip('./') for m in regular] == [f'data{i}.txt']
            archived_data = tf.extractfile(regular[0]).read()
        output = extracted_dir / f'data{i}.txt'
        assert output.is_file(), f'{output} was not extracted'
        assert output.read_bytes() == archived_data, f'{output} does not match {archive.name}'

    for i in (4, 5):
        archive = corrupted_dir / f'archive{i}.tar.gz'
        assert archive.is_file() and archive.stat().st_size > 9000
        result = subprocess.run(['tar', '-tzf', str(archive)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        assert result.returncode != 0, f'{archive.name} is not corrupted'
        assert f'data{i}.txt'.encode() in result.stdout, f'{archive.name} is not the expected damaged archive'


def test_filtered_log_content():
    assert FILTERED.is_file(), f'Filtered log file {FILTERED} is missing.'
    try:
        content = FILTERED.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        pytest.fail(f'File {FILTERED} is not valid UTF-8 encoded.')

    actual = blocks(content)
    valid_blocks_count = 0
    for block in actual:
        valid_blocks_count += 1
        duration_found = False
        for line in block.split('\n'):
            if line.startswith('Duration:'):
                duration_str = line.split(':')[1].strip().replace('ms', '')
                try:
                    duration = int(duration_str)
                    assert duration >= 4500, f'Found a log entry with duration {duration}ms, which is less than the threshold 4500ms.'
                    duration_found = True
                except ValueError:
                    pytest.fail(f'Could not parse duration from line: {line}')
        assert duration_found, f'Duration field missing in block: {block}'
    assert valid_blocks_count > 0, 'Filtered log file contains no valid log blocks.'

    expected = expected_filtered_blocks()
    assert actual == expected, 'filtered_system.log is not the complete filtered form of system.log'


def run_packer(text):
    FILTERED.write_text(text, encoding='utf-8')
    if OPTIMIZED.exists():
        OPTIMIZED.unlink()
    result = subprocess.run([str(PACKER)], cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, f'packer failed: {result.stderr.decode(errors="replace")}'
    assert OPTIMIZED.is_file(), 'packer did not create optimized.bin'
    data = OPTIMIZED.read_bytes()
    assert data, 'packer created an empty optimized.bin'
    return data


def test_packer_c_exists_and_operates():
    assert SOURCE.is_file(), f'C source file {SOURCE} is missing.'
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(SOURCE), '-o', str(PACKER)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, f'packer.c does not compile: {compile_result.stderr.decode(errors="replace")}'

    expected_blocks = expected_filtered_blocks()
    canonical = ''.join(block + '\n---\n' for block in expected_blocks)
    samples = [
        'ID: 00000000-0000-0000-0000-000000000001\nAction: READ\nDuration: 4500ms\nMessage: Alpha payload\n---\n',
        'ID: 00000000-0000-0000-0000-000000000002\nAction: READ\nDuration: 4500ms\nMessage: Alpha payload\n---\n',
        'ID: 00000000-0000-0000-0000-000000000001\nAction: WRITE\nDuration: 4501ms\nMessage: Beta payload\n---\n',
    ]

    try:
        sample_outputs = [run_packer(sample) for sample in samples]
        assert len(set(sample_outputs)) == len(sample_outputs), 'packer output does not depend on all input log data'

        packed = run_packer(canonical)
        raw_size = len(canonical.encode('utf-8'))
        size = len(packed)
        threshold = 12000
        assert size < threshold, f'Optimized binary size is {size} bytes, which is not less than the threshold of {threshold} bytes.'
        assert size < raw_size * 0.65, f'optimized.bin is not significantly smaller than the filtered text ({size} vs {raw_size} bytes)'
        assert size >= len(expected_blocks) * 8, 'optimized.bin is implausibly small to retain the variable record data'
        assert packed != canonical.encode('utf-8'), 'optimized.bin is just an uncompressed copy of the log'
    finally:
        FILTERED.write_text(canonical, encoding='utf-8')
        if PACKER.exists():
            subprocess.run([str(PACKER)], cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)


def test_optimized_bin_size():
    assert OPTIMIZED.is_file(), f'Optimized binary file {OPTIMIZED} is missing.'
    size = OPTIMIZED.stat().st_size
    threshold = 12000
    assert size < threshold, f'Optimized binary size is {size} bytes, which is not less than the threshold of {threshold} bytes.'
    assert size > 0, 'Optimized binary file is empty.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
