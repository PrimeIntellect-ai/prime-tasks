#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import random
import subprocess
import tempfile
import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
SCRIPT_PATH = "/home/user/filter_transcripts.py"
LOG_PATH = "/home/user/experiment_log.jsonl"


def count_csv_rows(filepath):
    if not os.path.exists(filepath):
        return 0
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)
        if not rows:
            return 0
        return len(rows) - 1


def run_script(input_csv, output_csv):
    cmd = ["python", SCRIPT_PATH, "--input", input_csv, "--output", output_csv]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_clean_corpus_preserved():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No clean CSV files found to test."

    modified_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(CLEAN_DIR, filename)
            output_path = os.path.join(tmpdir, f"out_{filename}")

            input_rows = count_csv_rows(input_path)
            success, stderr = run_script(input_path, output_path)

            if not success:
                modified_files.append(f"{filename} (script crashed: {stderr})")
                continue

            output_rows = count_csv_rows(output_path)
            if output_rows != input_rows:
                modified_files.append(f"{filename} (expected {input_rows} rows, got {output_rows})")

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified: {', '.join(modified_files)}")


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No evil CSV files found to test."

    bypassed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(EVIL_DIR, filename)
            output_path = os.path.join(tmpdir, f"out_{filename}")

            success, stderr = run_script(input_path, output_path)

            if not success:
                bypassed_files.append(f"{filename} (script crashed: {stderr})")
                continue

            output_rows = count_csv_rows(output_path)
            if output_rows > 0:
                bypassed_files.append(f"{filename} ({output_rows} rows bypassed)")

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_experiment_log_updated():
    assert os.path.isfile(LOG_PATH), f"Experiment log missing at {LOG_PATH}"

    with open(LOG_PATH, 'r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) > 0, "Experiment log is empty."

    for i, line in enumerate(lines):
        try:
            entry = json.loads(line)
            assert "input_file" in entry, f"Missing 'input_file' in log entry {i+1}"
            assert "accepted" in entry, f"Missing 'accepted' in log entry {i+1}"
            assert "rejected" in entry, f"Missing 'rejected' in log entry {i+1}"
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in log entry {i+1}: {line}")


def write_csv(path, rows):
    fieldnames = ["record_id", "transcript", "source"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return fieldnames


def read_csv(path):
    assert os.path.isfile(path), f"Output CSV was not created: {path}"
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return reader.fieldnames, list(reader)


def read_log_bytes():
    if not os.path.exists(LOG_PATH):
        return b""
    with open(LOG_PATH, "rb") as f:
        return f.read()


def run_hidden_case(input_path, output_path, rows, expected_rows):
    fieldnames = write_csv(input_path, rows)
    old_log = read_log_bytes()

    result = subprocess.run(
        ["python", SCRIPT_PATH, "--input", input_path, "--output", output_path],
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, f"Script failed on hidden input: {result.stderr}"

    output_fields, actual_rows = read_csv(output_path)
    assert output_fields == fieldnames, "Output CSV did not preserve the input columns"
    assert actual_rows == expected_rows, "Output did not contain exactly the relevant input rows in input order"

    new_log = read_log_bytes()
    assert new_log.startswith(old_log), "Experiment log was overwritten instead of appended"
    appended = new_log[len(old_log):].decode("utf-8")
    appended_lines = [line for line in appended.splitlines() if line.strip()]
    assert len(appended_lines) == 1, "Each invocation must append exactly one JSON log object"
    try:
        entry = json.loads(appended_lines[0])
    except json.JSONDecodeError as exc:
        pytest.fail(f"Appended experiment log entry is invalid JSON: {exc}")

    expected_entry = {
        "input_file": input_path,
        "accepted": len(expected_rows),
        "rejected": len(rows) - len(expected_rows),
    }
    assert entry == expected_entry, f"Incorrect experiment log entry: expected {expected_entry}, got {entry}"
    assert type(entry["accepted"]) is int and type(entry["rejected"]) is int


def test_hidden_semantic_filtering_transcription_and_logs():
    clean_rows = [
        {
            "record_id": "medical-A",
            "transcript": "Patient presents with high blood pressure and an elevated heart rate.",
            "source": "clinic",
        },
        {
            "record_id": "medical-B",
            "transcript": "The medical report notes mild hypertension together with a rapid heart rate.",
            "source": "ward",
        },
    ]
    evil_rows = [
        {
            "record_id": "noise-A",
            "transcript": "A sourdough loaf should cool completely before it is sliced.",
            "source": "kitchen",
        },
        {
            "record_id": "noise-B",
            "transcript": "The spacecraft photographed distant rings while orbiting the planet.",
            "source": "astronomy",
        },
        {
            "record_id": "noise-C",
            "transcript": "The software release adds keyboard shortcuts and a new color theme.",
            "source": "technology",
        },
    ]

    with tempfile.TemporaryDirectory(prefix="validation_") as tmpdir:
        clean_input = os.path.join(tmpdir, "batch_alpha.csv")
        evil_input = os.path.join(tmpdir, "batch_beta.csv")
        mixed_input = os.path.join(tmpdir, "batch_gamma.csv")

        run_hidden_case(clean_input, os.path.join(tmpdir, "clean_out.csv"), clean_rows, clean_rows)
        run_hidden_case(evil_input, os.path.join(tmpdir, "evil_out.csv"), evil_rows, [])

        mixed_rows = clean_rows + evil_rows
        random.SystemRandom().shuffle(mixed_rows)
        expected_mixed = [row for row in mixed_rows if row["record_id"].startswith("medical-")]
        run_hidden_case(mixed_input, os.path.join(tmpdir, "mixed_out.csv"), mixed_rows, expected_mixed)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
