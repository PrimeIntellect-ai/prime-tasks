#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest

EXPECTED_ARCHIVED_FILES = {
    'events/log_a.csv': (
        b'u1,click,100,1620000000\n'
        b'u2,view,,1620000001\n'
        b'u1,scroll,200,1620000002\n'
        b'u3,click,-50,1620000003\n'
        b'u5,scroll,4000,1620000010\n'
    ),
    'events/log_b.csv': (
        b'u2,click,150,1620000004\n'
        b'u3,view,6000,1620000005\n'
        b'u1,click,50,1620000006\n'
        b'u4,view,0,1620000007\n'
        b'u5,click,1000,1620000011\n'
    ),
}

def test_events_directory_removed():
    assert not os.path.exists('/home/user/events'), "The directory /home/user/events/ should have been deleted."

def test_archive_exists_and_valid():
    archive_path = '/home/user/events_archive.tar.gz'
    assert os.path.isfile(archive_path), f"The archive {archive_path} should exist."

    # Check if it's a valid tar.gz file and contains the events directory.
    try:
        with tarfile.open(archive_path, 'r:gz') as tar:
            names = tar.getnames()
            assert any(name.startswith('events') for name in names), "The archive must contain the 'events' directory."

            # Both original CSV files must be present exactly once as regular files,
            # with their original unmodified contents.
            members = tar.getmembers()
            for expected_name, expected_content in EXPECTED_ARCHIVED_FILES.items():
                matching = [member for member in members if member.name == expected_name]
                assert len(matching) == 1, (
                    f"The archive must contain exactly one {expected_name}."
                )
                member = matching[0]
                assert member.isfile(), f"{expected_name} must be a regular file in the archive."
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read {expected_name} from the archive."
                assert extracted.read() == expected_content, (
                    f"The archived contents of {expected_name} do not match the original log."
                )
    except (tarfile.ReadError, EOFError, OSError):
        pytest.fail(f"The file {archive_path} is not a valid gzip-compressed tarball.")

def test_user_durations_content():
    output_path = '/home/user/user_durations.csv'
    assert os.path.isfile(output_path), f"The output file {output_path} should exist."

    expected_lines = [
        "u5,5000",
        "u1,350",
        "u2,150",
        "u4,0"
    ]

    with open(output_path, 'r') as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {output_path} is incorrect. "
        f"Expected:\n{chr(10).join(expected_lines)}\nActual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
