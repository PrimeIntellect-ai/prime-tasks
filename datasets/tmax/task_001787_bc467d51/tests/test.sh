#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import difflib
import pytest

def test_translated_ui_accuracy():
    ui_strings_path = "/home/user/loc_task/ui_strings.txt"
    po_path = "/home/user/loc_task/es_ES.po"
    output_path = "/home/user/loc_task/translated_ui.json"

    assert os.path.exists(output_path), f"Expected output file not found at {output_path}"

    # Re-derive the ground truth
    extracted_strings = []
    with open(ui_strings_path, 'r', encoding='utf-8') as f:
        for line in f:
            if 'UI_EVENT: "' in line:
                val = line.split('UI_EVENT: "')[1].split('"')[0]
                extracted_strings.append(val)

    po_dict = {}
    with open(po_path, 'r', encoding='utf-8') as f:
        current_msgid = None
        for line in f:
            if line.startswith('msgid "'):
                current_msgid = line.split('"')[1]
            elif line.startswith('msgstr "') and current_msgid is not None:
                msgstr = line.split('"')[1]
                po_dict[current_msgid] = msgstr
                current_msgid = None

    expected_dict = {}
    for s in extracted_strings:
        if s in po_dict:
            expected_dict[s] = po_dict[s]
        else:
            matches = difflib.get_close_matches(s, po_dict.keys(), n=1, cutoff=0.85)
            if matches:
                expected_dict[s] = po_dict[matches[0]]
            else:
                expected_dict[s] = None

    # Load agent output
    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            pred_dict = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON.")

    # Calculate accuracy
    correct = 0
    total = len(expected_dict)

    for k, v in expected_dict.items():
        if k in pred_dict and pred_dict[k] == v:
            correct += 1

    accuracy = correct / total if total > 0 else 0.0

    # Assert accuracy
    threshold = 0.95
    assert accuracy >= threshold, (
        f"Accuracy {accuracy:.2f} is below the threshold of {threshold:.2f}. "
        f"Correct matches: {correct}/{total}. "
        f"Expected dict: {expected_dict}, Output dict: {pred_dict}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
