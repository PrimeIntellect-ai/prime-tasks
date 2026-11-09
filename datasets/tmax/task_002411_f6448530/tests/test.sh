#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import re
from datetime import datetime

def test_clean_translations_exists():
    json_path = '/home/user/clean_translations.json'
    assert os.path.exists(json_path), f"The file {json_path} is missing."
    assert os.path.isfile(json_path), f"The path {json_path} is not a file."

def test_clean_translations_content():
    log_path = '/home/user/vendor_updates.log'
    json_path = '/home/user/clean_translations.json'

    assert os.path.exists(log_path), f"Raw log file {log_path} missing."

    # Derive expected state
    expected_data = {}

    with open(log_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    records = []
    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Parse line: [{timestamp}] LANG={lang_code} | KEY={translation_key} | SRC={source_english_text} | TGT={target_translated_text}
        match = re.match(r'^\[(.*?)\]\s+LANG=(.*?)\s+\|\s+KEY=(.*?)\s+\|\s+SRC=(.*?)\s+\|\s+TGT=(.*)$', line)
        if not match:
            continue

        ts_str, lang, key, src, tgt = match.groups()

        # Parse timestamp
        try:
            ts = datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S')
        except ValueError:
            try:
                ts = datetime.strptime(ts_str, '%m/%d/%Y %H:%M:%S')
            except ValueError:
                continue

        # Anomaly detection
        if len(src) == 0:
            continue
        ratio = len(tgt) / len(src)
        if not (0.2 <= ratio <= 3.0):
            continue

        records.append({
            'ts': ts,
            'lang': lang,
            'key': key,
            'tgt': tgt
        })

    # Deduplicate
    latest_records = {}
    for rec in records:
        group_key = (rec['lang'], rec['key'])
        if group_key not in latest_records or rec['ts'] > latest_records[group_key]['ts']:
            latest_records[group_key] = rec

    # Build expected JSON
    for (lang, key), rec in latest_records.items():
        if lang not in expected_data:
            expected_data[lang] = {}
        expected_data[lang][key] = rec['tgt']

    # Read actual JSON
    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert actual_data == expected_data, f"The content of {json_path} does not match the expected deduplicated and cleaned data."

def test_clean_translations_format():
    json_path = '/home/user/clean_translations.json'

    with open(json_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Check for 2 spaces indentation
    assert "\n  " in content, "The JSON file does not appear to be pretty-printed with 2 spaces of indentation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
