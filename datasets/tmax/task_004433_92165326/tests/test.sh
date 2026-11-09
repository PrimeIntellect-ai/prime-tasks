#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import shutil
import stat
import subprocess
import tempfile
import pytest

SCRIPT_PATH = '/home/user/storage_manager.py'
CONFIG_PATH = '/home/user/storage_conf.ini'
SUMMARY_PATH = '/home/user/summary.json'


def test_summary_json_exists_and_correct():
    summary_path = '/home/user/summary.json'
    assert os.path.isfile(summary_path), f"Summary JSON file missing at {summary_path}"

    with open(summary_path, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not a valid JSON file.")

    assert "bytes_saved" in summary, "Missing 'bytes_saved' in summary.json"
    assert summary["bytes_saved"] == 10, f"Expected bytes_saved to be 10, got {summary['bytes_saved']}"

    assert "hard_links_created" in summary, "Missing 'hard_links_created' in summary.json"
    assert summary["hard_links_created"] == 1, f"Expected hard_links_created to be 1, got {summary['hard_links_created']}"

    assert "symlinks_created" in summary, "Missing 'symlinks_created' in summary.json"
    assert summary["symlinks_created"] == 3, f"Expected symlinks_created to be 3, got {summary['symlinks_created']}"
    assert set(summary) == {"bytes_saved", "hard_links_created", "symlinks_created"}


def test_hard_links_created_correctly():
    f1_path = '/home/user/data_volume/f1.dat'
    f2_path = '/home/user/data_volume/f2.dat'
    f3_path = '/home/user/data_volume/f3.dat'
    f4_path = '/home/user/data_volume/f4.dat'

    assert os.path.isfile(f1_path), f"{f1_path} is missing"
    assert os.path.isfile(f2_path), f"{f2_path} is missing"
    assert os.path.isfile(f3_path), f"{f3_path} is missing"
    assert os.path.isfile(f4_path), f"{f4_path} is missing"

    stat1 = os.stat(f1_path)
    stat2 = os.stat(f2_path)

    assert stat1.st_ino == stat2.st_ino, "f1.dat and f2.dat should be hardlinked (same inode), but they are not."

    stat3 = os.stat(f3_path)
    stat4 = os.stat(f4_path)

    assert stat3.st_ino != stat4.st_ino, "f3.dat and f4.dat are ACTIVE and should NOT be hardlinked, but they have the same inode."


def test_original_file_contents_and_f5_preserved():
    expected = {
        'f1.dat': b'AAAAAAAAAA',
        'f2.dat': b'AAAAAAAAAA',
        'f3.dat': b'BBBBBBBBBB',
        'f4.dat': b'BBBBBBBBBB',
        'f5.dat': b'CCCCC',
    }
    for name, content in expected.items():
        path = os.path.join('/home/user/data_volume', name)
        assert os.path.isfile(path), f"{path} is missing"
        with open(path, 'rb') as f:
            assert f.read() == content, f"Unexpected content in {path}"


def test_symlinks_created_correctly():
    archive_dir = '/home/user/archive_links'
    data_dir = '/home/user/data_volume'

    expected_symlinks = ['f1.dat', 'f2.dat', 'f5.dat']
    unexpected_symlinks = ['f3.dat', 'f4.dat']

    for fname in expected_symlinks:
        symlink_path = os.path.join(archive_dir, fname)
        target_path = os.path.join(data_dir, fname)

        assert os.path.islink(symlink_path), f"Expected symlink at {symlink_path} is missing or not a symlink."

        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}."

    for fname in unexpected_symlinks:
        symlink_path = os.path.join(archive_dir, fname)
        assert not os.path.exists(symlink_path), f"Symlink {symlink_path} should not exist because the file is ACTIVE."
        assert not os.path.lexists(symlink_path), f"Archive entry {symlink_path} should not exist."


def write_config(target, log, archive, deduplicate, archive_links):
    config = configparser.ConfigParser()
    config['Paths'] = {
        'TargetDir': target,
        'LogFile': log,
        'ArchiveLinksDir': archive,
    }
    config['Settings'] = {
        'Deduplicate': str(deduplicate),
        'CreateArchiveLinks': str(archive_links),
    }
    with open(CONFIG_PATH, 'w') as f:
        config.write(f)


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"storage_manager.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(SUMMARY_PATH), "Script did not generate summary.json"
    with open(SUMMARY_PATH) as f:
        return json.load(f)


def record(job, path, status, minute):
    return (
        f"[2026-01-01 12:{minute:02d}:00] INFO - Job Start\n"
        f"Job ID: {job}\n"
        f"File: {path}\n"
        f"Status: {status}"
    )


