#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import math
import glob
import pytest

INPUTS_DIR = "/home/user/inputs"
LOCALE_COSTS_FILE = "/home/user/locale_costs.json"
DROPPED_IDS_FILE = "/home/user/dropped_ids.log"

def compute_expected_results():
    csv_files = glob.glob(os.path.join(INPUTS_DIR, "*.csv"))

    locale_costs = {}
    dropped_ids = []

    for file_path in csv_files:
        with open(file_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                row_id = int(row["id"])
                locale = row["locale"]
                source_text = row["source_text"]
                target_text = row["target_text"]
                rate = float(row["rate_per_char"])

                len_source = len(source_text)
                len_target = len(target_text)

                if len_source == 0 or len_target == 0:
                    dropped_ids.append(row_id)
                    continue

                ratio = len_target / len_source
                if not (0.2 <= ratio <= 5.0):
                    dropped_ids.append(row_id)
                    continue

                cost = len_target * rate
                locale_costs[locale] = locale_costs.get(locale, 0.0) + cost

    # Round to 2 decimal places as per requirements
    for locale in locale_costs:
        locale_costs[locale] = round(locale_costs[locale], 2)

    dropped_ids.sort()
    return locale_costs, dropped_ids

def test_locale_costs_json():
    """Test that locale_costs.json exists and contains the correct aggregated costs."""
    assert os.path.exists(LOCALE_COSTS_FILE), f"Output file {LOCALE_COSTS_FILE} does not exist."

    with open(LOCALE_COSTS_FILE, "r", encoding="utf-8") as f:
        try:
            actual_costs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{LOCALE_COSTS_FILE} is not a valid JSON file.")

    expected_costs, _ = compute_expected_results()

    # Check that all expected locales are present and values match up to 2 decimal places
    assert set(actual_costs.keys()) == set(expected_costs.keys()), \
        f"Locales in JSON do not match. Expected {list(expected_costs.keys())}, got {list(actual_costs.keys())}."

    for locale, expected_cost in expected_costs.items():
        actual_cost = actual_costs[locale]
        assert math.isclose(actual_cost, expected_cost, rel_tol=1e-5, abs_tol=1e-2), \
            f"Cost for locale '{locale}' is incorrect. Expected {expected_cost}, got {actual_cost}."

def test_dropped_ids_log():
    """Test that dropped_ids.log exists and contains the correct sorted IDs."""
    assert os.path.exists(DROPPED_IDS_FILE), f"Output file {DROPPED_IDS_FILE} does not exist."

    with open(DROPPED_IDS_FILE, "r", encoding="utf-8") as f:
        lines = f.read().strip().splitlines()

    actual_dropped_ids = []
    for line in lines:
        try:
            actual_dropped_ids.append(int(line.strip()))
        except ValueError:
            pytest.fail(f"Invalid ID found in {DROPPED_IDS_FILE}: '{line.strip()}' is not an integer.")

    _, expected_dropped_ids = compute_expected_results()

    assert actual_dropped_ids == expected_dropped_ids, \
        f"Dropped IDs do not match. Expected {expected_dropped_ids}, got {actual_dropped_ids}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
