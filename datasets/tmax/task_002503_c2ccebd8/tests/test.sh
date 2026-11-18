#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import stat

RAW_LOG = '/home/user/raw_data/experiments.log'
PROCESSED_DIR = '/home/user/processed_data'
BY_STATUS_DIR = '/home/user/by_status'


def load_expected_records():
    with open(RAW_LOG, 'r') as f:
        source = f.read()

    records = re.findall(r'=== RUN START ===\n.*?=== RUN END ===', source, flags=re.DOTALL)
    assert len(records) == 100, f"Expected 100 source records, found {len(records)}."

    expected = {}
    for record in records:
        run_match = re.search(r'^RunID: (.+)$', record, flags=re.MULTILINE)
        status_match = re.search(r'^Status: (.+)$', record, flags=re.MULTILINE)
        assert run_match, "Source record is missing RunID."
        assert status_match, "Source record is missing Status."

        run_id = run_match.group(1)
        original_status = status_match.group(1)
        assert run_id not in expected, f"Duplicate RunID in source: {run_id}"

        if original_status == 'OK':
            normalized_status = 'SUCCESS'
        elif original_status.startswith('ERROR-'):
            normalized_status = 'FAILED'
        elif original_status in ('SUCCESS', 'FAILED'):
            normalized_status = original_status
        else:
            raise AssertionError(f"Unexpected source status for {run_id}: {original_status}")

        normalized_record = (
            record[:status_match.start(1)]
            + normalized_status
            + record[status_match.end(1):]
        )
        expected[run_id] = (normalized_status, normalized_record)

    return expected


def test_processed_data_files():
    processed_dir = '/home/user/processed_data'
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    processed_files = glob.glob(os.path.join(processed_dir, 'EXP-*.txt'))
    assert len(processed_files) == 100, f"Expected exactly 100 processed files, found {len(processed_files)}."

    for i in range(1, 101):
        expected_file = os.path.join(processed_dir, f"EXP-{i:05d}.txt")
        assert os.path.exists(expected_file), f"Expected processed file {expected_file} is missing."


def test_status_directories():
    by_status_dir = '/home/user/by_status'
    assert os.path.isdir(by_status_dir), f"Directory {by_status_dir} does not exist."

    status_dirs = os.listdir(by_status_dir)
    assert set(status_dirs) == {'SUCCESS', 'FAILED'}, f"Expected exactly SUCCESS and FAILED directories, found: {status_dirs}"


def test_symlinks_and_content():
    success_links = glob.glob('/home/user/by_status/SUCCESS/EXP-*.txt')
    failed_links = glob.glob('/home/user/by_status/FAILED/EXP-*.txt')

    assert len(success_links) + len(failed_links) == 100, f"Total symlinks should be 100, found {len(success_links) + len(failed_links)}."

    for link in success_links + failed_links:
        assert os.path.islink(link), f"Expected {link} to be a symbolic link."

        target = os.readlink(link)
        assert target.startswith('/home/user/processed_data/'), f"Symlink {link} does not point to an absolute path in /home/user/processed_data/. Target: {target}"

        assert os.path.exists(link), f"Symlink {link} is broken."

        with open(link, 'r') as f:
            content = f.read()

        assert "=== RUN START ===" in content, f"File {link} missing RUN START marker."
        assert "=== RUN END ===" in content, f"File {link} missing RUN END marker."

        if "SUCCESS" in link:
            assert "Status: SUCCESS\n" in content, f"File {link} should contain 'Status: SUCCESS'."
            assert "Status: OK\n" not in content, f"File {link} still contains unnormalized 'Status: OK'."
        elif "FAILED" in link:
            assert "Status: FAILED\n" in content, f"File {link} should contain 'Status: FAILED'."
            assert "Status: ERROR" not in content, f"File {link} still contains unnormalized 'ERROR' status."


def test_outputs_match_source_records():
    expected = load_expected_records()
    assert set(expected) == {f'EXP-{i:05d}' for i in range(1, 101)}

    for run_id, (normalized_status, normalized_record) in expected.items():
        processed_path = os.path.join(PROCESSED_DIR, f'{run_id}.txt')
        assert os.path.lexists(processed_path), f"Missing processed output for {run_id}."
        assert not os.path.islink(processed_path), f"Processed output must be a physical file: {processed_path}"
        assert stat.S_ISREG(os.stat(processed_path).st_mode), f"Processed output is not a regular file: {processed_path}"

        with open(processed_path, 'r') as f:
            actual = f.read()
        assert actual in (normalized_record, normalized_record + '\n'), \
            f"Processed file {processed_path} does not match its normalized source record."

        link_path = os.path.join(BY_STATUS_DIR, normalized_status, f'{run_id}.txt')
        assert os.path.islink(link_path), f"Missing status symlink for {run_id}: {link_path}"
        expected_target = os.path.join(PROCESSED_DIR, f'{run_id}.txt')
        actual_target = os.readlink(link_path)
        assert actual_target == expected_target, \
            f"Symlink {link_path} should point to {expected_target}, found {actual_target}."
        assert os.path.exists(link_path), f"Symlink {link_path} is broken."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
