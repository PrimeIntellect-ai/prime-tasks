#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.metadata
import json
import os
import re
import tarfile
from collections import Counter

import pytest

OUTPUT_FILE = '/home/user/curated_metadata.json'
ARCHIVE_FILE = '/home/user/incoming/repository.tar.gz'
REQUIRED_KEYS = {'Artifact-ID', 'Checksum', 'Status'}


def archive_ground_truth():
    expected = []
    binary_names = set()
    records = []

    with tarfile.open(ARCHIVE_FILE, 'r:*') as archive:
        for member in archive.getmembers():
            normalized = os.path.normpath('/' + member.name).lstrip('/')
            assert normalized != '..' and not normalized.startswith('../'), \
                f'Unsafe archive member: {member.name}'

            if member.isfile() and normalized.startswith('bins/'):
                binary_names.add(os.path.basename(normalized))

            if member.isfile() and normalized.endswith('.log'):
                extracted = archive.extractfile(member)
                assert extracted is not None
                text = extracted.read().decode('utf-8')
                blocks = re.findall(
                    r'^\[START ARTIFACT\]\s*$\n(.*?)^\[END ARTIFACT\]\s*$',
                    text,
                    flags=re.MULTILINE | re.DOTALL,
                )
                for block in blocks:
                    record = {}
                    for line in block.splitlines():
                        if ':' in line:
                            key, value = line.split(':', 1)
                            record[key.strip()] = value.strip()
                    records.append(record)

    assert records, 'No artifact records were found in the repository archive.'
    for record in records:
        assert REQUIRED_KEYS.issubset(record), f'Malformed artifact record: {record}'
        assert record['Artifact-ID'] in binary_names, \
            f"Artifact {record['Artifact-ID']} has no associated binary."
        if record['Status'] == 'VALID':
            expected.append({key: record[key] for key in REQUIRED_KEYS})

    return expected


def test_package_was_installed():
    distribution = importlib.metadata.distribution('fast-archive-parser')
    assert distribution.version == '1.2'

    module = importlib.import_module('fast_archive')
    assert callable(getattr(module, 'extract', None))
    module_path = os.path.realpath(module.__file__)
    assert 'site-packages' in module_path or 'dist-packages' in module_path, \
        f'fast_archive was not installed into the Python environment: {module_path}'


def test_curated_metadata_f1_score():
    assert os.path.exists(OUTPUT_FILE), f'Output file {OUTPUT_FILE} does not exist.'
    assert os.path.isfile(OUTPUT_FILE), f'Path {OUTPUT_FILE} is not a file.'
    assert not os.path.islink(OUTPUT_FILE), 'Output must be a regular file, not a symlink.'

    try:
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as stream:
            predicted = json.load(stream)
    except Exception as exc:
        pytest.fail(f'Failed to load JSON from {OUTPUT_FILE}: {exc}')

    assert isinstance(predicted, list), \
        f'Expected a JSON array, got {type(predicted).__name__}'

    for index, item in enumerate(predicted):
        assert isinstance(item, dict), f'Entry {index} is not an object.'
        assert set(item) == REQUIRED_KEYS, \
            f'Entry {index} must contain exactly {sorted(REQUIRED_KEYS)}.'
        assert all(isinstance(item[key], str) for key in REQUIRED_KEYS), \
            f'Entry {index} contains a non-string field.'
        assert item['Status'] == 'VALID', \
            f"Entry {index} is not a valid artifact: {item['Status']}"

    golden = archive_ground_truth()

    # Preserve the original F1 assertion, but derive its ground truth from the
    # repository rather than trusting a fixed subset.
    pred_set = set(
        f"{item.get('Artifact-ID')}_{item.get('Checksum')}"
        for item in predicted if item.get('Status') == 'VALID'
    )
    gold_set = set(
        f"{item['Artifact-ID']}_{item['Checksum']}" for item in golden
    )

    precision = 0.0
    recall = 0.0
    if not pred_set and not gold_set:
        f1 = 1.0
    elif not pred_set or not gold_set:
        f1 = 0.0
    else:
        true_positives = len(pred_set & gold_set)
        false_positives = len(pred_set - gold_set)
        false_negatives = len(gold_set - pred_set)
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)

    assert f1 >= 0.95, \
        f'F1 score {f1:.4f} is below the threshold of 0.95. Precision: {precision:.4f}, Recall: {recall:.4f}'

    # Reject ignored invalid records, duplicates, missing records, and extra fields.
    predicted_records = Counter(
        (item['Artifact-ID'], item['Checksum'], item['Status']) for item in predicted
    )
    golden_records = Counter(
        (item['Artifact-ID'], item['Checksum'], item['Status']) for item in golden
    )
    assert predicted_records == golden_records, \
        f'Curated metadata does not exactly match valid archive records: {predicted}'

    # A rename after writing updates ctime after the temporary file's final data
    # modification, providing filesystem evidence of the required atomic publish.
    stat = os.stat(OUTPUT_FILE)
    assert stat.st_ctime_ns > stat.st_mtime_ns, \
        'Output lacks evidence of being atomically published by rename.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
