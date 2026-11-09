#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_final_csv():
    """Verify that final.csv is correctly merged, filtered, gap-filled, and sorted."""
    final_csv_path = "/home/user/locales/final.csv"
    assert os.path.isfile(final_csv_path), f"File {final_csv_path} does not exist."

    with open(final_csv_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ERR_100,en,Error 100",
        "ERR_100,es,Error 100 actualizado",
        "ERR_100,fr,UNTRANSLATED",
        "ERR_200,en,Error 200",
        "ERR_200,es,UNTRANSLATED",
        "ERR_200,fr,Erreur 200",
        "ERR_404,en,Not found",
        "ERR_404,es,UNTRANSLATED",
        "ERR_404,fr,Introuvable",
        "ERR_500,en,Server error",
        "ERR_500,es,UNTRANSLATED",
        "ERR_500,fr,UNTRANSLATED"
    ]

    assert actual_lines == expected_lines, (
        f"Contents of {final_csv_path} do not match the expected output. "
        "Check your merge, regex filtering, gap-filling, and sorting logic."
    )

def test_review_csv():
    """Verify that review.csv contains exactly the first 2 rows for each language, correctly sorted."""
    review_csv_path = "/home/user/locales/review.csv"
    assert os.path.isfile(review_csv_path), f"File {review_csv_path} does not exist."

    with open(review_csv_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ERR_100,en,Error 100",
        "ERR_200,en,Error 200",
        "ERR_100,es,Error 100 actualizado",
        "ERR_200,es,UNTRANSLATED",
        "ERR_100,fr,UNTRANSLATED",
        "ERR_200,fr,Erreur 200"
    ]

    assert actual_lines == expected_lines, (
        f"Contents of {review_csv_path} do not match the expected output. "
        "Ensure you extract exactly the first 2 rows per language and sort by language_code then msg_id."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
