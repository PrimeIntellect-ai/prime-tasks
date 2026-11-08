#!/bin/bash
set -u
mkdir -p /logs/verifier

if (
    set -e

    PROJECT=/home/user/i18n_processor
    INPUT=/home/user/translations.jsonl
    OUTPUT=/home/user/processed_translations.json
    BACKUP=$(mktemp)

    test -d "$PROJECT"
    test -f "$PROJECT/Cargo.toml"
    test -s "$PROJECT/Cargo.toml"
    test -f "$PROJECT/src/main.rs"
    test -s "$PROJECT/src/main.rs"

    cp "$INPUT" "$BACKUP"
    cleanup() {
        cp "$BACKUP" "$INPUT"
        rm -f "$OUTPUT"
        (cd "$PROJECT" && timeout 180s /usr/bin/cargo run --quiet) >/dev/null 2>&1 || true
        rm -f "$BACKUP"
    }
    trap cleanup EXIT

    cat << 'VALIDATOR_EOF' > /tmp/validate_pipeline.py
import json
import re
import sys
from collections import defaultdict

input_path, output_path = sys.argv[1:3]

records = []
with open(input_path, "r", encoding="utf-8") as f:
    for line_number, line in enumerate(f, 1):
        if not line.strip():
            continue
        record = json.loads(line)
        assert set(record) == {"locale", "key", "text", "features"}, \
            f"Unexpected source fields on line {line_number}"
        records.append(record)

english = {
    record["key"]: record["text"]
    for record in records
    if record["locale"] == "en-US"
}

expected = defaultdict(list)
for record in records:
    text = record["text"]
    if record["locale"] != "en-US" and (text is None or text == ""):
        assert record["key"] in english, f"No en-US fallback for {record['key']}"
        text = english[record["key"]]
    assert isinstance(text, str) and text != ""
    expected[record["locale"]].append({
        "locale": record["locale"],
        "key": record["key"],
        "text": text,
        "features": {
            "char_count": len(text),
            "placeholders": len(re.findall(r"\{[^{}]+\}", text)),
        },
    })

expected = dict(expected)
for items in expected.values():
    items.sort(key=lambda item: item["key"])

with open(output_path, "r", encoding="utf-8") as f:
    raw = f.read()
assert raw, "Output is empty"
data = json.loads(raw)
assert isinstance(data, dict), "Top-level output must be an object"
assert data == expected, f"Output does not exactly match all source records.\nExpected: {expected!r}\nActual: {data!r}"

# serde_json's standard pretty formatter and Python's indent=2 representation
# have the same layout for these inputs. Preserve the submitted key ordering
# while requiring actual two-space pretty printing.
assert "\t" not in raw and "\r" not in raw, "Pretty output must use spaces and Unix newlines"
body = raw[:-1] if raw.endswith("\n") else raw
assert not body.endswith("\n"), "Output has more than one trailing newline"
assert body == json.dumps(data, ensure_ascii=False, indent=2), \
    "Output is not pretty-printed with 2 spaces"
VALIDATOR_EOF

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

OUTPUT_FILE = "/home/user/processed_translations.json"

@pytest.fixture
def processed_data():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output file {OUTPUT_FILE} is not valid JSON: {e}")

    return data

def test_top_level_keys(processed_data):
    expected_locales = {"en-US", "fr-FR", "ar-SA"}
    actual_locales = set(processed_data.keys())
    assert actual_locales == expected_locales, f"Expected locales {expected_locales}, but got {actual_locales}."

def test_sorting_by_key(processed_data):
    for loc, items in processed_data.items():
        keys = [item.get("key") for item in items]
        assert keys == sorted(keys), f"Items for locale '{loc}' are not sorted alphabetically by key. Got: {keys}"

def test_imputation(processed_data):
    fr_items = processed_data.get("fr-FR", [])
    fr_farewell = next((item for item in fr_items if item.get("key") == "farewell"), None)
    assert fr_farewell is not None, "Missing 'farewell' key in 'fr-FR' locale."
    assert fr_farewell.get("text") == "Goodbye 👋", "Imputation failed for fr-FR 'farewell'."

    ar_items = processed_data.get("ar-SA", [])
    ar_items_obj = next((item for item in ar_items if item.get("key") == "items"), None)
    assert ar_items_obj is not None, "Missing 'items' key in 'ar-SA' locale."
    assert ar_items_obj.get("text") == "You have {count} items in your {container}.", "Imputation failed for ar-SA 'items'."

def test_features_extraction(processed_data):
    en_items = processed_data.get("en-US", [])
    en_farewell = next((item for item in en_items if item.get("key") == "farewell"), None)
    assert en_farewell is not None, "Missing 'farewell' key in 'en-US' locale."

    features = en_farewell.get("features")
    assert features is not None, "Features object is missing for en-US 'farewell'."
    assert features.get("char_count") == 9, f"Expected char_count 9 for en-US 'farewell', got {features.get('char_count')}"
    assert features.get("placeholders") == 0, f"Expected placeholders 0 for en-US 'farewell', got {features.get('placeholders')}"

    en_welcome = next((item for item in en_items if item.get("key") == "welcome"), None)
    assert en_welcome is not None, "Missing 'welcome' key in 'en-US' locale."
    features = en_welcome.get("features")
    assert features is not None, "Features object is missing for en-US 'welcome'."
    assert features.get("char_count") == 21, f"Expected char_count 21 for en-US 'welcome', got {features.get('char_count')}"
    assert features.get("placeholders") == 1, f"Expected placeholders 1 for en-US 'welcome', got {features.get('placeholders')}"

    ar_items = processed_data.get("ar-SA", [])
    ar_welcome = next((item for item in ar_items if item.get("key") == "welcome"), None)
    assert ar_welcome is not None, "Missing 'welcome' key in 'ar-SA' locale."
    features = ar_welcome.get("features")
    assert features is not None, "Features object is missing for ar-SA 'welcome'."
    assert features.get("char_count") == 23, f"Expected char_count 23 for ar-SA 'welcome', got {features.get('char_count')}"
    assert features.get("placeholders") == 1, f"Expected placeholders 1 for ar-SA 'welcome', got {features.get('placeholders')}"

    ar_items_obj = next((item for item in ar_items if item.get("key") == "items"), None)
    assert ar_items_obj is not None, "Missing 'items' key in 'ar-SA' locale."
    features = ar_items_obj.get("features")
    assert features is not None, "Features object is missing for ar-SA 'items'."
    assert features.get("char_count") == 39, f"Expected char_count 39 for ar-SA 'items', got {features.get('char_count')}"
    assert features.get("placeholders") == 2, f"Expected placeholders 2 for ar-SA 'items', got {features.get('placeholders')}"
TEST_EOF

    rm -f "$OUTPUT"
    (cd "$PROJECT" && timeout 180s /usr/bin/cargo run --quiet)
    test -f "$OUTPUT"
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
    python3 /tmp/validate_pipeline.py "$INPUT" "$OUTPUT"

    cat << 'PROBE_EOF' > "$INPUT"
{"locale":"de-DE","key":"zeta","text":"Deutsch {name}","features":null}
{"locale":"en-US","key":"alpha","text":"A 👋 and {one} plus {two}","features":null}
{"locale":"ja-JP","key":"zeta","text":"","features":null}
{"locale":"en-US","key":"zeta","text":"Fallback 👋 {name}","features":null}
{"locale":"de-DE","key":"alpha","text":null,"features":null}
{"locale":"ja-JP","key":"alpha","text":"独自の文", "features":null}
PROBE_EOF

    rm -f "$OUTPUT"
    (cd "$PROJECT" && timeout 180s /usr/bin/cargo run --quiet)
    test -f "$OUTPUT"
    python3 /tmp/validate_pipeline.py "$INPUT" "$OUTPUT"

    cp "$BACKUP" "$INPUT"
    rm -f "$OUTPUT"
    (cd "$PROJECT" && timeout 180s /usr/bin/cargo run --quiet)
    python3 /tmp/validate_pipeline.py "$INPUT" "$OUTPUT"

    trap - EXIT
    rm -f "$BACKUP"
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
