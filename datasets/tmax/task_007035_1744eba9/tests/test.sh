#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
import tempfile
from collections import defaultdict

LOGS_PATH = "/home/user/translation_logs.csv"
SOURCE_PATH = "/home/user/process.rs"
PROCESS_PATH = "/home/user/process"
PIPELINE_PATH = "/home/user/pipeline.sh"
STATS_PATH = "/home/user/fr_stats.csv"
MAX_PATH = "/home/user/max_avg.txt"


def expected_from_input():
    daily_words = defaultdict(int)
    with open(LOGS_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["locale"] == "fr-FR":
                daily_words[row["timestamp"][:10]] += int(row["words"])

    sorted_dates = sorted(daily_words)
    expected_rows = []
    max_avg = 0.0
    for i, date in enumerate(sorted_dates):
        start_idx = max(0, i - 2)
        window = [daily_words[sorted_dates[j]] for j in range(start_idx, i + 1)]
        avg = sum(window) / len(window)
        expected_rows.append((date, str(daily_words[date]), f"{avg:.2f}"))
        if avg > max_avg:
            max_avg = avg
    return expected_rows, f"{max_avg:.2f}"


def check_stats(check_max=True):
    expected_rows, expected_max = expected_from_input()

    assert os.path.exists(STATS_PATH), f"{STATS_PATH} does not exist."
    with open(STATS_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["date", "daily_words", "rolling_avg"], "Incorrect header in fr_stats.csv."
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), (
        f"Incorrect number of rows in fr_stats.csv. Expected {len(expected_rows)}, "
        f"got {len(actual_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert tuple(actual) == expected, (
            f"Row {i + 1} mismatch in fr_stats.csv: expected {expected}, got {tuple(actual)}."
        )

    if check_max:
        assert os.path.exists(MAX_PATH), f"{MAX_PATH} does not exist."
        with open(MAX_PATH, "r", encoding="utf-8") as f:
            content = f.read().strip()
        assert content == expected_max, (
            f"Content of max_avg.txt mismatch: expected '{expected_max}', got '{content}'."
        )


def run_pipeline(require_rustc=True):
    result = subprocess.run(
        ["bash", "-x", PIPELINE_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    if require_rustc:
        trace = result.stderr
        assert re.search(r"(?m)^\+\s+(?:\S*/)?rustc(?:\s|$).*?/home/user/process\.rs(?:\s|$)", trace), (
            "pipeline.sh did not invoke rustc on /home/user/process.rs."
        )


def write_case(rows):
    with open(LOGS_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "locale", "words"])
        writer.writerows(rows)


def test_pipeline_sh_exists_and_executable():
    assert os.path.exists(PIPELINE_PATH), f"{PIPELINE_PATH} does not exist."
    assert os.access(PIPELINE_PATH, os.X_OK), f"{PIPELINE_PATH} is not executable."


def test_process_rs_is_valid_working_rust_source_and_pipeline_is_dynamic():
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
    with open(LOGS_PATH, "rb") as f:
        original_input = f.read()

    nonce = secrets.randbelow(5000) + 1000
    try:
        with tempfile.TemporaryDirectory() as td:
            independently_compiled = os.path.join(td, "process_from_source")
            result = subprocess.run(
                ["/usr/bin/rustc", SOURCE_PATH, "-o", independently_compiled],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
            assert result.returncode == 0, (
                f"process.rs does not compile with rustc.\nstdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )

            write_case([
                ["2024-02-01T01:00:00Z", "fr-FR", nonce],
                ["2024-02-01T04:00:00Z", "fr-FR", 17],
                ["2024-02-03T01:00:00Z", "es-ES", 99999],
                ["2024-02-05T01:00:00Z", "fr-FR", nonce + 31],
                ["2024-02-09T01:00:00Z", "fr-FR", 83],
                ["2024-02-20T01:00:00Z", "fr-FR", nonce + 107],
            ])
            if os.path.exists(STATS_PATH):
                os.remove(STATS_PATH)
            result = subprocess.run(
                [independently_compiled],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"The binary compiled directly from process.rs failed.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            check_stats(check_max=False)

        write_case([
            ["2025-01-11T08:00:00Z", "de-DE", nonce + 900],
            ["2025-01-02T08:00:00Z", "fr-FR", nonce + 3],
            ["2025-01-10T08:00:00Z", "fr-FR", 41],
            ["2025-01-04T08:00:00Z", "fr-FR", nonce + 57],
            ["2025-01-02T09:00:00Z", "fr-FR", 29],
            ["2025-01-15T08:00:00Z", "fr-FR", nonce + 211],
        ])
        for path in (PROCESS_PATH, STATS_PATH, MAX_PATH):
            if os.path.lexists(path):
                os.remove(path)
        run_pipeline(require_rustc=True)

        assert os.path.isfile(PROCESS_PATH), (
            f"{PROCESS_PATH} does not exist. Did the pipeline compile the Rust program?"
        )
        assert os.access(PROCESS_PATH, os.X_OK), f"{PROCESS_PATH} is not executable."
        with open(PROCESS_PATH, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{PROCESS_PATH} is not a compiled ELF binary."
        check_stats(check_max=True)

        # Exercise the exact binary produced by pipeline.sh on another unseen input.
        write_case([
            ["2026-03-07T00:00:00Z", "fr-FR", nonce + 401],
            ["2026-03-01T00:00:00Z", "fr-FR", 13],
            ["2026-03-02T00:00:00Z", "it-IT", nonce + 999],
            ["2026-03-09T00:00:00Z", "fr-FR", nonce + 19],
            ["2026-03-01T12:00:00Z", "fr-FR", 37],
        ])
        if os.path.exists(STATS_PATH):
            os.remove(STATS_PATH)
        result = subprocess.run(
            [PROCESS_PATH],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"The process binary produced by pipeline.sh failed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        check_stats(check_max=False)
    finally:
        with open(LOGS_PATH, "wb") as f:
            f.write(original_input)
        # Restore final artifacts for the original assertions below.
        subprocess.run(
            [PIPELINE_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )


def test_process_executable_exists():
    path = PROCESS_PATH
    assert os.path.exists(path), f"{path} does not exist. Did the pipeline compile the Rust program?"
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_fr_stats_csv_and_max_avg():
    assert os.path.exists(LOGS_PATH), f"{LOGS_PATH} does not exist."
    check_stats(check_max=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
