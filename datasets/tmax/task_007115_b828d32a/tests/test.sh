#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import csv


def normalize_path(path):
    return path[2:] if path.startswith('./') else path


def test_high_intensity_csv_exists_and_content():
    """Test that high_intensity.csv exists and contains the correct filtered data."""
    csv_path = '/home/user/high_intensity.csv'
    assert os.path.exists(csv_path), f"The file {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"The path {csv_path} is not a file."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"The file {csv_path} is empty."

    header = rows[0]
    expected_header = ['id', 'timestamp', 'intensity', 'wavelength']
    assert header == expected_header, f"Header is incorrect. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    expected_data = [
        ['2', '1005', '150', '405'],
        ['3', '1010', '200', '410'],
        ['7', '1030', '110', '430']
    ]

    # Sort both to allow any order
    data_rows_sorted = sorted(data_rows)
    expected_data_sorted = sorted(expected_data)

    assert data_rows_sorted == expected_data_sorted, f"Data rows do not match expected filtered data. Got {data_rows_sorted}"


def test_processed_archive_exists_and_contents():
    """Test that the archive contains exactly the required files with preserved contents."""
    archive_path = '/home/user/processed_spectroscopy.tar.gz'
    source_path = '/home/user/datasets/experiments.tar.gz'
    csv_path = '/home/user/high_intensity.csv'

    assert os.path.exists(archive_path), f"The archive {archive_path} does not exist."
    assert os.path.isfile(archive_path), f"The path {archive_path} is not a file."
    assert tarfile.is_tarfile(archive_path), f"The file {archive_path} is not a valid tar archive."

    expected_files = {
        'high_intensity.csv',
        'exp_001/meta.json',
        'exp_004/meta.json'
    }

    with tarfile.open(archive_path, 'r:gz') as tar:
        members = tar.getmembers()
        file_members = [m for m in members if m.isfile()]
        normalized_paths = {normalize_path(m.name) for m in file_members}

        assert normalized_paths == expected_files, f"Archive contents do not match expected. Expected {expected_files}, got {normalized_paths}."
        assert len(file_members) == len(expected_files), "Archive contains duplicate required file entries."

        archived_contents = {}
        for member in file_members:
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file {member.name}."
            archived_contents[normalize_path(member.name)] = extracted.read()

    with open(csv_path, 'rb') as f:
        expected_csv_bytes = f.read()
    assert archived_contents['high_intensity.csv'] == expected_csv_bytes, \
        "The archived high_intensity.csv does not match /home/user/high_intensity.csv."

    source_meta = {}
    with tarfile.open(source_path, 'r:gz') as source_tar:
        for member in source_tar.getmembers():
            normalized = normalize_path(member.name)
            if member.isfile() and normalized in {'exp_001/meta.json', 'exp_004/meta.json'}:
                extracted = source_tar.extractfile(member)
                assert extracted is not None, f"Could not read source file {member.name}."
                source_meta[normalized] = extracted.read()

    assert set(source_meta) == {'exp_001/meta.json', 'exp_004/meta.json'}, \
        "Could not locate the expected metadata files in the source archive."
    assert archived_contents['exp_001/meta.json'] == source_meta['exp_001/meta.json'], \
        "Archived exp_001/meta.json does not preserve the original file contents."
    assert archived_contents['exp_004/meta.json'] == source_meta['exp_004/meta.json'], \
        "Archived exp_004/meta.json does not preserve the original file contents."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
