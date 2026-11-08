#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import subprocess
import pytest

BASE = "/home/user/l10n"
PARSER = f"{BASE}/parse_logs"
PROCESS = f"{BASE}/process.sh"
INPUT = f"{BASE}/input.jsonl"
COUNTS = f"{BASE}/hourly_counts.csv"
SAMPLE = f"{BASE}/stratified_sample.tsv"


def run_parser(records):
    input_data = "".join(json.dumps(r, ensure_ascii=True) + "\n" for r in records)
    try:
        proc = subprocess.run(
            [PARSER], input=input_data.encode("utf-8"), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=3, check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"C parser crashed or returned non-zero exit code: {e}; stderr={e.stderr!r}")
    except subprocess.TimeoutExpired:
        pytest.fail("C parser timed out.")

    try:
        text = proc.stdout.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"Parser did not emit valid UTF-8: {e}")

    lines = text.splitlines()
    assert len(lines) == len(records), "Parser must emit exactly one TSV row per valid JSON-Lines record."
    parsed = []
    for line in lines:
        parts = line.split("\t")
        assert len(parts) == 3, f"Parser output is not timestamp\\tlocale\\tmessage: {line!r}"
        parsed.append(parts)

    for record, parts in zip(records, parsed):
        assert parts[0] == str(record["timestamp"]), "Parser emitted an incorrect timestamp."
        assert parts[1] == record["locale"], "Parser emitted an incorrect locale."
        decoded = record["message"]
        placeholder = "".join("?" if ord(ch) > 127 else ch for ch in decoded)
        assert parts[2] in {decoded, placeholder}, (
            f"Parser mishandled the message: expected decoded Unicode or '?' replacement, got {parts[2]!r}"
        )
    return parsed


def test_c_parser_compiled_and_executable():
    executable = PARSER
    assert os.path.isfile(executable), f"Compiled binary {executable} does not exist."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."


def test_c_parser_no_crash():
    executable = PARSER
    input_data = '{"timestamp": 1700014400, "locale": "ja-JP", "message": "Konnichiwa \\u3042"}\n'
    try:
        proc = subprocess.run(
            [executable], input=input_data.encode("utf-8"), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=2, check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"C parser crashed or returned non-zero exit code: {e}")
    except subprocess.TimeoutExpired:
        pytest.fail("C parser timed out.")

    stdout = proc.stdout.decode("utf-8")
    assert "1700014400" in stdout, "Parser output missing timestamp."
    assert "ja-JP" in stdout, "Parser output missing locale."
    assert stdout.splitlines() in [
        ["1700014400\tja-JP\tKonnichiwa ?"],
        ["1700014400\tja-JP\tKonnichiwa あ"],
    ], "Parser did not correctly preserve or replace the Unicode escape in the message."


def test_c_parser_general_parsing_and_messages():
    token = secrets.token_hex(5)
    records = [
        {"timestamp": 1810000001, "locale": f"aa-{token}", "message": f"plain message {token}"},
        {"timestamp": 1810003723, "locale": f"bb-{token}", "message": f"before Ω after {token}"},
        {"timestamp": 1810007444, "locale": f"cc-{token}", "message": f"two あ and é {token}"},
        {"timestamp": 1810011165, "locale": f"dd-{token}", "message": f"final ordinary text {token}"},
    ]
    run_parser(records)


def test_process_script_exists_and_executable():
    assert os.path.isfile(PROCESS), f"{PROCESS} does not exist."
    assert os.access(PROCESS, os.X_OK), f"{PROCESS} is not executable."