def test_script_exists_and_handles_fresh_derived_inputs():
    assert os.path.exists(SCRIPT_PATH), f"Missing required script {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "storage_manager.py must be a real file, not a symlink"
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "storage_manager.py is not a regular file"

    with open(CONFIG_PATH, 'rb') as f:
        original_config = f.read()
    original_summary = None
    if os.path.exists(SUMMARY_PATH):
        with open(SUMMARY_PATH, 'rb') as f:
            original_summary = f.read()

    root = tempfile.mkdtemp(prefix='storage_manager_test_')
    try:
        target = os.path.join(root, 'fresh_data')
        archive = os.path.join(root, 'fresh_archive')
        log = os.path.join(root, 'fresh_app.log')
        os.mkdir(target)

        contents = {
            'zeta.bin': b'R4ND0M-DUPLICATE',
            'alpha.bin': b'R4ND0M-DUPLICATE',
            'active_copy.bin': b'R4ND0M-DUPLICATE',
            'became_active.bin': b'changed-status',
            'became_inactive.bin': b'unique-inactive',
            'unlogged.bin': b'no-log-entry',
        }
        for name, data in contents.items():
            with open(os.path.join(target, name), 'wb') as f:
                f.write(data)

        paths = {name: os.path.abspath(os.path.join(target, name)) for name in contents}
        records = [
            record(201, paths['zeta.bin'], 'INACTIVE', 1),
            record(202, paths['alpha.bin'], 'INACTIVE', 2),
            record(203, paths['active_copy.bin'], 'ACTIVE', 3),
            record(204, paths['became_active.bin'], 'INACTIVE', 4),
            record(205, paths['became_inactive.bin'], 'ACTIVE', 5),
            record(206, paths['became_active.bin'], 'ACTIVE', 6),
            record(207, paths['became_inactive.bin'], 'INACTIVE', 7),
        ]
        with open(log, 'w') as f:
            f.write('\n\n'.join(records) + '\n')

        write_config(target, log, archive, True, True)
        summary = run_script()
        expected_size = len(contents['zeta.bin'])
        assert summary == {
            'bytes_saved': expected_size,
            'hard_links_created': 1,
            'symlinks_created': 3,
        }

        alpha = paths['alpha.bin']
        zeta = paths['zeta.bin']
        active_copy = paths['active_copy.bin']
        assert os.stat(alpha).st_ino == os.stat(zeta).st_ino
        assert os.stat(active_copy).st_ino != os.stat(alpha).st_ino
        for name, expected_content in contents.items():
            path = paths[name]
            assert os.path.isfile(path), f"Script removed {path}"
            with open(path, 'rb') as f:
                assert f.read() == expected_content

        expected_links = {'alpha.bin', 'zeta.bin', 'became_inactive.bin'}
        for name in contents:
            link = os.path.join(archive, name)
            if name in expected_links:
                assert os.path.islink(link), f"Missing archive symlink for {name}"
                assert os.readlink(link) == paths[name]
            else:
                assert not os.path.lexists(link), f"Unexpected archive entry for {name}"

        disabled_target = os.path.join(root, 'disabled_data')
        disabled_archive = os.path.join(root, 'disabled_archive')
        disabled_log = os.path.join(root, 'disabled.log')
        os.mkdir(disabled_target)
        p = os.path.abspath(os.path.join(disabled_target, 'p.bin'))
        q = os.path.abspath(os.path.join(disabled_target, 'q.bin'))
        with open(p, 'wb') as f:
            f.write(b'disabled-duplicate')
        with open(q, 'wb') as f:
            f.write(b'disabled-duplicate')
        with open(disabled_log, 'w') as f:
            f.write(record(301, p, 'INACTIVE', 1) + '\n\n' + record(302, q, 'INACTIVE', 2) + '\n')

        write_config(disabled_target, disabled_log, disabled_archive, False, False)
        disabled_summary = run_script()
        assert disabled_summary == {
            'bytes_saved': 0,
            'hard_links_created': 0,
            'symlinks_created': 0,
        }
        assert os.stat(p).st_ino != os.stat(q).st_ino
        assert not os.path.lexists(disabled_archive)
    finally:
        with open(CONFIG_PATH, 'wb') as f:
            f.write(original_config)
        if original_summary is None:
            if os.path.exists(SUMMARY_PATH):
                os.remove(SUMMARY_PATH)
        else:
            with open(SUMMARY_PATH, 'wb') as f:
                f.write(original_summary)
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
