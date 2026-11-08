#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import pytest


def test_processed_locales_csv_correct():
    json_path = "/home/user/locales.json"
    csv_path = "/home/user/processed_locales.csv"

    assert os.path.isfile(json_path), f"Input file {json_path} is missing."
    assert os.path.isfile(csv_path), f"Output file {csv_path} was not created."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    original_data = [
        {"id": "btn_save", "en": "Save", "fr": "Sauvegarder"},
        {"id": "btn_cancel", "en": "Cancel", "fr": "Annuler"},
        {"id": "msg_hello", "en": "Hello World", "fr": None},
        {"id": "msg_error", "en": "An unexpected error occurred during the process", "fr": "Erreur"},
        {"id": "btn_ok", "en": "OK", "fr": "OK"},
        {"id": "msg_welcome", "en": "Welcome", "fr": ""},
        {"id": "lbl_status", "en": "Status", "fr": "Statut"}
    ]
    assert data == original_data, f"Input file {json_path} was modified."

    expected_rows = [["id", "imputed_fr", "fr_len", "rolling_avg_3", "flag"]]
    len_fr_history = []

    for item in data:
        item_id = item.get("id", "")
        en = item.get("en", "")
        fr = item.get("fr")

        if fr is None or fr == "":
            imputed_fr = f"[FR]{en}"
        else:
            imputed_fr = fr

        len_en = len(en)
        len_fr = len(imputed_fr)

        len_fr_history.append(len_fr)
        window = len_fr_history[-3:]
        avg = sum(window) / len(window)
        rolling_avg_str = f"{avg:.1f}"

        if len_en == 0:
            flag = "0"
        else:
            dist = abs(len_en - len_fr) / len_en
            flag = "1" if dist > 0.5 else "0"

        expected_rows.append([item_id, imputed_fr, str(len_fr), rolling_avg_str, flag])

    actual_rows = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) > 0, f"The CSV file {csv_path} is empty."
    assert actual_rows[0] == expected_rows[0], f"CSV headers are incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}."
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i + 1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
