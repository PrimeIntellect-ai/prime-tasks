#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import codecs
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = '/home/user/backup_filter.py'
SIGNATURE = '[MALWARE-SIGNATURE-8821]'


def run_filter(path):
    return subprocess.run(
        ['python3', SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_backup_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "backup_filter.py not found at /home/user/backup_filter.py"


def test_adversarial_corpus_filtering():
    clean_dir = '/app/corpora/clean'
    evil_dir = '/app/corpora/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for f in clean_files:
        result = subprocess.run(['python3', SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run(['python3', SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean files modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil files bypassed: {', '.join(evil_failures)}")

    assert not error_messages, "Adversarial corpus verification failed: " + " | ".join(error_messages)


def test_filter_uses_file_contents_on_unlabeled_random_paths():
    workdir = tempfile.mkdtemp(prefix='verify_' + secrets.token_hex(8) + '_')
    cases = []

    for i in range(12):
        marker = secrets.token_hex(20)
        clean = f"Legacy résumé number {i}; token={marker}; harmless text."
        evil = f"Legacy entrée {i}; token={marker}; {SIGNATURE}; trailing text."
        cases.append((clean, 0))
        cases.append((evil, 1))

    random.SystemRandom().shuffle(cases)
    failures = []
    for content, expected in cases:
        path = os.path.join(workdir, secrets.token_hex(16) + '.txt')
        with open(path, 'wb') as f:
            f.write(content.encode('iso-8859-15'))
        actual = run_filter(path)
        if actual != expected:
            failures.append((os.path.basename(path), expected, actual))

    # Reuse one identical path with changing contents so classification cannot be
    # based on its directory or filename.
    reused = os.path.join(workdir, secrets.token_hex(16) + '.txt')
    transitions = [
        (f"ordinary {secrets.token_hex(24)}", 0),
        (f"prefix {SIGNATURE} suffix {secrets.token_hex(24)}", 1),
        (f"ordinary again {secrets.token_hex(24)}", 0),
    ]
    for content, expected in transitions:
        with open(reused, 'wb') as f:
            f.write(content.encode('iso-8859-15'))
        actual = run_filter(reused)
        if actual != expected:
            failures.append((os.path.basename(reused), expected, actual))

    assert not failures, f"Filter misclassified generated content: {failures}"


def test_processed_backup_directory():
    processed_dir = '/home/user/processed_backup'
    assert os.path.isdir(processed_dir), f"{processed_dir} directory does not exist."

    files = os.listdir(processed_dir)
    assert len(files) > 0, f"No files found in {processed_dir}."

    for f in files:
        assert f.startswith('BKP_2024_'), f"File {f} does not have the mandatory prefix 'BKP_2024_'."
        assert ' ' not in f, f"File {f} contains spaces, which should have been replaced with underscores."

        filepath = os.path.join(processed_dir, f)

        try:
            with codecs.open(filepath, 'r', encoding='utf-8') as file_obj:
                content = file_obj.read()
        except UnicodeDecodeError:
            assert False, f"File {f} is not properly encoded in UTF-8."

        assert SIGNATURE not in content, f"File {f} contains the malware signature, it should have been deleted."

    expected = {
        'BKP_2024_clean_file_1.txt': 'Clean content 1',
        'BKP_2024_clean_file_2.txt': 'Clean content 2',
    }
    assert set(files) == set(expected), (
        f"Processed backup must contain exactly the two clean extracted files; found: {sorted(files)}"
    )
    for name, expected_content in expected.items():
        path = os.path.join(processed_dir, name)
        assert os.path.isfile(path), f"{name} is not a regular file."
        with open(path, 'r', encoding='utf-8') as f:
            actual_content = f.read()
        assert actual_content == expected_content, f"Unexpected content in {name}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
