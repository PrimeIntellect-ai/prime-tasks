#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

def test_qa_sample_file_exists():
    """Check if the qa_sample.jsonl file exists."""
    file_path = "/home/user/qa_sample.jsonl"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

def test_qa_sample_content():
    """Check if the qa_sample.jsonl contains the correct sampled and processed data."""
    file_path = "/home/user/qa_sample.jsonl"

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 6, f"Expected exactly 6 lines in {file_path}, found {len(lines)}."

    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

    # Check sorting
    langs = [r['lang'] for r in records]
    seq_ids = [r['seq_id'] for r in records]

    expected_langs = ["de-DE"] * 3 + ["es-ES"] * 3
    assert langs == expected_langs, "Records are not sorted correctly by 'lang'."

    expected_seq_ids = [10, 11, 13, 1, 2, 4]
    assert seq_ids == expected_seq_ids, "Records are not sampled or sorted correctly by 'seq_id'."

    # Helper to hash email
    def hash_email(email):
        return hashlib.sha256(email.encode('utf-8')).hexdigest()

    expected_data = [
        {"lang": "de-DE", "seq_id": 10, "translator": hash_email("hans@test.com"), "text": "Guten Tag!"},
        {"lang": "de-DE", "seq_id": 11, "translator": "SYSTEM", "text": "UNTRANSLATED"},
        {"lang": "de-DE", "seq_id": 13, "translator": hash_email("hans@test.com"), "text": "Tschüss"},
        {"lang": "es-ES", "seq_id": 1, "translator": hash_email("ana@test.com"), "text": "Hola!"},
        {"lang": "es-ES", "seq_id": 2, "translator": hash_email("ana@test.com"), "text": "Adiós"},
        {"lang": "es-ES", "seq_id": 4, "translator": hash_email("luis@test.com"), "text": "Mañana"}
    ]

    for i, (actual, expected) in enumerate(zip(records, expected_data)):
        assert actual.get("lang") == expected["lang"], f"Line {i+1}: 'lang' mismatch."
        assert actual.get("seq_id") == expected["seq_id"], f"Line {i+1}: 'seq_id' mismatch."
        assert actual.get("translator") == expected["translator"], f"Line {i+1}: 'translator' mismatch (hashing/system logic failed)."
        assert actual.get("text") == expected["text"], f"Line {i+1}: 'text' mismatch (unicode decoding/system logic failed)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
