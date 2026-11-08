#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/data/raw_translations.csv /tmp/original_raw_translations.csv
trap 'cp /tmp/original_raw_translations.csv /home/user/data/raw_translations.csv' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import subprocess
from collections import defaultdict

RAW_FILE = "/home/user/data/raw_translations.csv"
OUTPUT_FILE = "/home/user/data/rolling_stats.csv"
CPP_FILE = "/home/user/pipeline/transform.cpp"
SCRIPT_PATH = "/home/user/pipeline/run_dag.sh"
DIRECT_BINARY = "/tmp/transform_under_test"
INPUT_HEADER = ["Timestamp", "JobId", "StringId", "TranslatorId", "WordCount", "DurationSeconds"]
OUTPUT_HEADER = ["TranslatorId", "Timestamp", "JobId", "StringId", "WPM", "RollingAvgWPM"]


def compute_expected_output(raw_file):
    with open(raw_file, "r") as f:
        reader = csv.DictReader(f)
        data = list(reader)

    # 1. Deduplication
    dedup = {}
    for row in data:
        key = (row['JobId'], row['StringId'])
        ts = int(row['Timestamp'])
        if key not in dedup or ts > int(dedup[key]['Timestamp']):
            dedup[key] = row

    # 2. Calculate WPM and group by TranslatorId
    translators = defaultdict(list)
    for row in dedup.values():
        wpm = int(row['WordCount']) / (int(row['DurationSeconds']) / 60.0)
        translators[row['TranslatorId']].append({
            'Timestamp': int(row['Timestamp']),
            'JobId': row['JobId'],
            'StringId': row['StringId'],
            'WPM': wpm
        })

    # 3. Sort and calculate rolling avg
    output = []
    for tid in sorted(translators.keys()):
        records = sorted(translators[tid], key=lambda x: x['Timestamp'])
        for i, rec in enumerate(records):
            start = max(0, i - 2)
            window = records[start:i+1]
            avg_wpm = sum(x['WPM'] for x in window) / len(window)
            output.append({
                'TranslatorId': tid,
                'Timestamp': str(rec['Timestamp']),
                'JobId': rec['JobId'],
                'StringId': rec['StringId'],
                'WPM': f"{rec['WPM']:.2f}",
                'RollingAvgWPM': f"{avg_wpm:.2f}"
            })

    return output


def validate_output(expected_records):
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created by the pipeline."

    with open(OUTPUT_FILE, "r") as f:
        reader = csv.DictReader(f)
        actual_records = list(reader)
        actual_header = reader.fieldnames

    assert actual_header == OUTPUT_HEADER, f"Output CSV header is incorrect. Expected {OUTPUT_HEADER}, got {actual_header}"
    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} rows in output, but got {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual['TranslatorId'] == expected['TranslatorId'], f"Row {i+1}: Expected TranslatorId {expected['TranslatorId']}, got {actual['TranslatorId']}"
        assert actual['Timestamp'] == expected['Timestamp'], f"Row {i+1}: Expected Timestamp {expected['Timestamp']}, got {actual['Timestamp']}"
        assert actual['JobId'] == expected['JobId'], f"Row {i+1}: Expected JobId {expected['JobId']}, got {actual['JobId']}"
        assert actual['StringId'] == expected['StringId'], f"Row {i+1}: Expected StringId {expected['StringId']}, got {actual['StringId']}"
        assert actual['WPM'] == expected['WPM'], f"Row {i+1}: Expected WPM {expected['WPM']}, got {actual['WPM']}"
        assert actual['RollingAvgWPM'] == expected['RollingAvgWPM'], f"Row {i+1}: Expected RollingAvgWPM {expected['RollingAvgWPM']}, got {actual['RollingAvgWPM']}"


def write_fixture(rows):
    with open(RAW_FILE, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(INPUT_HEADER)
        writer.writerows(rows)


def generate_fixture(seed, translator_count, records_per_translator):
    rng = random.Random(seed)
    translator_names = ["translator-10", "A_2", "Zed", "middle.name"][:translator_count]
    rows = []
    base_timestamp = 1700000000 + seed * 1000

    for t_index, translator in enumerate(translator_names):
        for record_index in range(records_per_translator):
            timestamp = base_timestamp + t_index * 10000 + record_index * 37
            job_id = f"Job_{seed}_{t_index}_{record_index}"
            string_id = f"String-{(record_index * 7 + t_index) % 19}"
            duration = rng.choice([60, 120, 240])
            word_count = rng.randint(31, 420)
            rows.append([timestamp, job_id, string_id, translator, word_count, duration])

            # Add an older retry with deliberately different metrics and, at times,
            # a different translator. Shuffling below ensures input order cannot be
            # used to identify the record that must be retained.
            if record_index % 2 == 1:
                older_translator = translator_names[(t_index + 1) % len(translator_names)]
                rows.append([
                    timestamp - rng.randint(1, 29),
                    job_id,
                    string_id,
                    older_translator,
                    word_count + rng.randint(5, 70),
                    rng.choice([60, 120, 240]),
                ])

    rng.shuffle(rows)
    return rows


def run_command(command, label):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"{label} failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def assert_compiled_transform_created():
    transform_path = "/home/user/pipeline/transform"
    assert os.path.isfile(transform_path), "run_dag.sh did not create the transform executable."
    assert os.access(transform_path, os.X_OK), "The generated transform file is not executable."
    with open(transform_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated transform is not a compiled ELF executable."


def test_pipeline_execution_and_output():
    assert os.path.isfile(CPP_FILE), f"C++ source file {CPP_FILE} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Shell script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK) or os.path.isfile(SCRIPT_PATH), f"Shell script {SCRIPT_PATH} should be executable or able to be run by bash."
    assert os.path.isfile(RAW_FILE), f"Raw data file {RAW_FILE} is missing."

    # Compile the submitted source independently so behavior cannot be delegated
    # to hardcoded output logic in run_dag.sh.
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", DIRECT_BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"transform.cpp failed to compile.\nStdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
    assert os.path.isfile(DIRECT_BINARY) and os.access(DIRECT_BINARY, os.X_OK), "Compiled transform executable was not created."

    # Preserve the original fixed-fixture assertions.
    original_expected = compute_expected_output(RAW_FILE)
    for path in (OUTPUT_FILE, "/home/user/pipeline/transform"):
        if os.path.exists(path):
            os.remove(path)
    run_command(["bash", SCRIPT_PATH], "run_dag.sh")
    assert_compiled_transform_created()
    validate_output(original_expected)

    # Exercise both the independently compiled C++ source and run_dag.sh on
    # several unseen inputs with differing sizes, values, ordering, and retries.
    cases = [
        generate_fixture(17, 2, 4),
        generate_fixture(43, 3, 5),
        generate_fixture(91, 4, 6),
    ]
    for case_number, rows in enumerate(cases, 1):
        write_fixture(rows)
        expected = compute_expected_output(RAW_FILE)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        run_command([DIRECT_BINARY], f"independently compiled transform on generated case {case_number}")
        validate_output(expected)

        # Rewrite the fixture in case a submitted program attempted to mutate it,
        # then verify that the DAG script itself compiles and runs correctly too.
        write_fixture(rows)
        expected = compute_expected_output(RAW_FILE)
        for path in (OUTPUT_FILE, "/home/user/pipeline/transform"):
            if os.path.exists(path):
                os.remove(path)
        run_command(["bash", SCRIPT_PATH], f"run_dag.sh on generated case {case_number}")
        assert_compiled_transform_created()
        validate_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
