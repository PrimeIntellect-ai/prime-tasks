#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'VERIFY_EOF' > /tmp/verify_pipeline.py
import os
import pwd
import secrets
import shutil
import subprocess
from pathlib import Path

HOME = Path('/home/user')
ARCHIVE = HOME / 'archive.txt'
CHUNKS = HOME / 'chunks'
EXTRACTOR = HOME / 'extractor.py'
RECOVERED = HOME / 'recovered_project'

assert ARCHIVE.is_file(), f'Expected archive {ARCHIVE} to exist.'
assert CHUNKS.is_dir(), f'Expected directory {CHUNKS} to exist.'
assert EXTRACTOR.is_file(), f'Expected Python script {EXTRACTOR} to exist.'
assert not EXTRACTOR.is_symlink(), f'{EXTRACTOR} must be a regular script, not a symlink.'

# Verify that the piece_* files are an exact 15-line split of archive.txt in
# alphabetical filename order, rather than arbitrary placeholder files.
archive_lines = ARCHIVE.read_text().splitlines(keepends=True)
assert archive_lines, 'archive.txt is empty.'
assert len(archive_lines) % 15 == 0, 'The supplied archive should split into complete 15-line chunks.'
expected_chunks = [archive_lines[i:i + 15] for i in range(0, len(archive_lines), 15)]
pieces = sorted(
    (p for p in CHUNKS.iterdir() if p.name.startswith('piece_')),
    key=lambda p: p.name,
)
assert len(pieces) == len(expected_chunks), (
    f'Expected {len(expected_chunks)} piece_* files, found {len(pieces)}.'
)
for piece, expected_lines in zip(pieces, expected_chunks):
    assert piece.is_file() and not piece.is_symlink(), f'{piece} must be a regular file.'
    actual_lines = piece.read_text().splitlines(keepends=True)
    assert len(actual_lines) == 15, f'{piece} does not contain exactly 15 lines.'
    assert actual_lines == expected_lines, f'{piece} is not the corresponding archive chunk.'

# Derive the valid stream from the submitted chunks, then actually pipe that
# stream to the submitted extractor while running it as the default user.
valid_pieces = []
for piece in pieces:
    text = piece.read_text()
    if '[VALID_BLOCK]' in text:
        valid_pieces.append(piece)
assert valid_pieces, 'No chunks containing [VALID_BLOCK] were found.'
valid_stream = ''.join(piece.read_text() for piece in valid_pieces).encode()

if RECOVERED.exists() or RECOVERED.is_symlink():
    if RECOVERED.is_symlink() or RECOVERED.is_file():
        RECOVERED.unlink()
    else:
        shutil.rmtree(RECOVERED)
RECOVERED.mkdir(parents=True)
user = pwd.getpwnam('user')
os.chown(RECOVERED, user.pw_uid, user.pw_gid)

result = subprocess.run(
    ['runuser', '-u', 'user', '--', 'python3', str(EXTRACTOR)],
    input=valid_stream,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    cwd=str(HOME),
    timeout=15,
)
assert result.returncode == 0, (
    f'extractor.py failed when reading the filtered stream from stdin:\n'
    f'{result.stderr.decode(errors="replace")}'
)

# Exercise stdin parsing with verifier-generated names and content, and ensure
# traversal and absolute paths cannot write outside recovered_project.
nonce = secrets.token_hex(12)
relative_one = f'verifier_{nonce}/nested/one.txt'
relative_two = f'verifier_{nonce}/two.txt'
content_one = f'random-content-{secrets.token_hex(16)}'
content_two = f'line-a-{secrets.token_hex(8)}\nline-b-{secrets.token_hex(8)}'
absolute_escape = Path('/tmp') / f'extractor_escape_{nonce}'
home_escape = HOME / f'extractor_escape_{nonce}'
for candidate in (absolute_escape, home_escape):
    if candidate.exists() or candidate.is_symlink():
        if candidate.is_dir() and not candidate.is_symlink():
            shutil.rmtree(candidate)
        else:
            candidate.unlink()

synthetic = (
    'noise before markers\n'
    '[VALID_BLOCK]\n'
    f'>>> PATH: {relative_one} <<<\n'
    f'{content_one}\n'
    '>>> END <<<\n'
    'discard this line too\n'
    f'>>> PATH: {relative_two} <<<\n'
    f'{content_two}\n'
    '>>> END <<<\n'
    f'>>> PATH: ../extractor_escape_{nonce} <<<\n'
    'unsafe-home-write\n'
    '>>> END <<<\n'
    f'>>> PATH: ../../../tmp/extractor_escape_{nonce} <<<\n'
    'unsafe-tmp-write\n'
    '>>> END <<<\n'
    f'>>> PATH: /tmp/extractor_escape_{nonce} <<<\n'
    'unsafe-absolute-write\n'
    '>>> END <<<\n'
    'noise after markers\n'
).encode()

result = subprocess.run(
    ['runuser', '-u', 'user', '--', 'python3', str(EXTRACTOR)],
    input=synthetic,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    cwd=str(HOME),
    timeout=15,
)
assert result.returncode == 0, (
    f'extractor.py failed on verifier-generated stdin:\n'
    f'{result.stderr.decode(errors="replace")}'
)
assert (RECOVERED / relative_one).read_text().rstrip('\n') == content_one
assert (RECOVERED / relative_two).read_text().rstrip('\n') == content_two
assert not absolute_escape.exists(), 'extractor.py allowed a path to escape into /tmp.'
assert not home_escape.exists(), 'extractor.py allowed a path to escape recovered_project.'
VERIFY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_recovered_main_py():
    path = '/home/user/recovered_project/src/main.py'
    assert os.path.isfile(path), f"Expected file {path} to exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    expected = "def hello_world():\n    print('Hello')"
    assert content == expected, f"Content of {path} is incorrect.\nExpected:\n{expected}\nGot:\n{content}"

def test_recovered_readme_md():
    path = '/home/user/recovered_project/docs/readme.md'
    assert os.path.isfile(path), f"Expected file {path} to exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    expected = "# Documentation\nThis is the readme."
    assert content == expected, f"Content of {path} is incorrect.\nExpected:\n{expected}\nGot:\n{content}"

def test_recovered_helper_py():
    path = '/home/user/recovered_project/src/utils/helper.py'
    assert os.path.isfile(path), f"Expected file {path} to exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    expected = "def add(a, b):\n    return a + b"
    assert content == expected, f"Content of {path} is incorrect.\nExpected:\n{expected}\nGot:\n{content}"

def test_invalid_file_not_extracted():
    path = '/home/user/recovered_project/evil/hidden.py'
    assert not os.path.exists(path), f"File {path} should not have been extracted because its chunk lacked [VALID_BLOCK]."

def test_chunks_directory_exists():
    path = '/home/user/chunks'
    assert os.path.isdir(path), f"Expected directory {path} to exist."

    # Check if there are files starting with piece_
    files = [f for f in os.listdir(path) if f.startswith('piece_')]
    assert len(files) > 0, f"Expected chunk files starting with 'piece_' in {path}."

def test_extractor_script_exists():
    path = '/home/user/extractor.py'
    assert os.path.isfile(path), f"Expected Python script {path} to exist."
TEST_EOF

if python3 /tmp/verify_pipeline.py 2>&1 && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
