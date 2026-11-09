#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_loc_report_exists():
    assert os.path.isfile('/home/user/loc_report.tsv'), "The output file /home/user/loc_report.tsv is missing."

def test_loc_report_content():
    expected_rows = [
        ["ID001", "UI_BUTTON", "Sauvegarder", "11.00"],
        ["ID002", "UI_BUTTON", "Annuler", "9.00"],
        ["ID003", "MENU", "Fichier", "8.33"],
        ["ID004", "MENU", "Modifier", "7.33"],
        ["ID005", "DIALOG", "Êtes-vous sûr ?", "10.00"],
        ["ID006", "DIALOG", "Avertissement", "12.00"]
    ]

    with open('/home/user/loc_report.tsv', 'r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 6, f"Expected 6 rows in the report, but found {len(lines)}."

    for i, line in enumerate(lines):
        columns = line.split('\t')
        assert len(columns) == 4, f"Row {i+1} does not have exactly 4 tab-separated columns: {repr(line)}"

        expected_col = expected_rows[i]
        assert columns[0] == expected_col[0], f"Row {i+1}: Expected StringID '{expected_col[0]}', got '{columns[0]}'"
        assert columns[1] == expected_col[1], f"Row {i+1}: Expected Category '{expected_col[1]}', got '{columns[1]}'"
        assert columns[2] == expected_col[2], f"Row {i+1}: Expected NormalizedFrenchText '{expected_col[2]}', got '{columns[2]}'"
        assert columns[3] == expected_col[3], f"Row {i+1}: Expected RollingAvgLen '{expected_col[3]}', got '{columns[3]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
