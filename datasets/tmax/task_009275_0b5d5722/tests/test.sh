#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import tarfile
import zipfile
from pathlib import PurePosixPath

BACKUP = '/home/user/backup.tar.gz'
EXTRACTED = '/home/user/extracted'
EXTRACTED_LOGS = '/home/user/extracted_logs'
TIMESTAMPS = '/home/user/binary_timestamps.txt'
SUMMARY = '/home/user/summary.csv'
REPORT = '/home/user/final_report.tar.gz'


def safe_parts(name):
    path = PurePosixPath(name)
    assert not path.is_absolute(), f'Archive member is absolute: {name}'
    assert '..' not in path.parts, f'Archive member escapes extraction root: {name}'
    return path.parts


def source_data():
    assert os.path.isfile(BACKUP), f'Backup not found: {BACKUP}'
    timestamps = []
    logs_archives = []

    with tarfile.open(BACKUP, 'r:gz') as tar:
        members = tar.getmembers()
        assert members, 'The source backup is empty'

        for member in members:
            parts = safe_parts(member.name)
            destination = os.path.join(EXTRACTED, *parts)

            if member.isdir():
                assert os.path.isdir(destination), f'Archive directory was not extracted: {member.name}'
            elif member.issym():
                assert os.path.lexists(destination), f'Archive symlink was not extracted: {member.name}'
                assert os.path.islink(destination), f'Expected a symlink at: {destination}'
                assert os.readlink(destination) == member.linkname, \
                    f'Symlink target differs for {member.name}'
            elif member.isfile():
                assert os.path.isfile(destination) and not os.path.islink(destination), \
                    f'Archive file was not extracted as a regular file: {member.name}'
                source_bytes = tar.extractfile(member).read()
                with open(destination, 'rb') as extracted_file:
                    assert extracted_file.read() == source_bytes, \
                        f'Extracted content differs for {member.name}'

                if member.name.endswith('.bin') and source_bytes.startswith(b'\xef\xbe\xad\xde') and len(source_bytes) >= 8:
                    timestamps.append(int.from_bytes(source_bytes[4:8], 'little', signed=False))
                if PurePosixPath(member.name).name == 'logs.zip':
                    logs_archives.append(source_bytes)

    assert len(logs_archives) == 1, f'Expected exactly one logs.zip, found {len(logs_archives)}'
    return sorted(timestamps), logs_archives[0]


def expected_errors_and_verify_logs(logs_zip_bytes):
    assert os.path.isdir(EXTRACTED_LOGS), f'Extraction directory not found: {EXTRACTED_LOGS}'
    errors = []

    with zipfile.ZipFile(io.BytesIO(logs_zip_bytes), 'r') as archive:
        for info in archive.infolist():
            parts = safe_parts(info.filename)
            destination = os.path.join(EXTRACTED_LOGS, *parts)
            if info.is_dir():
                assert os.path.isdir(destination), f'Log directory was not extracted: {info.filename}'
                continue

            assert os.path.isfile(destination) and not os.path.islink(destination), \
                f'Log file was not extracted as a regular file: {info.filename}'
            source_bytes = archive.read(info)
            with open(destination, 'rb') as extracted_file:
                assert extracted_file.read() == source_bytes, \
                    f'Extracted log content differs for {info.filename}'

            if info.filename.endswith('.json'):
                records = json.loads(source_bytes.decode('utf-8'))
                assert isinstance(records, list), f'JSON log is not a list: {info.filename}'
                errors.extend((record['id'], record['status']) for record in records
                              if record.get('status') == 'ERROR')

    return sorted(errors, key=lambda item: item[0])


def traversed_timestamps():
    values = []
    for root, dirs, files in os.walk(EXTRACTED, followlinks=False):
        dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(root, name))]
        for name in files:
            if not name.endswith('.bin'):
                continue
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            with open(path, 'rb') as binary_file:
                header = binary_file.read(8)
            if len(header) >= 8 and header[:4] == b'\xef\xbe\xad\xde':
                values.append(int.from_bytes(header[4:8], 'little', signed=False))
    return sorted(values)


def test_required_extractions_and_source_processing():
    assert os.path.isdir(EXTRACTED), f'Extraction directory not found: {EXTRACTED}'
    expected_timestamps, logs_zip_bytes = source_data()
    assert traversed_timestamps() == expected_timestamps, \
        'Extracted binary files do not produce the timestamps found in the source backup'
    expected_errors_and_verify_logs(logs_zip_bytes)


def test_binary_timestamps_content():
    expected_timestamps, _ = source_data()
    assert os.path.isfile(TIMESTAMPS), f'File not found: {TIMESTAMPS}'

    with open(TIMESTAMPS, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ['100', '200']
    assert lines == expected, f'Expected {expected} in {TIMESTAMPS}, but got {lines}'
    derived = [str(value) for value in expected_timestamps]
    assert lines == derived, f'Timestamps do not match the valid binaries in {BACKUP}'


def test_summary_csv_content():
    _, logs_zip_bytes = source_data()
    errors = expected_errors_and_verify_logs(logs_zip_bytes)
    assert os.path.isfile(SUMMARY), f'File not found: {SUMMARY}'

    with open(SUMMARY, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        'id,status',
        '101,ERROR',
        '105,ERROR',
        '108,ERROR'
    ]
    assert lines == expected, f'Expected {expected} in {SUMMARY}, but got {lines}'
    derived = ['id,status'] + [f'{record_id},{status}' for record_id, status in errors]
    assert lines == derived, f'Summary does not match ERROR records in the extracted logs'


def test_final_report_tar_gz():
    assert os.path.isfile(REPORT), f'Archive not found: {REPORT}'

    try:
        with tarfile.open(REPORT, 'r:gz') as tar:
            members = tar.getnames()
            expected_members = {'summary.csv', 'binary_timestamps.txt'}
            assert set(members) == expected_members, \
                f'Archive {REPORT} must contain exactly {expected_members} at the root, but got {members}'
            assert len(members) == 2, 'Final report must not contain duplicate archive members'

            for name, source_path in [('summary.csv', SUMMARY),
                                      ('binary_timestamps.txt', TIMESTAMPS)]:
                member = tar.getmember(name)
                assert member.isfile(), f'{name} must be a regular file in the final report'
                archived_bytes = tar.extractfile(member).read()
                with open(source_path, 'rb') as source_file:
                    assert archived_bytes == source_file.read(), \
                        f'Archived {name} does not contain the validated output file content'
    except tarfile.ReadError:
        assert False, f'Failed to read {REPORT} as a tar.gz archive'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
