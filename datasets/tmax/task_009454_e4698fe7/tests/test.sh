#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import tempfile

def test_summary_file():
    summary_path = '/home/user/summary.txt'
    assert os.path.exists(summary_path), f"Summary file {summary_path} does not exist."
    with open(summary_path, 'r') as f:
        content = f.read().strip()
    assert content == '3', f"Expected summary file to contain '3', but got '{content}'."

def test_clean_data_tarball():
    tarball_path = '/home/user/clean_data.tar.xz'
    assert os.path.exists(tarball_path), f"Tarball {tarball_path} does not exist."
    assert tarfile.is_tarfile(tarball_path), f"File {tarball_path} is not a valid tarball."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(tarball_path, 'r:xz') as tar:
            tar.extractall(path=tmpdir)

        # Determine the extracted directory structure. The instructions say to package the clean_data directory.
        # It could extract to `clean_data/SENSOR_Alpha.csv` or just `SENSOR_Alpha.csv` depending on how it was tarred.
        extracted_files = []
        for root, dirs, files in os.walk(tmpdir):
            for file in files:
                if file.endswith('.csv'):
                    extracted_files.append(os.path.join(root, file))

        # We expect exactly two CSV files
        assert len(extracted_files) == 2, f"Expected exactly 2 CSV files in the tarball, found {len(extracted_files)}."

        alpha_found = False
        beta_found = False

        for file_path in extracted_files:
            filename = os.path.basename(file_path)
            with open(file_path, 'r') as f:
                lines = [line.strip() for line in f.readlines() if line.strip()]

            assert len(lines) > 0, f"File {filename} is empty."
            assert lines[0] == "Date,Time,Sensor,OzoneLevel", f"Incorrect header in {filename}: {lines[0]}"

            data_lines = set(lines[1:])

            if filename == 'SENSOR_Alpha.csv':
                alpha_found = True
                expected_lines = {
                    "2023-01-05,14:00:00,SENSOR_Alpha,155.2",
                    "2023-02-11,12:00:00,SENSOR_Alpha,150.1"
                }
                assert data_lines == expected_lines, f"Incorrect data in {filename}. Expected {expected_lines}, got {data_lines}"
            elif filename == 'SENSOR_Beta.csv':
                beta_found = True
                expected_lines = {
                    "2023-02-10,11:30:00,SENSOR_Beta,160.5"
                }
                assert data_lines == expected_lines, f"Incorrect data in {filename}. Expected {expected_lines}, got {data_lines}"
            else:
                assert False, f"Unexpected file found in tarball: {filename}"

        assert alpha_found, "SENSOR_Alpha.csv not found in the tarball."
        assert beta_found, "SENSOR_Beta.csv not found in the tarball."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
