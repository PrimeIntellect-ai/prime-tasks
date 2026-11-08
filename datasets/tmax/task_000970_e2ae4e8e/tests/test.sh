#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_script_exists():
    path = "/home/user/process_locales.py"
    assert os.path.isfile(path), f"Script missing: {path}"

def test_pipeline_log():
    path = "/home/user/pipeline.log"
    assert os.path.isfile(path), f"Log file missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "Pipeline started" in content, "Log file missing 'Pipeline started' message."
    assert "Pipeline finished" in content, "Log file missing 'Pipeline finished' message."

def test_final_locales_csv():
    path = "/home/user/final_locales.csv"
    assert os.path.isfile(path), f"Output file missing: {path}"

    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 12, f"Expected 12 rows in final_locales.csv, got {len(rows)}"

    expected_rows = [
        {"term": "apple", "lang": "de", "translation": "apfel", "category": "food", "rolling_len_avg": "5.0"},
        {"term": "apple", "lang": "es", "translation": "manzana", "category": "food", "rolling_len_avg": "6.0"},
        {"term": "apple", "lang": "fr", "translation": "pomme", "category": "food", "rolling_len_avg": "6.0"},
        {"term": "exit", "lang": "de", "translation": "beenden", "category": "menu", "rolling_len_avg": "7.0"},
        {"term": "exit", "lang": "es", "translation": "salirzzzz", "category": "menu", "rolling_len_avg": "8.0"},
        {"term": "exit", "lang": "fr", "translation": "quitter", "category": "menu", "rolling_len_avg": "8.0"},
        {"term": "open", "lang": "de", "translation": "öffnen", "category": "menu", "rolling_len_avg": "6.5"},
        {"term": "open", "lang": "es", "translation": "abrir", "category": "menu", "rolling_len_avg": "5.5"},
        {"term": "open", "lang": "fr", "translation": "ouvrir", "category": "menu", "rolling_len_avg": "5.5"},
        {"term": "save", "lang": "de", "translation": "speichern", "category": "menu", "rolling_len_avg": "7.5"},
        {"term": "save", "lang": "es", "translation": "guardar", "category": "menu", "rolling_len_avg": "8.0"},
        {"term": "save", "lang": "fr", "translation": "sauvegarder", "category": "menu", "rolling_len_avg": "9.0"}
    ]

    for i, expected in enumerate(expected_rows):
        actual = rows[i]
        for key, val in expected.items():
            assert actual.get(key) == val, f"Row {i+1} mismatch for column '{key}': expected '{val}', got '{actual.get(key)}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
