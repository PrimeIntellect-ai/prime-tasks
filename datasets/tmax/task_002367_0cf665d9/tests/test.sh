#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tarfile
import tempfile
import uuid

import imageio.v3 as iio
import numpy as np
from scipy.ndimage import gaussian_filter

SCRIPT_PATH = '/home/user/process_video.sh'
PROCESSED_DIR = '/home/user/processed'
PERCENTAGES = [10, 20, 30, 40, 50, 60, 70, 80, 90, 99]
EXPECTED_FILES = {f'fig_{i:02d}.jpg' for i in range(1, 11)} | {'manifest.sha256'}


def calculate_ssim(img1, img2):
    if img1.shape != img2.shape:
        return 0.0

    C1 = (0.01 * 255) ** 2
    C2 = (0.03 * 255) ** 2
    img1 = img1.astype(np.float64)
    img2 = img2.astype(np.float64)
    sigma = 1.5

    mu1 = gaussian_filter(img1, sigma)
    mu2 = gaussian_filter(img2, sigma)
    mu1_sq = mu1 ** 2
    mu2_sq = mu2 ** 2
    mu1_mu2 = mu1 * mu2
    sigma1_sq = gaussian_filter(img1 ** 2, sigma) - mu1_sq
    sigma2_sq = gaussian_filter(img2 ** 2, sigma) - mu2_sq
    sigma12 = gaussian_filter(img1 * img2, sigma) - mu1_mu2

    ssim_map = ((2 * mu1_mu2 + C1) * (2 * sigma12 + C2)) / (
        (mu1_sq + mu2_sq + C1) * (sigma1_sq + sigma2_sq + C2)
    )
    return float(np.mean(ssim_map))


def canonical_member_name(name):
    while name.startswith('./'):
        name = name[2:]
    return name


def safely_unpack_and_validate(archive_path, extract_dir):
    assert os.path.exists(archive_path), f'Archive not found: {archive_path}'
    assert tarfile.is_tarfile(archive_path), f'Not a valid tar archive: {archive_path}'

    regular_members = {}
    with tarfile.open(archive_path, 'r:gz') as tar:
        for member in tar.getmembers():
            name = canonical_member_name(member.name)
            assert name not in ('', '.', '..'), 'Invalid archive member name'
            assert not os.path.isabs(name), f'Absolute archive member: {member.name}'
            assert '..' not in name.split('/'), f'Unsafe archive member: {member.name}'

            if member.isdir():
                continue
            assert member.isfile(), f'Archive contains non-regular content: {member.name}'
            assert '/' not in name, f'Archive member is not at archive root: {member.name}'
            assert name not in regular_members, f'Duplicate archive member: {name}'
            regular_members[name] = member

        assert set(regular_members) == EXPECTED_FILES, (
            f'Expected exactly {sorted(EXPECTED_FILES)}, found {sorted(regular_members)}'
        )

        for name, member in regular_members.items():
            source = tar.extractfile(member)
            assert source is not None, f'Could not read archive member: {name}'
            with open(os.path.join(extract_dir, name), 'wb') as out:
                out.write(source.read())


def verify_manifest(extract_dir):
    manifest_path = os.path.join(extract_dir, 'manifest.sha256')
    assert os.path.exists(manifest_path), 'manifest.sha256 not found in extracted archive'

    with open(manifest_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Preserve the original assertion that exactly ten image entries are present.
    jpg_lines = [line for line in lines if '.jpg' in line]
    assert len(jpg_lines) == 10, (
        f'Expected 10 image checksums in manifest, found {len(jpg_lines)}'
    )
    assert len(lines) == 10, f'Expected exactly 10 manifest lines, found {len(lines)}'

    entries = {}
    pattern = re.compile(r'^([0-9a-fA-F]{64}) [ *](fig_[0-9]{2}\.jpg)$')
    for line in lines:
        match = pattern.fullmatch(line.rstrip('\n'))
        assert match, f'Invalid manifest line: {line!r}'
        digest, filename = match.groups()
        assert filename not in entries, f'Duplicate manifest entry: {filename}'
        entries[filename] = digest.lower()

    expected_images = {f'fig_{i:02d}.jpg' for i in range(1, 11)}
    assert set(entries) == expected_images, 'Manifest filenames are not fig_01.jpg through fig_10.jpg'

    for filename, expected_digest in entries.items():
        with open(os.path.join(extract_dir, filename), 'rb') as f:
            actual_digest = hashlib.sha256(f.read()).hexdigest()
        assert actual_digest == expected_digest, f'Incorrect SHA256 for {filename}'


def video_duration(video_path):
    cmd = [
        'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', video_path,
    ]
    try:
        return float(subprocess.check_output(cmd, text=True).strip())
    except Exception as exc:
        raise AssertionError(f'Failed to get video duration: {exc}')


def verify_frames(video_path, extract_dir):
    duration = video_duration(video_path)
    scores = []

    with tempfile.TemporaryDirectory(prefix='golden_frames_') as golden_dir:
        for i, percentage in enumerate(PERCENTAGES, 1):
            timestamp = duration * (percentage / 100.0)
            golden_path = os.path.join(golden_dir, f'fig_{i:02d}.jpg')
            subprocess.run(
                [
                    'ffmpeg', '-y', '-ss', str(timestamp), '-i', video_path,
                    '-frames:v', '1', '-q:v', '2', golden_path,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )

            agent_path = os.path.join(extract_dir, f'fig_{i:02d}.jpg')
            assert os.path.exists(agent_path), f'Agent image not found: fig_{i:02d}.jpg'
            agent_img = iio.imread(agent_path)
            golden_img = iio.imread(golden_path)

            if agent_img.ndim == 3:
                agent_img = np.dot(agent_img[..., :3], [0.2989, 0.5870, 0.1140])
            if golden_img.ndim == 3:
                golden_img = np.dot(golden_img[..., :3], [0.2989, 0.5870, 0.1140])

            scores.append(calculate_ssim(golden_img, agent_img))

    avg_ssim = sum(scores) / len(scores)
    assert avg_ssim >= 0.90, f'Average SSIM {avg_ssim:.4f} is below threshold 0.90'


def verify_archive(archive_path, video_path):
    with tempfile.TemporaryDirectory(prefix='agent_frames_') as extract_dir:
        safely_unpack_and_validate(archive_path, extract_dir)
        verify_manifest(extract_dir)
        verify_frames(video_path, extract_dir)


def test_00_script_exists_and_processes_an_argument():
    assert os.path.exists(SCRIPT_PATH), f'Script not found: {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'Not a regular file: {SCRIPT_PATH}'

    token = uuid.uuid4().hex
    duration = secrets.choice([6, 7, 8, 9])
    width, height = secrets.choice([(320, 240), (352, 288), (480, 270)])
    hue = secrets.randbelow(360)
    video_path = f'/tmp/{token}.mp4'
    archive_path = os.path.join(PROCESSED_DIR, f'{token}_assets.tar.gz')

    subprocess.run(
        [
            'ffmpeg', '-y', '-f', 'lavfi',
            '-i', f'testsrc2=duration={duration}:size={width}x{height}:rate=30',
            '-vf', f'hue=h={hue}', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
            video_path,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )

    if os.path.exists(archive_path):
        os.remove(archive_path)
    subprocess.run(['bash', SCRIPT_PATH, video_path], check=True, timeout=180)
    verify_archive(archive_path, video_path)


def test_video_processing_ssim():
    verify_archive(
        '/home/user/processed/tutorial_assets.tar.gz',
        '/app/tutorial.mp4',
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
