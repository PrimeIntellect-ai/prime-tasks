#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import tarfile
import subprocess
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter


def calculate_ssim(img1, img2):
    """Compute Structural Similarity Index Measure (SSIM) between two images."""
    C1 = (0.01 * 255) ** 2
    C2 = (0.03 * 255) ** 2

    img1 = img1.astype(np.float64)
    img2 = img2.astype(np.float64)

    mu1 = gaussian_filter(img1, sigma=1.5, truncate=3.5)
    mu2 = gaussian_filter(img2, sigma=1.5, truncate=3.5)

    mu1_sq = mu1 ** 2
    mu2_sq = mu2 ** 2
    mu1_mu2 = mu1 * mu2

    sigma1_sq = gaussian_filter(img1 ** 2, sigma=1.5, truncate=3.5) - mu1_sq
    sigma2_sq = gaussian_filter(img2 ** 2, sigma=1.5, truncate=3.5) - mu2_sq
    sigma12 = gaussian_filter(img1 * img2, sigma=1.5, truncate=3.5) - mu1_mu2

    ssim_map = ((2 * mu1_mu2 + C1) * (2 * sigma12 + C2)) / (
        (mu1_sq + mu2_sq + C1) * (sigma1_sq + sigma2_sq + C2)
    )
    return ssim_map.mean()


def safe_name(name):
    assert not name.startswith('/'), f"Absolute archive path is not allowed: {name}"
    parts = []
    for part in name.split('/'):
        if part in ('', '.'):
            continue
        assert part != '..', f"Parent traversal is not allowed in archive path: {name}"
        parts.append(part)
    return '/'.join(parts)


def test_final_archive_and_metrics():
    """Verify archive contents, encodings, replacements, and frame quality."""
    agent_archive = '/home/user/docs_package.tar.gz'
    assert os.path.exists(agent_archive), f"Archive not found: {agent_archive}"
    assert os.path.isfile(agent_archive) and not os.path.islink(agent_archive), \
        f"Final archive must be a regular file: {agent_archive}"

    # Derive the required transformed documents from the supplied legacy archive.
    expected_text = {}
    with tarfile.open('/app/legacy_docs.tar.gz', 'r:gz') as legacy_tar:
        for member in legacy_tar.getmembers():
            name = safe_name(member.name)
            if member.isfile() and name.endswith('.txt'):
                source = legacy_tar.extractfile(member)
                assert source is not None
                original = source.read().decode('iso-8859-1')
                expected_text[name] = original.replace('AcmeCorp', 'NovaTech').encode('utf-8')
    assert expected_text, "No source .txt files found in the legacy archive."

    extract_dir = '/tmp/agent_extract_test'
    shutil.rmtree(extract_dir, ignore_errors=True)
    os.makedirs(extract_dir)

    # Validate member types before materializing anything. In particular, required
    # frames and documents cannot be symlinks or hard links to verifier-created data.
    regular_members = {}
    with tarfile.open(agent_archive, 'r:gz') as agent_tar:
        members = agent_tar.getmembers()
        for member in members:
            name = safe_name(member.name)
            assert member.isfile() or member.isdir(), \
                f"Archive member must be a regular file or directory: {member.name}"
            if member.isfile():
                assert name, "Archive contains a regular file with an empty path."
                assert name not in regular_members, f"Duplicate archive member: {name}"
                regular_members[name] = member

        required_names = set(expected_text) | {f'frame_{t}.jpg' for t in [2, 4, 6, 8, 10]}
        for name in required_names:
            assert name in regular_members, f"Required regular file missing from archive: {name}"

        # Safely materialize regular files without invoking tar link semantics.
        for name, member in regular_members.items():
            destination = os.path.join(extract_dir, *name.split('/'))
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            source = agent_tar.extractfile(member)
            assert source is not None, f"Could not read archive member: {name}"
            with open(destination, 'wb') as output:
                shutil.copyfileobj(source, output)

    # Check that every original document is present with exactly the required
    # ISO-8859-1-to-UTF-8 conversion and AcmeCorp-to-NovaTech replacement.
    for name, expected in expected_text.items():
        filepath = os.path.join(extract_dir, *name.split('/'))
        with open(filepath, 'rb') as f:
            content = f.read()
        assert content == expected, f"Transformed content is incorrect for {name}."

    # Preserve the original UTF-8 and replacement assertions for top-level text files.
    txt_files = [f for f in os.listdir(extract_dir) if f.endswith('.txt')]
    assert len(txt_files) > 0, "No .txt files found in the extracted archive."
    for txt_file in txt_files:
        filepath = os.path.join(extract_dir, txt_file)
        with open(filepath, 'rb') as f:
            content = f.read()
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError:
            assert False, f"File {txt_file} is not valid UTF-8. Encoding conversion failed."
        assert 'AcmeCorp' not in text, f"Legacy text 'AcmeCorp' still found in {txt_file}."
        assert 'NovaTech' in text, f"Replacement text 'NovaTech' not found in {txt_file}."

    # Generate independent ground-truth frames only after the archive has been
    # validated and safely materialized.
    gt_dir = '/tmp/gt_frames_test'
    shutil.rmtree(gt_dir, ignore_errors=True)
    os.makedirs(gt_dir)
    times = [2, 4, 6, 8, 10]
    for t in times:
        subprocess.run(
            ['ffmpeg', '-y', '-ss', f'00:00:{t:02d}', '-i',
             '/app/demo_recording.mp4', '-frames:v', '1', '-q:v', '2',
             f'{gt_dir}/frame_{t}.jpg'],
            capture_output=True, check=True
        )

    total_ssim = 0.0
    for t in times:
        agent_frame = os.path.join(extract_dir, f'frame_{t}.jpg')
        gt_frame = os.path.join(gt_dir, f'frame_{t}.jpg')
        assert os.path.exists(agent_frame), f"Extracted frame missing from archive: {agent_frame}"
        assert os.path.isfile(agent_frame) and not os.path.islink(agent_frame), \
            f"Extracted frame is not a regular file: {agent_frame}"

        img1 = np.array(Image.open(agent_frame).convert('L'))
        img2 = np.array(Image.open(gt_frame).convert('L'))

        if img1.shape != img2.shape:
            img1_pil = Image.open(agent_frame).convert('L')
            img1 = np.array(img1_pil.resize((img2.shape[1], img2.shape[0])))

        score = calculate_ssim(img1, img2)
        total_ssim += score

    avg_ssim = total_ssim / len(times)
    assert avg_ssim >= 0.95, \
        f"Average SSIM {avg_ssim:.4f} is below the required threshold of 0.95."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