def test_hourly_counts_csv():
    csv_file = COUNTS
    assert os.path.isfile(csv_file), f"{csv_file} does not exist."

    with open(csv_file, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{csv_file} is empty."

    parsed_counts = {}
    for row in rows:
        if len(row) != 2:
            continue
        try:
            ts = int(row[0])
            count = int(row[1])
            parsed_counts[ts] = count
        except ValueError:
            continue

    assert len(parsed_counts) >= 5, "Not enough rows in hourly_counts.csv. Did you fill the gaps?"

    keys = sorted(list(parsed_counts.keys()))
    if keys[0] < 1000000:
        expected_keys = list(range(472222, 472227))
    else:
        expected_keys = [h * 3600 for h in range(472222, 472227)]

    for k in expected_keys:
        assert k in parsed_counts, f"Missing expected time bin {k} in hourly_counts.csv (gap filling failed)."

    assert parsed_counts[expected_keys[0]] == 1, "Incorrect count for first hour."
    assert parsed_counts[expected_keys[1]] == 1, "Incorrect count for second hour."
    assert parsed_counts[expected_keys[2]] == 0, "Incorrect count for third hour (gap)."
    assert parsed_counts[expected_keys[3]] == 0, "Incorrect count for fourth hour (gap)."
    assert parsed_counts[expected_keys[4]] == 2, "Incorrect count for fifth hour."


def test_stratified_sample():
    tsv_file = SAMPLE
    assert os.path.isfile(tsv_file), f"{tsv_file} does not exist."

    with open(tsv_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    locales_found = set()
    for line in lines:
        parts = line.split("\t")
        if len(parts) >= 2:
            locales_found.add(parts[1])

    assert "en-US" in locales_found, "Missing en-US in stratified sample."
    assert "es-ES" in locales_found, "Missing es-ES in stratified sample."
    assert "ja-JP" in locales_found, "Missing ja-JP in stratified sample."

    en_us_lines = [line for line in lines if "\ten-US\t" in line or line.endswith("\ten-US") or len(line.split("\t")) >= 2 and line.split("\t")[1] == "en-US"]
    assert len(en_us_lines) == 1, "There should be exactly one entry per locale in stratified sample."
    assert en_us_lines[0].startswith("1700000000"), "The stratified sample did not pick the earliest entry for en-US."

    rows = [line.split("\t") for line in lines]
    assert all(len(row) == 3 for row in rows), "Every sample row must have exactly three TSV fields."
    assert len(rows) == 3, "There must be exactly one sample row for each locale and no extra rows."
    by_locale = {row[1]: row for row in rows}
    assert len(by_locale) == 3, "There must be exactly one sample row per locale."
    assert by_locale["es-ES"] == ["1700003600", "es-ES", "Hola"], "The earliest es-ES entry is incorrect."
    assert by_locale["ja-JP"][0:2] == ["1700014400", "ja-JP"], "The earliest ja-JP entry is incorrect."
    assert by_locale["ja-JP"][2] in {"Konnichiwa ?", "Konnichiwa あ"}, "The ja-JP message is incorrect."


def test_randomized_end_to_end_pipeline():
    token = secrets.token_hex(6)
    base_hour = 520000 + secrets.randbelow(50000)
    locales = [f"loc-{token}-{i}" for i in range(4)]

    def rec(offset, seconds, locale_index, message):
        return {
            "timestamp": (base_hour + offset) * 3600 + seconds,
            "locale": locales[locale_index],
            "message": f"{message}-{token}",
        }

    # Later entries deliberately precede earlier ones in file order. Hours 3 and 4 are gaps.
    records = [
        rec(5, 100, 0, "later-A Ω"),
        rec(5, 200, 1, "later-B"),
        rec(2, 500, 3, "later-D あ"),
        rec(1, 250, 1, "earliest-B é"),
        rec(5, 300, 2, "later-C"),
        rec(0, 700, 0, "earliest-A"),
        rec(2, 150, 2, "earliest-C Ω"),
        rec(0, 100, 3, "earliest-D"),
    ]

    paths = [INPUT, COUNTS, SAMPLE]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    try:
        with open(INPUT, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=True) + "\n")

        parser_rows = run_parser(records)
        try:
            subprocess.run([PROCESS], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=8, check=True)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"process.sh failed on generated input: {e}; stderr={e.stderr!r}")
        except subprocess.TimeoutExpired:
            pytest.fail("process.sh timed out on generated input.")

        assert os.path.isfile(COUNTS), "process.sh did not create hourly_counts.csv."
        with open(COUNTS, newline="") as f:
            raw_rows = [row for row in csv.reader(f) if row]
        counts = {}
        header_seen = False
        for index, row in enumerate(raw_rows):
            assert len(row) == 2, f"Malformed hourly count row: {row!r}"
            try:
                key, value = int(row[0]), int(row[1])
            except ValueError:
                assert index == 0 and not header_seen, "Only one optional CSV header is allowed."
                header_seen = True
                continue
            assert key not in counts, f"Duplicate hourly bin {key}."
            counts[key] = value

        expected_by_hour = {hour: 0 for hour in range(base_hour, base_hour + 6)}
        for record in records:
            expected_by_hour[record["timestamp"] // 3600] += 1
        index_expected = expected_by_hour
        timestamp_expected = {hour * 3600: count for hour, count in expected_by_hour.items()}
        assert counts in (index_expected, timestamp_expected), (
            f"Hourly output must contain exactly every bin from min through max with derived counts; got {counts!r}"
        )

        assert os.path.isfile(SAMPLE), "process.sh did not create stratified_sample.tsv."
        with open(SAMPLE, encoding="utf-8") as f:
            sample_lines = [line.rstrip("\n") for line in f if line.strip()]
        sample_rows = [line.split("\t") for line in sample_lines]
        assert all(len(row) == 3 for row in sample_rows), "Sample must contain exactly three TSV fields per row."
        assert len(sample_rows) == len(locales), "Sample must contain exactly one row per unique locale."
        assert len({row[1] for row in sample_rows}) == len(locales), "A locale appears more than once in the sample."
        assert {row[1] for row in sample_rows} == set(locales), "Sample locale set does not match the input."

        expected_sample = {}
        for row in parser_rows:
            locale = row[1]
            if locale not in expected_sample or int(row[0]) < int(expected_sample[locale][0]):
                expected_sample[locale] = row
        actual_sample = {row[1]: row for row in sample_rows}
        assert actual_sample == expected_sample, "Sample did not select the chronologically earliest parsed row for every locale."
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)


def test_cron_job():
    try:
        proc = subprocess.run(
            ["crontab", "-l", "-u", "user"], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, check=True
        )
        crontab_out = proc.stdout.decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Failed to list crontab for 'user'.")

    lines = [line.strip() for line in crontab_out.splitlines() if line.strip() and not line.startswith("#")]

    cron_found = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 6:
            minute = parts[0]
            cmd = " ".join(parts[5:])
            if minute == "0" and "/home/user/l10n/process.sh" in cmd:
                cron_found = True
                break

    assert cron_found, "Cron job for user not found or incorrectly scheduled. Expected minute '0' and command '/home/user/l10n/process.sh'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
