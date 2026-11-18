#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile

def test_anomalies_csv_contents():
    csv_path = "/home/user/data/anomalies.csv"
    assert os.path.isfile(csv_path), f"Expected file {csv_path} does not exist."

    expected_content = [
        "station,temp",
        "ST-A1,43.0",
        "ST-A1,41.2",
        "ST-A2,40.0",
        "ST-B1,42.5",
        "ST-C1,45.1",
        "ST-C2,40.5"
    ]

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_content, f"Content of {csv_path} does not match expected output. Got: {lines}"

def test_anomalies_tar_gz():
    tar_path = "/home/user/data/anomalies.tar.gz"
    csv_path = "/home/user/data/anomalies.csv"
    assert os.path.isfile(tar_path), f"Expected file {tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"File {tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as tar:
        names = tar.getnames()
        assert names == ["anomalies.csv"], f"Archive should contain exactly 'anomalies.csv' (no nested directories). Got: {names}"
        member = tar.getmember("anomalies.csv")
        assert member.isfile(), "The anomalies.csv archive member must be a regular file."
        archived_file = tar.extractfile(member)
        assert archived_file is not None, "Could not read anomalies.csv from the archive."
        archived_content = archived_file.read()

    with open(csv_path, "rb") as f:
        expected_archived_content = f.read()

    assert archived_content == expected_archived_content, "The archived anomalies.csv does not match /home/user/data/anomalies.csv."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
