#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import string
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/process.sh"
RAW_PATH = "/home/user/raw_tx.csv"
INVALID_PATH = "/home/user/invalid_rows.log"
SUMMARY_PATH = "/home/user/summary.tsv"
LOG_PATH = "/home/user/pipeline.log"
OUTPUT_PATHS = [INVALID_PATH, SUMMARY_PATH, LOG_PATH]
RATES = {"USD": 1.00, "EUR": 1.08, "GBP": 1.25}


def remove_outputs():
    for path in OUTPUT_PATHS:
        if os.path.lexists(path):
            if os.path.isdir(path):
                raise AssertionError(f"Output path {path} is a directory")
            os.unlink(path)


def run_process():
    remove_outputs()
    env = os.environ.copy()
    env["PS4"] = "__PROCESS_TRACE__ "

    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as trace:
        env["BASH_XTRACEFD"] = str(trace.fileno())
        result = subprocess.run(
            ["/bin/bash", "-x", SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            pass_fds=(trace.fileno(),),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        trace.seek(0)
        execution_trace = trace.read()

    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    forbidden_runtime = re.compile(
        r"(?:^|[\s/])(python(?:[0-9.]*)?|perl|ruby|node(?:js)?|php|lua(?:[0-9.]*)?)(?:\s|$)",
        re.IGNORECASE | re.MULTILINE,
    )
    assert not forbidden_runtime.search(execution_trace), (
        "process.sh invoked a non-bash language runtime; the requested solution must be a bash-only pipeline"
    )


def expected_from_raw(path):
    invalid = []
    aggregated = {}
    valid_count = 0
    invalid_count = 0

    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if len(row) < 6:
                continue
            amount = float(row[3])
            currency = row[4]
            if amount <= 0 or currency not in RATES:
                invalid.append(",".join(row))
                invalid_count += 1
                continue

            valid_count += 1
            email = row[2]
            email_parts = email.split("@")
            if len(email_parts) == 2:
                masked_email = email_parts[0][0] + "***@" + email_parts[1]
            else:
                masked_email = email
            usd_amount = amount * RATES[currency]
            aggregated[masked_email] = aggregated.get(masked_email, 0.0) + usd_amount

    summary = sorted(aggregated.items(), key=lambda x: x[1], reverse=True)
    log = f"[INFO] Processed {valid_count} valid records, dropped {invalid_count} invalid records."
    return invalid, summary, log


def assert_outputs_match_raw(path):
    expected_invalid, expected_summary, expected_log = expected_from_raw(path)

    assert os.path.isfile(INVALID_PATH), f"Output file {INVALID_PATH} is missing or is not a file."
    with open(INVALID_PATH, "r", encoding="utf-8") as f:
        actual_invalid = [line.strip() for line in f if line.strip()]
    assert expected_invalid == actual_invalid, f"Contents of {INVALID_PATH} do not match expected invalid rows."

    assert os.path.isfile(SUMMARY_PATH), f"Output file {SUMMARY_PATH} is missing or is not a file."
    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == len(expected_summary), (
        f"Expected {len(expected_summary)} lines in {SUMMARY_PATH}, found {len(actual_lines)}."
    )
    for actual_line, (expected_email, expected_amount) in zip(actual_lines, expected_summary):
        parts = actual_line.split("\t")
        assert len(parts) == 2, f"Line in {SUMMARY_PATH} is not tab-separated: {actual_line}"
        assert parts[0] == expected_email, f"Expected masked email {expected_email}, got {parts[0]}"
        assert math.isclose(float(parts[1]), expected_amount, rel_tol=1e-5), (
            f"Expected amount {expected_amount:.2f}, got {parts[1]}"
        )

    assert os.path.isfile(LOG_PATH), f"Output file {LOG_PATH} is missing or is not a file."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        actual_log = f.read().strip()
    assert actual_log == expected_log, f"Expected log '{expected_log}', got '{actual_log}'"


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.path.getsize(SCRIPT_PATH) > 0, f"Script {SCRIPT_PATH} is empty."

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert syntax.returncode == 0, f"process.sh is not valid bash syntax: {syntax.stderr}"

    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    forbidden_source = re.compile(
        r"(?:^|[;&|()]\s*)(?:command\s+|exec\s+)?(?:/[^\s;|&]+/)?"
        r"(?:python(?:[0-9.]*)?|perl|ruby|node(?:js)?|php|lua(?:[0-9.]*)?)(?:\s|$)",
        re.IGNORECASE | re.MULTILINE,
    )
    assert not forbidden_source.search(source), (
        "process.sh invokes a non-bash language runtime; use bash and standard command-line tools only"
    )

    literal_masks = source.count("***")
    mask_variables = re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*['\"]\*\*\*['\"]", source)
    reused_mask_variable = any(
        len(re.findall(rf"\b{re.escape(variable)}\b", source)) >= 3
        for variable in mask_variables
    )
    assert literal_masks >= 2 or reused_mask_variable, (
        "process.sh does not contain evidence that both name and email masking are implemented"
    )

    last_character_operation = re.search(
        r"substr\s*\([^\n]*length\s*\(|substr\s*\([^,\n]+,\s*-\s*1|"
        r"\$\{[^}]+:\s*-\s*1[^}]*\}|length\s*\([^)]*\)\s*\]|\\2",
        source,
        re.IGNORECASE,
    )
    assert last_character_operation, (
        "process.sh does not contain an operation that preserves the final character when masking names"
    )

    run_process()


def test_process_script_exists():
    script_path = "/home/user/process.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."


def test_invalid_rows_log():
    raw_path = "/home/user/raw_tx.csv"
    invalid_path = "/home/user/invalid_rows.log"

    assert os.path.exists(raw_path), f"Raw data file {raw_path} is missing."
    assert os.path.exists(invalid_path), f"Output file {invalid_path} is missing."

    expected_invalid = []
    with open(raw_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) < 6:
                continue
            amount = float(row[3])
            currency = row[4]
            if amount <= 0 or currency not in ["USD", "EUR", "GBP"]:
                expected_invalid.append(",".join(row))

    with open(invalid_path, "r", encoding="utf-8") as f:
        actual_invalid = [line.strip() for line in f if line.strip()]

    assert expected_invalid == actual_invalid, f"Contents of {invalid_path} do not match expected invalid rows."


def test_summary_tsv():
    raw_path = "/home/user/raw_tx.csv"
    summary_path = "/home/user/summary.tsv"

    assert os.path.exists(summary_path), f"Output file {summary_path} is missing."

    rates = {"USD": 1.00, "EUR": 1.08, "GBP": 1.25}
    aggregated = {}

    with open(raw_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) < 6:
                continue
            amount = float(row[3])
            currency = row[4]
            if amount > 0 and currency in rates:
                email = row[2]
                email_parts = email.split("@")
                if len(email_parts) == 2:
                    masked_email = email_parts[0][0] + "***@" + email_parts[1]
                else:
                    masked_email = email

                usd_amount = amount * rates[currency]
                aggregated[masked_email] = aggregated.get(masked_email, 0.0) + usd_amount

    expected_summary = sorted(aggregated.items(), key=lambda x: x[1], reverse=True)

    with open(summary_path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_summary), f"Expected {len(expected_summary)} lines in {summary_path}, found {len(actual_lines)}."

    for actual_line, (expected_email, expected_amount) in zip(actual_lines, expected_summary):
        parts = actual_line.split("\t")
        assert len(parts) == 2, f"Line in {summary_path} is not tab-separated: {actual_line}"
        assert parts[0] == expected_email, f"Expected masked email {expected_email}, got {parts[0]}"
        assert math.isclose(float(parts[1]), expected_amount, rel_tol=1e-5), f"Expected amount {expected_amount:.2f}, got {parts[1]}"


def test_pipeline_log():
    raw_path = "/home/user/raw_tx.csv"
    log_path = "/home/user/pipeline.log"

    assert os.path.exists(log_path), f"Output file {log_path} is missing."

    valid_count = 0
    invalid_count = 0
    with open(raw_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) < 6:
                continue
            amount = float(row[3])
            currency = row[4]
            if amount > 0 and currency in ["USD", "EUR", "GBP"]:
                valid_count += 1
            else:
                invalid_count += 1

    expected_log = f"[INFO] Processed {valid_count} valid records, dropped {invalid_count} invalid records."
    with open(log_path, "r", encoding="utf-8") as f:
        actual_log = f.read().strip()
    assert actual_log == expected_log, f"Expected log '{expected_log}', got '{actual_log}'"


def test_pipeline_on_unseen_input():
    with open(RAW_PATH, "r", encoding="utf-8") as f:
        original_raw = f.read()

    token = "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(10))
    rows = [
        ["91", "Quincy North", f"quincy.{token}@alpha.test", "17.35", "GBP", "2025-01-01"],
        ["92", "Rita South", f"rita.{token}@beta.test", "8.40", "EUR", "2025-01-02"],
        ["93", "Quincy North", f"quincy.{token}@alpha.test", "3.20", "USD", "2025-01-03"],
        ["94", "Uma West", f"uma.{token}@gamma.test", "0.00", "USD", "2025-01-04"],
        ["95", "Victor East", f"victor.{token}@delta.test", "700.00", "CAD", "2025-01-05"],
        ["96", "Wendy Lake", f"wendy.{token}@epsilon.test", "-4.50", "GBP", "2025-01-06"],
        ["97", "Xavier Hill", f"xavier.{token}@zeta.test", "0.75", "USD", "2025-01-07"],
    ]

    try:
        with open(RAW_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["tx_id", "name", "email", "amount", "currency", "date"])
            writer.writerows(rows)

        run_process()
        assert_outputs_match_raw(RAW_PATH)
    finally:
        with open(RAW_PATH, "w", encoding="utf-8") as f:
            f.write(original_raw)
        run_process()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
