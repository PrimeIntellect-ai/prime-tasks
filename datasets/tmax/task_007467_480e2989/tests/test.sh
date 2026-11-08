#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import struct
import subprocess
import secrets
import zlib

SOURCE = '/home/user/extract_docs.cpp'
BINARY = '/home/user/extract_docs'
CONFIG = '/home/user/extraction.conf'
ARCHIVE = '/home/user/archive.pak'
SUMMARY = '/home/user/summary.txt'


def make_record(rec_type, category, doc_id, payload):
    category_bytes = category.encode('ascii')
    return (struct.pack('<cB', rec_type.encode('ascii'), len(category_bytes)) +
            category_bytes + struct.pack('<II', doc_id, len(payload)) + payload)


def log_payload(entries):
    return ''.join(
        'BEGIN_LOG\n'
        f'DocID: {doc_id}\n'
        f'Version: {version}\n'
        f'Status: {status}\n'
        'END_LOG\n'
        for doc_id, version, status in entries
    ).encode('ascii')


def remove_outputs(prefix):
    shutil.rmtree(prefix, ignore_errors=True)
    try:
        os.remove(SUMMARY)
    except FileNotFoundError:
        pass


def write_challenge(prefix, token, offset):
    category_a = 'API' + token
    category_b = 'Guide' + token
    ignored_category = 'Internal' + token
    doc_a = offset + 31
    doc_b = offset + 7
    doc_ignored = offset + 19
    doc_draft = offset + 43
    content_a = ('Generated API payload ' + secrets.token_hex(20)).encode('ascii')
    content_b = ('Generated guide payload ' + secrets.token_hex(20)).encode('ascii')

    with open(CONFIG, 'w') as f:
        f.write(f'Extract-Prefix: {prefix}\n')
        f.write(f'Target-Categories: {category_a},{category_b}\n')
        f.write('Other-Setting: verifier-generated\n')

    records = [
        # Compressed data before its logs.
        make_record('C', category_a, doc_a, zlib.compress(content_a)),
        make_record('L', category_a, doc_a, log_payload([
            (doc_a, 2, 'RELEASED'),
            (doc_a, 9, 'DRAFT'),
            (doc_a, 5, 'RELEASED'),
        ])),
        # Logs before compressed data.
        make_record('L', category_b, doc_b, log_payload([
            (doc_b, 3, 'RELEASED'),
            (doc_b, 8, 'RELEASED'),
        ])),
        make_record('C', category_b, doc_b, zlib.compress(content_b)),
        # A released document in a category not selected by the config.
        make_record('L', ignored_category, doc_ignored,
                    log_payload([(doc_ignored, 12, 'RELEASED')])),
        make_record('C', ignored_category, doc_ignored,
                    zlib.compress(b'must not be extracted')),
        # A selected document with no released version.
        make_record('C', category_a, doc_draft,
                    zlib.compress(b'draft must not be extracted')),
        make_record('L', category_a, doc_draft,
                    log_payload([(doc_draft, 99, 'DRAFT')])),
    ]
    with open(ARCHIVE, 'wb') as f:
        f.write(b'ARCv1')
        for record in records:
            f.write(record)

    expected_files = {
        f'{category_a}_{doc_a}_v5.txt': content_a,
        f'{category_b}_{doc_b}_v8.txt': content_b,
    }
    expected_summary = [
        f'Extracted DocID {doc_id} of Category {category} at Version {version}'
        for doc_id, category, version in sorted([
            (doc_a, category_a, 5),
            (doc_b, category_b, 8),
        ])
    ]
    return expected_files, expected_summary


def run_and_check(program, prefix, expected_files, expected_summary):
    remove_outputs(prefix)
    subprocess.run([program], cwd='/home/user', check=True, timeout=20)

    assert os.path.isdir(prefix), f'Extraction directory {prefix} was not created.'
    entries = sorted(os.listdir(prefix))
    assert entries == sorted(expected_files), (
        f'Expected exactly {sorted(expected_files)} in {prefix}, got {entries}'
    )
    for name, expected in expected_files.items():
        path = os.path.join(prefix, name)
        assert os.path.isfile(path), f'Expected extracted document {path} is missing.'
        with open(path, 'rb') as f:
            assert f.read() == expected, f'Content of {path} is incorrect.'

    assert os.path.isfile(SUMMARY), 'Summary log file is missing.'
    with open(SUMMARY, 'r') as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]
    assert lines == expected_summary, f'Incorrect generated summary: {lines}'


