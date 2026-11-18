#!/bin/bash
set -u
mkdir -p /logs/verifier

if python3 - <<'PY'
import hashlib
import os
import re
import secrets
import shutil
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

SCRIPT = Path('/home/user/recover.sh')
ROOT = Path('/app/corrupted_docs')
STAMP = Path('/app/stamp.png')
COMPILED = Path('/app/compiled_docs.txt')
ARCHIVE = Path('/app/compiled_docs.tar.xz')

# Preserve the original artifact assertion and require an actual regular script.
assert SCRIPT.is_file(), f'Missing required script: {SCRIPT}'
assert not SCRIPT.is_symlink(), f'Recovery script must be a regular file: {SCRIPT}'

# Replace the public fixed subset with a fresh instance so hardcoded output cannot pass.
if os.path.lexists(ROOT):
    if ROOT.is_symlink() or not ROOT.is_dir():
        ROOT.unlink()
    else:
        shutil.rmtree(ROOT)
ROOT.mkdir(parents=True)
(ROOT / 'dir1' / 'dir2').mkdir(parents=True)
(ROOT / 'extra' / 'deep').mkdir(parents=True)

nonce = secrets.token_hex(8).upper()
documents = {
    ROOT / 'file_A.txt': (
        f'System Overview {nonce}\n'
        'This is a DEPRECATED feature.\n'
        'Core logic goes here.\n'
    ).encode(),
    ROOT / 'dir1' / 'file_B.txt': (
        'API Endpoints\n'
        'DEPRECATED: v1 endpoint\n'
        f'New v2 endpoint is active ({nonce}).\n'
    ).encode(),
    ROOT / 'extra' / 'deep' / f'notes_{nonce}.txt': (
        f'Recovery Notes {nonce}\n'
        'Remove this DEPRECATED paragraph.\n'
        'Symlink-safe traversal is required.\n'
    ).encode(),
}
for path, data in documents.items():
    path.write_bytes(data)

# Duplicate paths, a broken path, and a recursive directory symlink exercise safe traversal.
os.symlink(ROOT / 'file_A.txt', ROOT / 'dir1' / 'link_A.txt')
os.symlink(ROOT / 'dir1' / 'file_B.txt', ROOT / 'extra' / 'link_B.txt')
os.symlink(ROOT / 'dir1', ROOT / 'dir1' / 'dir2' / 'loop')
os.symlink(ROOT / 'does-not-exist.txt', ROOT / 'broken.txt')

stamp_text = f'SECURITY-CLASSIFICATION: TOP-SECRET-{nonce}'
subprocess.run([
    'convert', '-size', '1100x80', 'xc:white', '-font', 'DejaVu-Sans',
    '-pointsize', '28', '-fill', 'black', '-draw',
    f"text 12,50 '{stamp_text}'", str(STAMP)
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

ocr = subprocess.run(
    ['tesseract', str(STAMP), 'stdout'],
    check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
).stdout.decode('utf-8').rstrip()
assert ocr, 'Verifier could not derive nonempty OCR text from the generated stamp'

word = re.compile(r'(?<![A-Za-z0-9_])DEPRECATED(?![A-Za-z0-9_])')
processed = []
for path, data in documents.items():
    kept = []
    for line in data.decode('utf-8').splitlines(keepends=True):
        if not word.search(line):
            kept.append(line)
    body = ''.join(kept)
    processed.append((hashlib.sha256(data).hexdigest(), (ocr + '\n' + body).encode()))
expected = b''.join(content for _, content in sorted(processed))

# Outputs must be produced by this script for the fresh tree and stamp.
for output in (COMPILED, ARCHIVE):
    if os.path.lexists(output):
        if output.is_dir() and not output.is_symlink():
            shutil.rmtree(output)
        else:
            output.unlink()

run = subprocess.run(
    ['timeout', '30', 'bash', str(SCRIPT)], cwd='/home/user',
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
)
assert run.returncode == 0, (
    f'Recovery script failed or did not safely terminate (exit {run.returncode}).\n'
    f'stdout:\n{run.stdout}\nstderr:\n{run.stderr}'
)

# Preserve and strengthen the original output assertions.
assert COMPILED.is_file(), f'Missing required file: {COMPILED}'
assert not COMPILED.is_symlink(), f'Compiled output must be a regular file: {COMPILED}'
actual = COMPILED.read_bytes()
assert actual == expected, (
    'Compiled content does not match OCR-derived, deduplicated, SHA256-sorted input.\n'
    f'Expected:\n{expected.decode(errors="replace")}\n'
    f'Actual:\n{actual.decode(errors="replace")}'
)

assert ARCHIVE.is_file(), f'Missing required archive: {ARCHIVE}'
assert not ARCHIVE.is_symlink(), f'Archive must be a regular file: {ARCHIVE}'

# It must be a valid xz-compressed tar containing the generated compiled file.
with tarfile.open(ARCHIVE, mode='r:xz') as tf:
    members = tf.getmembers()
    regular = [m for m in members if m.isfile()]
    assert len(regular) == 1 and PurePosixPath(regular[0].name).name == 'compiled_docs.txt', (
        'Archive must contain exactly one regular compiled_docs.txt member'
    )
    extracted = tf.extractfile(regular[0])
    assert extracted is not None
    assert extracted.read() == expected, 'Archived compiled_docs.txt differs from the required output'

# Preset -9 uses the maximum standard LZMA2 dictionary (64 MiB).
env = os.environ.copy()
env['LC_ALL'] = 'C'
listing = subprocess.run(
    ['xz', '-lvv', str(ARCHIVE)], env=env,
    check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
).stdout
assert re.search(r'dict=(?:64MiB|67108864|64M(?:iB)?)', listing), (
    'Archive was not compressed with maximum xz compression (-9); xz details:\n' + listing
)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
