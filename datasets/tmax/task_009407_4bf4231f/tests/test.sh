#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import tarfile

def test_staging_csv_files_no_empty_lines():
    """Verify that CSV files in staging exist and have no empty lines."""
    staging_dir = '/home/user/staging'
    expected_files = ['server1.csv', 'server2.csv', 'server3.csv', 'server4.csv']

    for filename in expected_files:
        filepath = os.path.join(staging_dir, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."

        with open(filepath, 'r') as f:
            lines = f.readlines()

        for line in lines:
            assert line.strip() != "", f"Found an empty line in {filepath}."

        if filename in ['server1.csv', 'server2.csv']:
            assert len(lines) == 3, f"Unexpected number of lines in {filepath}."
        elif filename in ['server3.csv', 'server4.csv']:
            assert len(lines) == 2, f"Unexpected number of lines in {filepath}."

def test_json_logs_content():
    """Verify that JSON files are correctly formatted and contain the right data."""
    json_dir = '/home/user/json_logs'
    expected_files = ['server1.json', 'server2.json', 'server3.json', 'server4.json']

    for filename in expected_files:
        filepath = os.path.join(json_dir, filename)
        assert os.path.isfile(filepath), f"JSON file {filepath} is missing."

        with open(filepath, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                assert False, f"File {filepath} does not contain valid JSON."

        assert isinstance(data, list), f"JSON data in {filepath} should be a list."

        if filename in ['server1.json', 'server2.json']:
            expected = [{"time": "100", "event": "start"}, {"time": "101", "event": "stop"}]
            assert data == expected, f"Incorrect JSON content in {filepath}."
        elif filename in ['server3.json', 'server4.json']:
            expected = [{"time": "200", "event": "start"}]
            assert data == expected, f"Incorrect JSON content in {filepath}."

def test_hard_links_deduplication():
    """Verify that identical JSON files are hard-linked together."""
    json_dir = '/home/user/json_logs'
    s1 = os.path.join(json_dir, 'server1.json')
    s2 = os.path.join(json_dir, 'server2.json')
    s3 = os.path.join(json_dir, 'server3.json')
    s4 = os.path.join(json_dir, 'server4.json')

    assert os.path.isfile(s1) and os.path.isfile(s2), "server1.json or server2.json is missing."
    assert os.path.isfile(s3) and os.path.isfile(s4), "server3.json or server4.json is missing."

    ino1 = os.stat(s1).st_ino
    ino2 = os.stat(s2).st_ino
    ino3 = os.stat(s3).st_ino
    ino4 = os.stat(s4).st_ino

    assert ino1 == ino2, "server1.json and server2.json are not hard-linked (different inodes)."
    assert ino3 == ino4, "server3.json and server4.json are not hard-linked (different inodes)."
    assert ino1 != ino3, "server1.json and server3.json should not be hard-linked."

def test_optimized_archive():
    """Verify that the optimized archive exists and contains the JSON files."""
    archive_path = '/home/user/optimized_logs.tar.gz'
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."

    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()
        # The user might have archived the directory itself or the files inside
        # We check if the basenames of the expected files are in the archive
        basenames = [os.path.basename(n) for n in names]
        expected_files = ['server1.json', 'server2.json', 'server3.json', 'server4.json']
        for expected in expected_files:
            assert expected in basenames, f"File {expected} is missing from the archive."

def test_report_content():
    """Verify that the report contains the correct number of unique inodes."""
    report_path = '/home/user/report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as f:
        content = f.read().strip()

    assert content == "2", f"Report file contains '{content}', expected '2'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
