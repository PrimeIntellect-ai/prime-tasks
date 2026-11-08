#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import zipfile
import pytest

ZIP_PATH = "/home/user/workspace/clean_docs.zip"

def test_zip_exists():
    assert os.path.exists(ZIP_PATH), f"The file {ZIP_PATH} does not exist."

def test_zip_contents():
    assert zipfile.is_zipfile(ZIP_PATH), f"The file {ZIP_PATH} is not a valid zip archive."

    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        names = z.namelist()
        assert set(names) == {"metadata.json", "specs.txt"}, (
            f"Zip contains incorrect files: {names}. "
            "Expected exactly 'metadata.json' and 'specs.txt' at the root."
        )

def test_metadata_json_content():
    assert zipfile.is_zipfile(ZIP_PATH), f"The file {ZIP_PATH} is not a valid zip archive."

    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        try:
            with z.open("metadata.json") as f:
                data = json.load(f)
        except Exception as e:
            pytest.fail(f"Failed to read or parse metadata.json from zip: {e}")

    assert isinstance(data, list), "metadata.json must contain a JSON array."
    assert len(data) == 2, f"metadata.json array must have exactly 2 items, found {len(data)}."

    assert data[0].get("title") == "Guía de usuario", "First item title mismatch. Ensure correct UTF-8 encoding."
    assert data[1].get("title") == "Resumé", "Second item title mismatch. Ensure correct UTF-8 encoding."

    assert data[0].get("id") == "101", "First item id mismatch."
    assert data[0].get("status") == "Active", "First item status mismatch."

    assert data[1].get("id") == "102", "Second item id mismatch."
    assert data[1].get("status") == "Archived", "Second item status mismatch."

def test_specs_txt_content():
    assert zipfile.is_zipfile(ZIP_PATH), f"The file {ZIP_PATH} is not a valid zip archive."

    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        try:
            with z.open("specs.txt") as f:
                text = f.read().decode('utf-8').strip()
        except Exception as e:
            pytest.fail(f"Failed to read specs.txt from zip or decode as UTF-8: {e}")

    text = text.replace('\r\n', '\n')
    expected = "Introducción a la plataforma.\nConfiguración de red: Módulo eléctrico."

    assert text == expected, f"specs.txt content mismatch.\nGot:\n{text}\nExpected:\n{expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