def write_original_inputs():
    with open(CONFIG, 'w') as f:
        f.write('Extract-Prefix: /home/user/extracted_docs\n')
        f.write('Target-Categories: API,Tutorial\n')
        f.write('Other-Setting: IgnoreThis\n')

    logs_payload_1 = log_payload([
        (101, 1, 'RELEASED'),
        (101, 2, 'DRAFT'),
    ])
    logs_payload_2 = log_payload([
        (202, 1, 'RELEASED'),
        (202, 3, 'RELEASED'),
    ])
    logs_payload_3 = log_payload([(303, 1, 'DRAFT')])

    with open(ARCHIVE, 'wb') as f:
        f.write(b'ARCv1')
        f.write(make_record('L', 'API', 101, logs_payload_1))
        f.write(make_record('C', 'API', 101,
                            zlib.compress(b'This is the API documentation.')))
        f.write(make_record('C', 'Tutorial', 202,
                            zlib.compress(b'This is the Tutorial documentation.')))
        f.write(make_record('L', 'Tutorial', 202, logs_payload_2))
        f.write(make_record('C', 'Architecture', 303,
                            zlib.compress(b'This is Architecture, should be ignored by category.')))
        f.write(make_record('L', 'Architecture', 303, logs_payload_3))
        f.write(make_record('C', 'API', 404,
                            zlib.compress(b'This is API but never released.')))


def assert_original_outputs():
    # Preserve the original verifier's assertions.
    doc1_path = '/home/user/extracted_docs/API_101_v1.txt'
    doc2_path = '/home/user/extracted_docs/Tutorial_202_v3.txt'

    assert os.path.isfile(doc1_path), f'Expected extracted document {doc1_path} is missing.'
    assert os.path.isfile(doc2_path), f'Expected extracted document {doc2_path} is missing.'

    with open(doc1_path, 'r') as f:
        content1 = f.read().strip()
    assert content1 == 'This is the API documentation.', f'Content of {doc1_path} is incorrect. Got: {content1}'

    with open(doc2_path, 'r') as f:
        content2 = f.read().strip()
    assert content2 == 'This is the Tutorial documentation.', f'Content of {doc2_path} is incorrect. Got: {content2}'

    extract_dir = '/home/user/extracted_docs'
    assert os.path.isdir(extract_dir), f'Extraction directory {extract_dir} does not exist.'
    files = os.listdir(extract_dir)
    assert len(files) == 2, f'Expected exactly 2 files in {extract_dir}, but found {len(files)}: {files}'

    assert os.path.isfile(SUMMARY), f'Summary log file {SUMMARY} is missing.'
    with open(SUMMARY, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]
    expected_lines = [
        'Extracted DocID 101 of Category API at Version 1',
        'Extracted DocID 202 of Category Tutorial at Version 3',
    ]
    assert lines == expected_lines, f'Content of {SUMMARY} does not match expected output. Got: {lines}'


def test_program_source_binary_and_execution():
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f'{SOURCE} must be a regular C++ source file.'

    binary_stat = os.lstat(BINARY)
    assert stat.S_ISREG(binary_stat.st_mode), f'{BINARY} must be a regular compiled executable.'
    assert os.access(BINARY, os.X_OK), f'{BINARY} is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{BINARY} is not a compiled ELF executable.'

    rebuilt = '/tmp/extract_docs_rebuilt'
    subprocess.run(
        ['g++', '-std=c++17', SOURCE, '-o', rebuilt, '-lz'],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    with open(rebuilt, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Recompiling the submitted C++ did not produce an ELF executable.'

    token1 = secrets.token_hex(4)
    prefix1 = '/home/user/extracted_' + token1
    expected1, summary1 = write_challenge(prefix1, token1, 10000 + secrets.randbelow(100000))
    run_and_check(BINARY, prefix1, expected1, summary1)

    token2 = secrets.token_hex(4)
    prefix2 = '/home/user/extracted_' + token2
    expected2, summary2 = write_challenge(prefix2, token2, 200000 + secrets.randbelow(100000))
    run_and_check(rebuilt, prefix2, expected2, summary2)

    write_original_inputs()
    remove_outputs('/home/user/extracted_docs')
    subprocess.run([BINARY], cwd='/home/user', check=True, timeout=20)
    assert_original_outputs()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
