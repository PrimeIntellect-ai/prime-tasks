#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re


def get_expected_anomalies(csv_path):
    anomalies = []
    prev_ts = None
    prev_loc = None

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row['timestamp'])
            loc = row['locale']
            strings = int(row['strings_translated'])
            errors = int(row['errors_reported'])

            # Skip consecutive duplicates
            if ts == prev_ts and loc == prev_loc:
                continue

            prev_ts = ts
            prev_loc = loc

            if strings > 100:
                rate = errors / strings
                if rate > 0.20:
                    anomalies.append({
                        "timestamp": ts,
                        "locale": loc,
                        "error_rate": round(rate, 2)
                    })
    return anomalies


def test_anomalies_json_exists():
    path = "/home/user/anomalies.json"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."


def test_anomalies_json_content():
    csv_path = "/home/user/loc_metrics.csv"
    json_path = "/home/user/anomalies.json"

    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."
    expected_anomalies = get_expected_anomalies(csv_path)

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            actual_anomalies = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"Failed to parse {json_path} as valid JSON: {e}"

    assert isinstance(actual_anomalies, list), f"Expected JSON root to be an array, got {type(actual_anomalies).__name__}."
    assert len(actual_anomalies) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_anomalies)}."

    for i, (actual, expected) in enumerate(zip(actual_anomalies, expected_anomalies)):
        assert isinstance(actual, dict), f"Expected item at index {i} to be an object."
        assert "timestamp" in actual, f"Item at index {i} is missing 'timestamp'."
        assert "locale" in actual, f"Item at index {i} is missing 'locale'."
        assert "error_rate" in actual, f"Item at index {i} is missing 'error_rate'."

        assert actual["timestamp"] == expected["timestamp"], f"Mismatch in 'timestamp' at index {i}: expected {expected['timestamp']}, got {actual['timestamp']}."
        assert actual["locale"] == expected["locale"], f"Mismatch in 'locale' at index {i}: expected {expected['locale']}, got {actual['locale']}."

        # Compare error_rate with a small tolerance due to floating point representation in JSON
        diff = abs(actual["error_rate"] - expected["error_rate"])
        assert diff < 0.001, f"Mismatch in 'error_rate' at index {i}: expected {expected['error_rate']}, got {actual['error_rate']}."


def test_error_rates_have_exactly_two_decimal_places():
    json_path = "/home/user/anomalies.json"
    expected_count = len(get_expected_anomalies("/home/user/loc_metrics.csv"))
    with open(json_path, 'r', encoding='utf-8') as f:
        raw = f.read()

    tokens = re.findall(r'"error_rate"\s*:\s*([^,}\]\s]+)', raw)
    assert len(tokens) == expected_count, "Could not find exactly one textual error_rate value per anomaly."
    for i, token in enumerate(tokens):
        assert re.fullmatch(r'-?(?:0|[1-9]\d*)\.\d{2}', token), \
            f"error_rate at index {i} must be rendered with exactly two decimal places, got {token!r}."
TEST_EOF

if (
    source_path=/home/user/process_metrics.c
    input_path=/home/user/loc_metrics.csv
    binary_path=/tmp/process_metrics_submission
    backup_csv=$(mktemp)

    test -f "$source_path" || exit 1
    test -s "$source_path" || exit 1
    cp "$input_path" "$backup_csv" || exit 1
    trap 'cp "$backup_csv" "$input_path"; rm -f "$backup_csv" "$binary_path"' EXIT

    gcc "$source_path" -o "$binary_path" || exit 1
    test -x "$binary_path" || exit 1

    # Run and validate against the original supplied input.
    rm -f /home/user/anomalies.json
    (cd /home/user && timeout 10 "$binary_path") || exit 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || exit 1

    # Replace the input with an unpredictable valid fixture so a hardcoded JSON
    # answer cannot pass. Expected results are derived independently by the tests.
    python3 - << 'PY_EOF' || exit 1
import secrets

base = 1800000000 + secrets.randbelow(1000000)
tag = secrets.token_hex(4).upper()
e1 = 2 * secrets.randbelow(25) + 42
e2 = 2 * secrets.randbelow(25) + 42
e3 = 2 * secrets.randbelow(25) + 42

rows = [
    (base, f"BASE-{tag}", 100, 99),
    (base + 10, f"A-{tag}", 200, e1),
    (base + 10, f"A-{tag}", 1000, 0),
    (base + 10, f"B-{tag}", 200, 40),
    (base + 10, f"A-{tag}", 200, e2),
    (base + 20, f"C-{tag}", 500, 100),
    (base + 30, f"D-{tag}", 99, 99),
    (base + 40, f"E-{tag}", 200, e3),
    (base + 40, f"E-{tag}", 200, 180),
    (base + 50, f"F-{tag}", 250, 51),
]

with open('/home/user/loc_metrics.csv', 'w', encoding='utf-8', newline='') as f:
    f.write('timestamp,locale,strings_translated,errors_reported\n')
    for row in rows:
        f.write(','.join(map(str, row)) + '\n')
PY_EOF

    rm -f /home/user/anomalies.json
    (cd /home/user && timeout 10 "$binary_path") || exit 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || exit 1

    # Restore the supplied input and leave output corresponding to that input.
    cp "$backup_csv" "$input_path" || exit 1
    rm -f /home/user/anomalies.json
    (cd /home/user && timeout 10 "$binary_path") || exit 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || exit 1
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
