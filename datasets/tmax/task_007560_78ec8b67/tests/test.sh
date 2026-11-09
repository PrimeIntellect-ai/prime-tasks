#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import itertools
import os
import pwd
import shutil
import stat
import subprocess
import uuid

import pytest


def encode_base64_rle(data):
    encoded = base64.b64encode(data).decode('ascii')
    return ''.join(f'{sum(1 for _ in group)}{char}' for char, group in itertools.groupby(encoded)).encode('ascii')


def expected_chunk_map(data):
    compressed = encode_base64_rle(data)
    pieces = [compressed[i:i + 10000] for i in range(0, len(compressed), 10000)]
    return {f'chunk_{i:02d}': piece for i, piece in enumerate(pieces)}


def select_script():
    py_script = '/home/user/decompress.py'
    sh_script = '/home/user/decompress.sh'

    if os.path.exists(py_script):
        assert os.path.isfile(py_script) and not os.path.islink(py_script), \
            f'Phase 4 Failed: {py_script} is not a regular script file.'
        return ['python3', py_script]
    if os.path.exists(sh_script):
        assert os.path.isfile(sh_script) and not os.path.islink(sh_script), \
            f'Phase 4 Failed: {sh_script} is not a regular script file.'
        return ['bash', sh_script]

    pytest.fail('Phase 4 Failed: Neither decompress.py nor decompress.sh was found in /home/user/.')


def run_script(cmd):
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
            preexec_fn=demote,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Phase 4 Failed: Decompression script timed out.')
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f'Phase 4 Failed: Decompression script execution failed with exit code {e.returncode}.\n'
            f'Stderr: {e.stderr}'
        )


def make_unambiguous_probe(byte_count=18000):
    # The specified RLE has no delimiter between a decimal count and a Base64
    # character. Generate an unpredictable probe whose Base64 contains no digits,
    # so a conforming decoder can parse it without that specification ambiguity.
    accepted = bytearray()
    while len(accepted) < byte_count:
        block = os.urandom(3)
        quartet = base64.b64encode(block)
        if not any(48 <= char <= 57 for char in quartet):
            accepted.extend(block)
    return bytes(accepted[:byte_count])


def test_phase1_deduplication():
    db_dumps_dir = '/home/user/db_dumps'
    assert os.path.isdir(db_dumps_dir), f'Directory {db_dumps_dir} is missing.'

    expected_names = {f'dump_{i}.sql' for i in range(1, 51)}
    actual_names = set(os.listdir(db_dumps_dir))
    assert actual_names == expected_names, \
        'Phase 1 Failed: /home/user/db_dumps must still contain exactly dump_1.sql through dump_50.sql.'

    files = []
    for name in sorted(expected_names):
        path = os.path.join(db_dumps_dir, name)
        info = os.lstat(path)
        assert stat.S_ISREG(info.st_mode) and not os.path.islink(path), \
            f'Phase 1 Failed: {path} is not a regular dump file.'
        assert info.st_size == 1024, f'Phase 1 Failed: {path} was modified or truncated.'
        files.append(path)

    assert len(files) > 0, 'No files found in /home/user/db_dumps.'

    content_map = {}
    for path in files:
        with open(path, 'rb') as file:
            content = file.read()
        content_map.setdefault(content, []).append(path)

    for content, flist in content_map.items():
        inodes = {(os.stat(path).st_dev, os.stat(path).st_ino) for path in flist}
        assert len(inodes) == 1, \
            f'Phase 1 Failed: Identical files do not share the same inode. Files: {flist}'


def test_phase2_chunks():
    chunks_dir = '/home/user/archive_chunks'
    assert os.path.isdir(chunks_dir), f'Phase 2 Failed: Directory {chunks_dir} is missing.'

    chunks = sorted(os.listdir(chunks_dir))
    assert len(chunks) > 0, 'Phase 2 Failed: No chunks found in /home/user/archive_chunks.'
    for chunk in chunks:
        assert chunk.startswith('chunk_'), \
            f"Chunk name '{chunk}' does not match the expected 'chunk_XX' format."

    with open('/home/user/massive_log.bin', 'rb') as source:
        expected = expected_chunk_map(source.read())

    assert chunks == sorted(expected), \
        'Phase 2 Failed: Chunk names or chunk count do not match the required 10,000-byte splitting.'

    for name, expected_data in expected.items():
        path = os.path.join(chunks_dir, name)
        info = os.lstat(path)
        assert stat.S_ISREG(info.st_mode) and not os.path.islink(path), \
            f'Phase 2 Failed: {name} is not a regular chunk file.'
        with open(path, 'rb') as chunk_file:
            actual_data = chunk_file.read()
        assert actual_data == expected_data, \
            f'Phase 2 Failed: {name} does not contain the required Base64-RLE data.'


