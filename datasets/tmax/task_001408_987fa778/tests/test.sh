#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import gzip
import hashlib
import os
import re
import secrets
import shutil
import subprocess

DRAFTS_DIR = '/home/user/drafts'
FINAL_DIR = '/home/user/final_docs'
LOG_FILE = '/home/user/rename.log'

ORIGINAL_TITLES = {
    'draft_001.txt.gz': 'TITLE: API Reference v2\n',
    'draft_002.txt.gz': 'TITLE: User Guide 2023!\n',
    'draft_003.txt.gz': 'TITLE: Troubleshooting Network \n',
    'draft_004.txt.gz': 'TITLE: Architecture Overview\n',
    'draft_005.txt.gz': 'TITLE: Getting Started: Intro\n',
}

EXPECTED_FILES = {
    'api_reference_v2.txt.gz',
    'user_guide_2023.txt.gz',
    'troubleshooting_network.txt.gz',
    'architecture_overview.txt.gz',
    'getting_started_intro.txt.gz',
}

EXPECTED_LOG = (
    'draft_001.txt.gz -> api_reference_v2.txt.gz\n'
    'draft_002.txt.gz -> user_guide_2023.txt.gz\n'
    'draft_003.txt.gz -> troubleshooting_network.txt.gz\n'
    'draft_004.txt.gz -> architecture_overview.txt.gz\n'
    'draft_005.txt.gz -> getting_started_intro.txt.gz'
)

DUMMY_LINE = ('Some dummy text for the documentation draft. ' * 20 + '\n').encode()
MORE_LINE = ('More documentation content here. ' * 20 + '\n').encode()


def expected_original_hash(title_line):
    h = hashlib.sha256()
    for _ in range(50):
        h.update(DUMMY_LINE)
    h.update(title_line.encode())
    for _ in range(5000):
        h.update(MORE_LINE)
    return h.hexdigest()


def gzip_content_hash(path):
    h = hashlib.sha256()
    with gzip.open(path, 'rb') as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def slug(title):
    return re.sub(r'[^a-z0-9_]', '', title.lower().replace(' ', '_'))


