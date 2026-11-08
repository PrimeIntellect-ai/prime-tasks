#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import os
import re
import tarfile
import zipfile

import pytest
import pytesseract
from PIL import Image

CLEAN_PATH = '/home/user/clean.gz'
MERGED_PATH = '/home/user/merged.txt'


def derive_expected():
    note_text = pytesseract.image_to_string(Image.open('/app/note.png'))
    match = re.search(r'XOR[_\s-]*KEY\s*=\s*(\d+)', note_text, re.IGNORECASE)
    assert match, f'Could not derive XOR key from note.png; OCR returned {note_text!r}'
    key = int(match.group(1))
    assert 0 <= key <= 255

    recovered = []

    def visit_file(name, data):
        lower = name.lower()
        if lower.endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for info in archive.infolist():
                    if not info.is_dir():
                        visit_file(name + '!/' + info.filename, archive.read(info))
        elif lower.endswith('.tar.gz') or lower.endswith('.tgz'):
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
                for member in archive.getmembers():
                    if member.isfile():
                        extracted = archive.extractfile(member)
                        assert extracted is not None
                        visit_file(name + '!/' + member.name, extracted.read())
        elif lower.endswith('.txt'):
            recovered.append((os.path.basename(name), name, data))
        elif lower.endswith('.enc'):
            decoded = bytes(value ^ key for value in data)
            txt_name = os.path.basename(name[:-4] + '.txt')
            recovered.append((txt_name, name, decoded))

    with tarfile.open('/app/project_backup.tar', mode='r:*') as archive:
        for member in archive.getmembers():
            if member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None
                visit_file(member.name, extracted.read())

    recovered.sort(key=lambda item: (item[0], item[1]))
    seen = set()
    output = []
    for _, _, data in recovered:
        text = data.decode('utf-8')
        for line in text.splitlines(keepends=True):
            if line not in seen:
                seen.add(line)
                output.append(line)
    return ''.join(output).encode('utf-8')


def test_clean_gz_size():
    """The compressed output must retain the original target size assertion."""
    filepath = CLEAN_PATH
    assert os.path.exists(filepath), f'Output file does not exist: {filepath}'

    size = os.path.getsize(filepath)
    threshold = 250

    assert size <= threshold, f'Metric: {size}. Expected size <= {threshold} bytes. The file is too large, indicating failure to deduplicate or decode properly.'


def test_clean_gz_validity():
    """The output must remain a valid, nonempty gzip archive."""
    filepath = CLEAN_PATH
    assert os.path.exists(filepath), f'Output file does not exist: {filepath}'

    try:
        with gzip.open(filepath, 'rt') as f:
            content = f.read()
    except Exception as e:
        pytest.fail(f'Failed to read {filepath} as a gzip file: {e}')

    assert len(content) > 0, 'The decompressed file is empty, data recovery failed.'


def test_recovered_content_and_merge():
    expected = derive_expected()

    assert os.path.isfile(MERGED_PATH), f'Merged output does not exist: {MERGED_PATH}'
    with open(MERGED_PATH, 'rb') as merged_file:
        merged = merged_file.read()
    assert merged == expected, 'merged.txt does not contain the correctly ordered, decoded, and deduplicated data.'

    assert os.path.isfile(CLEAN_PATH), f'Compressed output does not exist: {CLEAN_PATH}'
    with gzip.open(CLEAN_PATH, 'rb') as compressed_file:
        payload = compressed_file.read()
    assert payload == expected, 'clean.gz does not contain the required merged.txt content.'


def test_maximum_gzip_compression_flag():
    with open(CLEAN_PATH, 'rb') as compressed_file:
        header = compressed_file.read(10)
    assert len(header) == 10 and header[:3] == b'\x1f\x8b\x08', 'clean.gz is not a gzip stream using DEFLATE.'
    assert header[8] == 2, 'clean.gz was not produced using maximum gzip compression.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
