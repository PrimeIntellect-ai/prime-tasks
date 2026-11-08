#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import bz2
import cv2
import hashlib
import io
import os
import re
import tarfile
import zipfile

DATA_DIR = '/home/user/data'
ARCHIVE_PATH = '/home/user/optimized_data.tar.gz'
EXPECTED_FILES = {
    'file1.bin',
    'file2.bin',
    'file3.bin',
    'sub/file4.bin',
    'sub/file5.bin',
}


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def normalize_member_name(name):
    if name.startswith('/'):
        raise AssertionError(f'Archive contains an absolute path: {name!r}')
    while name.startswith('./'):
        name = name[2:]
    parts = [p for p in name.split('/') if p not in ('', '.')]
    if '..' in parts:
        raise AssertionError(f'Archive contains path traversal: {name!r}')
    clean = '/'.join(parts)
    for root in ('home/user/data', 'data'):
        if clean == root:
            return ''
        if clean.startswith(root + '/'):
            return clean[len(root) + 1:]
    return clean


def incident_paths():
    outer_path = '/home/user/backups/incident_logs.tar.gz'
    assert os.path.isfile(outer_path), 'The nested incident archive is missing'
    with tarfile.open(outer_path, 'r:gz') as outer:
        candidates = [m for m in outer.getmembers() if m.isfile() and m.name.endswith('.zip')]
        assert len(candidates) == 1, 'Expected exactly one zip archive in the outer archive'
        zip_bytes = outer.extractfile(candidates[0]).read()

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as middle:
        candidates = [n for n in middle.namelist() if n.endswith('.tar.bz2')]
        assert len(candidates) == 1, 'Expected exactly one tar.bz2 in the zip archive'
        inner_bytes = middle.read(candidates[0])

    with tarfile.open(fileobj=io.BytesIO(inner_bytes), mode='r:bz2') as inner:
        candidates = [m for m in inner.getmembers() if m.isfile() and m.name.endswith('error.log')]
        assert len(candidates) == 1, 'Expected exactly one error.log in the inner archive'
        log = inner.extractfile(candidates[0]).read().decode('utf-8')

    prefix = 'ELOOP: Too many levels of symbolic links: '
    paths = {
        line[len(prefix):]
        for line in log.splitlines()
        if line.startswith(prefix)
    }
    assert paths, 'No ELOOP paths were found in error.log'
    return paths


def test_video_result_is_derived_from_the_video():
    cap = cv2.VideoCapture('/app/disk_monitor.mp4')
    assert cap.isOpened(), 'Unable to open disk_monitor.mp4'
    expected = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        region = frame[0:10, 0:10]
        red_pixels = ((region[:, :, 2] > 200) &
                      (region[:, :, 1] < 50) &
                      (region[:, :, 0] < 50))
        if int(red_pixels.sum()) >= 50:
            expected += 1
    cap.release()

    assert expected == 67, f'Unexpected source-video alert count: {expected}'
    with open('/home/user/alert_frames.txt', 'r') as f:
        result = int(f.read().strip())
    assert result == expected, f'Alert count is {result}, expected {expected}'


