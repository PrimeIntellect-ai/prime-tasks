#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import pytest

def test_no_path_traversal():
    assert not os.path.exists('/home/user/evil.sh'), "Path traversal vulnerability exploited: /home/user/evil.sh was extracted"

def test_no_bad_symlink():
    badlink_path = '/home/user/configs/badlink'
    if os.path.islink(badlink_path):
        target = os.readlink(badlink_path)
        assert target != '/etc/passwd', "Symlink vulnerability exploited: badlink points to /etc/passwd"

        abs_target = os.path.abspath(os.path.join('/home/user/configs', target))
        assert abs_target.startswith('/home/user/configs'), "Symlink points outside target directory"

def test_configs_state():
    app1_path = '/home/user/configs/app1.json'
    app2_path = '/home/user/configs/app2.json'
    app3_path = '/home/user/configs/app3.json'

    assert os.path.isfile(app1_path), f"{app1_path} is missing"
    with open(app1_path, 'r') as f:
        data = json.load(f)
        assert data.get("version") == "1.1", f"app1.json version should be updated to 1.1, got {data.get('version')}"

    assert os.path.isfile(app2_path), f"{app2_path} is missing"
    with open(app2_path, 'r') as f:
        data = json.load(f)
        assert data.get("version") == "1.2", f"app2.json version should remain 1.2, got {data.get('version')}"

    assert os.path.isfile(app3_path), f"{app3_path} is missing"
    with open(app3_path, 'r') as f:
        data = json.load(f)
        assert data.get("version") == "2.0", f"app3.json version should be 2.0, got {data.get('version')}"

def test_csv_summary():
    csv_path = '/home/user/config_summary.csv'
    assert os.path.isfile(csv_path), f"{csv_path} is missing"

    expected_rows = [
        ['filename', 'version'],
        ['app1.json', '1.1'],
        ['app2.json', '1.2'],
        ['app3.json', '2.0']
    ]

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert rows == expected_rows, f"CSV content does not match expected. Got: {rows}"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_behavior.py
import csv
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import uuid
import zipfile

SCRIPT = '/home/user/process_update.py'
CONFIGS = '/home/user/configs'
ARCHIVE = '/home/user/incoming/update.zip'
SUMMARY = '/home/user/config_summary.csv'


def add_file(tar, name, data):
    payload = data if isinstance(data, bytes) else data.encode('utf-8')
    member = tarfile.TarInfo(name)
    member.size = len(payload)
    member.mode = 0o644
    tar.addfile(member, io.BytesIO(payload))


def test_script_on_unseen_archive_and_security_cases():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} is missing or is not a regular file'
    assert not os.path.islink(SCRIPT), f'{SCRIPT} must not be a symlink'

    token = uuid.uuid4().hex
    update_name = f'alpha_{token}.json'
    retained_name = f'middle_{token}.json'
    new_name = f'zeta_{token}.json'
    update_version = f'7.{int(token[:2], 16)}'
    retained_version = f'8.{int(token[2:4], 16)}'
    new_version = f'9.{int(token[4:6], 16)}'

    shutil.rmtree(CONFIGS, ignore_errors=True)
    os.makedirs(CONFIGS, exist_ok=True)
    with open(os.path.join(CONFIGS, update_name), 'w') as f:
        json.dump({'version': 'old', 'source': 'preexisting'}, f)
    with open(os.path.join(CONFIGS, retained_name), 'w') as f:
        json.dump({'version': retained_version, 'source': 'retained'}, f)

    escape1 = f'/home/user/escape_{token}'
    escape2 = f'/home/user/escape2_{token}'
    absolute_escape = f'/tmp/absolute_escape_{token}'
    outside_dir = f'/home/user/outside_{token}'
    os.makedirs(outside_dir, exist_ok=True)
    outside_child = os.path.join(outside_dir, 'pwned.json')
    guard = os.path.join(outside_dir, 'guard.txt')
    with open(guard, 'wb') as f:
        f.write(b'ORIGINAL-GUARD')

    zip_escape_candidates = [
        f'/home/user/incoming/zip_escape_{token}',
        f'/home/user/zip_escape_{token}',
        f'/home/zip_escape_{token}',
        f'/tmp/zip_escape_{token}',
        f'/zip_escape_{token}',
    ]
    for path in [escape1, escape2, absolute_escape, outside_child] + zip_escape_candidates:
        try:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        except FileNotFoundError:
            pass

    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode='w') as tar:
        add_file(tar, update_name, json.dumps({'version': update_version, 'source': token}))
        add_file(tar, new_name, json.dumps({'version': new_version, 'source': token}))
        add_file(tar, f'note_{token}.txt', 'not a configuration')
        add_file(tar, f'../escape_{token}', 'TRAVERSAL')
        add_file(tar, f'nested/../../escape2_{token}', 'NORMALIZED-TRAVERSAL')
        add_file(tar, absolute_escape, 'ABSOLUTE-TRAVERSAL')

        pivot = tarfile.TarInfo(f'pivot_{token}')
        pivot.type = tarfile.SYMTYPE
        pivot.linkname = f'../outside_{token}'
        tar.addfile(pivot)
        add_file(tar, f'pivot_{token}/pwned.json', json.dumps({'version': 'pwned'}))

        absolute_link = tarfile.TarInfo(f'absolute_link_{token}')
        absolute_link.type = tarfile.SYMTYPE
        absolute_link.linkname = '/etc/passwd'
        tar.addfile(absolute_link)

        hardlink = tarfile.TarInfo(f'hardlink_{token}')
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = f'../outside_{token}/guard.txt'
        tar.addfile(hardlink)

    os.makedirs(os.path.dirname(ARCHIVE), exist_ok=True)
    with zipfile.ZipFile(ARCHIVE, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('payload.tar', tar_buffer.getvalue())
        archive.writestr(f'../zip_escape_{token}', b'ZIP-TRAVERSAL')

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'process_update.py failed on a valid update archive. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )

    expected = {
        update_name: update_version,
        retained_name: retained_version,
        new_name: new_version,
    }
    for filename, version in expected.items():
        path = os.path.join(CONFIGS, filename)
        assert os.path.isfile(path), f'Safe configuration was not produced: {path}'
        with open(path) as f:
            assert json.load(f).get('version') == version

    with open(SUMMARY, newline='') as f:
        rows = list(csv.reader(f))
    expected_rows = [['filename', 'version']] + [
        [name, expected[name]] for name in sorted(expected)
    ]
    assert rows == expected_rows, f'Dynamic CSV content is wrong: {rows}'

    assert not os.path.lexists(escape1), 'A ../ traversal member escaped configs'
    assert not os.path.lexists(escape2), 'A normalized traversal member escaped configs'
    assert not os.path.lexists(absolute_escape), 'An absolute tar member escaped configs'
    assert not os.path.lexists(outside_child), 'A file was written through an escaping symlink'
    with open(guard, 'rb') as f:
        assert f.read() == b'ORIGINAL-GUARD', 'An outside file was overwritten or linked'
    assert not os.path.lexists(os.path.join(CONFIGS, f'pivot_{token}'))
    assert not os.path.lexists(os.path.join(CONFIGS, f'absolute_link_{token}'))
    assert not os.path.lexists(os.path.join(CONFIGS, f'hardlink_{token}'))
    for path in zip_escape_candidates:
        assert not os.path.lexists(path), f'Zip traversal wrote outside its intended member: {path}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest /tmp/test_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
