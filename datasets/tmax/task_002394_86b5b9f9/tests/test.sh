#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import tempfile
import uuid
import pytest

PROJECT = '/home/user/legacy_project'


def archive_member(tar, relative_path):
    wanted = relative_path.strip('/')
    for member in tar.getmembers():
        name = member.name.lstrip('./').lstrip('/')
        if name == wanted or name.endswith('/' + wanted):
            return member
    return None


def archive_bytes(tar, relative_path):
    member = archive_member(tar, relative_path)
    assert member is not None, f"Archive is missing {relative_path}."
    assert member.isfile(), f"Archived {relative_path} is not a regular file."
    stream = tar.extractfile(member)
    assert stream is not None, f"Could not read archived {relative_path}."
    return stream.read()


def test_log_sanitation():
    app_log_path = '/home/user/legacy_project/logs/app.log'
    debug_log_path = '/home/user/legacy_project/logs/old/debug.log'

    assert os.path.isfile(app_log_path), f"Log file {app_log_path} is missing."
    assert os.path.isfile(debug_log_path), f"Log file {debug_log_path} is missing."

    with open(app_log_path, 'r') as f:
        app_content = f.read()
        assert "[REDACTED]" in app_content, "Emails in app.log were not redacted."
        assert "admin@example.com" not in app_content, "admin@example.com was not redacted in app.log."
        assert "support@domain.co.uk" not in app_content, "support@domain.co.uk was not redacted in app.log."

    with open(debug_log_path, 'r') as f:
        debug_content = f.read()
        assert "[REDACTED]" in debug_content, "Emails in debug.log were not redacted."
        assert "test1@test.com" not in debug_content, "test1@test.com was not redacted in debug.log."
        assert "test.user@sub.domain.org" not in debug_content, "test.user@sub.domain.org was not redacted in debug.log."

    email_re = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
    for root, _, files in os.walk(PROJECT):
        for name in files:
            if name.endswith('.log'):
                path = os.path.join(root, name)
                with open(path, 'r', errors='replace') as f:
                    assert not email_re.search(f.read()), f"Unsanitized email remains in {path}."


def test_binary_categorization():
    script = '/home/user/organize_binaries.py'
    elf_dir = '/home/user/legacy_project/organized/elf'
    png_dir = '/home/user/legacy_project/organized/png'
    unknown_dir = '/home/user/legacy_project/organized/unknown'
    assets_dir = '/home/user/legacy_project/assets'

    assert os.path.isfile(script), f"Organizer script {script} is missing."
    assert os.path.isfile(os.path.join(elf_dir, 'file1_bin')), "file1_bin was not moved to the elf directory."
    assert os.path.isfile(os.path.join(elf_dir, 'file4_bin')), "file4_bin was not moved to the elf directory."
    assert os.path.isfile(os.path.join(png_dir, 'file2_img')), "file2_img was not moved to the png directory."
    assert os.path.isfile(os.path.join(unknown_dir, 'file3_rand')), "file3_rand was not moved to the unknown directory."

    expected_originals = {
        os.path.join(elf_dir, 'file1_bin'): b'\x7fELF\x02\x01\x01\x00',
        os.path.join(elf_dir, 'file4_bin'): b'\x7fELF\x01\x01\x01\x00',
        os.path.join(png_dir, 'file2_img'): b'\x89PNG\r\n\x1a\n',
        os.path.join(unknown_dir, 'file3_rand'): b'\x00' * 8,
    }
    for path, expected in expected_originals.items():
        with open(path, 'rb') as f:
            assert f.read() == expected, f"Contents of {path} were altered."

    if os.path.isdir(assets_dir):
        assert len(os.listdir(assets_dir)) == 0, f"{assets_dir} should be empty after moving files."
    else:
        os.makedirs(assets_dir)

    token = uuid.uuid4().hex
    probes = {
        f'probe_{token}_a': (b'\x7fELF' + os.urandom(19), elf_dir),
        f'probe_{token}_b': (b'\x89PNG' + os.urandom(17), png_dir),
        f'probe_{token}_c': (b'ABCD' + os.urandom(13), unknown_dir),
        f'probe_{token}_d': (b'\x7fEL', unknown_dir),
    }
    for name, (content, _) in probes.items():
        with open(os.path.join(assets_dir, name), 'wb') as f:
            f.write(content)

    subprocess.run(['python3', script], check=True, timeout=20)

    for name, (content, destination) in probes.items():
        result = os.path.join(destination, name)
        assert os.path.isfile(result), f"Organizer did not classify runtime probe {name} correctly."
        with open(result, 'rb') as f:
            assert f.read() == content, f"Organizer altered runtime probe {name}."
        assert not os.path.exists(os.path.join(assets_dir, name)), f"Organizer did not move runtime probe {name}."


