#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_storage_optimizer.py
import ast
import fcntl
import json
import os
import subprocess
import tempfile
import time

import pytest
import yaml


def test_report_exists_and_content():
    report_path = '/home/user/optimizer_report.json'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r', encoding='utf-8') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} is not valid JSON.")

    assert report.get('total_files_processed') == 5, "total_files_processed should be 5."
    assert report.get('csv_to_json_conversions') == 2, "csv_to_json_conversions should be 2."
    assert report.get('hard_links_created') == 2, "hard_links_created should be 2."


def test_csv_files_deleted():
    assert not os.path.exists('/home/user/logs/appA/log1.csv'), "log1.csv should have been deleted."
    assert not os.path.exists('/home/user/logs/appA/log3.csv'), "log3.csv should have been deleted."


def test_json_files_exist_and_utf8():
    expected_files = [
        '/home/user/logs/appA/log1.json',
        '/home/user/logs/appB/log2.json',
        '/home/user/logs/appA/log3.json',
        '/home/user/logs/appB/log4.json',
        '/home/user/logs/appA/log5.json'
    ]

    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Expected JSON file {file_path} is missing."
        with open(file_path, 'rb') as f:
            raw_content = f.read()
        try:
            text_content = raw_content.decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail(f"File {file_path} is not valid UTF-8.")
        try:
            json.loads(text_content)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")


def test_hard_links_created():
    log1_path = '/home/user/logs/appA/log1.json'
    log2_path = '/home/user/logs/appB/log2.json'
    log3_path = '/home/user/logs/appA/log3.json'
    log4_path = '/home/user/logs/appB/log4.json'
    log5_path = '/home/user/logs/appA/log5.json'

    for path in [log1_path, log2_path, log3_path, log4_path, log5_path]:
        assert os.path.exists(path), f"{path} does not exist."

    stat1 = os.stat(log1_path)
    stat2 = os.stat(log2_path)
    stat3 = os.stat(log3_path)
    stat4 = os.stat(log4_path)
    stat5 = os.stat(log5_path)

    assert stat1.st_ino == stat2.st_ino, "log1.json and log2.json should be hard-linked (same inode)."
    assert stat3.st_ino == stat4.st_ino, "log3.json and log4.json should be hard-linked (same inode)."
    assert stat5.st_nlink == 1, "log5.json should not have any additional hard links (nlink == 1)."