def reset_directory(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    os.makedirs(path)


def candidate_scripts():
    result = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__'}]
        for name in files:
            if not name.endswith('.py'):
                continue
            path = os.path.join(root, name)
            if os.path.isfile(path) and not os.path.islink(path):
                result.append(path)
    return sorted(result)


def is_streaming_python(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            source = f.read()
        tree = ast.parse(source, filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False

    # Reject the common non-streaming forms that consume the entire decompressed
    # file at once. Chunked read(size) remains permitted.
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == 'read' and not node.args and not node.keywords:
                return False
            if node.func.attr == 'readlines':
                return False
    return True


def write_dynamic_fixture(token):
    reset_directory(DRAFTS_DIR)
    reset_directory(FINAL_DIR)

    titles = {
        'draft_001.txt.gz': f'Audit {token} Alpha!',
        'draft_002.txt.gz': f'Beta  {token} (Guide)',
        'draft_003.txt.gz': f'Network-{token} Notes',
        'draft_004.txt.gz': f'{token} Architecture v3.1',
        'draft_005.txt.gz': f'Getting Started {token}: Intro',
    }
    expected_hashes = {}

    for index, (filename, title) in enumerate(sorted(titles.items())):
        path = os.path.join(DRAFTS_DIR, filename)
        h = hashlib.sha256()
        with gzip.open(path, 'wb') as f:
            for n in range(50):
                line = f'preface {token} {index} {n}\n'.encode()
                f.write(line)
                h.update(line)
            title_line = f'TITLE: {title}\n'.encode()
            f.write(title_line)
            h.update(title_line)
            for n in range(200):
                line = (f'body {token} {index} {n} ' + ('content ' * 40) + '\n').encode()
                f.write(line)
                h.update(line)
        expected_hashes[slug(title) + '.txt.gz'] = h.hexdigest()

    expected_output = [
        f'{filename} -> {slug(titles[filename])}.txt.gz'
        for filename in sorted(titles)
    ]
    return expected_hashes, expected_output


def validate_dynamic_result(expected_hashes, expected_output, capture):
    if os.path.exists(DRAFTS_DIR):
        assert os.path.isdir(DRAFTS_DIR)
        assert os.listdir(DRAFTS_DIR) == []

    assert os.path.isdir(FINAL_DIR)
    assert set(os.listdir(FINAL_DIR)) == set(expected_hashes)
    for filename, expected_hash in expected_hashes.items():
        path = os.path.join(FINAL_DIR, filename)
        assert os.path.isfile(path) and not os.path.islink(path)
        assert gzip_content_hash(path) == expected_hash

    with open(capture, 'r', encoding='utf-8') as f:
        actual_output = f.read().strip().splitlines()
    assert actual_output == expected_output


def test_complete_task():
    # Preserve the original final-state assertions.
    if os.path.exists(DRAFTS_DIR):
        assert os.path.isdir(DRAFTS_DIR), f'{DRAFTS_DIR} exists but is not a directory.'
        files = os.listdir(DRAFTS_DIR)
        assert len(files) == 0, f'Expected {DRAFTS_DIR} to be empty, but found: {files}'

    assert os.path.isdir(FINAL_DIR), f'Directory {FINAL_DIR} does not exist.'
    actual_files = set(os.listdir(FINAL_DIR))
    assert actual_files == EXPECTED_FILES, (
        f'Expected files {EXPECTED_FILES} in {FINAL_DIR}, but got {actual_files}'
    )

    # Fully decompress and verify every moved file against its original content.
    expected_name_by_draft = {
        'draft_001.txt.gz': 'api_reference_v2.txt.gz',
        'draft_002.txt.gz': 'user_guide_2023.txt.gz',
        'draft_003.txt.gz': 'troubleshooting_network.txt.gz',
        'draft_004.txt.gz': 'architecture_overview.txt.gz',
        'draft_005.txt.gz': 'getting_started_intro.txt.gz',
    }
    for draft, final_name in expected_name_by_draft.items():
        path = os.path.join(FINAL_DIR, final_name)
        assert os.path.isfile(path) and not os.path.islink(path), f'{path} is not a regular file.'
        assert gzip_content_hash(path) == expected_original_hash(ORIGINAL_TITLES[draft]), (
            f'{path} does not preserve the original draft content.'
        )

    assert os.path.isfile(LOG_FILE), f'Log file {LOG_FILE} does not exist.'
    with open(LOG_FILE, 'r', encoding='utf-8') as f:
        actual_log = f.read().strip()
    assert actual_log == EXPECTED_LOG.strip(), (
        f'Content of {LOG_FILE} does not match expected output.\n'
        f'Expected:\n{EXPECTED_LOG}\nGot:\n{actual_log}'
    )

    scripts = [path for path in candidate_scripts() if is_streaming_python(path)]
    assert scripts, 'No usable streaming Python script was left under /home/user.'

    # Exercise the submitted script on titles unknown until verification. The
    # shell invocation deliberately captures stdout using standard redirection.
    success = False
    failures = []
    for script in scripts:
        token = secrets.token_hex(6)
        expected_hashes, expected_output = write_dynamic_fixture(token)
        capture = '/tmp/rename_dynamic.log'
        if os.path.exists(capture):
            os.unlink(capture)
        try:
            completed = subprocess.run(
                ['bash', '-c', 'python3 "$1" > "$2"', 'verifier', script, capture],
                cwd='/home/user', timeout=30, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            assert completed.returncode == 0, completed.stderr
            validate_dynamic_result(expected_hashes, expected_output, capture)
            success = True
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')

    assert success, 'No submitted Python script passed the dynamic test: ' + '; '.join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
