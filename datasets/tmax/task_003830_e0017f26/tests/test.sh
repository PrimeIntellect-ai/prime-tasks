#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

TRUE_OFFSETS = {1024, 50000, 1048576, 25000000, 49999992}
MARKER = b'DOC_MARK'


def regular_script(path):
    p = Path(path)
    assert p.exists(), f"Required script {path} does not exist."
    assert not p.is_symlink(), f"Required script {path} must be a regular file, not a symlink."
    assert stat.S_ISREG(p.stat().st_mode), f"Required script {path} is not a regular file."
    return p.read_text()


def test_vendored_fix_is_installed():
    vendored = Path('/app/fs/fs/osfs.py')
    assert vendored.is_file(), "Vendored fs/osfs.py is missing."
    source = vendored.read_text()
    ast.parse(source)
    assert 'entry.is_symlink()' in source, (
        "The vendored OSFS implementation still does not evaluate directory-entry symlinks safely."
    )

    import fs.osfs
    installed = Path(fs.osfs.__file__)
    assert installed.is_file(), "The installed fs.osfs module has no Python source file."
    assert installed.read_bytes() == vendored.read_bytes(), (
        "The installed fs.osfs module does not match the repaired vendored implementation."
    )


def test_backup_script_and_copy():
    source = regular_script('/home/user/backup_docs.py')
    tree = ast.parse(source)

    imported_fs_copy = any(
        isinstance(node, ast.Import)
        and any(alias.name == 'fs.copy' for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imported_fs_copy, "backup_docs.py must import fs.copy."

    required_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if not (
            isinstance(func, ast.Attribute) and func.attr == 'copy_fs'
            and isinstance(func.value, ast.Attribute) and func.value.attr == 'copy'
            and isinstance(func.value.value, ast.Name) and func.value.value.id == 'fs'
        ):
            continue
        if len(node.args) >= 2:
            first = node.args[0]
            second = node.args[1]
            if (isinstance(first, ast.Constant) and first.value == 'osfs:///home/user/docs'
                    and isinstance(second, ast.Constant)
                    and second.value == 'osfs:///home/user/backup_staging'):
                required_call = True
                break
    assert required_call, (
        "backup_docs.py must call fs.copy.copy_fs with the two required OSFS URLs."
    )

    staging = Path('/home/user/backup_staging')
    if staging.exists() or staging.is_symlink():
        if staging.is_dir() and not staging.is_symlink():
            shutil.rmtree(staging)
        else:
            staging.unlink()
    staging.mkdir(parents=True)

    result = subprocess.run(
        ['python3', '/home/user/backup_docs.py'],
        cwd='/home/user', text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"backup_docs.py failed. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert (staging / 'file1.md').exists(), "The top-level documentation file was not copied."
    assert (staging / 'nested' / 'file2.md').exists(), "The nested documentation file was not copied."


def expected_offsets(path):
    data = Path(path).read_bytes()
    found = []
    start = 0
    while True:
        pos = data.find(MARKER, start)
        if pos < 0:
            return found
        found.append(pos)
        start = pos + 1


def read_offsets(path):
    with open(path, 'r') as f:
        lines = f.read().strip().split()
    assert all(x.isdigit() for x in lines), "offsets.txt must contain only integer offsets."
    return [int(x) for x in lines]


def run_process_meta(timeout=30):
    result = subprocess.run(
        ['python3', '/home/user/process_meta.py'],
        cwd='/home/user', text=True, capture_output=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"process_meta.py failed. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_process_meta_uses_mmap_and_handles_derived_input():
    source = regular_script('/home/user/process_meta.py')
    tree = ast.parse(source)
    imported_mmap = any(
        isinstance(node, ast.Import)
        and any(alias.name == 'mmap' for alias in node.names)
        for node in ast.walk(tree)
    )
    used_mmap = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == 'mmap'
        and node.func.attr == 'mmap'
        for node in ast.walk(tree)
    )
    assert imported_mmap, "process_meta.py must import the mmap module."
    assert used_mmap, "process_meta.py must create and use an mmap mapping."

    metadata = Path('/home/user/metadata.bin')
    saved = Path('/home/user/metadata.bin.verifier_saved')
    if saved.exists():
        saved.unlink()
    os.replace(metadata, saved)

    try:
        size = 2 * 1024 * 1024 + 137
        payload = bytearray(os.urandom(size))
        rng = random.SystemRandom()
        positions = sorted(rng.sample(range(32, size - len(MARKER) - 32), 9))
        for pos in positions:
            payload[pos:pos + len(MARKER)] = MARKER
        metadata.write_bytes(payload)

        derived_expected = expected_offsets(metadata)
        run_process_meta()
        actual = read_offsets('/home/user/offsets.txt')
        assert actual == derived_expected, (
            f"Offsets for verifier-generated metadata were {actual}, expected {derived_expected}."
        )
    finally:
        if metadata.exists():
            metadata.unlink()
        os.replace(saved, metadata)

    # Re-run against the real large metadata artifact and leave the requested output in place.
    run_process_meta(timeout=60)


def test_backup_staging_exists():
    backup_file = '/home/user/backup_staging/file1.md'
    assert os.path.exists(backup_file), (
        f"Backup file {backup_file} does not exist. "
        "The recursive copy likely failed due to the symlink loop."
    )


def test_offsets_f1_score():
    offsets_file = '/home/user/offsets.txt'
    assert os.path.exists(offsets_file), f"Offsets file {offsets_file} does not exist."

    try:
        with open(offsets_file, 'r') as f:
            lines = f.read().strip().split()
        predicted_offsets = {int(x) for x in lines if x.strip().isdigit()}
    except Exception as e:
        pytest.fail(f"Failed to read or parse {offsets_file}: {e}")

    true_positives = len(predicted_offsets.intersection(TRUE_OFFSETS))
    false_positives = len(predicted_offsets - TRUE_OFFSETS)
    false_negatives = len(TRUE_OFFSETS - predicted_offsets)

    if (true_positives + false_positives) == 0:
        precision = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)

    if (true_positives + false_negatives) == 0:
        recall = 0.0
    else:
        recall = true_positives / (true_positives + false_negatives)

    if precision + recall == 0:
        f1 = 0.0
    else:
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 1.0, (
        f"F1 score for found offsets is {f1:.2f}, which is below the threshold of 1.0. "
        f"Predicted: {predicted_offsets}, Expected: {TRUE_OFFSETS}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
