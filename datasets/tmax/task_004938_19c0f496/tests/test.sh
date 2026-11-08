#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import subprocess
import zipfile
from pathlib import PurePosixPath

import numpy as np
from PIL import Image

CLEAN_DIR = '/home/user/clean_dataset'
NOTES_PATH = '/home/user/important_notes.txt'
ORIGINAL_NOTES = b'These are my important notes.'


def calculate_mse(imageA_path, imageB_path):
    try:
        imgA = np.array(Image.open(imageA_path).convert('RGB')).astype('float')
        imgB = np.array(Image.open(imageB_path).convert('RGB')).astype('float')
        if imgA.shape != imgB.shape:
            return float('inf')
        err = np.sum((imgA - imgB) ** 2)
        err /= float(imgA.shape[0] * imgA.shape[1])
        return err
    except Exception:
        return float('inf')


def read_key():
    result = subprocess.run(
        ['tesseract', '/app/obfuscation_key.png', 'stdout', '--psm', '6'],
        check=True, capture_output=True, text=True, timeout=20
    )
    match = re.search(r'KEY\s*=\s*(\d+)', result.stdout, re.IGNORECASE)
    assert match, f'Could not derive KEY from obfuscation_key.png: {result.stdout!r}'
    key = int(match.group(1))
    assert 0 <= key <= 255
    return key


def expected_outputs():
    key = read_key()
    safe_entries = []
    with zipfile.ZipFile('/app/raw_dataset.zip', 'r') as archive:
        for info in archive.infolist():
            path = PurePosixPath(info.filename.replace('\\', '/'))
            if info.is_dir() or path.is_absolute() or '..' in path.parts:
                continue
            if path.suffix.lower() not in ('.jpg', '.jpeg'):
                continue
            safe_entries.append((info.filename, archive.read(info)))

    safe_entries.sort(key=lambda item: item[0])
    return {
        f'dataset_{index:03d}.jpg': bytes(byte ^ key for byte in data)
        for index, (_, data) in enumerate(safe_entries, 1)
    }


EXPECTED = expected_outputs()


def find_scripts():
    candidates = []
    verifier_path = os.path.realpath(__file__)
    for root in ('/app', '/home/user', '/tmp'):
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            if os.path.realpath(directory).startswith(os.path.realpath(CLEAN_DIR) + os.sep):
                subdirs[:] = []
                continue
            subdirs[:] = [d for d in subdirs if d not in ('__pycache__', '.cache')]
            for name in files:
                path = os.path.join(directory, name)
                if not name.endswith('.py') or os.path.realpath(path) == verifier_path:
                    continue
                if os.path.isfile(path) and not os.path.islink(path):
                    candidates.append(path)
    return sorted(set(candidates), key=lambda p: os.path.getmtime(p), reverse=True)


def reset_state():
    if os.path.lexists(CLEAN_DIR):
        if os.path.islink(CLEAN_DIR) or not os.path.isdir(CLEAN_DIR):
            os.unlink(CLEAN_DIR)
        else:
            shutil.rmtree(CLEAN_DIR)
    with open(NOTES_PATH, 'wb') as notes:
        notes.write(ORIGINAL_NOTES)


def output_is_correct():
    if not os.path.isdir(CLEAN_DIR) or os.path.islink(CLEAN_DIR):
        return False
    if sorted(os.listdir(CLEAN_DIR)) != sorted(EXPECTED):
        return False
    for name, expected in EXPECTED.items():
        path = os.path.join(CLEAN_DIR, name)
        try:
            if not stat.S_ISREG(os.lstat(path).st_mode):
                return False
            with open(path, 'rb') as produced:
                if produced.read() != expected:
                    return False
            with Image.open(path) as image:
                image.verify()
            with Image.open(path) as image:
                if image.format != 'JPEG':
                    return False
        except Exception:
            return False
    try:
        with open(NOTES_PATH, 'rb') as notes:
            return notes.read() == ORIGINAL_NOTES
    except OSError:
        return False


def test_required_script_executes_safely():
    assert os.path.isfile(NOTES_PATH), 'important_notes.txt was removed.'
    with open(NOTES_PATH, 'rb') as notes:
        assert notes.read() == ORIGINAL_NOTES, 'important_notes.txt was overwritten, indicating unsafe extraction.'

    scripts = find_scripts()
    assert scripts, 'No Python extraction/decoding script was written.'

    attempts = []
    for script in scripts:
        for cwd in dict.fromkeys(['/app', os.path.dirname(script)]):
            reset_state()
            try:
                result = subprocess.run(
                    ['python3', script], cwd=cwd, capture_output=True,
                    text=True, timeout=30
                )
            except Exception as exc:
                attempts.append(f'{script} (cwd={cwd}): {exc}')
                continue
            if result.returncode == 0 and output_is_correct():
                return
            attempts.append(
                f'{script} (cwd={cwd}): exit={result.returncode}, '
                f'stdout={result.stdout[-300:]!r}, stderr={result.stderr[-300:]!r}'
            )

    raise AssertionError('No submitted Python script produced all required outputs safely. ' + ' | '.join(attempts))


def test_extracted_files_exist():
    assert os.path.isdir(CLEAN_DIR), f'Directory {CLEAN_DIR} does not exist.'
    files = sorted(os.listdir(CLEAN_DIR))
    expected_files = ['dataset_001.jpg', 'dataset_002.jpg']
    for filename in expected_files:
        assert filename in files, f'Expected file {filename} is missing from {CLEAN_DIR}.'
    assert len(files) == 2, f'Expected exactly 2 files in {CLEAN_DIR}, but found {len(files)}: {files}'


def test_all_decoded_images_are_exact_and_valid():
    assert sorted(EXPECTED) == ['dataset_001.jpg', 'dataset_002.jpg']
    for filename, expected in EXPECTED.items():
        path = os.path.join(CLEAN_DIR, filename)
        assert os.path.isfile(path) and not os.path.islink(path), f'{filename} is not a regular file.'
        with open(path, 'rb') as produced:
            assert produced.read() == expected, f'{filename} was not correctly decoded or ordered.'
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            assert image.format == 'JPEG', f'{filename} is not a valid JPEG.'


def test_mse_metric():
    target_img = '/home/user/clean_dataset/dataset_001.jpg'
    ref_img = '/app/.hidden_ref.jpg'
    assert os.path.isfile(target_img), f'Target image {target_img} is missing.'
    assert os.path.isfile(ref_img), f'Reference image {ref_img} is missing.'
    mse = calculate_mse(target_img, ref_img)
    threshold = 1.0
    assert mse <= threshold, f'MSE {mse} exceeds the threshold of {threshold}. The image was not correctly decoded.'


def test_path_traversal_prevented():
    with open(NOTES_PATH, 'rb') as notes:
        assert notes.read() == ORIGINAL_NOTES, 'important_notes.txt was overwritten by the traversal ZIP entry.'
    assert sorted(os.listdir(CLEAN_DIR)) == ['dataset_001.jpg', 'dataset_002.jpg']
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
