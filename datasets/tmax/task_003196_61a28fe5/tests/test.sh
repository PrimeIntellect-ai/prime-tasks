#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from collections import defaultdict

def test_daily_locale_clicks_exists():
    assert os.path.isfile("/home/user/daily_locale_clicks.csv"), "The output file /home/user/daily_locale_clicks.csv does not exist."

def test_daily_locale_clicks_content():
    translations_path = "/home/user/translations.csv"
    metrics_path = "/home/user/metrics.csv"
    output_path = "/home/user/daily_locale_clicks.csv"

    assert os.path.isfile(translations_path), f"Missing {translations_path}"
    assert os.path.isfile(metrics_path), f"Missing {metrics_path}"
    assert os.path.isfile(output_path), f"Missing {output_path}"

    # 1. Load valid translations
    valid_translations = set()
    with open(translations_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            valid_translations.add((row['string_id'], row['locale']))

    # 2. Process metrics
    aggregated = defaultdict(lambda: defaultdict(int))
    all_locales = set()
    all_dates = set()

    with open(metrics_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            clicks = int(row['clicks'])
            if clicks < 0:
                continue

            string_id = row['string_id']
            locale = row['locale']
            if (string_id, locale) not in valid_translations:
                continue

            # Extract date from ISO timestamp (YYYY-MM-DD)
            date = row['timestamp'][:10]

            aggregated[date][locale] += clicks
            all_locales.add(locale)
            all_dates.add(date)

    sorted_locales = sorted(list(all_locales))
    sorted_dates = sorted(list(all_dates))

    # 3. Build expected output
    expected_rows = []
    header = ['date'] + sorted_locales
    expected_rows.append(header)

    for date in sorted_dates:
        row = [date]
        for loc in sorted_locales:
            row.append(str(aggregated[date][loc]))
        expected_rows.append(row)

    # 4. Read actual output
    actual_rows = []
    with open(output_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if any(cell.strip() for cell in row):  # ignore empty lines
                actual_rows.append(row)

    # 5. Compare
    assert len(actual_rows) > 0, "The output file is empty."
    assert actual_rows[0] == expected_rows[0], f"Header mismatch. Expected: {expected_rows[0]}, Got: {actual_rows[0]}"

    assert len(actual_rows) == len(expected_rows), f"Row count mismatch. Expected {len(expected_rows)} rows, got {len(actual_rows)}"

    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], f"Data row {i} mismatch. Expected: {expected_rows[i]}, Got: {actual_rows[i]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
