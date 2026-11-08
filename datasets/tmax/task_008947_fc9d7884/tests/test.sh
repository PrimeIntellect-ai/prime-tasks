#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import gzip
import io
import json
import os
import tarfile

PROJECT = '/home/user/project'
ARCHIVE = '/home/user/legacy_project.tar.gz'
ASSETS = '/home/user/public_html/assets'

ORIGINAL_CONTENTS = {
    'dev_settings.csv': b'key,value\ntheme,dark\nport,8080\n',
    'dev_data.csv': b'id,user\n1,admin\n2,guest\n',
    'dev_background.png': b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...',
    'dev_icon.png': b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...',
}
EXPECTED_LOG = (
    b'INFO: Server started\n'
    b'WARNING: High memory usage\n'
    b'CRITICAL: Database connection lost\n'
    b'INFO: Retrying connection\n'
    b'CRITICAL: Disk full\n'
    b'INFO: Shutting down\n'
)
EXPECTED_ARCHIVE_NAMES = set(ORIGINAL_CONTENTS) | {'dev_server_logs.gz'}


def read_archive():
    assert os.path.isfile(ARCHIVE), f'Archive {ARCHIVE} does not exist.'
    result = {}
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        names = [m.name.lstrip('./') for m in members]
        assert len(names) == len(set(names)), 'Archive contains duplicate file names.'
        assert set(names) == EXPECTED_ARCHIVE_NAMES, 'The source archive was altered.'
        for member, name in zip(members, names):
            stream = tar.extractfile(member)
            assert stream is not None
            result[name] = stream.read()

    for name, expected in ORIGINAL_CONTENTS.items():
        assert result[name] == expected, f'The archived source file {name} was altered.'
    with gzip.GzipFile(fileobj=io.BytesIO(result['dev_server_logs.gz']), mode='rb') as stream:
        assert stream.read() == EXPECTED_LOG, 'The archived log stream was altered.'
    return result


def test_project_directory_exists():
    assert os.path.isdir(PROJECT), 'Directory /home/user/project does not exist.'


def test_files_renamed_no_dev_prefix():
    project_files = os.listdir(PROJECT)
    for f in project_files:
        assert not f.startswith('dev_'), f"File {f} still has the 'dev_' prefix."
    for root, dirs, files in os.walk(PROJECT):
        for name in dirs + files:
            assert not name.startswith('dev_'), f"File {name} still has the 'dev_' prefix."


def test_csv_to_json_conversion():
    settings_json_path = '/home/user/project/settings.json'
    data_json_path = '/home/user/project/data.json'
    assert os.path.isfile(settings_json_path), f'JSON file {settings_json_path} does not exist.'
    assert os.path.isfile(data_json_path), f'JSON file {data_json_path} does not exist.'
    with open(settings_json_path, 'r') as f:
        settings_data = json.load(f)
    expected_settings = [{'key': 'theme', 'value': 'dark'}, {'key': 'port', 'value': '8080'}]
    assert settings_data == expected_settings, f'Contents of {settings_json_path} are incorrect.'
    with open(data_json_path, 'r') as f:
        data_data = json.load(f)
    expected_data = [{'id': '1', 'user': 'admin'}, {'id': '2', 'user': 'guest'}]
    assert data_data == expected_data, f'Contents of {data_json_path} are incorrect.'


def test_csv_files_deleted():
    assert not os.path.exists('/home/user/project/settings.csv'), 'settings.csv was not deleted.'
    assert not os.path.exists('/home/user/project/data.csv'), 'data.csv was not deleted.'
    assert not os.path.exists('/home/user/project/dev_settings.csv'), 'dev_settings.csv was not deleted.'
    assert not os.path.exists('/home/user/project/dev_data.csv'), 'dev_data.csv was not deleted.'
    for root, _, files in os.walk(PROJECT):
        assert not any(name.lower().endswith('.csv') for name in files), 'A CSV file was not converted and deleted.'


def test_critical_errors_extracted():
    errors_path = '/home/user/project/critical_errors.txt'
    assert os.path.isfile(errors_path), f'File {errors_path} does not exist.'
    with open(errors_path, 'r') as f:
        lines = f.read().splitlines()
    expected_lines = ['CRITICAL: Database connection lost', 'CRITICAL: Disk full']
    assert lines == expected_lines, 'critical_errors.txt does not contain the correct CRITICAL lines.'


def test_symlinks_created():
    assert os.path.isdir(ASSETS), f'Directory {ASSETS} does not exist.'
    bg_link = os.path.join(ASSETS, 'background.png')
    icon_link = os.path.join(ASSETS, 'icon.png')
    assert os.path.islink(bg_link), f'{bg_link} is not a symlink.'
    assert os.readlink(bg_link) == '/home/user/project/background.png', f'{bg_link} does not point to the correct absolute path.'
    assert os.path.islink(icon_link), f'{icon_link} is not a symlink.'
    assert os.readlink(icon_link) == '/home/user/project/icon.png', f'{icon_link} does not point to the correct absolute path.'


def test_every_archived_file_was_processed_and_preserved():
    archived = read_archive()

    for archived_name, raw in archived.items():
        renamed = archived_name[4:] if archived_name.startswith('dev_') else archived_name
        source_path = os.path.join(PROJECT, renamed)

        if renamed.endswith('.csv'):
            json_path = os.path.splitext(source_path)[0] + '.json'
            assert os.path.isfile(json_path), f'Missing conversion output {json_path}.'
            expected_rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8'))))
            with open(json_path, encoding='utf-8') as stream:
                actual_rows = json.load(stream)
            assert isinstance(actual_rows, list), f'{json_path} is not a JSON array.'
            assert actual_rows == expected_rows, f'{json_path} was not correctly derived from its CSV.'
            assert not os.path.lexists(source_path), f'{source_path} was not deleted after conversion.'
        else:
            assert os.path.isfile(source_path), f'Extracted source file {source_path} is missing.'
            with open(source_path, 'rb') as stream:
                assert stream.read() == raw, f'{source_path} differs from its archived source.'

    log_path = os.path.join(PROJECT, 'server_logs.gz')
    with gzip.open(log_path, 'rt', encoding='utf-8') as stream:
        expected_critical = [line.rstrip('\r\n') for line in stream if 'CRITICAL' in line]
    with open(os.path.join(PROJECT, 'critical_errors.txt'), encoding='utf-8') as stream:
        assert stream.read().splitlines() == expected_critical

    for name in ('background.png', 'icon.png'):
        target = os.path.join(PROJECT, name)
        link = os.path.join(ASSETS, name)
        assert os.path.isfile(target), f'Symlink target {target} does not exist.'
        assert os.path.islink(link), f'{link} is not a symlink.'
        assert os.path.isabs(os.readlink(link)), f'{link} does not use an absolute target.'
        assert os.readlink(link) == target, f'{link} points to the wrong target.'
        assert os.path.exists(link), f'{link} is a dangling symlink.'
        assert os.path.samefile(link, target), f'{link} does not resolve to {target}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
