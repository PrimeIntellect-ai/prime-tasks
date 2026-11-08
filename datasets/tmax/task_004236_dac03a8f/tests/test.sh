#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile
import uuid

FINAL_DOCS_DIR = "/home/user/final_docs"
EXTRACTED_DOCS_DIR = "/home/user/extracted_docs"
LEGACY_DOCS_DIR = "/home/user/legacy_docs"

EXPECTED_EXTRACTED = {
    'intro.txt': (
        b"Welcome to [COMPANY_NAME]!\n"
        b"DRAFT: This is a note to the editor.\n"
        b"We are excited to have you. [COMPANY_NAME] values its employees.\n"
        b"DRAFT: Fix the punctuation here.\n"
        b"End of document."
    ),
    'report.txt': (
        b"DRAFT: To be deleted.\n"
        b"The [COMPANY_NAME] quarterly report.\n"
        b"Revenue is up by 15% at [COMPANY_NAME]."
    ),
    'normal.txt': (
        b"Just a normal file.\n"
        b"No drafts here.\n"
        b"Only [COMPANY_NAME] everywhere."
    ),
}

EXPECTED_FINAL = {
    'intro.txt': (
        "Welcome to Acme Corp!\n"
        "We are excited to have you. Acme Corp values its employees.\n"
        "End of document."
    ),
    'report.txt': (
        "The Acme Corp quarterly report.\n"
        "Revenue is up by 15% at Acme Corp."
    ),
    'normal.txt': (
        "Just a normal file.\n"
        "No drafts here.\n"
        "Only Acme Corp everywhere."
    ),
}


def python_scripts():
    found = []
    excluded = {LEGACY_DOCS_DIR, EXTRACTED_DOCS_DIR, FINAL_DOCS_DIR}
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if os.path.join(root, d) not in excluded]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path):
                found.append(path)
    return found


def test_directories_exist():
    assert os.path.isdir(EXTRACTED_DOCS_DIR), f"Directory {EXTRACTED_DOCS_DIR} does not exist."
    assert os.path.isdir(FINAL_DOCS_DIR), f"Directory {FINAL_DOCS_DIR} does not exist."


def test_extracted_docs_contents():
    extracted_files = set(os.listdir(EXTRACTED_DOCS_DIR))
    expected_files = {'intro.txt', 'report.txt', 'normal.txt'}
    assert extracted_files == expected_files, f"Extracted files mismatch. Found: {extracted_files}, Expected: {expected_files}"

    for filename, expected_bytes in EXPECTED_EXTRACTED.items():
        filepath = os.path.join(EXTRACTED_DOCS_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."
        with open(filepath, 'rb') as f:
            content = f.read()
        assert content == expected_bytes, f"Extracted payload in {filepath} is incorrect."


def test_final_docs_contents():
    final_files = set(os.listdir(FINAL_DOCS_DIR))
    expected_files = {'intro.txt', 'report.txt', 'normal.txt'}
    assert final_files == expected_files, f"Final files mismatch. Found: {final_files}, Expected: {expected_files}"


def test_final_docs_text_transformations():
    for filename, expected_text in EXPECTED_FINAL.items():
        filepath = os.path.join(FINAL_DOCS_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."

        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        assert content == expected_text, f"Content of {filepath} does not match expected transformations.\nExpected:\n{expected_text}\n\nGot:\n{content}"

        raw = EXPECTED_EXTRACTED[filename].decode('utf-8')
        derived = ''.join(line for line in raw.splitlines(keepends=True) if not line.startswith('DRAFT:'))
        derived = derived.replace('[COMPANY_NAME]', 'Acme Corp')
        assert content == derived, f"Content of {filepath} was not derived from its extracted payload using the required rules."


def test_python_extraction_script_exists_and_runs_on_fresh_assets():
    scripts = python_scripts()
    assert scripts, "No Python extraction script was found under /home/user."

    token = uuid.uuid4().hex
    text_name = f"verification_{token}.asset"
    text_out = f"verification_{token}.txt"
    image_name = f"verification_image_{token}.asset"
    payload = (
        f"Fresh verification payload {token}.\n"
        "DRAFT: This must remain in the raw extraction.\n"
        "Marker: [COMPANY_NAME]"
    ).encode('utf-8')

    backup = tempfile.mkdtemp(prefix='asset_verifier_')
    originals = {}
    for label, path in [('legacy', LEGACY_DOCS_DIR), ('extracted', EXTRACTED_DOCS_DIR), ('final', FINAL_DOCS_DIR)]:
        destination = os.path.join(backup, label)
        shutil.copytree(path, destination)
        originals[path] = destination

    working_legacy = os.path.join(backup, 'working_legacy')
    shutil.copytree(originals[LEGACY_DOCS_DIR], working_legacy)
    with open(os.path.join(working_legacy, text_name), 'wb') as f:
        f.write(b'DOCS' + struct.pack('>I', 1) + struct.pack('>Q', 987654321) + payload)
    with open(os.path.join(working_legacy, image_name), 'wb') as f:
        f.write(b'DOCS' + struct.pack('>I', 2) + struct.pack('>Q', 987654321) + b'not text')

    succeeded = False
    errors = []
    try:
        for script in scripts:
            shutil.rmtree(LEGACY_DOCS_DIR, ignore_errors=True)
            shutil.copytree(working_legacy, LEGACY_DOCS_DIR)
            shutil.rmtree(EXTRACTED_DOCS_DIR, ignore_errors=True)
            shutil.rmtree(FINAL_DOCS_DIR, ignore_errors=True)
            os.makedirs(EXTRACTED_DOCS_DIR)
            os.makedirs(FINAL_DOCS_DIR)

            try:
                result = subprocess.run(
                    ['python3', script],
                    cwd=os.path.dirname(script) or '/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                    check=False,
                )
                output_path = os.path.join(EXTRACTED_DOCS_DIR, text_out)
                image_output = os.path.join(EXTRACTED_DOCS_DIR, image_name[:-6] + '.txt')
                if result.returncode == 0 and os.path.isfile(output_path):
                    with open(output_path, 'rb') as f:
                        extracted = f.read()
                    if extracted == payload and not os.path.exists(image_output):
                        succeeded = True
                        break
                errors.append(f"{script}: exit {result.returncode}")
            except Exception as exc:
                errors.append(f"{script}: {exc}")
    finally:
        for path, saved in originals.items():
            shutil.rmtree(path, ignore_errors=True)
            shutil.copytree(saved, path)
        shutil.rmtree(backup, ignore_errors=True)

    assert succeeded, "No submitted Python script correctly extracted a fresh Type 1 asset while filtering a Type 2 asset. " + '; '.join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
