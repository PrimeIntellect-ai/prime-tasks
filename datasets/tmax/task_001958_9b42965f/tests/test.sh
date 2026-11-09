#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_cleaned_translations_json_exists():
    assert os.path.isfile('/home/user/cleaned_translations.json'), "The output file /home/user/cleaned_translations.json is missing."

def test_loc_stats_txt_exists():
    assert os.path.isfile('/home/user/loc_stats.txt'), "The output file /home/user/loc_stats.txt is missing."

def test_loc_stats_content():
    with open('/home/user/loc_stats.txt', 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "de: 2",
        "es: 2",
        "fr: 1"
    ]

    assert lines == expected_lines, f"Expected loc_stats.txt to have {expected_lines}, but got {lines}."

def test_cleaned_translations_content():
    with open('/home/user/cleaned_translations.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/cleaned_translations.json is not a valid JSON file.")

    assert isinstance(data, list), "The JSON output should be a list of objects."
    assert len(data) == 5, f"Expected 5 records, but found {len(data)}."

    expected_data = [
        {
            "normalized_source": "error: not found",
            "target_lang": "de",
            "translation": "Fehler: Nicht gefunden",
            "epoch_timestamp": 1697090200
        },
        {
            "normalized_source": "submit",
            "target_lang": "de",
            "translation": "Einreichen",
            "epoch_timestamp": 1697091500
        },
        {
            "normalized_source": "cancel",
            "target_lang": "es",
            "translation": "Cancelar",
            "epoch_timestamp": 1697090400
        },
        {
            "normalized_source": "hello world",
            "target_lang": "es",
            "translation": "Hola mundo!",
            "epoch_timestamp": 1697090100
        },
        {
            "normalized_source": "login",
            "target_lang": "fr",
            "translation": "Identifier",
            "epoch_timestamp": 1697091000
        }
    ]

    # Check that each record matches exactly, allowing for float/int differences in epoch_timestamp
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("normalized_source") == expected["normalized_source"], f"Record {i} normalized_source mismatch."
        assert actual.get("target_lang") == expected["target_lang"], f"Record {i} target_lang mismatch."
        assert actual.get("translation") == expected["translation"], f"Record {i} translation mismatch."

        actual_ts = actual.get("epoch_timestamp")
        assert actual_ts is not None, f"Record {i} is missing epoch_timestamp."
        assert float(actual_ts) == float(expected["epoch_timestamp"]), f"Record {i} epoch_timestamp mismatch."

    # Check sorting
    langs = [r.get("target_lang") for r in data]
    sources = [r.get("normalized_source") for r in data]

    assert langs == sorted(langs), "The JSON array is not sorted alphabetically by target_lang."

    # Check secondary sorting by source text
    for lang in set(langs):
        lang_sources = [r.get("normalized_source") for r in data if r.get("target_lang") == lang]
        assert lang_sources == sorted(lang_sources), f"The JSON array is not sorted alphabetically by normalized_source for lang '{lang}'."

def test_json_indentation():
    with open('/home/user/cleaned_translations.json', 'r') as f:
        content = f.read()

    assert "    {" in content or "    \"" in content, "The JSON file does not appear to be formatted with 4-space indentation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
