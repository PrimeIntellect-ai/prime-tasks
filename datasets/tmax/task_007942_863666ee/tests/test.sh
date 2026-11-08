#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import re
import stat
import subprocess
import uuid

import pytest

SCRIPT = "/home/user/process_l10n.sh"
INPUT = "/home/user/l10n_input.csv"


def run_script():
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}, stderr: {result.stderr!r}"
    )


def test_script_exists_is_executable_and_runs():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing or is not a regular file."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    run_script()


def test_valid_translations_jsonl():
    """Test that valid_translations.jsonl contains the correct JSON objects."""
    filepath = "/home/user/valid_translations.jsonl"
    assert os.path.exists(filepath), f"File {filepath} is missing."

    expected = [
        {"id": "str_001", "locale": "en-US", "word_count": 2},
        {"id": "str_002", "locale": "fr-FR", "word_count": 3},
        {"id": "str_006", "locale": "it-IT", "word_count": 4}
    ]

    actual = []
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual.append(json.loads(line))
                except json.JSONDecodeError as e:
                    assert False, f"Invalid JSON in {filepath}: {line} ({e})"

    expected_sorted = sorted(expected, key=lambda x: x.get("id", ""))
    actual_sorted = sorted(actual, key=lambda x: x.get("id", ""))

    assert actual_sorted == expected_sorted, f"Content of {filepath} does not match expected output. Expected: {expected_sorted}, Actual: {actual_sorted}"


def test_anomalies_csv():
    """Test that anomalies.csv contains the correct rows and preserves formatting."""
    filepath = "/home/user/anomalies.csv"
    assert os.path.exists(filepath), f"File {filepath} is missing."

    expected_rows = [
        ['string_id', 'locale', 'translation', 'status'],
        ['str_004', 'pt-BR', '', 'approved'],
        ['str_005', 'de-DE', 'Ein sehr langes Wort das eigentlich ein Satz ist und mehr als zwanzig Worte enthält um die Anomalieerkennung zu triggern eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn zwanzig einundzwanzig', 'approved']
    ]

    with open(filepath, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"{filepath} is empty."
    assert actual_rows[0] == expected_rows[0], f"CSV header in {filepath} is missing or incorrect. Expected: {expected_rows[0]}, Actual: {actual_rows[0]}"

    expected_data = sorted(expected_rows[1:], key=lambda x: x[0])
    actual_data = sorted(actual_rows[1:], key=lambda x: x[0])

    assert actual_data == expected_data, f"Data rows in {filepath} do not match expected anomalies. Expected: {expected_data}, Actual: {actual_data}"


def normalize_locale(locale):
    language, separator, country = locale.partition('-')
    return language.lower() + (separator + country.upper() if separator else '')


def word_count(text):
    return len(re.findall(r'[^\s]+', text))


def test_script_processes_unseen_csv_fixture():
    token = uuid.uuid4().hex
    long_translation = " ".join(f"word{i}_{token}" for i in range(1, 22))
    rows = [
        [f"valid_a_{token}", "EN-us", f"Hello\t{token}\nworld", "approved"],
        [f"valid_b_{token}", "jA-jp", 'Alpha, "beta"\ngamma', "pending"],
        [f"empty_{token}", "PT-br", "", "approved"],
        [f"space_{token}", "NL-nl", " \t\n  ", "pending"],
        [f"long_{token}", "DE-de", long_translation, "approved"],
        [f"rejected_{token}", "ES-es", "must disappear", "rejected"],
        [f"wrongcase_{token}", "FR-fr", "must disappear too", "Approved"],
        [f"blankstatus_{token}", "IT-it", "also absent", ""],
        [f"spacedstatus_{token}", "KO-kr", "also absent", "approved "],
    ]

    expected_valid = []
    expected_anomalies = []
    for string_id, locale, translation, status in rows:
        if status not in ("approved", "pending"):
            continue
        normalized = normalize_locale(locale)
        count = word_count(translation)
        if count == 0 or count > 20:
            expected_anomalies.append([string_id, normalized, translation, status])
        else:
            expected_valid.append({
                "id": string_id,
                "locale": normalized,
                "word_count": count,
            })

    with open(INPUT, "rb") as f:
        original_input = f.read()

    try:
        with open(INPUT, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["string_id", "locale", "translation", "status"])
            writer.writerows(rows)

        run_script()

        json_path = "/home/user/valid_translations.jsonl"
        assert os.path.isfile(json_path), f"File {json_path} is missing."
        actual_valid = []
        with open(json_path, "r", encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                obj = json.loads(line)
                assert set(obj.keys()) == {"id", "locale", "word_count"}, (
                    f"JSON object has incorrect keys: {obj}"
                )
                assert isinstance(obj["word_count"], int) and not isinstance(obj["word_count"], bool)
                actual_valid.append(obj)

        assert sorted(actual_valid, key=lambda x: x["id"]) == sorted(expected_valid, key=lambda x: x["id"])

        anomalies_path = "/home/user/anomalies.csv"
        assert os.path.isfile(anomalies_path), f"File {anomalies_path} is missing."
        with open(anomalies_path, "r", encoding="utf-8", newline="") as f:
            actual_anomalies = list(csv.reader(f))

        assert actual_anomalies, f"{anomalies_path} is empty."
        assert actual_anomalies[0] == ["string_id", "locale", "translation", "status"]
        assert sorted(actual_anomalies[1:], key=lambda x: x[0]) == sorted(expected_anomalies, key=lambda x: x[0])
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
