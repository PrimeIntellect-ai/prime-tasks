#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
import uuid

V1_DIR = '/home/user/snapshots/v1'
V2_DIR = '/home/user/snapshots/v2'
RAW_DIR = '/home/user/raw_data'
TAR_PATH = '/home/user/patch_v1_to_v2.tar.gz'
REPORT_PATH = '/home/user/report.txt'
SCRIPT_PATH = '/home/user/create_snapshot.py'


def test_snapshot_script_exists_and_works_generically():
    assert os.path.exists(SCRIPT_PATH), f"Snapshot script {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    with tempfile.TemporaryDirectory(prefix='snapshot_verifier_') as root:
        source = os.path.join(root, 'source')
        previous = os.path.join(root, 'previous')
        destination = os.path.join(root, 'destination')
        os.mkdir(source)
        os.mkdir(previous)
        os.mkdir(destination)

        token = uuid.uuid4().hex
        unchanged = f'unchanged_{token}.bin'
        modified = f'modified_{token}.bin'
        new_file = f'new_{token}.bin'
        deleted = f'deleted_{token}.bin'
        stale = f'stale_{token}.bin'

        def write_file(directory, name, data, mtime_ns):
            path = os.path.join(directory, name)
            with open(path, 'wb') as handle:
                handle.write(data)
            os.utime(path, ns=(mtime_ns, mtime_ns))
            return path

        unchanged_time = 1672531200123456789
        old_time = 1672531300123456789
        new_time = 1672531400123456789

        prev_unchanged = write_file(previous, unchanged, b'unchanged-' + token.encode(), unchanged_time)
        src_unchanged = write_file(source, unchanged, b'unchanged-' + token.encode(), unchanged_time)
        prev_modified = write_file(previous, modified, b'old-' + token.encode(), old_time)
        src_modified = write_file(source, modified, b'new-and-longer-' + token.encode(), new_time)
        src_new = write_file(source, new_file, b'brand-new-' + token.encode(), new_time)
        write_file(previous, deleted, b'deleted-' + token.encode(), old_time)

        write_file(destination, stale, b'stale', old_time)
        write_file(destination, unchanged, b'incorrect-existing-data', old_time)
        write_file(destination, modified, b'incorrect-existing-data', old_time)

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH, source, destination, previous],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Snapshot script failed when called with the required three arguments. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        expected = {unchanged, modified, new_file}
        assert set(os.listdir(destination)) == expected, (
            'The script did not synchronize a fresh fixture exactly, including removal of stale files.'
        )

        for name in expected:
            src_path = os.path.join(source, name)
            dst_path = os.path.join(destination, name)
            assert stat.S_ISREG(os.lstat(dst_path).st_mode), f"{dst_path} is not a regular file."
            with open(src_path, 'rb') as src_handle, open(dst_path, 'rb') as dst_handle:
                assert src_handle.read() == dst_handle.read(), f"Incorrect copied content for {name}."
            assert os.stat(src_path).st_mtime_ns == os.stat(dst_path).st_mtime_ns, (
                f"Modification time was not preserved for {name}."
            )

        dst_unchanged = os.path.join(destination, unchanged)
        assert os.stat(prev_unchanged).st_dev == os.stat(dst_unchanged).st_dev
        assert os.stat(prev_unchanged).st_ino == os.stat(dst_unchanged).st_ino, (
            'An unchanged file was not hard-linked from the previous snapshot.'
        )

        dst_modified = os.path.join(destination, modified)
        assert (os.stat(prev_modified).st_dev, os.stat(prev_modified).st_ino) != (
            os.stat(dst_modified).st_dev, os.stat(dst_modified).st_ino
        ), 'A modified file was incorrectly hard-linked from the previous snapshot.'
        assert (os.stat(src_modified).st_dev, os.stat(src_modified).st_ino) != (
            os.stat(dst_modified).st_dev, os.stat(dst_modified).st_ino
        ), 'A modified file was linked rather than copied as a standard file.'

        dst_new = os.path.join(destination, new_file)
        assert (os.stat(src_new).st_dev, os.stat(src_new).st_ino) != (
            os.stat(dst_new).st_dev, os.stat(dst_new).st_ino
        ), 'A new file was linked rather than copied as a standard file.'
        assert os.path.exists(src_unchanged), 'The script improperly removed a source file.'


def test_v2_directory_exists():
    assert os.path.isdir(V2_DIR), f"The destination directory {V2_DIR} was not created."


