#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest


def test_restored_system_log():
    filepath = '/home/user/restored/system_log.txt'
    assert os.path.exists(filepath), f"Expected restored file {filepath} does not exist."

    expected_content = 'INFO: System booted successfully.\n' * 5
    with open(filepath, 'r') as f:
        content = f.read()
    assert content == expected_content, f"Content of {filepath} is incorrect."


def test_restored_cpu_metrics():
    filepath = '/home/user/restored/cpu_metrics.csv'
    assert os.path.exists(filepath), f"Expected restored file {filepath} does not exist."

    expected_content = 'cpu0,100\ncpu1,98\ncpu2,100\n'
    with open(filepath, 'r') as f:
        content = f.read()
    assert content == expected_content, f"Content of {filepath} is incorrect."


def test_symlink_job_8081():
    linkpath = '/home/user/restored/job_8081.link'
    assert os.path.islink(linkpath), f"Expected symlink {linkpath} does not exist or is not a symlink."

    target = os.readlink(linkpath)
    expected_targets = ['system_log.txt', '/home/user/restored/system_log.txt']
    assert target in expected_targets, f"Symlink {linkpath} points to {target}, expected one of {expected_targets}."


def test_symlink_job_8083():
    linkpath = '/home/user/restored/job_8083.link'
    assert os.path.islink(linkpath), f"Expected symlink {linkpath} does not exist or is not a symlink."

    target = os.readlink(linkpath)
    expected_targets = ['cpu_metrics.csv', '/home/user/restored/cpu_metrics.csv']
    assert target in expected_targets, f"Symlink {linkpath} points to {target}, expected one of {expected_targets}."


def test_failed_job_not_restored():
    filepath = '/home/user/restored/do_not_restore.txt'
    assert not os.path.exists(filepath), f"File {filepath} should not have been restored as its job status was FAILED."


def test_c_program_exists():
    filepath = '/home/user/restore.c'
    assert os.path.exists(filepath), f"C program {filepath} does not exist."
    assert os.path.isfile(filepath) and not os.path.islink(filepath), f"C program {filepath} must be a regular source file."


def _rle_archive(path, filename, data, magic=b'BKUP'):
    name = filename.encode('ascii')
    assert len(name) <= 32
    payload = bytearray()
    pos = 0
    while pos < len(data):
        count = 1
        while pos + count < len(data) and data[pos + count] == data[pos] and count < 255:
            count += 1
        payload.extend((count, data[pos]))
        pos += count
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(name + b'\x00' * (32 - len(name)))
        f.write(payload)


def test_program_compiles_and_handles_fresh_manifest_and_archives():
    token = secrets.token_hex(6)
    base_job = 200000 + secrets.randbelow(600000)
    good_job, failed_job, bad_magic_job = base_job, base_job + 1, base_job + 2

    good_name = f'dyn_{token}.txt'
    failed_name = f'failed_{token}.txt'
    bad_name = f'bad_{token}.txt'
    good_archive = f'/home/user/backups/dyn_{token}.bin'
    failed_archive = f'/home/user/backups/failed_{token}.bin'
    bad_archive = f'/home/user/backups/bad_{token}.bin'
    good_output = f'/home/user/restored/{good_name}'
    failed_output = f'/home/user/restored/{failed_name}'
    bad_output = f'/home/user/restored/{bad_name}'
    good_link = f'/home/user/restored/job_{good_job}.link'
    failed_link = f'/home/user/restored/job_{failed_job}.link'
    bad_link = f'/home/user/restored/job_{bad_magic_job}.link'
    executable = f'/tmp/restore_under_test_{token}'
    manifest_path = '/home/user/backup_manifest.log'

    marker = secrets.token_hex(8).encode('ascii')
    expected = b'A' * 260 + b'\nmanifest-' + marker + b'\nZ' * 17
    failed_data = b'This failed record must not be restored: ' + marker
    bad_data = b'This invalid-magic archive must be skipped: ' + marker

    had_manifest = os.path.exists(manifest_path)
    old_manifest = open(manifest_path, 'rb').read() if had_manifest else None
    generated_paths = [good_archive, failed_archive, bad_archive, good_output,
                       failed_output, bad_output, good_link, failed_link,
                       bad_link, executable]

    try:
        for path in generated_paths:
            if os.path.lexists(path):
                os.unlink(path)

        _rle_archive(good_archive, good_name, expected)
        _rle_archive(failed_archive, failed_name, failed_data)
        _rle_archive(bad_archive, bad_name, bad_data, magic=b'NOPE')

        manifest = (
            f'Job-ID: {good_job}\n'
            f'Archive: {good_archive}\n'
            'Status: SUCCESS\n\n'
            f'Job-ID: {failed_job}\n'
            f'Archive: {failed_archive}\n'
            'Status: FAILED\n\n'
            f'Job-ID: {bad_magic_job}\n'
            f'Archive: {bad_archive}\n'
            'Status: SUCCESS\n'
        )
        with open(manifest_path, 'w') as f:
            f.write(manifest)

        compile_result = subprocess.run(
            ['gcc', '-std=c11', '-O2', '/home/user/restore.c', '-o', executable],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, f"restore.c did not compile:\n{compile_result.stderr}"

        run_result = subprocess.run(
            [executable], cwd='/home/user', stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert run_result.returncode == 0, (
            f"Compiled restore program failed with code {run_result.returncode}:\n"
            f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        )

        assert os.path.isfile(good_output) and not os.path.islink(good_output), \
            f"Fresh successful archive was not restored to {good_output}."
        with open(good_output, 'rb') as f:
            assert f.read() == expected, 'Fresh RLE payload was decompressed incorrectly.'

        assert os.path.islink(good_link), f"Expected fresh symlink {good_link}."
        target = os.readlink(good_link)
        assert target in [good_name, good_output], \
            f"Symlink {good_link} points to {target}, expected {good_name} or {good_output}."

        assert not os.path.lexists(failed_output), 'A fresh FAILED record was restored.'
        assert not os.path.lexists(failed_link), 'A link was created for a fresh FAILED record.'
        assert not os.path.lexists(bad_output), 'A fresh invalid-magic archive was restored.'
        assert not os.path.lexists(bad_link), 'A link was created for a fresh invalid-magic archive.'
    finally:
        if had_manifest:
            with open(manifest_path, 'wb') as f:
                f.write(old_manifest)
        elif os.path.exists(manifest_path):
            os.unlink(manifest_path)
        for path in generated_paths:
            if os.path.lexists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
