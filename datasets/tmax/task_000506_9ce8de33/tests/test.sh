#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_recovery.py
import cv2
import io
import math
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path

PROJECT = Path('/home/user/config_manager')
OUTPUT = Path('/home/user/final_state.dat')
EXTRACTED = Path('/home/user/extracted_configs')
VIDEO = Path('/app/stability.mp4')
ARCHIVES = Path('/app/archives')


def find_revision(video_path):
    cap = cv2.VideoCapture(str(video_path))
    assert cap.isOpened(), f'Could not open video: {video_path}'
    best_frame = None
    best_y = -1
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        ys, _ = (gray > 180).nonzero()
        assert len(ys), f'No stability indicator found in frame {index}'
        frame_y = int(ys.max())
        if frame_y > best_y:
            best_y = frame_y
            best_frame = index
        index += 1
    cap.release()
    assert index == 500, f'Expected 500 frames, decoded {index}'
    assert best_frame is not None
    return best_frame


def safe_name(name):
    p = Path(name)
    assert not p.is_absolute() and '..' not in p.parts, f'Unsafe archive member: {name}'
    return p.as_posix().lstrip('./')


def expected_state(video_path, archive_dir):
    revision = find_revision(video_path)
    restored = {}

    for i in range(revision + 1):
        zip_path = archive_dir / f'rev_{i}.zip'
        assert zip_path.is_file(), f'Missing archive {zip_path}'
        with zipfile.ZipFile(zip_path) as zf:
            tar_members = [n for n in zf.namelist() if n.lower().endswith('.tar')]
            assert tar_members, f'No tarball in {zip_path}'
            for tar_name in tar_members:
                with tarfile.open(fileobj=io.BytesIO(zf.read(tar_name)), mode='r:*') as tf:
                    for member in tf.getmembers():
                        if member.isfile():
                            src = tf.extractfile(member)
                            assert src is not None
                            restored[safe_name(member.name)] = src.read()

    renamed = {}
    for old_name in sorted(restored):
        new_name = re.sub(r'\.mod\d+$', '', old_name)
        if new_name in renamed:
            renamed[new_name] += restored[old_name]
        else:
            renamed[new_name] = restored[old_name]

    stream = b''.join(renamed[name] for name in sorted(renamed))
    encoded = bytearray()
    pos = 0
    while pos < len(stream):
        value = stream[pos]
        count = 1
        while pos + count < len(stream) and stream[pos + count] == value and count < 255:
            count += 1
        encoded.extend((count, value))
        pos += count

    return revision, renamed, bytes(encoded)


def clean_outputs():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    if EXTRACTED.exists():
        shutil.rmtree(EXTRACTED)


def run_tool():
    clean_outputs()
    result = subprocess.run(
        ['/usr/bin/cargo', 'run', '--quiet', '--offline'],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
        env={**os.environ, 'HOME': '/root', 'PATH': '/usr/bin:/bin:/usr/local/bin'},
    )
    assert result.returncode == 0, (
        'Rust tool failed:\n' + result.stdout.decode('utf-8', errors='replace')[-8000:]
    )


def verify_outputs(expected_files, expected_dat, label):
    assert OUTPUT.exists(), f'{label}: target file missing at {OUTPUT}'
    assert OUTPUT.is_file(), f'{label}: target path {OUTPUT} is not a file'
    actual_dat = OUTPUT.read_bytes()
    assert actual_dat == expected_dat, f'{label}: final_state.dat has incorrect RLE content'

    actual_files = {}
    assert EXTRACTED.is_dir(), f'{label}: extracted_configs directory is missing'
    for path in EXTRACTED.rglob('*'):
        if path.is_file():
            actual_files[path.relative_to(EXTRACTED).as_posix()] = path.read_bytes()
    assert actual_files == expected_files, f'{label}: extracted or renamed configuration files are incorrect'


def make_challenge_video(path, trigger):
    import numpy as np
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*'mp4v'), 10, (200, 200))
    assert writer.isOpened(), 'Could not create challenge video'
    for t in range(500):
        frame = np.zeros((200, 200, 3), dtype=np.uint8)
        y = 185 if t == trigger else int(90 + 70 * math.sin(t * 0.071))
        frame[y:y + 10, 100:110] = (255, 255, 255)
        writer.write(frame)
    writer.release()


def make_challenge_archive(path, token):
    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode='w') as tf:
        files = {
            'config_A.conf.mod1': b'Q' * 271 + token + b'R' * 19,
            'challenge.conf.mod7': token * 5 + b'\n',
        }
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))
    with zipfile.ZipFile(path, 'w') as zf:
        zf.writestr('payload.tar', tar_buffer.getvalue())


assert PROJECT.is_dir(), 'Missing /home/user/config_manager Cargo project'
assert (PROJECT / 'Cargo.toml').is_file(), 'Missing Cargo.toml'
rust_sources = list((PROJECT / 'src').rglob('*.rs')) if (PROJECT / 'src').is_dir() else []
assert rust_sources, 'Cargo project contains no Rust source files'
assert sum(p.stat().st_size for p in rust_sources) >= 500, 'Rust implementation is not substantive'

original_revision, original_files, original_dat = expected_state(VIDEO, ARCHIVES)
assert original_revision == 342, f'Original video revision should be 342, got {original_revision}'
assert len(original_dat) < 2692, 'Reference output does not satisfy the stated size threshold'

trigger = 25 + secrets.randbelow(50)
token = secrets.token_hex(24).encode('ascii')
video_backup = Path('/tmp/stability.original.mp4')
archive_path = ARCHIVES / f'rev_{trigger}.zip'
archive_backup = Path('/tmp/challenge.original.zip')
shutil.copy2(VIDEO, video_backup)
shutil.copy2(archive_path, archive_backup)

try:
    make_challenge_video(VIDEO, trigger)
    make_challenge_archive(archive_path, token)
    challenge_revision, challenge_files, challenge_dat = expected_state(VIDEO, ARCHIVES)
    assert challenge_revision == trigger
    run_tool()
    verify_outputs(challenge_files, challenge_dat, 'dynamic challenge')
finally:
    shutil.copy2(video_backup, VIDEO)
    shutil.copy2(archive_backup, archive_path)
    video_backup.unlink(missing_ok=True)
    archive_backup.unlink(missing_ok=True)

run_tool()
verify_outputs(original_files, original_dat, 'original recovery')
assert OUTPUT.stat().st_size < 2692, 'final_state.dat is not below the required size threshold'
PY_EOF

if python3 /tmp/verify_recovery.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