def test_phase3_symlink():
    symlink_path = '/home/user/latest_archive'
    assert os.path.islink(symlink_path), f'Phase 3 Failed: {symlink_path} is not a symbolic link.'

    target = os.readlink(symlink_path)
    assert os.path.basename(os.path.normpath(target)) == 'archive_chunks', \
        f'Phase 3 Failed: Symlink points to {target}, expected it to point to archive_chunks.'
    assert os.path.realpath(symlink_path) == os.path.realpath('/home/user/archive_chunks'), \
        'Phase 3 Failed: latest_archive does not resolve to /home/user/archive_chunks/.'


def test_phase4_decompression_script():
    cmd = select_script()
    restored_file = '/home/user/restored_log.bin'
    original_file = '/home/user/massive_log.bin'
    chunks_dir = '/home/user/archive_chunks'

    # Preserve the original assertion: execute the submitted script on the archive
    # it created and compare its output with massive_log.bin.
    if os.path.lexists(restored_file):
        if os.path.isdir(restored_file) and not os.path.islink(restored_file):
            shutil.rmtree(restored_file)
        else:
            os.unlink(restored_file)

    run_script(cmd)
    assert os.path.isfile(restored_file), \
        f'Phase 4 Failed: {restored_file} was not created by the script.'

    with open(original_file, 'rb') as f1, open(restored_file, 'rb') as f2:
        original_data = f1.read()
        restored_data = f2.read()
    assert original_data == restored_data, \
        'Phase 4 Failed: The contents of restored_log.bin do not perfectly match massive_log.bin.'

    # Exercise the script against a fresh, unpredictable archive while making the
    # source file a different decoy. A script that merely copies massive_log.bin
    # therefore cannot pass.
    probe_data = make_unambiguous_probe()
    probe_chunks = expected_chunk_map(probe_data)
    token = uuid.uuid4().hex
    backup_root = f'/root/verifier-backup-{token}'
    backup_chunks = os.path.join(backup_root, 'archive_chunks')
    backup_massive = os.path.join(backup_root, 'massive_log.bin')
    os.mkdir(backup_root, 0o700)

    try:
        os.rename(chunks_dir, backup_chunks)
        os.rename(original_file, backup_massive)

        os.mkdir(chunks_dir, 0o755)
        for name, contents in probe_chunks.items():
            path = os.path.join(chunks_dir, name)
            with open(path, 'wb') as chunk_file:
                chunk_file.write(contents)
            os.chmod(path, 0o444)

        with open(original_file, 'wb') as decoy:
            decoy.write(os.urandom(len(probe_data) + 37))
        os.chmod(original_file, 0o444)

        if os.path.lexists(restored_file):
            if os.path.isdir(restored_file) and not os.path.islink(restored_file):
                shutil.rmtree(restored_file)
            else:
                os.unlink(restored_file)

        run_script(cmd)
        assert os.path.isfile(restored_file), \
            'Phase 4 Failed: The script did not create restored_log.bin for a fresh archive.'
        with open(restored_file, 'rb') as restored:
            probe_result = restored.read()
        assert probe_result == probe_data, \
            'Phase 4 Failed: The script did not actually merge and decompress the supplied chunks.'
    finally:
        if os.path.lexists(restored_file):
            if os.path.isdir(restored_file) and not os.path.islink(restored_file):
                shutil.rmtree(restored_file)
            else:
                os.unlink(restored_file)
        if os.path.lexists(chunks_dir):
            if os.path.isdir(chunks_dir) and not os.path.islink(chunks_dir):
                shutil.rmtree(chunks_dir)
            else:
                os.unlink(chunks_dir)
        if os.path.lexists(original_file):
            os.unlink(original_file)
        if os.path.exists(backup_chunks):
            os.rename(backup_chunks, chunks_dir)
        if os.path.exists(backup_massive):
            os.rename(backup_massive, original_file)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
