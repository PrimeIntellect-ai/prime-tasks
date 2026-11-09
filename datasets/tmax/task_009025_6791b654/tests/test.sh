#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import zipfile
import pytest

def test_organized_directory_and_files():
    organized_dir = '/home/user/organized'
    assert os.path.isdir(organized_dir), f"Directory {organized_dir} does not exist."

    files = sorted(os.listdir(organized_dir))
    expected_files = ['fileA.txt', 'fileB.txt', 'fileC.txt']
    assert files == expected_files, f"Expected files {expected_files} in {organized_dir}, but found {files}."

def test_file_contents():
    expected_contents = {
        'fileA.txt': "Database_Host=localhost\nDatabase_Port=5432\n",
        'fileB.txt': "API_Key=xyz123abc\nAPI_Endpoint=https://api.example.com/v1\n",
        'fileC.txt': "Project_Name=SuperNova\nProject_Version=1.0.4\n"
    }

    for filename, expected_text in expected_contents.items():
        filepath = os.path.join('/home/user/organized', filename)
        with open(filepath, 'r') as f:
            content = f.read()
            assert content.strip() == expected_text.strip(), f"Content of {filename} is incorrect."

def test_zip_file_exists_and_contents():
    zip_path = '/home/user/organized_files.zip'
    assert os.path.isfile(zip_path), f"Zip file {zip_path} does not exist."

    with zipfile.ZipFile(zip_path, 'r') as z:
        zip_files = sorted(z.namelist())
        expected_files = ['fileA.txt', 'fileB.txt', 'fileC.txt']
        assert zip_files == expected_files, f"Zip file should contain exactly {expected_files} at the root, but contains {zip_files}."

        expected_contents = {
            'fileA.txt': "Database_Host=localhost\nDatabase_Port=5432\n",
            'fileB.txt': "API_Key=xyz123abc\nAPI_Endpoint=https://api.example.com/v1\n",
            'fileC.txt': "Project_Name=SuperNova\nProject_Version=1.0.4\n"
        }

        for filename, expected_text in expected_contents.items():
            with z.open(filename) as f:
                content = f.read().decode('utf-8')
                assert content.strip() == expected_text.strip(), f"Content of {filename} inside zip is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
