#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import tarfile
from collections import Counter
import pytest

TARGET_ARCHIVE = '/home/user/updated_docs.tar.gz'
SOURCE_FILE = '/app/corrupted_docs.bin'
ARCHIVE_OFFSET = 512

EXPECTED_REPLACEMENTS = {
    b'ACME_CORP': b'GLOBAL_TECH_INC',
    b'LEGACY_SYSTEM_V1': b'CLOUD_NATIVE_V2',
    b'USER_MANUAL': b'ADMIN_GUIDE',
}


def member_kind(member):
    if member.isdir():
        return 'dir'
    if member.isfile():
        return 'file'
    return 'other'


def transformed(content):
    for old, new in EXPECTED_REPLACEMENTS.items():
        content = content.replace(old, new)
    return content


def test_updated_docs_archive_accuracy():
    target_archive = TARGET_ARCHIVE
    assert os.path.exists(target_archive), f'Target archive not found at {target_archive}'
    assert os.path.isfile(target_archive) and not os.path.islink(target_archive), 'Target archive must be a regular file'

    # Derive the required member names, types, and contents from the real hidden
    # archive rather than trusting counts supplied by the submission.
    with open(SOURCE_FILE, 'rb') as source:
        source.seek(ARCHIVE_OFFSET)
        with tarfile.open(fileobj=source, mode='r:gz') as reference_tar:
            reference_members = reference_tar.getmembers()
            reference_layout = [(m.name, member_kind(m)) for m in reference_members]
            assert all(kind in ('file', 'dir') for _, kind in reference_layout)
            expected_contents = {}
            for member in reference_members:
                if member.isfile():
                    fd = reference_tar.extractfile(member)
                    assert fd is not None
                    expected_contents[member.name] = transformed(fd.read())

    extract_dir = '/tmp/verify_docs_test'
    if os.path.exists(extract_dir):
        shutil.rmtree(extract_dir)
    os.makedirs(extract_dir)

    try:
        with tarfile.open(target_archive, 'r:gz') as tar:
            submitted_members = tar.getmembers()
            submitted_layout = [(m.name, member_kind(m)) for m in submitted_members]

            assert len({m.name for m in submitted_members}) == len(submitted_members), 'Archive contains duplicate member names'
            assert Counter(submitted_layout) == Counter(reference_layout), 'Archive filenames, file counts, or structure differ from the source archive'
            assert all(member_kind(m) in ('file', 'dir') for m in submitted_members), 'Archive contains unsupported member types'

            # Compare every documentation file byte-for-byte with the source
            # content after applying the required global replacements.
            for member in submitted_members:
                if member.isfile():
                    fd = tar.extractfile(member)
                    assert fd is not None
                    actual = fd.read()
                    assert actual == expected_contents[member.name], f'Incorrect content in {member.name}'

            # Extract only after layout validation, avoiding unsafe paths and links.
            for member in submitted_members:
                destination = os.path.join(extract_dir, member.name)
                if member.isdir():
                    os.makedirs(destination, exist_ok=True)
                else:
                    os.makedirs(os.path.dirname(destination), exist_ok=True)
                    fd = tar.extractfile(member)
                    assert fd is not None
                    with open(destination, 'wb') as output:
                        shutil.copyfileobj(fd, output)
    except AssertionError:
        raise
    except Exception as e:
        pytest.fail(f'Failed to extract {target_archive}: {e}')

    expected_replacements = {
        'ACME_CORP': 'GLOBAL_TECH_INC',
        'LEGACY_SYSTEM_V1': 'CLOUD_NATIVE_V2',
        'USER_MANUAL': 'ADMIN_GUIDE'
    }

    correct = 0
    incorrect = 0
    txt_count = 0
    xml_count = 0

    for root, _, files in os.walk(extract_dir):
        for f in files:
            if f.endswith('.txt'):
                txt_count += 1
                with open(os.path.join(root, f), 'r') as fd:
                    content = fd.read()
                    for old, new in expected_replacements.items():
                        correct += content.count(new)
                        incorrect += content.count(old)
            elif f.endswith('.xml'):
                xml_count += 1
                with open(os.path.join(root, f), 'r') as fd:
                    content = fd.read()
                    for old, new in expected_replacements.items():
                        correct += content.count(new)
                        incorrect += content.count(old)

    assert txt_count > 0 or xml_count > 0, 'No .txt or .xml files found in the extracted archive.'

    # Based on the setup, there are 10 txt files and 10 xml files.
    # Each txt file has 3 terms to replace. Each xml file has 2 terms to replace.
    # 10 * 3 + 10 * 2 = 50
    total_expected = 50
    score = max(0.0, (correct - incorrect) / total_expected)

    assert score >= 0.95, f'Term replacement accuracy is {score:.2f}, which is below the threshold of 0.95. (Correct: {correct}, Incorrect remaining: {incorrect})'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
