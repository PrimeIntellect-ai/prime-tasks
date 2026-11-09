#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile

EXPECTED_FILES = {
    "sensor_A.csv": b"timestamp,temp,humidity\n1600000000,20.0,50.0\n1600000060,21.0,55.0\n1600000120,120.0,52.0\n1600000180,23.0,58.0\n1600000240,24.0,\n1600000300,25.0,60.0\n1600000360,26.0,65.0\n1600000420,-60.0,63.0\n1600000480,28.0,68.0\n1600000540,29.0,70.0\n",
    "sensor_B.csv": b"timestamp,pressure,radiation\n1600000000,1010.0,10.0\n1600000060,1005.0,11.0\n1600000120,1008.0,12.0\n1600000180,1002.0,13.0\n1600000240,1000.0,14.0\n1600000300,995.0,15.0\n1600000360,990.0,16.0\n1600000420,992.0,17.0\n1600000480,985.0,18.0\n1600000540,980.0,19.0\n",
}

def test_analysis_env_exists():
    assert os.path.isdir("/home/user/analysis_env"), "Directory /home/user/analysis_env does not exist"

def test_highest_correlation_file():
    filepath = "/home/user/analysis_env/highest_correlation.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist"
    with open(filepath, "r") as f:
        content = f.read().strip()
    assert content == "radiation,temp,0.978", f"Expected 'radiation,temp,0.978', got '{content}'"

def test_storage_archive_exists():
    assert os.path.isdir("/home/user/storage_archive"), "Directory /home/user/storage_archive does not exist"

def test_tarball_exists():
    filepath = "/home/user/storage_archive/raw_data.tar.gz"
    assert os.path.isfile(filepath), f"File {filepath} does not exist"
    assert tarfile.is_tarfile(filepath), f"File {filepath} is not a valid tar archive"
    with tarfile.open(filepath, "r:*") as tar:
        names = tar.getnames()
        assert any("sensor_A.csv" in name for name in names), "sensor_A.csv not found in tarball"
        assert any("sensor_B.csv" in name for name in names), "sensor_B.csv not found in tarball"

        for filename, expected_content in EXPECTED_FILES.items():
            matches = [
                member for member in tar.getmembers()
                if os.path.basename(member.name.rstrip("/")) == filename
            ]
            assert len(matches) == 1, f"Expected exactly one {filename} in tarball"
            member = matches[0]
            assert member.isfile(), f"{filename} in tarball is not a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read {filename} from tarball"
            actual_content = extracted.read()
            assert actual_content == expected_content, f"{filename} in tarball does not preserve the original data"

def test_raw_data_deleted():
    assert not os.path.exists("/home/user/raw_data"), "Directory /home/user/raw_data was not deleted"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
