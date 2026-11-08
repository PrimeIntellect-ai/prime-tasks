#!/bin/bash
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:$PATH"

PROJECT_DIR="/home/user/l10n_processor"
INPUT_JSON="$PROJECT_DIR/input.json"
MAIN_RS="$PROJECT_DIR/src/main.rs"
BACKUP_INPUT=$(mktemp)
status=0

if ! cp "$INPUT_JSON" "$BACKUP_INPUT"; then
    status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import pytest

PROJECT_DIR = "/home/user/l10n_processor"
INPUT_JSON = os.path.join(PROJECT_DIR, "input.json")
OUTPUT_CSV = os.path.join(PROJECT_DIR, "output.csv")
MAIN_RS = os.path.join(PROJECT_DIR, "src", "main.rs")


def expected_rows(data):
    filtered = []
    for row in data:
        text = row.get("text", "")
        if text == "" or "\ufffd" in text:
            continue
        filtered.append(row)

    dedup = {}
    for row in filtered:
        key = (row["key"], row["lang"])
        if key not in dedup or row["timestamp"] > dedup[key]["timestamp"]:
            dedup[key] = row

    records = sorted(dedup.values(), key=lambda row: (row["key"], row["lang"]))
    return [["key", "lang", "text"]] + [
        [row["key"], row["lang"], row["text"]] for row in records
    ]


def read_output():
    with open(OUTPUT_CSV, "r", encoding="utf-8", newline="") as handle:
        return list(csv.reader(handle))


def run_program():
    if os.path.exists(OUTPUT_CSV):
        os.remove(OUTPUT_CSV)
    subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT_DIR,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


assert os.path.isfile(INPUT_JSON), f"Input file missing: {INPUT_JSON}"
with open(INPUT_JSON, "r", encoding="utf-8") as handle:
    ORIGINAL_DATA = json.load(handle)
ORIGINAL_EXPECTED = expected_rows(ORIGINAL_DATA)
run_program()


def test_main_rs_exists_and_is_nonempty():
    assert os.path.isfile(MAIN_RS), f"Rust source file missing: {MAIN_RS}"
    assert os.path.getsize(MAIN_RS) > 0, "Rust source file is empty"


def test_output_csv_exists():
    assert os.path.isfile(OUTPUT_CSV), f"Output file missing: {OUTPUT_CSV}"


def test_output_csv_content():
    actual_rows = read_output()
    assert actual_rows == ORIGINAL_EXPECTED, (
        "The generated CSV does not match the expected output. "
        "Ensure you correctly filtered empty/corrupted records, deduplicated by highest timestamp, "
        "and sorted by key then lang."
    )


def hidden_cases():
    token = secrets.token_hex(10)
    return [
        [
            {"key": f"z.{token}", "lang": "en", "text": "old", "timestamp": -10},
            {"key": f"z.{token}", "lang": "en", "text": "new", "timestamp": 900},
            {"key": f"a.{token}", "lang": "ja", "text": "有効", "timestamp": 4},
            {"key": f"a.{token}", "lang": "ja", "text": "broken\ufffdvalue", "timestamp": 999},
            {"key": f"a.{token}", "lang": "de", "text": "", "timestamp": 1000},
            {"key": f"a.{token}", "lang": "en", "text": f"random-{token}", "timestamp": 3},
            {"key": f"m.{token}", "lang": "fr", "text": "first", "timestamp": 1},
            {"key": f"m.{token}", "lang": "fr", "text": "second", "timestamp": 2},
        ],
        [
            {"key": f"quote.{token}", "lang": "es", "text": "comma, quote \" and\nnewline", "timestamp": 8},
            {"key": f"quote.{token}", "lang": "ar", "text": "مرحبا", "timestamp": 7},
            {"key": f"space.{token}", "lang": "en", "text": "   ", "timestamp": 6},
            {"key": f"unicode.{token}", "lang": "zh", "text": "你好", "timestamp": 5},
            {"key": f"unicode.{token}", "lang": "zh", "text": "损坏\ufffd", "timestamp": 4},
        ],
    ]


@pytest.mark.parametrize("data", hidden_cases())
def test_program_on_hidden_input(data):
    with open(INPUT_JSON, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False)
    run_program()
    assert os.path.isfile(OUTPUT_CSV), "Program did not generate output.csv"
    assert read_output() == expected_rows(data)
TEST_EOF

if [ ! -f "$MAIN_RS" ] || [ ! -s "$MAIN_RS" ]; then
    status=1
elif ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    status=1
fi

if ! cp "$BACKUP_INPUT" "$INPUT_JSON"; then
    status=1
fi
rm -f "$BACKUP_INPUT"

# Leave output.csv generated from the agent's original input, as requested.
if ! (cd "$PROJECT_DIR" && cargo run --quiet >/tmp/final_cargo_stdout.log 2>/tmp/final_cargo_stderr.log); then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
