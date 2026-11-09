#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import difflib
import tarfile
import pytest

EXPECTED_CONTENT = {
    'network_config.conf': 'network configuration data: café\n',
    'database_schema.sql': 'CREATE TABLE users (id INT); -- propriétaire\n',
    'legacy_handlers.py': "def legacy_handler(): return 'olá'\n",
}

def test_transcription_similarity():
    memo_path = '/home/user/memo.txt'
    assert os.path.exists(memo_path), f"Transcription file {memo_path} not found."

    with open(memo_path, 'r', encoding='utf-8') as f:
        agent_transcript = f.read().strip().lower()

    ground_truth = "Please prepare the following files for the client delivery: network_config.conf, database_schema.sql, and legacy_handlers.py. Make sure they are converted properly.".lower()

    similarity = difflib.SequenceMatcher(None, agent_transcript, ground_truth).ratio()
    assert similarity >= 0.85, f"Transcription similarity {similarity:.2f} is below the threshold of 0.85."

def test_files_converted_to_utf8():
    expected_files = ['network_config.conf', 'database_schema.sql', 'legacy_handlers.py']
    for filename in expected_files:
        filepath = os.path.join('/home/user/project_raw', filename)
        assert os.path.exists(filepath), f"File {filepath} not found."

        # Check if it can be read as UTF-8
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {filepath} is not properly converted to UTF-8.")

        assert content == EXPECTED_CONTENT[filename], f"Contents of {filepath} were not preserved during conversion."
        with open(filepath, 'rb') as f:
            assert f.read() == EXPECTED_CONTENT[filename].encode('utf-8'), f"File {filepath} is not encoded as the expected UTF-8 bytes."

    # Files not named in the memo must remain untouched.
    assert open('/home/user/project_raw/dummy_file_1.txt', 'rb').read() == b'dummy data 1\n'
    assert open('/home/user/project_raw/old_notes.md', 'rb').read() == b'dummy data 2\n'

def test_staging_directory_and_symlinks():
    staging_dir = '/home/user/staging'
    assert os.path.isdir(staging_dir), f"Staging directory {staging_dir} not found."

    expected_files = ['network_config.conf', 'database_schema.sql', 'legacy_handlers.py']
    for filename in expected_files:
        link_path = os.path.join(staging_dir, filename)
        assert os.path.exists(link_path), f"Symlink {link_path} not found."
        assert os.path.islink(link_path), f"Path {link_path} is not a symlink."

        target_path = os.readlink(link_path)
        expected_target = os.path.join('/home/user/project_raw', filename)
        # Handle relative or absolute symlinks
        if not os.path.isabs(target_path):
            target_path = os.path.normpath(os.path.join(staging_dir, target_path))
        assert target_path == expected_target, f"Symlink {link_path} points to {target_path}, expected {expected_target}."

def test_tarball_archive():
    tarball_path = '/home/user/delivery.tar.gz'
    assert os.path.exists(tarball_path), f"Archive {tarball_path} not found."
    assert tarfile.is_tarfile(tarball_path), f"File {tarball_path} is not a valid tar archive."

    expected_files = {'network_config.conf', 'database_schema.sql', 'legacy_handlers.py'}

    try:
        with tarfile.open(tarball_path, 'r:gz') as tar:
            relevant = [m for m in tar.getmembers() if m.isfile() or m.issym()]
            members = [os.path.basename(m.name) for m in relevant]
            assert expected_files.issubset(set(members)), f"Archive does not contain all expected files. Found: {members}"

            for filename in expected_files:
                matches = [m for m in relevant if os.path.basename(m.name) == filename]
                assert len(matches) == 1, f"Archive must contain exactly one entry for {filename}."
                member = matches[0]
                if member.issym():
                    target_path = member.linkname
                    if not os.path.isabs(target_path):
                        target_path = os.path.normpath(os.path.join('/home/user/staging', target_path))
                    expected_target = os.path.join('/home/user/project_raw', filename)
                    assert target_path == expected_target, f"Archived symlink {filename} points to {target_path}, expected {expected_target}."
                else:
                    archived_data = tar.extractfile(member).read()
                    assert archived_data == EXPECTED_CONTENT[filename].encode('utf-8'), f"Archived file {filename} does not contain the converted content."
    except Exception as e:
        pytest.fail(f"Failed to read tar archive {tarball_path}: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
