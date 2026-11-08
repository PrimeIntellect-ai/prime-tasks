#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import json
import os
import tarfile
import pytest

EXPECTED_CONFIGS = {
    "db_config.json": b'{"db": "mysql", "host": "localhost"}\n',
    "cache_config.json": b'{"cache": "redis", "ttl": 3600}\n',
}


def test_clean_configs_extracted():
    clean_configs_dir = "/home/user/clean_configs/"
    assert os.path.isdir(clean_configs_dir), f"Directory {clean_configs_dir} is missing"

    files = set(os.listdir(clean_configs_dir))
    expected_files = {"db_config.json", "cache_config.json"}

    assert files == expected_files, f"Expected exactly {expected_files} in {clean_configs_dir}, but found {files}"

    # Check contents of the configs to ensure they are the correct ones
    with open(os.path.join(clean_configs_dir, "db_config.json"), "r") as f:
        db_config = json.load(f)
        assert db_config.get("db") == "mysql", "db_config.json content is incorrect"

    with open(os.path.join(clean_configs_dir, "cache_config.json"), "r") as f:
        cache_config = json.load(f)
        assert cache_config.get("cache") == "redis", "cache_config.json content is incorrect"

    # The extracted files must be complete copies, not minimal fabricated JSON.
    for name, expected_content in EXPECTED_CONFIGS.items():
        path = os.path.join(clean_configs_dir, name)
        with open(path, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, (
            f"{name} does not exactly match the config from the valid backup"
        )


def test_critical_errors_log():
    log_path = "/home/user/critical_errors.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "CRITICAL: Database connection lost in app1",
        "CRITICAL: Out of memory in sys"
    ]

    # The instructions require the file to be sorted alphabetically
    expected_sorted = sorted(expected_lines)

    assert lines == expected_sorted, f"Expected sorted lines in {log_path}:\n{expected_sorted}\nBut got:\n{lines}"


def test_consolidated_configs_archive():
    archive_path = "/home/user/consolidated_configs.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing"

    try:
        # Read the complete gzip stream so its trailer and CRC are validated.
        with gzip.open(archive_path, "rb") as gz:
            tar_data = gz.read()
        with tarfile.open(fileobj=io.BytesIO(tar_data), mode="r:") as tar:
            members = tar.getnames()
            member_objects = tar.getmembers()

            # The files should be at the root of the tarball (no directories)
            expected_members = {"db_config.json", "cache_config.json"}
            assert set(members) == expected_members, f"Expected exactly {expected_members} at the root of {archive_path}, but found {set(members)}"
            assert len(members) == len(expected_members), "Archive contains duplicate members"

            for member in member_objects:
                assert member.isfile(), f"Archive member {member.name} is not a regular file"
                assert os.path.basename(member.name) == member.name, (
                    f"Archive member {member.name} is not at the archive root"
                )
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archive member {member.name}"
                archived_content = extracted.read()
                assert archived_content == EXPECTED_CONFIGS[member.name], (
                    f"Archived content of {member.name} is incorrect"
                )

                with open(os.path.join("/home/user/clean_configs", member.name), "rb") as f:
                    disk_content = f.read()
                assert archived_content == disk_content, (
                    f"Archived content of {member.name} differs from the extracted file"
                )
    except AssertionError:
        raise
    except Exception as e:
        pytest.fail(f"Failed to open or fully validate {archive_path} as a tar.gz file: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
