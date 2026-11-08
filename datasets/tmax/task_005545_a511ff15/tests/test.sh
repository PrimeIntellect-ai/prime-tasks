#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import secrets
import shutil
import struct
import subprocess
import tarfile
import tempfile

REPORT_PATH = '/home/user/report.json'
SCRIPT_PATH = '/home/user/parse_snaps.py'
SNAPSHOT_DIR = '/home/user/snapshots'


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Expected output file {REPORT_PATH} does not exist."
    try:
        with open(REPORT_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"{REPORT_PATH} does not contain valid JSON.")
    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    return data


def make_snap(path, version, commit, author, raw_changes, *, magic=b'SNAP', corrupt=False):
    changelog = f"Commit: {commit}\nAuthor: {author}\nChanges:\n"
    for change in raw_changes:
        changelog += f" - {change}\n"

    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w:gz') as archive:
        content = changelog.encode('utf-8')
        info = tarfile.TarInfo('changelog.txt')
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))

    payload = stream.getvalue()
    checksum = hashlib.md5(payload).digest()
    if corrupt:
        checksum = bytes([checksum[0] ^ 0xff]) + checksum[1:]

    with open(path, 'wb') as f:
        f.write(magic + struct.pack('<H', version) + checksum + payload)


def test_original_report_and_script_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."
    assert os.path.getsize(SCRIPT_PATH) > 0, f"Expected Python script {SCRIPT_PATH} is empty."

    # Preserve all assertions made by the original verifier.
    data = load_report()
    expected_data = [
        {
            "filename": "01_init.snap",
            "version": 1,
            "commit": "7a8f9e0",
            "author": "sysadmin",
            "changes": ["Initial deployment", "Setup firewall rules"]
        },
        {
            "filename": "03_update.snap",
            "version": 2,
            "commit": "b4c5d6e",
            "author": "devops_bob",
            "changes": [
                "Increased max connections",
                "Updated SSL certificates",
                "Removed old user accounts"
            ]
        }
    ]

    assert len(data) == len(expected_data), \
        f"Expected {len(expected_data)} entries in the report, but found {len(data)}."
    filenames = [entry.get('filename') for entry in data]
    assert filenames == sorted(filenames), "The JSON array is not sorted alphabetically by filename."

    for i, expected_entry in enumerate(expected_data):
        actual_entry = data[i]
        assert actual_entry.get('filename') == expected_entry['filename'], f"Mismatch in filename at index {i}."
        assert actual_entry.get('version') == expected_entry['version'], f"Mismatch in version at index {i}."
        assert actual_entry.get('commit') == expected_entry['commit'], f"Mismatch in commit at index {i}."
        assert actual_entry.get('author') == expected_entry['author'], f"Mismatch in author at index {i}."
        assert actual_entry.get('changes') == expected_entry['changes'], f"Mismatch in changes at index {i}."

    for entry in data:
        assert entry.get('filename') != '02_bad.snap', "Corrupt file '02_bad.snap' was not skipped."

    # Replace the snapshots with unpredictable cases and execute the submitted script.
    token = secrets.token_hex(8)
    version_a = secrets.randbelow(30000) + 257
    version_z = secrets.randbelow(30000) + 35000
    name_a = f'a_{token}.snap'
    name_z = f'z_{token}.snap'
    bad_checksum = f'm_{token}_corrupt.snap'
    bad_magic = f'n_{token}_magic.snap'

    backup_root = tempfile.mkdtemp(prefix='snap-verifier-')
    backup_snapshots = os.path.join(backup_root, 'snapshots')
    report_existed = os.path.exists(REPORT_PATH)
    report_backup = os.path.join(backup_root, 'report.json')
    if report_existed:
        shutil.copy2(REPORT_PATH, report_backup)

    os.rename(SNAPSHOT_DIR, backup_snapshots)
    os.makedirs(SNAPSHOT_DIR)

    try:
        make_snap(
            os.path.join(SNAPSHOT_DIR, name_z), version_z,
            f'commit-{token}-z', f'author-{token}-z',
            [f'Enabled service {token}   ', 'Rotated credentials\t']
        )
        make_snap(
            os.path.join(SNAPSHOT_DIR, name_a), version_a,
            f'commit-{token}-a', f'author-{token}-a',
            ['Added first dynamic setting  ', f'Updated value {token}', 'Final change\t']
        )
        make_snap(
            os.path.join(SNAPSHOT_DIR, bad_checksum), 9,
            f'bad-{token}', 'corrupt-author', ['Must not appear'], corrupt=True
        )
        make_snap(
            os.path.join(SNAPSHOT_DIR, bad_magic), 10,
            f'magic-{token}', 'wrong-magic-author', ['Must not appear'], magic=b'NOPE'
        )
        with open(os.path.join(SNAPSHOT_DIR, f'truncated_{token}.snap'), 'wb') as f:
            f.write(b'SNAP\x01')
        with open(os.path.join(SNAPSHOT_DIR, f'ignored_{token}.txt'), 'w', encoding='utf-8') as f:
            f.write('not a snapshot')

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30
        )
        assert result.returncode == 0, \
            f"parse_snaps.py exited with {result.returncode}. stderr: {result.stderr}"

        dynamic_data = load_report()
        expected_dynamic = [
            {
                'filename': name_a,
                'version': version_a,
                'commit': f'commit-{token}-a',
                'author': f'author-{token}-a',
                'changes': ['Added first dynamic setting', f'Updated value {token}', 'Final change']
            },
            {
                'filename': name_z,
                'version': version_z,
                'commit': f'commit-{token}-z',
                'author': f'author-{token}-z',
                'changes': [f'Enabled service {token}', 'Rotated credentials']
            }
        ]
        assert dynamic_data == expected_dynamic, \
            f"Report from dynamically generated snapshots was incorrect: {dynamic_data!r}"
        assert [entry['filename'] for entry in dynamic_data] == sorted(
            entry['filename'] for entry in dynamic_data
        ), "The dynamically generated report is not sorted alphabetically by filename."
    finally:
        shutil.rmtree(SNAPSHOT_DIR, ignore_errors=True)
        os.rename(backup_snapshots, SNAPSHOT_DIR)
        if report_existed:
            shutil.copy2(report_backup, REPORT_PATH)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
