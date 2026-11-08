#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

EXPECTED_DOCS = {
    'docs/intro.txt': 'Welcome to the docs. %%AUTHOR:Alice%% %%DATE:2020-01-01 %%\n',
    'docs/api/v1.txt': 'API V1. %%AUTHOR:Bob%% %%DATE:2021-05-12%%\n',
    'docs/api/v2.txt': 'API V2. %%AUTHOR:Charlie  %% %%DATE:2022-10-10%%\n',
    'docs/guides/guide1.txt': 'Guide 1. %%AUTHOR:Dave%%\n',
}

EXPECTED_LINES = [
    'docs/api/v1.txt,Bob,2021-05-12',
    'docs/api/v2.txt,Charlie,2022-10-10',
    'docs/guides/guide1.txt,Dave,UNKNOWN',
    'docs/intro.txt,Alice,2020-01-01',
]


def run_parser(executable, path, cwd=None):
    result = subprocess.run(
        [str(executable), str(path)],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f'{executable} failed for {path}: rc={result.returncode}, stderr={result.stderr!r}'
    )
    return result.stdout.rstrip('\n')


def exercise_parser(executable):
    token = uuid.uuid4().hex
    author1 = 'Author' + token[:10]
    date1 = 'Date' + token[10:20]
    author2 = 'Writer' + token[20:28]
    date2 = 'Stamp' + token[4:14]

    with tempfile.TemporaryDirectory(prefix='parser-check-') as td:
        root = Path(td)
        nested = root / 'nested path'
        nested.mkdir()

        cases = [
            (nested / 'both.txt',
             f'prefix %%DATE:{date1}%% middle\n%%AUTHOR:{author1} %% tail\n',
             author1, date1),
            (root / 'author-only.txt',
             f'%%AUTHOR:{author2}%% no date here\n',
             author2, 'UNKNOWN'),
            (root / 'date-only.txt',
             f'no author here %%DATE:{date2} extra text\n',
             'UNKNOWN', date2),
            (root / 'neither.txt',
             'ordinary text without metadata tags\n',
             'UNKNOWN', 'UNKNOWN'),
        ]

        for path, content, author, date in cases:
            path.write_text(content)
            expected = f'{path},{author},{date}'
            assert run_parser(executable, path) == expected


def test_parser_c_exists():
    assert os.path.exists('/home/user/parser.c'), 'parser.c does not exist'
    assert os.path.isfile('/home/user/parser.c'), 'parser.c is not a file'


def test_parser_executable_exists():
    parser = '/home/user/parser'
    assert os.path.exists(parser), 'compiled parser does not exist'
    assert os.path.isfile(parser), 'parser is not a file'
    assert os.access(parser, os.X_OK), 'parser is not executable'
    with open(parser, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'parser is not a compiled executable'


def test_parser_source_and_binary_behavior():
    exercise_parser('/home/user/parser')

    with tempfile.TemporaryDirectory(prefix='compile-parser-') as td:
        rebuilt = os.path.join(td, 'parser-from-source')
        result = subprocess.run(
            ['gcc', '-std=c11', '/home/user/parser.c', '-o', rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert result.returncode == 0, f'parser.c does not compile: {result.stderr}'
        exercise_parser(rebuilt)


def test_extracted_docs_are_normalized_source_files():
    actual = set()
    for root, _, files in os.walk('/home/user/docs'):
        for name in files:
            if name.endswith('.txt'):
                actual.add(os.path.relpath(os.path.join(root, name), '/home/user'))

    assert actual == set(EXPECTED_DOCS), f'Unexpected extracted .txt files: {sorted(actual)}'
    for relative, expected_content in EXPECTED_DOCS.items():
        with open(os.path.join('/home/user', relative), 'r') as f:
            assert f.read() == expected_content, f'Incorrect normalized content in {relative}'


def test_metadata_csv_contents():
    csv_path = '/home/user/metadata.csv'
    assert os.path.exists(csv_path), 'metadata.csv does not exist'

    with open(csv_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_LINES, f'metadata.csv contents do not match expected. Got: {lines}'

    generated = []
    for relative in sorted(EXPECTED_DOCS):
        generated.append(run_parser('/home/user/parser', relative, cwd='/home/user'))
    assert generated == lines, 'metadata.csv is not the sorted output of the submitted parser'


def test_processed_docs_archive():
    archive_path = '/home/user/processed_docs.tar.gz'
    assert os.path.exists(archive_path), f'Archive {archive_path} does not exist'
    assert tarfile.is_tarfile(archive_path), f'File {archive_path} is not a valid tar archive'

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()

        # Check metadata.csv is in archive
        assert 'metadata.csv' in names or './metadata.csv' in names, 'metadata.csv not found in processed_docs.tar.gz'

        # Check docs files are in archive
        docs_files = [n for n in names if n.startswith('docs/') and n.endswith('.txt')]
        assert len(docs_files) == 4, 'Not all expected docs files are in the archive'
        assert set(docs_files) == set(EXPECTED_DOCS), f'Incorrect docs files in archive: {docs_files}'

        for name, expected_content in EXPECTED_DOCS.items():
            members = tar.getmembers()
            matching = [m for m in members if m.name == name]
            assert len(matching) == 1 and matching[0].isfile(), f'Invalid archive member {name}'
            content = tar.extractfile(matching[0]).read().decode('utf-8')
            assert content == expected_content, f'Incorrect normalized content in archived {name}'

        metadata_name = 'metadata.csv' if 'metadata.csv' in names else './metadata.csv'
        metadata_members = [m for m in tar.getmembers() if m.name == metadata_name]
        assert len(metadata_members) == 1 and metadata_members[0].isfile(), 'Invalid archived metadata.csv'
        archived_lines = [
            line.strip()
            for line in tar.extractfile(metadata_members[0]).read().decode('utf-8').splitlines()
            if line.strip()
        ]
        assert archived_lines == EXPECTED_LINES, 'Archived metadata.csv has incorrect contents'

        # Verify normalization using the original checks.
        for member in tar.getmembers():
            if member.name.startswith('docs/') and member.name.endswith('.txt'):
                f = tar.extractfile(member)
                content = f.read().decode('utf-8')

                assert not re.search(r'%%\s+AUTHOR', content), f'Unnormalized AUTHOR tag found in {member.name}'
                assert not re.search(r'AUTHOR\s+:', content), f'Unnormalized AUTHOR tag found in {member.name}'
                assert not re.search(r':\s+', content[:content.find('%%AUTHOR:')+20] if '%%AUTHOR:' in content else content), f'Unnormalized spaces after colon in {member.name}'

                assert not re.search(r'%%\s+DATE', content), f'Unnormalized DATE tag found in {member.name}'
                assert not re.search(r'DATE\s+:', content), f'Unnormalized DATE tag found in {member.name}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
