#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tarfile

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
import pytest


def compute_ssim(img1, img2):
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
    return ssim_map.mean()


def extract_reference_frames():
    os.makedirs('/tmp/golden_frames', exist_ok=True)
    for frame in range(0, 1001, 25):
        output = f'/tmp/golden_frames/frame_{frame}.jpg'
        cmd = [
            'ffmpeg', '-loglevel', 'error', '-i', '/app/experiment.mp4',
            '-vf', f'select=eq(n\\,{frame})', '-vsync', 'vfr',
            '-q:v', '2', output, '-y'
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def load_raw_metadata():
    by_frame = {}
    for root, _, files in os.walk('/home/user/raw_metadata'):
        for name in files:
            if not name.endswith('.json'):
                continue
            path = os.path.join(root, name)
            with open(path, 'r', encoding='utf-8') as handle:
                data = json.load(handle)
            if 'target_frame' in data:
                frame = data['target_frame']
                assert isinstance(frame, int) and not isinstance(frame, bool), \
                    f'Invalid target_frame in {path}'
                assert frame not in by_frame, f'Duplicate metadata for frame {frame}'
                by_frame[frame] = path
    return by_frame


def canonical_tar_name(name):
    name = name.replace('\\', '/')
    while name.startswith('./'):
        name = name[2:]
    return name.lstrip('/')


def is_curated_member(member, expected_name):
    name = canonical_tar_name(member.name)
    if os.path.basename(name) != expected_name:
        return False
    parent_parts = name.split('/')[:-1]
    return not parent_parts or 'curated_dataset' in parent_parts


def hardlink_targets(member):
    target = canonical_tar_name(member.linkname)
    targets = {target}
    parent = os.path.dirname(canonical_tar_name(member.name))
    if parent:
        targets.add(canonical_tar_name(os.path.join(parent, member.linkname)))
    return targets


def test_final_state():
    extract_reference_frames()

    curated_dir = '/home/user/curated_dataset'
    assert os.path.isdir(curated_dir), f'Curated directory not found at {curated_dir}'

    expected_frames = list(range(0, 1001, 25))
    raw_metadata = load_raw_metadata()
    assert set(expected_frames).issubset(raw_metadata), 'Raw metadata is missing expected target frames'

    expected_names = set()
    total_ssim = 0.0
    count = 0

    for frame in expected_frames:
        padded = str(frame).zfill(6)
        jpg_name = f'sample_{padded}.jpg'
        json_name = f'sample_{padded}.json'
        expected_names.update((jpg_name, json_name))

        agent_img = os.path.join(curated_dir, jpg_name)
        agent_json = os.path.join(curated_dir, json_name)
        golden_img = f'/tmp/golden_frames/frame_{frame}.jpg'

        assert os.path.exists(golden_img), f'Test setup failed to extract golden frame {frame}'
        assert os.path.isfile(agent_img), f'Missing expected extracted frame at {agent_img}'
        assert not os.path.islink(agent_img), f'{agent_img} must be a hard link, not a symbolic link'
        img_stat = os.stat(agent_img)
        assert stat.S_ISREG(img_stat.st_mode), f'{agent_img} is not a regular file'
        assert img_stat.st_nlink >= 2, f'{agent_img} is not hard-linked to its extracted source image'

        imgA = np.array(Image.open(golden_img).convert('L'))
        imgB = Image.open(agent_img).convert('L')
        imgB = imgB.resize((imgA.shape[1], imgA.shape[0]))
        imgB = np.array(imgB)
        total_ssim += compute_ssim(imgA, imgB)
        count += 1

        assert os.path.isfile(agent_json), f'Missing matching metadata at {agent_json}'
        assert not os.path.islink(agent_json), f'{agent_json} must be a hard link, not a symbolic link'
        curated_stat = os.stat(agent_json)
        raw_stat = os.stat(raw_metadata[frame])
        assert (curated_stat.st_dev, curated_stat.st_ino) == (raw_stat.st_dev, raw_stat.st_ino), \
            f'{agent_json} is not a hard link to the matching raw metadata file'
        with open(agent_json, 'r', encoding='utf-8') as handle:
            curated_metadata = json.load(handle)
        assert curated_metadata.get('target_frame') == frame, \
            f'{agent_json} has the wrong target_frame'

    actual_names = set(os.listdir(curated_dir))
    assert actual_names == expected_names, \
        f'Curated dataset has unexpected or missing entries: {sorted(actual_names ^ expected_names)}'

    avg_ssim = total_ssim / count if count else 0.0

    backup_path = '/home/user/dataset_backup.tar.gz'
    assert os.path.exists(backup_path), f'Backup archive not found at {backup_path}'

    try:
        with tarfile.open(backup_path, 'r:gz') as tar:
            members = tar.getmembers()
            assert len(members) >= 40, \
                f'Archive contains too few members ({len(members)}). It should contain the dataset.'

            names_to_members = {}
            incoming_hardlinks = set()
            for member in members:
                canonical = canonical_tar_name(member.name)
                assert canonical not in names_to_members, f'Duplicate archive member {member.name}'
                names_to_members[canonical] = member
                if member.islnk():
                    incoming_hardlinks.update(hardlink_targets(member))

            for expected_name in sorted(expected_names):
                candidates = [m for m in members if is_curated_member(m, expected_name)]
                assert len(candidates) == 1, \
                    f'Archive must contain exactly one curated member named {expected_name}'
                member = candidates[0]
                assert member.isfile() or member.islnk(), \
                    f'Archived curated entry {member.name} is not a regular file or hard link'

                member_name = canonical_tar_name(member.name)
                participates = member.islnk() or member_name in incoming_hardlinks
                assert participates, \
                    f'Archive dereferenced hard link for curated entry {member.name}'

                if member.islnk():
                    targets = hardlink_targets(member)
                    assert any(target in names_to_members for target in targets), \
                        f'Archive hard link {member.name} has no archived target'

                archived_file = tar.extractfile(member)
                assert archived_file is not None, f'Cannot read archived member {member.name}'
                archived_bytes = archived_file.read()
                with open(os.path.join(curated_dir, expected_name), 'rb') as current_file:
                    assert archived_bytes == current_file.read(), \
                        f'Archived content for {expected_name} does not match curated dataset'
    except (tarfile.TarError, OSError) as exc:
        pytest.fail(f'Failed to open or validate archive {backup_path}: {exc}')

    assert avg_ssim >= 0.95, \
        f'Average SSIM {avg_ssim:.4f} is below the threshold of 0.95'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
