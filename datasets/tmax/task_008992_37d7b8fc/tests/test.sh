#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile

def test_processed_logs_csv_content():
    csv_path = "/home/user/processed_logs.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    expected_content = (
        "timestamp,level,message\n"
        "2023-01-01T12:00:00Z,INFO,System booted successfully.\n"
        "2023-01-01T12:05:00Z,ERROR,Timeout[ x4]occured[!x3]\n"
        "2023-01-01T12:10:00Z,WARN,Disk space l[ox4]w\n"
        "2023-01-01T12:15:00Z,INFO,All good now.\n"
    )

    with open(csv_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Contents of {csv_path} do not match expected.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )

def test_optimized_logs_tar_gz():
    tar_path = "/home/user/optimized_logs.tar.gz"
    assert os.path.isfile(tar_path), f"File {tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"File {tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as t:
        names = t.getnames()
        assert len(names) == 1, f"Expected exactly 1 file in {tar_path}, found {len(names)}: {names}"
        assert names[0] == "processed_logs.csv", f"Expected file 'processed_logs.csv' in archive, found {names[0]}"

        # Verify the content inside the tarball matches the expected as well
        f = t.extractfile("processed_logs.csv")
        assert f is not None, "Could not extract processed_logs.csv from archive."

        content = f.read().decode("utf-8")
        expected_content = (
            "timestamp,level,message\n"
            "2023-01-01T12:00:00Z,INFO,System booted successfully.\n"
            "2023-01-01T12:05:00Z,ERROR,Timeout[ x4]occured[!x3]\n"
            "2023-01-01T12:10:00Z,WARN,Disk space l[ox4]w\n"
            "2023-01-01T12:15:00Z,INFO,All good now.\n"
        )
        assert content.strip() == expected_content.strip(), "Contents of processed_logs.csv inside tarball do not match expected."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
