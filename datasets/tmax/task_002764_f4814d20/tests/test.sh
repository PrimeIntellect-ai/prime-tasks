#!/bin/bash
mkdir -p /logs/verifier
status=0
ORIGINAL_LOGS=/tmp/original_logs.jsonl

if ! cp /home/user/data/logs.jsonl "$ORIGINAL_LOGS"; then
    status=1
fi

cat <<'PY' > /tmp/check_script.py
import ast
import os
import sys

path = "/home/user/process_logs.py"
assert os.path.isfile(path), f"Required script {path} does not exist or is not a file."
with open(path, "r", encoding="utf-8") as f:
    source = f.read()
tree = ast.parse(source, filename=path)
stdlib = set(sys.stdlib_module_names)
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        names = [alias.name.split('.')[0] for alias in node.names]
    elif isinstance(node, ast.ImportFrom):
        assert node.level == 0, "Relative/local imports are not allowed; use only the standard library."
        names = [node.module.split('.')[0]] if node.module else []
    else:
        continue
    for name in names:
        assert name in stdlib, f"Non-standard-library import found: {name}"
PY
python3 /tmp/check_script.py || status=1

cat <<'PY' > /tmp/make_adversarial_logs.py
import json
import secrets
from collections import defaultdict

path = "/home/user/data/logs.jsonl"
expected_path = "/tmp/adversarial_expected.json"
nonce = secrets.token_hex(6)
types = [
    "login-" + nonce,
    "quoted,\"type-" + nonce,
    "café-" + nonce,
    "zeta-" + nonce,
]
timestamps = [
    "2024-02-01T00:17:31Z",
    "2024-02-01T09:59:59Z",
    "2024-02-02T03:01:02Z",
    "2024-02-03T22:44:05Z",
]
counts = defaultdict(int)
line_count = 120000
padding = "x" * 1500

with open(path, "w", encoding="utf-8", newline="\n") as f:
    for i in range(line_count):
        ts = timestamps[(i * 7) % len(timestamps)]
        event_type = types[(i * 11 + i // 13) % len(types)]
        hour = ts[:14] + "00:00Z"
        counts[(hour, event_type)] += 1

        # A nested decoy appears first, so regex extraction does not identify
        # the actual top-level fields. Some real keys and values use legal JSON
        # escapes which a JSON parser must decode.
        decoy = json.dumps({"ts": "1999-01-01T00:00:00Z", "type": "decoy"})
        ts_key = '"t\\u0073"' if i % 2 == 0 else '"ts"'
        type_key = '"ty\\u0070e"' if i % 3 == 0 else '"type"'

        if i % 19 == 0:
            # Deliberately incomplete Unicode escape, matching the legacy bug.
            msg = '"' + padding + '\\uD8"'
        elif i % 23 == 0:
            # Syntactically complete but isolated surrogate half.
            msg = '"' + padding + '\\uD800tail"'
        else:
            msg = json.dumps(padding + " valid café", ensure_ascii=True)

        line = (
            '{"decoy":' + decoy + ',"msg":' + msg + ',' +
            ts_key + ':' + json.dumps(ts) + ',' +
            type_key + ':' + json.dumps(event_type, ensure_ascii=True) + '}'
        )
        f.write(line + "\n")

rows = [[hour, event_type, str(counts[(hour, event_type)])]
        for hour, event_type in sorted(counts)]
with open(expected_path, "w", encoding="utf-8") as f:
    json.dump({"header": ["hour", "type", "count"],
               "rows": rows, "total": line_count}, f, ensure_ascii=False)
PY
python3 /tmp/make_adversarial_logs.py || status=1

# The fixture is larger than this address-space limit. A line-by-line solution
# has ample memory, while loading the complete input into memory does not.
if ! (ulimit -v 150000; timeout 90s python3 -I -S /home/user/process_logs.py); then
    status=1
fi

cat <<'PY' > /tmp/check_adversarial.py
import csv
import json
import os

summary = "/home/user/summary.csv"
assert os.path.isfile(summary), f"Output file {summary} does not exist."
with open("/tmp/adversarial_expected.json", "r", encoding="utf-8") as f:
    expected = json.load(f)
with open(summary, "r", encoding="utf-8", newline="") as f:
    rows = list(csv.reader(f))
assert rows, f"{summary} is empty."
assert rows[0] == expected["header"], f"Incorrect header: {rows[0]}"
assert rows[1:] == expected["rows"], "Adversarial aggregation is incorrect or unsorted."
assert sum(int(row[2]) for row in rows[1:]) == expected["total"], \
    "Not every JSON object, including malformed-Unicode objects, was counted."
PY
python3 /tmp/check_adversarial.py || status=1

# Restore the shipped input and require the submitted artifact to produce the
# requested final output from it.
if ! cp "$ORIGINAL_LOGS" /home/user/data/logs.jsonl; then
    status=1
fi
if ! timeout 60s python3 -I -S /home/user/process_logs.py; then
    status=1
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
from collections import defaultdict
import pytest

SUMMARY_CSV = "/home/user/summary.csv"
LOGS_FILE = "/home/user/data/logs.jsonl"

def get_expected_summary():
    counts = defaultdict(int)
    with open(LOGS_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            ts_match = re.search(r'"ts":\s*"([^"]+)"', line)
            type_match = re.search(r'"type":\s*"([^"]+)"', line)
            if ts_match and type_match:
                ts = ts_match.group(1)
                etype = type_match.group(1)
                hour = ts[:14] + "00:00Z"
                counts[(hour, etype)] += 1
            else:
                pytest.fail(f"Could not extract ts and type from line: {line}")

    sorted_keys = sorted(counts.keys())
    expected = []
    for k in sorted_keys:
        expected.append([k[0], k[1], str(counts[k])])
    return expected

def test_summary_csv_exists():
    assert os.path.exists(SUMMARY_CSV), f"Output file {SUMMARY_CSV} does not exist."
    assert os.path.isfile(SUMMARY_CSV), f"{SUMMARY_CSV} is not a file."

def test_summary_csv_content():
    assert os.path.exists(SUMMARY_CSV), f"Output file {SUMMARY_CSV} does not exist."

    with open(SUMMARY_CSV, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"{SUMMARY_CSV} is empty.")

        assert header == ['hour', 'type', 'count'], f"Header is incorrect. Expected ['hour', 'type', 'count'], got {header}"
        student_rows = list(reader)

    expected_rows = get_expected_summary()
    assert len(student_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but found {len(student_rows)}. Did you skip malformed lines?"
    for i, (student_row, expected_row) in enumerate(zip(student_rows, expected_rows)):
        assert student_row == expected_row, f"Row {i+2} mismatch. Expected {expected_row}, got {student_row}"

def test_total_count():
    assert os.path.exists(SUMMARY_CSV), f"Output file {SUMMARY_CSV} does not exist."
    total_count = 0
    with open(SUMMARY_CSV, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_count += int(row['count'])
    assert total_count == 10000, f"Expected total count of 10000 events, but got {total_count}. Malformed lines must be repaired and counted, not skipped."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