def test_v2_matches_raw_data():
    raw_files = set(os.listdir(RAW_DIR))
    v2_files = set(os.listdir(V2_DIR))

    assert raw_files == v2_files, f"Files in {V2_DIR} do not match {RAW_DIR}. Expected {raw_files}, got {v2_files}"

    for filename in raw_files:
        raw_path = os.path.join(RAW_DIR, filename)
        v2_path = os.path.join(V2_DIR, filename)

        with open(raw_path, 'rb') as f1, open(v2_path, 'rb') as f2:
            assert f1.read() == f2.read(), f"Content of {v2_path} does not match {raw_path}"


def test_hardlinks_for_unmodified_files():
    for filename in ['unchanged1.txt', 'unchanged2.txt']:
        v1_path = os.path.join(V1_DIR, filename)
        v2_path = os.path.join(V2_DIR, filename)

        assert os.path.exists(v1_path), f"Expected file {v1_path} is missing."
        assert os.path.exists(v2_path), f"Expected file {v2_path} is missing."

        stat_v1 = os.stat(v1_path)
        stat_v2 = os.stat(v2_path)

        assert stat_v1.st_ino == stat_v2.st_ino, f"File {filename} is not hardlinked between v1 and v2."


def test_no_hardlinks_for_modified_files():
    filename = 'modified1.txt'
    v1_path = os.path.join(V1_DIR, filename)
    v2_path = os.path.join(V2_DIR, filename)

    assert os.path.exists(v1_path), f"Expected file {v1_path} is missing."
    assert os.path.exists(v2_path), f"Expected file {v2_path} is missing."

    stat_v1 = os.stat(v1_path)
    stat_v2 = os.stat(v2_path)

    assert stat_v1.st_ino != stat_v2.st_ino, f"File {filename} is incorrectly hardlinked between v1 and v2."


def expected_incremental_files():
    expected = set()
    for filename in os.listdir(V2_DIR):
        v2_path = os.path.join(V2_DIR, filename)
        v1_path = os.path.join(V1_DIR, filename)
        if not os.path.exists(v1_path):
            expected.add(filename)
            continue
        v1_stat = os.stat(v1_path)
        v2_stat = os.stat(v2_path)
        if v1_stat.st_size != v2_stat.st_size or v1_stat.st_mtime_ns != v2_stat.st_mtime_ns:
            expected.add(filename)
    return expected


def test_patch_archive_contents():
    assert os.path.isfile(TAR_PATH), f"Patch archive {TAR_PATH} is missing."

    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        names = tar.getnames()
        normalized_names = {n.lstrip('./') for n in names}

        expected = {'modified1.txt', 'new1.txt', 'new2.txt'}
        assert expected == normalized_names, f"Tarball contents incorrect. Expected {expected}, got {normalized_names}"

        derived_expected = expected_incremental_files()
        assert normalized_names == derived_expected, (
            f"Archive members do not match the files derived from v1 and v2: {derived_expected}"
        )
        assert len(names) == len(normalized_names), 'The archive contains duplicate members.'

        for member in tar.getmembers():
            normalized = member.name.lstrip('./')
            assert member.name in (normalized, './' + normalized), f"Unsafe or non-relative archive path: {member.name}"
            assert normalized in derived_expected, f"Unexpected archive member: {member.name}"
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            archived = tar.extractfile(member)
            assert archived is not None
            with archived, open(os.path.join(V2_DIR, normalized), 'rb') as expected_file:
                assert archived.read() == expected_file.read(), (
                    f"Archived content for {normalized} does not match the v2 snapshot."
                )


def derived_report_lines():
    new_count = 0
    modified_count = 0
    unmodified_count = 0
    for filename in os.listdir(V2_DIR):
        v2_path = os.path.join(V2_DIR, filename)
        v1_path = os.path.join(V1_DIR, filename)
        if not os.path.exists(v1_path):
            new_count += 1
            continue
        v1_stat = os.stat(v1_path)
        v2_stat = os.stat(v2_path)
        if v1_stat.st_size == v2_stat.st_size and v1_stat.st_mtime_ns == v2_stat.st_mtime_ns:
            unmodified_count += 1
        else:
            modified_count += 1
    return [
        f'New files: {new_count}',
        f'Modified files: {modified_count}',
        f'Unmodified files: {unmodified_count}',
    ]


def test_report_contents():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

    with open(REPORT_PATH, 'r') as f:
        report = f.read().strip()

    assert "New files: 2" in report, "Report does not correctly state 'New files: 2'"
    assert "Modified files: 1" in report, "Report does not correctly state 'Modified files: 1'"
    assert "Unmodified files: 2" in report, "Report does not correctly state 'Unmodified files: 2'"

    with open(REPORT_PATH, 'r') as f:
        exact_lines = f.read().splitlines()
    assert exact_lines == derived_report_lines(), (
        f"Report must contain exactly the three required lines. Got {exact_lines!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
