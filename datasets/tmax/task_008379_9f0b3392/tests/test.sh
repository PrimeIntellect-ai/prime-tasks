#!/bin/bash
mkdir -p /logs/verifier

run_checks() {
    test -f /home/user/loc_updater.go || return 1
    test -s /home/user/loc_updater.go || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

def test_es_json_updated():
    es_path = "/home/user/locales/es.json"
    assert os.path.isfile(es_path), f"File {es_path} does not exist."
    with open(es_path, 'r') as f:
        data = json.load(f)

    expected = {
        "bye": "goodbye",
        "hello": "hola",
        "help": "help me",
        "thanks": "thank you",
        "welcome": "bienvenido"
    }
    assert data == expected, f"Content of {es_path} does not match expected final state."

def test_fr_json_updated():
    fr_path = "/home/user/locales/fr.json"
    assert os.path.isfile(fr_path), f"File {fr_path} does not exist."
    with open(fr_path, 'r') as f:
        data = json.load(f)

    expected = {
        "bye": "goodbye",
        "hello": "bonjour",
        "help": "help me"
    }
    assert data == expected, f"Content of {fr_path} does not match expected final state."

def test_hourly_summary_csv():
    csv_path = "/home/user/hourly_summary.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    expected_rows = [
        ['locale', 'hour_bucket', 'count'],
        ['es', '2023-10-05 09:00', '2'],
        ['es', '2023-10-05 10:00', '2'],
        ['fr', '2023-10-05 09:00', '1'],
        ['fr', '2023-10-05 10:00', '1']
    ]

    assert rows == expected_rows, f"Content of {csv_path} does not match expected final state."

def test_pipeline_log():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert "Updated locale: es" in lines, "pipeline.log is missing 'Updated locale: es'"
    assert "Updated locale: fr" in lines, "pipeline.log is missing 'Updated locale: fr'"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    python3 << 'PREP_EOF' || return 1
import json
import os
import secrets
import shutil

base = "/home/user"
token = secrets.token_hex(8)
locale_existing = "aa_" + token
locale_new = "zz_" + token
existing_key = "preserve_" + token
new_key = "new_" + token
duplicate_key = "duplicate_" + token
other_key = "other_" + token

initial = {
    locale_existing: {
        existing_key: "original " + token,
        "untouched_" + token: "keep " + token,
    },
    locale_new: {},
}

locales_dir = os.path.join(base, "locales")
shutil.rmtree(locales_dir, ignore_errors=True)
os.makedirs(locales_dir)
with open(os.path.join(locales_dir, locale_existing + ".json"), "w") as f:
    json.dump(initial[locale_existing], f, indent=2)
    f.write("\n")

lines = [
    f"2024-02-03 11:05:01 | {locale_existing} | {existing_key} | replacement {token}",
    f"2024-02-03 11:20:02 | {locale_existing} | {new_key} | fresh value {token}",
    f"2024-02-03 11:59:59 | {locale_existing} | {new_key} | later value {token}",
    f"2024-02-03 12:00:00 | {locale_existing} | {duplicate_key} | duplicate value {token}",
    f"2024-02-02 23:45:00 | {locale_new} | {other_key} | other value {token}",
    f"2024-02-02 23:50:00 | {locale_new} | {other_key} | ignored duplicate {token}",
]
with open(os.path.join(base, "missing_strings.log"), "w") as f:
    f.write("\n".join(lines) + "\n")

for path in (os.path.join(base, "hourly_summary.csv"), os.path.join(base, "pipeline.log")):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

with open("/tmp/loc_dynamic_fixture.json", "w") as f:
    json.dump({"initial": initial, "locales": [locale_existing, locale_new]}, f)
PREP_EOF

    cd /home/user || return 1
    timeout 60s go run /home/user/loc_updater.go || return 1

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_state.py
import csv
import json
import os
from collections import Counter
from datetime import datetime

BASE = "/home/user"

with open("/tmp/loc_dynamic_fixture.json") as f:
    fixture = json.load(f)

with open(os.path.join(BASE, "missing_strings.log")) as f:
    events = []
    for raw in f:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        timestamp, locale, key, default_text = raw.split(" | ", 3)
        events.append((timestamp, locale, key, default_text))


def expected_translations():
    expected = {locale: dict(values) for locale, values in fixture["initial"].items()}
    for _, locale, key, default_text in events:
        expected.setdefault(locale, {})
        expected[locale].setdefault(key, default_text)
    return expected


def test_dynamic_json_updates_and_creation():
    expected = expected_translations()
    for locale, wanted in expected.items():
        path = os.path.join(BASE, "locales", locale + ".json")
        assert os.path.isfile(path), f"missing locale file {path}"
        with open(path) as f:
            actual = json.load(f)
        assert actual == wanted

        with open(path) as f:
            rendered = f.read().splitlines()
        property_lines = [line for line in rendered if line.lstrip().startswith('"')]
        assert property_lines
        assert all(line.startswith('  "') and not line.startswith('\t') for line in property_lines)


def test_dynamic_summary_counts_duplicates_and_is_sorted():
    counts = Counter()
    for timestamp, locale, _, _ in events:
        dt = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
        bucket = dt.strftime("%Y-%m-%d %H:00")
        counts[(locale, bucket)] += 1

    expected = [["locale", "hour_bucket", "count"]]
    expected.extend([[locale, bucket, str(count)] for (locale, bucket), count in sorted(counts.items())])

    path = os.path.join(BASE, "hourly_summary.csv")
    assert os.path.isfile(path)
    with open(path, newline="") as f:
        actual = list(csv.reader(f))
    assert actual == expected


def test_dynamic_pipeline_logging():
    path = os.path.join(BASE, "pipeline.log")
    assert os.path.isfile(path)
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    for locale in fixture["locales"]:
        assert f"Updated locale: {locale}" in lines
DYNAMIC_EOF

    python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
