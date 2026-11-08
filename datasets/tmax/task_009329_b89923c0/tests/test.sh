#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import pathlib
import subprocess
import tarfile
import uuid
from collections import Counter

import pytest


def test_safe_extract_script_exists():
    assert os.path.isfile('/home/user/safe_extract.py'), "/home/user/safe_extract.py is missing"


def test_safe_extract_script_behavior():
    token = uuid.uuid4().hex
    sandbox = pathlib.Path('/tmp') / f'safe_extract_verify_{token}'
    target = sandbox / 'target'
    sandbox.mkdir()
    target.mkdir()

    outside_relative = pathlib.Path('/tmp') / f'escape_{token}.txt'
    outside_absolute = pathlib.Path('/tmp') / f'absolute_{token}.txt'
    assert not outside_relative.exists()
    assert not outside_absolute.exists()

    payloads = {
        'normal/deep/ordinary.txt': f'ordinary-{token}'.encode(),
        f'../../escape_{token}.txt': f'relative-{token}'.encode(),
        str(outside_absolute): f'absolute-{token}'.encode(),
        f'../nested/../neutralized_{token}.txt': f'neutralized-{token}'.encode(),
    }

    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode='w') as tf:
        for name, content in payloads.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(content)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(content))

    result = subprocess.run(
        ['python3', '/home/user/safe_extract.py', str(target)],
        input=archive.getvalue(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        'safe_extract.py failed when reading a tar archive from stdin: '
        + result.stderr.decode(errors='replace')
    )

    assert not outside_relative.exists(), 'Relative traversal escaped the target directory'
    assert not outside_absolute.exists(), 'Absolute archive path escaped the target directory'
    assert (target / 'normal/deep/ordinary.txt').read_bytes() == payloads['normal/deep/ordinary.txt']

    files = []
    for path in target.rglob('*'):
        assert not path.is_symlink(), f'Extractor unexpectedly created a symlink: {path}'
        if path.is_file():
            assert target.resolve() in path.resolve().parents
            files.append(path.read_bytes())

    assert Counter(files) == Counter(payloads.values()), (
        'All archive file payloads must be extracted exactly once within the target directory'
    )


def test_no_path_traversal_escape():
    assert not os.path.exists('/tmp/escaped.txt'), "Path traversal vulnerability exploited: /tmp/escaped.txt was created"


def test_extracted_source_state_and_moves():
    root = pathlib.Path('/home/user/safe_output')
    expected_chunks = {
        'app.log.aa': b'chunk1\n',
        'app.log.ab': b'chunk2\n',
        'app.log.ac': b'chunk3\n',
    }
    for name, content in expected_chunks.items():
        path = root / 'logs' / name
        assert path.is_file(), f'{path} is missing from the extracted archive'
        assert path.read_bytes() == content, f'{path} has incorrect content'

    assert not (root / 'data/metric_a1.data').exists(), 'metric_a1.data was not moved from safe_output/data'
    assert not (root / 'data/metric_b2.data').exists(), 'metric_b2.data was not moved from safe_output/data'


def test_app_complete_log():
    log_path = '/home/user/final_data/app_complete.log'
    assert os.path.isfile(log_path), f"{log_path} is missing"

    with open(log_path, 'r') as f:
        content = f.read()

    assert "chunk1" in content, "app_complete.log does not contain 'chunk1'"
    assert "chunk2" in content, "app_complete.log does not contain 'chunk2'"
    assert "chunk3" in content, "app_complete.log does not contain 'chunk3'"

    idx1 = content.find("chunk1")
    idx2 = content.find("chunk2")
    idx3 = content.find("chunk3")
    assert idx1 < idx2 < idx3, "Log chunks are not in alphabetical order"
    assert content == 'chunk1\nchunk2\nchunk3\n', 'app_complete.log is not the exact ordered merge of the chunks'


def test_bulk_renaming():
    csv1 = '/home/user/final_data/processed_metric_a1.csv'
    csv2 = '/home/user/final_data/processed_metric_b2.csv'

    assert os.path.isfile(csv1), f"{csv1} is missing"
    assert os.path.isfile(csv2), f"{csv2} is missing"

    with open(csv1, 'r') as f:
        assert "1,2,3" in f.read(), f"Content of {csv1} is incorrect"

    with open(csv2, 'r') as f:
        assert "4,5,6" in f.read(), f"Content of {csv2} is incorrect"

    assert pathlib.Path(csv1).read_bytes() == b'1,2,3\n'
    assert pathlib.Path(csv2).read_bytes() == b'4,5,6\n'


def _changed_final_files():
    final_root = pathlib.Path('/home/user/final_data')
    base_root = pathlib.Path('/home/user/base_backup')
    changed = {}
    for path in final_root.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        rel = path.relative_to(final_root).as_posix()
        base = base_root / rel
        content = path.read_bytes()
        if not base.is_file() or base.read_bytes() != content:
            changed[rel] = content
    return changed


def _match_archive_name(name, expected_names):
    pure = pathlib.PurePosixPath(name)
    assert not pure.is_absolute(), f'Differential archive contains an absolute path: {name}'
    parts = tuple(part for part in pure.parts if part not in ('', '.'))
    assert '..' not in parts, f'Differential archive contains path traversal: {name}'

    matches = []
    for expected in expected_names:
        expected_parts = pathlib.PurePosixPath(expected).parts
        if len(parts) >= len(expected_parts) and parts[-len(expected_parts):] == expected_parts:
            matches.append(expected)
    assert len(matches) == 1, f'Unexpected or ambiguous file in differential archive: {name}'
    return matches[0]


def test_diff_backup_tar():
    tar_path = '/home/user/diff_backup.tar'
    assert os.path.isfile(tar_path), f"{tar_path} is missing"

    try:
        with tarfile.open(tar_path, 'r') as tar:
            names = tar.getnames()
    except tarfile.TarError:
        pytest.fail(f"{tar_path} is not a valid tar archive")

    basenames = [os.path.basename(name) for name in names]

    assert "app_complete.log" in basenames, "app_complete.log is missing from diff_backup.tar"
    assert "processed_metric_a1.csv" in basenames, "processed_metric_a1.csv is missing from diff_backup.tar"
    assert "processed_metric_b2.csv" in basenames, "processed_metric_b2.csv is missing from diff_backup.tar"
    assert "processed_metric_old.csv" not in basenames, "processed_metric_old.csv should not be in the differential backup"

    expected = _changed_final_files()
    assert expected, 'No new or changed final-data files were found'

    archived = {}
    with tarfile.open(tar_path, 'r') as tar:
        for member in tar.getmembers():
            if member.isdir():
                continue
            assert member.isfile(), f'Unexpected non-regular member in differential archive: {member.name}'
            rel = _match_archive_name(member.name, expected.keys())
            assert rel not in archived, f'Duplicate differential archive entry for {rel}'
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived[rel] = extracted.read()

    assert set(archived) == set(expected), (
        'Differential archive must contain exactly the files new or changed relative to base_backup'
    )
    for rel, content in expected.items():
        assert archived[rel] == content, f'Differential archive content is incorrect for {rel}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
