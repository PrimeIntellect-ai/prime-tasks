#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import subprocess
import tempfile
import uuid
from collections import defaultdict
import pytest

PIPELINE_BIN = "/home/user/pipeline"
PIPELINE_SOURCE = "/home/user/pipeline.c"
LEGACY_FILTER = "/app/legacy_filter"
EVIL_CORPUS_DIR = "/opt/eval/evil"
CLEAN_CORPUS_DIR = "/opt/eval/clean"


def legacy_rejects(message):
    result = subprocess.run(
        [LEGACY_FILTER, message],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=2,
    )
    assert result.returncode in (0, 1), f"legacy_filter returned {result.returncode}"
    return result.returncode == 1


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows(rows)


def prepare_corpora():
    os.makedirs(EVIL_CORPUS_DIR, exist_ok=True)
    os.makedirs(CLEAN_CORPUS_DIR, exist_ok=True)
    for directory in (EVIL_CORPUS_DIR, CLEAN_CORPUS_DIR):
        for name in os.listdir(directory):
            if name.endswith(".csv"):
                os.remove(os.path.join(directory, name))

    token = uuid.uuid4().hex
    candidates = [
        f"ordinary support message {token}",
        f"UNION  SELECT is written with two spaces {token}",
        f"x1234567812345678y {token}",
        f"_1234-5678-1234-5678_ {token}",
        f"only 123456781234567 digits {token}",
        f"standalone о symbol {token}",
        f"please UNION SELECT records {token}",
        f"prefix uNiOn SeLeCt suffix {token}",
        f"card 1234567812345678! {token}",
        f"card 1234-5678-1234-5678! {token}",
        f"card 1234 5678 1234 5678! {token}",
        f"card 1234-5678 1234-5678! {token}",
        f"asciiоascii {token}",
        f"оx {token}",
    ]
    evil = [message for message in candidates if legacy_rejects(message)]
    clean = [message for message in candidates if not legacy_rejects(message)]
    assert len(evil) >= 7, "Generated corpus did not contain enough legacy-rejected cases"
    assert len(clean) >= 5, "Generated corpus did not contain enough legacy-clean cases"

    evil_rows = [[str(1800000000 + i), f"evil_{i}", message] for i, message in enumerate(evil)]
    write_csv(os.path.join(EVIL_CORPUS_DIR, f"evil_{token}.csv"), evil_rows)

    clean_rows = []
    for i, message in enumerate(clean[:6]):
        clean_rows.append([str(1800000100 + (i // 2) * 3), f"clean_{i % 2}", message])
    clean_rows.sort(key=lambda row: (int(row[0]), row[1]))
    write_csv(os.path.join(CLEAN_CORPUS_DIR, f"clean_{token}.csv"), clean_rows)

    return clean, evil


CLEAN_MESSAGES, EVIL_MESSAGES = prepare_corpora()


def test_pipeline_binary_exists():
    assert os.path.exists(PIPELINE_BIN), f"Pipeline binary not found at {PIPELINE_BIN}"
    assert os.access(PIPELINE_BIN, os.X_OK), f"Pipeline binary at {PIPELINE_BIN} is not executable"


def test_required_artifacts_are_c_and_elf():
    assert os.path.isfile(PIPELINE_SOURCE), f"C source not found at {PIPELINE_SOURCE}"
    with open(PIPELINE_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Pipeline must be a compiled executable, not a script"
    with open(PIPELINE_BIN, "rb") as submitted, open(LEGACY_FILTER, "rb") as legacy:
        assert submitted.read() != legacy.read(), "Pipeline must not be a byte-identical copy of legacy_filter"


def run_pipeline(input_csv, pipeline_bin=PIPELINE_BIN):
    fd, output_csv = tempfile.mkstemp(suffix=".csv")
    os.close(fd)
    try:
        result = subprocess.run(
            [pipeline_bin, input_csv, output_csv],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"Pipeline failed on {input_csv} with exit code {result.returncode}\nStderr: {result.stderr}"

        with open(output_csv, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            rows = list(reader)
        return rows
    finally:
        if os.path.exists(output_csv):
            os.remove(output_csv)


def test_evil_corpus():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.skip(f"Evil corpus dir {EVIL_CORPUS_DIR} not found.")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".csv")]
    assert evil_files, "No evil corpus files found."

    failed_files = []
    for evil_file in evil_files:
        output_rows = run_pipeline(evil_file)
        if len(output_rows) > 0:
            failed_files.append(os.path.basename(evil_file))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def test_clean_corpus():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.skip(f"Clean corpus dir {CLEAN_CORPUS_DIR} not found.")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".csv")]
    assert clean_files, "No clean corpus files found."

    failed_files = []
    for clean_file in clean_files:
        with open(clean_file, "r", encoding="utf-8") as f:
            input_rows = list(csv.reader(f))

        users = defaultdict(list)
        for row in input_rows:
            if len(row) >= 3:
                users[row[1]].append(row)

        expected_per_user = {}
        for user, rows in users.items():
            rows.sort(key=lambda x: int(x[0]))
            expected = []
            for i in range(len(rows)):
                if i > 0:
                    prev_t = int(rows[i-1][0])
                    curr_t = int(rows[i][0])
                    for t in range(prev_t + 1, curr_t):
                        expected.append([str(t), user, "[GAP]"])
                expected.append(rows[i])
            expected_per_user[user] = expected

        output_rows = run_pipeline(clean_file)

        actual_per_user = defaultdict(list)
        for row in output_rows:
            if len(row) >= 3:
                actual_per_user[row[1]].append(row)

        match = True
        if set(expected_per_user.keys()) != set(actual_per_user.keys()):
            match = False
        else:
            for user in expected_per_user:
                actual_user_rows = sorted(actual_per_user[user], key=lambda x: int(x[0]))
                if actual_user_rows != expected_per_user[user]:
                    match = False
                    break

        if not match:
            failed_files.append(os.path.basename(clean_file))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified or incorrectly gap-filled: {', '.join(failed_files)}"


def expected_for_rows(input_rows):
    survivors = defaultdict(list)
    for row in input_rows:
        if not legacy_rejects(row[2]):
            survivors[row[1]].append(row)

    expected = {}
    for user, rows in survivors.items():
        rows = sorted(rows, key=lambda row: int(row[0]))
        expanded = []
        for i, row in enumerate(rows):
            if i:
                previous = int(rows[i - 1][0])
                current = int(row[0])
                for timestamp in range(previous + 1, current):
                    expanded.append([str(timestamp), user, "[GAP]"])
            expanded.append(row)
        expected[user] = expanded
    return expected


def assert_exact_output(actual_rows, expected):
    assert all(len(row) == 3 for row in actual_rows), "Every output row must have exactly three CSV columns"
    actual = defaultdict(list)
    for row in actual_rows:
        int(row[0])
        actual[row[1]].append(row)
    actual = {user: sorted(rows, key=lambda row: int(row[0])) for user, rows in actual.items()}
    assert actual == expected


def test_mixed_filtering_and_gap_filling_from_oracle(tmp_path):
    token = uuid.uuid4().hex[:10]
    base = 1900000000
    rows = []
    for i in range(3):
        user = f"mixed_{token}_{i}"
        rows.extend([
            [str(base), user, CLEAN_MESSAGES[i % len(CLEAN_MESSAGES)]],
            [str(base + 2), user, EVIL_MESSAGES[i % len(EVIL_MESSAGES)]],
            [str(base + 4), user, CLEAN_MESSAGES[(i + 1) % len(CLEAN_MESSAGES)]],
            [str(base + 6), user, CLEAN_MESSAGES[(i + 2) % len(CLEAN_MESSAGES)]],
        ])
    rows.sort(key=lambda row: (int(row[0]), row[1]))
    input_path = tmp_path / "mixed.csv"
    write_csv(input_path, rows)
    expected = expected_for_rows(rows)

    assert_exact_output(run_pipeline(str(input_path)), expected)

    rebuilt = tmp_path / "pipeline-rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-O2", PIPELINE_SOURCE, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"pipeline.c does not compile:\n{compile_result.stderr}"
    assert_exact_output(run_pipeline(str(input_path), str(rebuilt)), expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