def test_backups():
    full_backup = '/home/user/backups/backup_full.tar'
    inc_backup = '/home/user/backups/backup_inc.tar'
    snar_file = '/home/user/backups/project.snar'
    update_txt = '/home/user/legacy_project/organized/update.txt'

    assert os.path.isfile(full_backup), f"Full backup {full_backup} is missing."
    assert os.path.isfile(inc_backup), f"Incremental backup {inc_backup} is missing."
    assert os.path.isfile(snar_file), f"Snapshot file {snar_file} is missing."
    assert os.path.isfile(update_txt), f"Update file {update_txt} is missing."

    with open(update_txt, 'r') as f:
        assert f.read().strip() == "Backup test", "update.txt does not contain the correct text."

    with open(snar_file, 'rb') as f:
        snapshot_data = f.read()
    assert snapshot_data.startswith(b'GNU tar-'), "project.snar is not a GNU tar snapshot file."

    expected_full_files = [
        'legacy_project/logs/app.log',
        'legacy_project/logs/old/debug.log',
        'legacy_project/organized/elf/file1_bin',
        'legacy_project/organized/elf/file4_bin',
        'legacy_project/organized/png/file2_img',
        'legacy_project/organized/unknown/file3_rand',
    ]

    try:
        with tarfile.open(full_backup, 'r:*') as tar:
            assert any(m.type == tarfile.GNUTYPE_DUMPDIR for m in tar.getmembers()), \
                "Full backup is not a GNU snapshot-based archive."
            assert archive_member(tar, 'legacy_project/organized/update.txt') is None, \
                "Full backup was not created before update.txt."
            for relative in expected_full_files:
                live_path = os.path.join('/home/user', relative)
                with open(live_path, 'rb') as f:
                    expected = f.read()
                assert archive_bytes(tar, relative) == expected, f"Full backup has incorrect data for {relative}."
    except tarfile.TarError as exc:
        pytest.fail(f"Could not read tar file {full_backup}: {exc}")

    try:
        with tarfile.open(inc_backup, 'r:*') as tar:
            assert any(m.type == tarfile.GNUTYPE_DUMPDIR for m in tar.getmembers()), \
                "Incremental backup is not a GNU snapshot-based archive."
            assert archive_bytes(tar, 'legacy_project/organized/update.txt') == b'Backup test\n' or \
                   archive_bytes(tar, 'legacy_project/organized/update.txt') == b'Backup test', \
                "The incremental backup has incorrect update.txt data."
    except tarfile.TarError as exc:
        pytest.fail(f"Could not read tar file {inc_backup}: {exc}")

    probe_name = f'verifier_snapshot_probe_{uuid.uuid4().hex}.txt'
    probe_path = os.path.join(PROJECT, probe_name)
    probe_data = os.urandom(32)
    with open(probe_path, 'wb') as f:
        f.write(probe_data)

    with tempfile.NamedTemporaryFile(suffix='.tar', delete=False) as tmp:
        verifier_archive = tmp.name
    try:
        subprocess.run([
            'tar', f'--listed-incremental={snar_file}', '-cf', verifier_archive,
            'legacy_project'
        ], cwd='/home/user', check=True, timeout=30)
        with tarfile.open(verifier_archive, 'r:*') as tar:
            assert archive_bytes(tar, f'legacy_project/{probe_name}') == probe_data, \
                "The supplied snapshot file does not support a real subsequent incremental backup."
    finally:
        if os.path.exists(verifier_archive):
            os.unlink(verifier_archive)
        if os.path.exists(probe_path):
            os.unlink(probe_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