def test_script_on_fresh_randomized_inputs_and_locking():
    script = '/home/user/storage_optimizer.py'
    assert os.path.isfile(script), f"Required script {script} is missing."

    with open(script, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=script)
    has_required_flock = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != 'flock' or not isinstance(node.func.value, ast.Name):
            continue
        if node.func.value.id != 'fcntl' or len(node.args) < 2:
            continue
        mode = node.args[1]
        if (isinstance(mode, ast.Attribute) and mode.attr == 'LOCK_EX' and
                isinstance(mode.value, ast.Name) and mode.value.id == 'fcntl'):
            has_required_flock = True
            break
    assert has_required_flock, "The script must call fcntl.flock(fd, fcntl.LOCK_EX)."

    root = tempfile.mkdtemp(prefix='optimizer_case_', dir='/home/user')
    first = os.path.join(root, 'aa')
    second = os.path.join(root, 'zz')
    os.makedirs(first)
    os.makedirs(second)

    paths = {
        'dup_csv_1': os.path.join(first, 'alpha.csv'),
        'dup_csv_2': os.path.join(second, 'beta.csv'),
        'latin_csv': os.path.join(first, 'latin.csv'),
        'dup_json_1': os.path.join(first, 'same.json'),
        'dup_json_2': os.path.join(second, 'same.json'),
        'utf16_json': os.path.join(second, 'wide.json'),
    }

    duplicate_csv = 'id,city,message\n17,Montréal,Déjà vu\n'
    with open(paths['dup_csv_1'], 'wb') as f:
        f.write(duplicate_csv.encode('utf-16le'))
    with open(paths['dup_csv_2'], 'wb') as f:
        f.write(duplicate_csv.encode('utf-16le'))

    latin_csv = 'id,city,message\n23,München,Grüße\n'
    with open(paths['latin_csv'], 'wb') as f:
        f.write(latin_csv.encode('iso-8859-1'))

    duplicate_json_object = [{'id': '31', 'kind': 'duplicate', 'message': 'same bytes'}]
    duplicate_json_bytes = json.dumps(duplicate_json_object, ensure_ascii=False, indent=2).encode('utf-8')
    with open(paths['dup_json_1'], 'wb') as f:
        f.write(duplicate_json_bytes)
    with open(paths['dup_json_2'], 'wb') as f:
        f.write(duplicate_json_bytes)

    wide_object = [{'id': '47', 'kind': 'wide', 'message': '雪'}]
    with open(paths['utf16_json'], 'wb') as f:
        f.write(json.dumps(wide_object, ensure_ascii=False).encode('utf-16le'))

    config = {'directories': [first, second], 'target_format': 'json'}
    with open('/home/user/config.yaml', 'w', encoding='utf-8') as f:
        yaml.safe_dump(config, f)

    original_bytes = {}
    locked_files = []
    for path in paths.values():
        with open(path, 'rb') as f:
            original_bytes[path] = f.read()
        fd = open(path, 'rb')
        fcntl.flock(fd.fileno(), fcntl.LOCK_EX)
        locked_files.append(fd)

    proc = subprocess.Popen(
        ['python3', script], cwd='/home/user',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    try:
        time.sleep(1.2)
        assert proc.poll() is None, "The script did not wait for exclusive locks on its input files."
        for path, content in original_bytes.items():
            assert os.path.exists(path), f"The locked input {path} was removed before its lock was acquired."
            with open(path, 'rb') as f:
                assert f.read() == content, f"The locked input {path} was modified before its lock was acquired."
        assert not os.path.exists(os.path.join(first, 'alpha.json'))
        assert not os.path.exists(os.path.join(second, 'beta.json'))
        assert not os.path.exists(os.path.join(first, 'latin.json'))
    finally:
        for fd in locked_files:
            fcntl.flock(fd.fileno(), fcntl.LOCK_UN)
            fd.close()

    try:
        stdout, stderr = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        pytest.fail(f"Optimizer did not finish after locks were released. stdout={stdout!r} stderr={stderr!r}")
    assert proc.returncode == 0, f"Optimizer failed with code {proc.returncode}. stdout={stdout!r} stderr={stderr!r}"

    expected_paths = {
        'dup_csv_1': os.path.join(first, 'alpha.json'),
        'dup_csv_2': os.path.join(second, 'beta.json'),
        'latin_csv': os.path.join(first, 'latin.json'),
        'dup_json_1': paths['dup_json_1'],
        'dup_json_2': paths['dup_json_2'],
        'utf16_json': paths['utf16_json'],
    }
    assert not os.path.exists(paths['dup_csv_1'])
    assert not os.path.exists(paths['dup_csv_2'])
    assert not os.path.exists(paths['latin_csv'])

    actual_files = set()
    for directory in (first, second):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isfile(path):
                actual_files.add(path)
    assert actual_files == set(expected_paths.values())

    decoded = {}
    for key, path in expected_paths.items():
        with open(path, 'rb') as f:
            raw = f.read()
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail(f"{path} was not normalized to UTF-8.")
        decoded[key] = json.loads(text)

    expected_duplicate_csv = [{'id': '17', 'city': 'Montréal', 'message': 'Déjà vu'}]
    assert decoded['dup_csv_1'] == expected_duplicate_csv
    assert decoded['dup_csv_2'] == expected_duplicate_csv
    assert decoded['latin_csv'] == [{'id': '23', 'city': 'München', 'message': 'Grüße'}]
    assert decoded['dup_json_1'] == duplicate_json_object
    assert decoded['dup_json_2'] == duplicate_json_object
    assert decoded['utf16_json'] == wide_object

    csv_dup_stats = [os.stat(expected_paths['dup_csv_1']), os.stat(expected_paths['dup_csv_2'])]
    json_dup_stats = [os.stat(expected_paths['dup_json_1']), os.stat(expected_paths['dup_json_2'])]
    assert csv_dup_stats[0].st_ino == csv_dup_stats[1].st_ino
    assert json_dup_stats[0].st_ino == json_dup_stats[1].st_ino
    assert csv_dup_stats[0].st_nlink == 2
    assert json_dup_stats[0].st_nlink == 2
    assert os.stat(expected_paths['latin_csv']).st_nlink == 1
    assert os.stat(expected_paths['utf16_json']).st_nlink == 1

    with open('/home/user/optimizer_report.json', 'r', encoding='utf-8') as f:
        report = json.load(f)
    assert report == {
        'total_files_processed': 6,
        'csv_to_json_conversions': 3,
        'hard_links_created': 2,
    }
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_storage_optimizer.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
