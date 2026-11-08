#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile

def test_processed_archive_exists():
    processed_path = "/home/user/processed_configs.tar.gz"
    assert os.path.exists(processed_path), f"The file {processed_path} does not exist."
    assert os.path.isfile(processed_path), f"The path {processed_path} is not a file."
    assert tarfile.is_tarfile(processed_path), f"The file {processed_path} is not a valid tar archive."

def test_processed_archive_contents():
    processed_path = "/home/user/processed_configs.tar.gz"

    expected_files = {
        "server_tracked.conf": b"port=8080\n",
        "db_tracked.conf": b"db=mysql\n",
        "celery_tracked.conf": b"workers=4\n"
    }

    header = b"# MANAGED BY CONFIG_TRACKER v2.0\n"

    found_expected = set()

    with tarfile.open(processed_path, "r:gz") as tar:
        members = tar.getmembers()

        # Filter out directories
        files = [m for m in members if m.isfile()]

        assert len(files) == 3, f"Expected exactly 3 files in the archive, found {len(files)}."

        for member in files:
            filename = os.path.basename(member.name)

            assert filename.endswith("_tracked.conf"), f"Found unexpected file in archive: {member.name}"

            # Check file content
            f = tar.extractfile(member)
            assert f is not None, f"Could not extract {member.name}"

            content = f.read()

            # Check header
            assert content.startswith(header), f"File {member.name} does not start with the required header."

            # Check original content
            original_content = content[len(header):]

            if filename in expected_files:
                assert expected_files[filename].strip() == original_content.strip(), \
                    f"Content of {member.name} does not match expected original content."
                found_expected.add(filename)
            else:
                assert False, f"Unexpected tracked conf file found: {filename}"

    assert len(found_expected) == 3, "Not all expected *_tracked.conf files were found in the archive."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
