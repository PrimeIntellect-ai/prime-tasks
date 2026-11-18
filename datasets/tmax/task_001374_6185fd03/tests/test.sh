#!/bin/bash
mkdir -p /logs/verifier

if (
    set -euo pipefail

    CLEANER_DIR=/home/user/cleaner
    RAW=/home/user/raw_reviews.csv
    CLEANED=/home/user/cleaned_reviews.csv
    CORRELATION=/home/user/correlation.txt
    BIN=/tmp/cleaner_submission
    ORIGINAL_RAW=/tmp/raw_reviews.original.$$

    test -d "$CLEANER_DIR"
    test -f "$CLEANER_DIR/go.mod"
    test -n "$(find "$CLEANER_DIR" -type f -name '*.go' -print -quit)"
    test "$(cd "$CLEANER_DIR" && go list -m)" = "cleaner"
    (cd "$CLEANER_DIR" && go build -o "$BIN" .)
    test -x "$BIN"

    cp "$RAW" "$ORIGINAL_RAW"
    trap 'cp "$ORIGINAL_RAW" "$RAW" 2>/dev/null || true; rm -f "$ORIGINAL_RAW"' EXIT

    run_cleaner() {
        rm -f "$CLEANED" "$CORRELATION"
        (cd "$CLEANER_DIR" && timeout 30s "$BIN")
        test -f "$CLEANED"
        test -f "$CORRELATION"
    }

    # Execute the submitted Go application on the supplied dataset.
    run_cleaner

    cat > /tmp/check_original.py <<'PY'
import csv
import os

CLEANED_CSV_PATH = '/home/user/cleaned_reviews.csv'
CORRELATION_TXT_PATH = '/home/user/correlation.txt'

assert os.path.isfile(CLEANED_CSV_PATH), f"{CLEANED_CSV_PATH} does not exist. Did you save the cleaned dataset?"
expected_rows = [
    ['1', 'Great product, loved it.', '5', '10.5', '4'],
    ['2', 'Terrible. Do not buy.', '1', '15.0', '4'],
    ['6', 'Average.', '3', '10.0', '1'],
    ['7', 'I am absolutely amazed by the quality of this item.', '5', '25.0', '10'],
    ['8', 'Broke after one use', '1', '8.0', '4'],
    ['9', 'It is fine', '3', '11.5', '3'],
    ['10', 'Not what I expected', '2', '9.99', '4']
]
with open(CLEANED_CSV_PATH, 'r', encoding='utf-8', newline='') as f:
    rows = list(csv.reader(f))
assert len(rows) > 0, f"{CLEANED_CSV_PATH} is empty."
expected_header = ['ReviewID', 'Text', 'Rating', 'Price', 'TokenCount']
assert rows[0] == expected_header, f"Header in {CLEANED_CSV_PATH} is incorrect. Expected {expected_header}, got {rows[0]}."
data_rows = rows[1:]
assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but found {len(data_rows)}."
for i, expected in enumerate(expected_rows):
    assert data_rows[i] == expected, f"Row {i+1} mismatch. Expected {expected}, got {data_rows[i]}."

assert os.path.isfile(CORRELATION_TXT_PATH), f"{CORRELATION_TXT_PATH} does not exist. Did you save the correlation coefficient?"
with open(CORRELATION_TXT_PATH, 'r', encoding='utf-8') as f:
    content = f.read().strip()
expected_val = '0.3845'
assert content == expected_val, f"Incorrect correlation value in {CORRELATION_TXT_PATH}. Expected '{expected_val}', got '{content}'."
PY
    python3 /tmp/check_original.py

    # Generate a fresh, well-formed CSV so hardcoded supplied-output files cannot pass.
    python3 - <<'PY'
import csv
import json
import math
import secrets

nonce = secrets.token_hex(8)
base = secrets.randbelow(800000) + 100000
input_rows = [
    [str(base + 1), f'Vivid{nonce} product, works.', '5', '13.25'],
    [str(base + 2), f'Bad-{nonce} item', '1', '0'],
    [str(base + 3), '', '3', '12.0'],
    [str(base + 4), f'Below {nonce}', '0', '4.0'],
    [str(base + 5), f'Above {nonce}', '6', '5.0'],
    [str(base + 6), f'Negative {nonce}', '3', '-0.01'],
    [str(base + 7), f'{nonce}.', '3', '7.75'],
    [str(base + 8), f'Many fresh words for {nonce}', '2', '9.50'],
]
with open('/home/user/raw_reviews.csv', 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(['ReviewID', 'Text', 'Rating', 'Price'])
    writer.writerows(input_rows)

valid = [input_rows[i] for i in (0, 1, 6, 7)]
expected_rows = []
xs = []
ys = []
for review_id, text, rating, price in valid:
    token_count = len(text.lower().replace('.', '').replace(',', '').split(' '))
    expected_rows.append([review_id, text, rating, price, str(token_count)])
    xs.append(float(token_count))
    ys.append(float(rating))
mx = sum(xs) / len(xs)
my = sum(ys) / len(ys)
correlation = sum((x-mx)*(y-my) for x, y in zip(xs, ys)) / math.sqrt(
    sum((x-mx)**2 for x in xs) * sum((y-my)**2 for y in ys)
)
with open('/tmp/dynamic_expected.json', 'w', encoding='utf-8') as f:
    json.dump({'rows': expected_rows, 'correlation': f'{correlation:.4f}'}, f)
PY

    run_cleaner

    python3 - <<'PY'
import csv
import json
import os

cleaned = '/home/user/cleaned_reviews.csv'
correlation = '/home/user/correlation.txt'
assert os.path.isfile(cleaned)
assert os.path.isfile(correlation)
with open('/tmp/dynamic_expected.json', encoding='utf-8') as f:
    expected = json.load(f)
with open(cleaned, encoding='utf-8', newline='') as f:
    rows = list(csv.reader(f))
header = ['ReviewID', 'Text', 'Rating', 'Price', 'TokenCount']
assert rows and rows[0] == header, (header, rows[0] if rows else None)
assert rows[1:] == expected['rows'], (expected['rows'], rows[1:])
with open(correlation, encoding='utf-8') as f:
    actual_correlation = f.read().strip()
assert actual_correlation == expected['correlation'], (expected['correlation'], actual_correlation)
PY

    # Restore the supplied input and ensure the executable reproducibly regenerates its outputs.
    cp "$ORIGINAL_RAW" "$RAW"
    run_cleaner
    python3 /tmp/check_original.py
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
