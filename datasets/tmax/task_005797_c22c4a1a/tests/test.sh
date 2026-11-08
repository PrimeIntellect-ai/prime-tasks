#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import xml.etree.ElementTree as ET

BASE_DIR = '/home/user/project_logs'
SUMMARY_CSV = '/home/user/split_summary.csv'

# Immutable facts from the original task setup. These prevent submissions from
# shrinking or deleting the inputs and then generating self-consistent output.
ORIGINAL_MODULES = {
    'auth': {'lines': 250, 'chunk_size': 100},
    'payment': {'lines': 120, 'chunk_size': 50},
    'inventory': {'lines': 400, 'chunk_size': 500},
    'notifications': {'lines': 30, 'chunk_size': 10},
}


def get_module_info():
    modules = {}
    if not os.path.exists(BASE_DIR):
        return modules

    for mod in os.listdir(BASE_DIR):
        mod_dir = os.path.join(BASE_DIR, mod)
        if not os.path.isdir(mod_dir):
            continue

        settings_path = os.path.join(mod_dir, 'settings.xml')
        data_path = os.path.join(mod_dir, 'data.jsonl')

        if not os.path.exists(settings_path) or not os.path.exists(data_path):
            continue

        tree = ET.parse(settings_path)
        chunk_lines = int(tree.getroot().find('chunk_lines').text)

        with open(data_path, 'r') as f:
            total_lines = sum(1 for _ in f)

        num_chunks = math.ceil(total_lines / chunk_lines) if chunk_lines > 0 else 0

        modules[mod] = {
            'total_lines': total_lines,
            'chunk_size': chunk_lines,
            'num_chunks': num_chunks,
            'mod_dir': mod_dir,
            'data_path': data_path,
        }
    return modules


def test_original_inputs_are_present_and_unchanged():
    assert os.path.isdir(BASE_DIR), f'Missing project directory: {BASE_DIR}'

    for mod, expected in ORIGINAL_MODULES.items():
        mod_dir = os.path.join(BASE_DIR, mod)
        settings_path = os.path.join(mod_dir, 'settings.xml')
        data_path = os.path.join(mod_dir, 'data.jsonl')

        assert os.path.isdir(mod_dir), f'Missing original module directory: {mod_dir}'
        assert os.path.isfile(settings_path), f'Missing settings.xml for original module {mod}'
        assert os.path.isfile(data_path), f'Missing data.jsonl for original module {mod}'

        root = ET.parse(settings_path).getroot()
        assert root.tag == 'config', f'Incorrect XML root for module {mod}'
        element = root.find('chunk_lines')
        assert element is not None, f'Missing chunk_lines for module {mod}'
        assert int(element.text) == expected['chunk_size'], \
            f'Original chunk size was changed for module {mod}'

        expected_lines = [
            json.dumps({'id': i, 'module': mod, 'status': 'ok'}) + '\n'
            for i in range(expected['lines'])
        ]
        with open(data_path, 'r') as f:
            actual_lines = f.readlines()
        assert actual_lines == expected_lines, \
            f'Original data.jsonl was changed or truncated for module {mod}'


def test_summary_csv_exists_and_correct():
    assert os.path.isfile(SUMMARY_CSV), f'Summary CSV not found at {SUMMARY_CSV}'

    modules = get_module_info()
    for mod in ORIGINAL_MODULES:
        assert mod in modules, f'Original module missing from processing: {mod}'

    expected_rows = []
    for mod in sorted(modules.keys()):
        info = modules[mod]
        expected_rows.append([
            mod,
            str(info['total_lines']),
            str(info['chunk_size']),
            str(info['num_chunks']),
        ])

    with open(SUMMARY_CSV, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, 'Summary CSV is empty.'

    header = rows[0]
    expected_header = ['module_dir_name', 'total_lines', 'chunk_size', 'num_chunks']
    assert header == expected_header, \
        f'CSV header incorrect. Expected {expected_header}, got {header}'

    data_rows = rows[1:]
    assert data_rows == expected_rows, \
        f'CSV data rows incorrect. Expected {expected_rows}, got {data_rows}'


def test_chunk_files_created_correctly():
    modules = get_module_info()
    assert len(modules) > 0, 'No valid modules found to test.'
    for mod in ORIGINAL_MODULES:
        assert mod in modules, f'Original module missing from processing: {mod}'

    for mod, info in modules.items():
        mod_dir = info['mod_dir']
        chunk_size = info['chunk_size']
        total_lines = info['total_lines']
        num_chunks = info['num_chunks']

        with open(info['data_path'], 'r') as f:
            original_lines = f.readlines()

        reconstructed_lines = []

        for i in range(num_chunks):
            chunk_file = os.path.join(mod_dir, f'data_chunk_{i}.jsonl')
            assert os.path.isfile(chunk_file), f'Expected chunk file missing: {chunk_file}'

            with open(chunk_file, 'r') as f:
                chunk_lines = f.readlines()

            reconstructed_lines.extend(chunk_lines)

            expected_chunk_length = (
                chunk_size if i < num_chunks - 1
                else total_lines - (num_chunks - 1) * chunk_size
            )
            assert len(chunk_lines) == expected_chunk_length, \
                f'Chunk file {chunk_file} has {len(chunk_lines)} lines, expected {expected_chunk_length}'

        assert reconstructed_lines == original_lines, \
            f'Reconstructed lines from chunks do not match original data.jsonl for module {mod}'

        extra_chunk = os.path.join(mod_dir, f'data_chunk_{num_chunks}.jsonl')
        assert not os.path.exists(extra_chunk), f'Extra chunk file found: {extra_chunk}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
