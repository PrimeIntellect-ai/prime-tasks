#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

WATERMARK_RE = re.compile(r'\[DRAFT_WATERMARK_[0-9]+\]')


def expected_cleaned_documents():
    expected = {}
    for archive in sorted(glob.glob('/home/user/docs_raw/*.tar.gz')):
        with tarfile.open(archive, 'r:gz') as tf:
            for member in tf.getmembers():
                if member.isfile() and member.name.endswith('.md'):
                    extracted = tf.extractfile(member)
                    assert extracted is not None
                    name = os.path.basename(member.name)
                    assert name not in expected, f'Duplicate Markdown filename in source archives: {name}'
                    source = extracted.read().decode('utf-8')
                    expected[name] = WATERMARK_RE.sub('', source)
    return expected


def test_docs_cleaned_exists_and_watermarks_removed():
    cleaned_dir = '/home/user/docs_cleaned'
    assert os.path.isdir(cleaned_dir), f'Directory {cleaned_dir} does not exist'

    expected_files = ['docA.md', 'docB.md']
    derived_expected = expected_cleaned_documents()
    assert set(expected_files) == set(derived_expected)

    for f in expected_files:
        filepath = os.path.join(cleaned_dir, f)
        assert os.path.isfile(filepath), f'File {filepath} is missing'

        with open(filepath, 'r', encoding='utf-8') as file:
            content = file.read()
            assert not WATERMARK_RE.search(content), f'Watermark found in {filepath}'
            assert content == derived_expected[f], f'{filepath} is not the correctly transformed source document'


def test_extractor_go_exists():
    go_file = '/home/user/extractor.go'
    assert os.path.isfile(go_file), f'Go program {go_file} does not exist'


def test_compiled_config_json():
    json_file = '/home/user/compiled_config.json'
    assert os.path.isfile(json_file), f'JSON file {json_file} does not exist'

    with open(json_file, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{json_file} is not valid JSON')

    expected_data = {
        'endpoint': 'https://api.example.com/v1',
        'timeout': '30s',
        'retry_count': '5',
        'backoff_multiplier': '1.5'
    }

    stringified_data = {k: str(v).strip() for k, v in data.items()}
    for key, value in expected_data.items():
        assert key in stringified_data, f"Key '{key}' missing from compiled JSON"
        assert stringified_data[key] == value, f"Value for '{key}' is incorrect. Expected '{value}', got '{stringified_data[key]}'"


def test_final_docs_zip():
    zip_path = '/home/user/final_docs.zip'
    assert os.path.isfile(zip_path), f'Zip file {zip_path} does not exist'

    with zipfile.ZipFile(zip_path, 'r') as zf:
        namelist = zf.namelist()
        expected_files = {'docA.md', 'docB.md', 'compiled_config.json'}
        actual_files = set(namelist)

        assert expected_files.issubset(actual_files), f'Zip file is missing expected files. Found: {actual_files}'

        for f in actual_files:
            assert '/' not in f and '\\' not in f, f'File {f} is not at the root of the zip archive'

        for md_file in ['docA.md', 'docB.md']:
            if md_file in actual_files:
                content = zf.read(md_file).decode('utf-8')
                assert not WATERMARK_RE.search(content), f'Watermark found in zipped {md_file}'
                with open(os.path.join('/home/user/docs_cleaned', md_file), 'r', encoding='utf-8') as disk_file:
                    assert content == disk_file.read(), f'Zipped {md_file} does not match the cleaned document'

        with open('/home/user/compiled_config.json', 'rb') as disk_json:
            assert zf.read('compiled_config.json') == disk_json.read(), 'Zipped JSON does not match compiled_config.json'


def test_go_extractor_executes_and_derives_config_from_rules_and_documents():
    docs_dir = '/home/user/docs_cleaned'
    rules_path = '/home/user/doc_rules.ini'
    output_path = '/home/user/compiled_config.json'

    backup_root = tempfile.mkdtemp(prefix='extractor-verifier-')
    backup_docs = os.path.join(backup_root, 'docs_cleaned')
    backup_rules = os.path.join(backup_root, 'doc_rules.ini')
    backup_output = os.path.join(backup_root, 'compiled_config.json')
    shutil.copytree(docs_dir, backup_docs)
    shutil.copy2(rules_path, backup_rules)
    shutil.copy2(output_path, backup_output)

    token = secrets.token_hex(12)
    start_marker = f'@@ BEGIN {token} @@'
    end_marker = f'@@ END {token} @@'
    key_a = f'host_{token}'
    key_b = f'limit_{token}'
    key_c = f'mode_{token}'
    expected = {
        key_a: f'https://dynamic.invalid/{token}:8443/path',
        key_b: str(int(token[:6], 16)),
        key_c: f'active-{token}'
    }

    try:
        shutil.rmtree(docs_dir)
        os.makedirs(docs_dir)
        with open(rules_path, 'w', encoding='utf-8') as f:
            f.write('[extraction]\n')
            f.write(f'start_marker = {start_marker}\n')
            f.write(f'end_marker = {end_marker}\n')

        with open(os.path.join(docs_dir, 'dynamic_one.md'), 'w', encoding='utf-8') as f:
            f.write(f'outside_key: must_not_be_in_json\n{start_marker}\n')
            f.write(f'{key_a}: {expected[key_a]}\n{key_b}: {expected[key_b]}\n')
            f.write(f'{end_marker}\nafter_key: also_must_not_be_in_json\n')

        with open(os.path.join(docs_dir, 'dynamic_two.md'), 'w', encoding='utf-8') as f:
            f.write(f'Introduction\n{start_marker}\n{key_c}: {expected[key_c]}\n{end_marker}\n')

        with open(os.path.join(docs_dir, 'ignored.txt'), 'w', encoding='utf-8') as f:
            f.write(f'{start_marker}\nignored_key: ignored_value\n{end_marker}\n')

        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            ['go', 'run', '/home/user/extractor.go'],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
        )
        assert result.returncode == 0, f'Go extractor failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        assert os.path.isfile(output_path), 'Executing extractor.go did not create compiled_config.json'

        with open(output_path, 'r', encoding='utf-8') as f:
            try:
                produced = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f'Extractor produced invalid JSON: {exc}')

        normalized = {str(k): str(v).strip() for k, v in produced.items()}
        assert normalized == expected, f'Extractor did not derive the expected dynamic configuration: {normalized}'
    finally:
        if os.path.exists(docs_dir):
            shutil.rmtree(docs_dir)
        shutil.copytree(backup_docs, docs_dir)
        shutil.copy2(backup_rules, rules_path)
        shutil.copy2(backup_output, output_path)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