def test_cleanup_deduplication_and_archive_contents():
    bad_paths = incident_paths()
    for path in bad_paths:
        assert os.path.commonpath([DATA_DIR, os.path.abspath(path)]) == DATA_DIR, path
        assert not os.path.lexists(path), f'Offending symlink was not deleted: {path}'

    actual_files = set()
    for root, dirs, files in os.walk(DATA_DIR, followlinks=False):
        for name in dirs + files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f'Symlink remains in data directory: {path}'
        for name in files:
            path = os.path.join(root, name)
            assert os.path.isfile(path), f'Non-regular data entry: {path}'
            actual_files.add(os.path.relpath(path, DATA_DIR))
    assert actual_files == EXPECTED_FILES, f'Unexpected live data files: {actual_files}'

    live_hashes = {rel: file_hash(os.path.join(DATA_DIR, rel)) for rel in EXPECTED_FILES}
    live_stats = {rel: os.stat(os.path.join(DATA_DIR, rel)) for rel in EXPECTED_FILES}
    for rel in EXPECTED_FILES:
        assert live_stats[rel].st_size == 5 * 1024 * 1024, f'Wrong size for {rel}'

    group1 = {'file1.bin', 'file2.bin', 'file3.bin'}
    group2 = {'sub/file4.bin', 'sub/file5.bin'}
    assert len({live_hashes[p] for p in group1}) == 1, 'file1-file3 are no longer duplicates'
    assert len({live_hashes[p] for p in group2}) == 1, 'file4-file5 are no longer duplicates'
    assert live_hashes['file1.bin'] != live_hashes['sub/file4.bin'], 'The two original datasets must differ'
    assert len({(live_stats[p].st_dev, live_stats[p].st_ino) for p in group1}) == 1, 'file1-file3 were not hardlinked'
    assert len({(live_stats[p].st_dev, live_stats[p].st_ino) for p in group2}) == 1, 'file4-file5 were not hardlinked'

    assert os.path.isfile(ARCHIVE_PATH), 'optimized_data.tar.gz is missing'
    with open(ARCHIVE_PATH, 'rb') as f:
        assert f.read(2) == b'\x1f\x8b', 'Archive is not gzip data'
    assert os.path.getsize(ARCHIVE_PATH) >= int(9.5 * 1024 * 1024), 'Archive is implausibly smaller than the incompressible unique data'

    with tarfile.open(ARCHIVE_PATH, 'r:gz') as archive:
        members = archive.getmembers()
        files = {}
        for member in members:
            rel = normalize_member_name(member.name)
            if member.isdir():
                continue
            assert member.isfile() or member.islnk(), f'Unsupported or unsafe archive entry: {member.name}'
            assert rel and rel not in files, f'Duplicate archive path: {rel}'
            files[rel] = member

        assert set(files) == EXPECTED_FILES, f'Archive file set is wrong: {set(files)}'
        assert sum(m.islnk() for m in files.values()) == 3, 'Archive does not preserve the three duplicate files as hardlinks'
        assert sum(m.isfile() for m in files.values()) == 2, 'Archive should store only the two unique file payloads'

        def canonical(rel, seen=None):
            seen = set() if seen is None else seen
            assert rel not in seen, f'Hardlink cycle in archive at {rel}'
            seen.add(rel)
            member = files[rel]
            if member.isfile():
                return rel
            target = normalize_member_name(member.linkname)
            assert target in files, f'Hardlink target is missing: {member.linkname}'
            return canonical(target, seen)

        assert len({canonical(p) for p in group1}) == 1, 'Archive does not hardlink file1-file3 together'
        assert len({canonical(p) for p in group2}) == 1, 'Archive does not hardlink file4-file5 together'
        assert canonical('file1.bin') != canonical('sub/file4.bin'), 'Distinct data groups share one archive payload'

        for rel, member in files.items():
            stream = archive.extractfile(member)
            assert stream is not None, f'Cannot read archived file: {rel}'
            h = hashlib.sha256()
            size = 0
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                size += len(chunk)
                h.update(chunk)
            assert size == live_stats[rel].st_size, f'Archived size differs for {rel}'
            assert h.hexdigest() == live_hashes[rel], f'Archived content differs for {rel}'


def test_task_metric_threshold():
    target_frames = 67

    # Compute the optimal archive size based on the unique file contents in /home/user/data.
    # Since the files are generated from /dev/urandom, they are incompressible, so the optimal
    # gzip tarball size is approximately the sum of the unique file sizes.
    unique_hashes = set()
    optimal_size_bytes = 0
    data_dir = '/home/user/data'

    if os.path.exists(data_dir):
        for root, dirs, files in os.walk(data_dir):
            for f in files:
                p = os.path.join(root, f)
                if os.path.isfile(p) and not os.path.islink(p):
                    try:
                        with open(p, 'rb') as fobj:
                            h = hashlib.md5(fobj.read()).hexdigest()
                        if h not in unique_hashes:
                            unique_hashes.add(h)
                            optimal_size_bytes += os.path.getsize(p)
                    except Exception:
                        pass

    # Convert to MB
    optimal_archive_size_mb = optimal_size_bytes / (1024 * 1024)

    # 1. Check frame count
    try:
        with open('/home/user/alert_frames.txt', 'r') as f:
            agent_frames = int(f.read().strip())
    except Exception:
        agent_frames = 0

    frame_error = abs(agent_frames - target_frames)

    # 2. Check archive size
    archive_path = '/home/user/optimized_data.tar.gz'
    try:
        actual_size = os.path.getsize(archive_path) / (1024 * 1024)
    except Exception:
        actual_size = 1000.0  # heavy penalty if missing

    size_error = max(0, actual_size - optimal_archive_size_mb)

    # 3. Calculate composite error score
    total_error = frame_error + size_error

    assert total_error <= 5.0, (
        f"Metric threshold exceeded: total_error={total_error:.2f} > 5.0. "
        f"Frame error={frame_error} (agent={agent_frames}, target={target_frames}), "
        f"Size error={size_error:.2f}MB (actual={actual_size:.2f}MB, optimal={optimal_archive_size_mb:.2f}MB)."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
