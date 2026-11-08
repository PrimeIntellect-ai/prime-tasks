#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import zipfile
from pathlib import Path, PurePosixPath


def test_directory_state_accuracy():
    """Retain the original scoring assertions."""
    score = 0.0

    evil_path = '/home/user/docs_clean/DOC_evil.txt'
    if os.path.exists(evil_path):
        try:
            with open(evil_path, 'r') as f:
                if 'PUBLISHED document' in f.read():
                    score += 0.25
        except Exception:
            pass

    valid_path = '/home/user/docs_clean/DOC_valid_doc.md'
    if os.path.exists(valid_path):
        try:
            with open(valid_path, 'r') as f:
                if 'This is in PUBLISHED.' in f.read():
                    score += 0.25
        except Exception:
            pass

    img_path = '/home/user/docs_clean/DOC_image_file.png'
    if os.path.exists(img_path):
        try:
            with open(img_path, 'rb') as f:
                header = f.read(8)
                if header == b'\x89PNG\r\n\x1a\n':
                    score += 0.25
        except Exception:
            pass

    if not os.path.exists('/home/etc/evil.txt') and not os.path.exists('/etc/evil.txt'):
        score += 0.25

    assert score >= 1.0, f"Score {score} is below the threshold of 1.0. Ensure all instructions were applied correctly and zip slip was prevented."


def read_ocr_rules():
    text = subprocess.check_output(
        ['tesseract', '/app/instructions.png', 'stdout', '--psm', '6'],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    prefix_match = re.search(r'PREFIX_ALL_FILES:\s*(\S+)', text, re.IGNORECASE)
    replace_match = re.search(
        r"REPLACE_TEXT:\s*['\"‘’]?([A-Z_]+)['\"‘’]?\s+to\s+['\"‘’]?([A-Z_]+)",
        text,
        re.IGNORECASE,
    )
    assert prefix_match and replace_match, f'Could not derive rules from OCR output: {text!r}'
    return prefix_match.group(1), replace_match.group(1), replace_match.group(2)


def expected_files():
    prefix, old_text, new_text = read_ocr_rules()
    expected = {}

    with zipfile.ZipFile('/app/docs_update.zip', 'r') as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue

            original = PurePosixPath(info.filename)
            parts = original.parts
            if original.is_absolute() or '..' in parts:
                safe_relative = PurePosixPath(original.name)
            else:
                safe_relative = PurePosixPath(*[p for p in parts if p not in ('', '.')])

            data = archive.read(info)
            name = safe_relative.name
            if data.startswith(b'\x89PNG\r\n\x1a\n') and not name.lower().endswith('.png'):
                name += '.png'

            if name.lower().endswith(('.txt', '.md')):
                data = data.decode('utf-8').replace(old_text, new_text).encode('utf-8')

            final_relative = safe_relative.parent / (prefix + name)
            key = final_relative.as_posix()
            assert key not in expected, f'Expected-name collision for {key}'
            expected[key] = data

    return expected


def test_complete_exact_final_state():
    root = Path('/home/user/docs_clean')
    assert root.is_dir() and not root.is_symlink(), 'docs_clean must be a real directory'

    expected = expected_files()
    actual_files = set()
    actual_dirs = set()

    for current, dirnames, filenames in os.walk(root, followlinks=False):
        current_path = Path(current)
        for dirname in dirnames:
            path = current_path / dirname
            relative = path.relative_to(root).as_posix()
            assert not path.is_symlink(), f'Unexpected directory symlink: {relative}'
            actual_dirs.add(relative)
        for filename in filenames:
            path = current_path / filename
            relative = path.relative_to(root).as_posix()
            mode = path.lstat().st_mode
            assert stat.S_ISREG(mode), f'Output is not a regular file: {relative}'
            actual_files.add(relative)

    expected_dirs = set()
    for relative in expected:
        parent = PurePosixPath(relative).parent
        while parent != PurePosixPath('.'):
            expected_dirs.add(parent.as_posix())
            parent = parent.parent

    assert actual_files == set(expected), f'Wrong output files: expected {sorted(expected)}, got {sorted(actual_files)}'
    assert actual_dirs == expected_dirs, f'Unexpected or missing directories: expected {sorted(expected_dirs)}, got {sorted(actual_dirs)}'

    for relative, wanted in expected.items():
        path = root / relative
        assert path.read_bytes() == wanted, f'Incorrect complete contents for {relative}'

    # Verify the known traversal destinations remain untouched.
    assert not Path('/home/etc/evil.txt').exists()
    assert not Path('/etc/evil.txt').exists()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
