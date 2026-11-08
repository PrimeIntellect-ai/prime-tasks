#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
import threading
import time
from collections import Counter
from decimal import Decimal, InvalidOperation

import pandas as pd
import pytest

AGENT_BIN = "/home/user/clean_data"
AGENT_SRC = "/home/user/clean_data.c"
INPUT_CSV = "/app/historical_transactions.csv"
OUTPUT_CSV = "/home/user/cleaned_transactions.csv"
SUM_FILE = "/home/user/total_sum.txt"
REBUILT_BIN = "/tmp/clean_data_rebuilt"


def test_executable_exists():
    assert os.path.isfile(AGENT_BIN), "Executable /home/user/clean_data not found."
    assert os.access(AGENT_BIN, os.X_OK), "/home/user/clean_data is not executable."
    assert os.path.isfile(AGENT_SRC), "Source /home/user/clean_data.c not found."

    source = open(AGENT_SRC, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"pthread_create\s*\(|#\s*pragma\s+omp\s+parallel", source), \
        "C source does not contain a pthread or OpenMP parallel region."

    subprocess.run(
        ["gcc", "-O3", "-fopenmp", "-pthread", AGENT_SRC, "-lm", "-o", REBUILT_BIN],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_original_input_was_not_replaced():
    assert os.path.isfile(INPUT_CSV), f"CSV file {INPUT_CSV} missing."
    with open(INPUT_CSV, "rb") as f:
        lines = f.read().splitlines()

    assert len(lines) == 1000002, \
        f"Historical CSV should contain 1,000,000 retry rows and 2 recovered audio rows; found {len(lines)}."

    base = lines[:200000]
    for copy_no in range(1, 5):
        start = copy_no * 200000
        assert lines[start:start + 200000] == base, \
            f"Historical retry block {copy_no + 1} is not an exact copy of the original block."

    for i, raw in enumerate(base):
        try:
            row = next(csv.reader([raw.decode("utf-8")], skipinitialspace=True))
        except Exception as exc:
            pytest.fail(f"Invalid UTF-8/CSV in historical row {i}: {exc}")
        assert len(row) == 3, f"Historical row {i} does not have three fields."

        expected_name = f"User{i}"
        if i % 10 == 0:
            expected_name = "José"
        if i % 11 == 0:
            expected_name = "Müller"
        if i % 12 == 0:
            expected_name = "Wei"
        expected_ssn = f"{100 + i % 800:03d}-{10 + i % 80:02d}-{1000 + i % 8000:04d}"

        assert row[0].strip() == expected_name, f"Unexpected name in historical row {i}."
        assert row[1].strip() == expected_ssn, f"Unexpected SSN in historical row {i}."
        try:
            amount = Decimal(row[2].strip())
        except InvalidOperation:
            pytest.fail(f"Invalid amount in historical row {i}: {row[2]!r}")
        assert Decimal("10.00") <= amount <= Decimal("1000.00"), \
            f"Historical amount out of range in row {i}."
        assert amount.as_tuple().exponent >= -2, f"Historical amount has too many decimal places in row {i}."

    recovered = []
    for raw in lines[1000000:]:
        row = next(csv.reader([raw.decode("utf-8")], skipinitialspace=True))
        assert len(row) == 3, "Recovered audio row does not have three fields."
        recovered.append((row[0].strip(), row[1].strip(), Decimal(row[2].strip())))

    assert Counter(recovered) == Counter([
        ("Francois", "111-22-3333", Decimal("450.75")),
        ("Taro", "444-55-6666", Decimal("1200.00")),
    ]), "The two records from retry_audio.wav were not appended exactly once."


def test_speedup_and_output():
    ref_c = "/app/reference_serial.c"
    ref_bin = "/tmp/ref"
    assert os.path.isfile(ref_c), f"Reference source {ref_c} missing."

    subprocess.run(["gcc", "-O3", ref_c, "-o", ref_bin], check=True)

    start_ref = time.time()
    subprocess.run([ref_bin], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time_ref = time.time() - start_ref

    start_agent = time.time()
    subprocess.run([AGENT_BIN], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time_agent = time.time() - start_agent

    speedup = time_ref / time_agent if time_agent > 0 else float("inf")
    assert speedup >= 1.5, \
        f"Speedup is {speedup:.2f}, which is less than the required 1.5 threshold. (Ref: {time_ref:.2f}s, Agent: {time_agent:.2f}s)"


def test_program_on_independently_generated_combined_dataset():
    unique_rows = []
    expected = Counter()
    expected_sum = Decimal("0")

    for i in range(200000):
        token = secrets.token_hex(4)
        if i % 3 == 0:
            name = f"José-{token}"
        elif i % 3 == 1:
            name = f"Müller-{token}"
        else:
            name = f"魏-{token}"
        ssn = f"{100 + i % 900:03d}-{10 + i % 90:02d}-{1000 + i % 9000:04d}"
        cents = 1000 + secrets.randbelow(99001)
        amount_text = f"{cents // 100}.{cents % 100:02d}"
        unique_rows.append(f"{name}, {ssn}, {amount_text}\n")
        amount = Decimal(amount_text)
        expected[(name, f"***-**-{ssn[-4:]}", amount)] += 1
        expected_sum += amount

    audio_rows = [
        ("Francois", "111-22-3333", "450.75"),
        ("Taro", "444-55-6666", "1200.00"),
    ]
    for name, ssn, amount_text in audio_rows:
        unique_rows.append(f"{name}, {ssn}, {amount_text}\n")
        amount = Decimal(amount_text)
        expected[(name, f"***-**-{ssn[-4:]}", amount)] += 1
        expected_sum += amount

    with open(INPUT_CSV, "w", encoding="utf-8", newline="") as f:
        for _ in range(5):
            f.writelines(unique_rows)

    proc = subprocess.Popen([REBUILT_BIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    max_threads = 1

    def observe_threads():
        nonlocal max_threads
        task_dir = f"/proc/{proc.pid}/task"
        while proc.poll() is None:
            try:
                max_threads = max(max_threads, len(os.listdir(task_dir)))
            except FileNotFoundError:
                pass
            time.sleep(0.0002)

    observer = threading.Thread(target=observe_threads)
    observer.start()
    try:
        return_code = proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        pytest.fail("Rebuilt clean_data did not finish within 10 seconds.")
    observer.join()

    assert return_code == 0, f"Rebuilt clean_data exited with status {return_code}."
    assert max_threads >= 2, "clean_data did not create multiple threads while processing the dataset."
    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} missing."
    assert os.path.isfile(SUM_FILE), f"Output file {SUM_FILE} missing."

    actual = Counter()
    with open(OUTPUT_CSV, "r", encoding="utf-8", newline="") as f:
        for line_no, row in enumerate(csv.reader(f, skipinitialspace=True), 1):
            assert len(row) == 3, f"Cleaned output row {line_no} does not have three fields."
            name, ssn, amount_text = (field.strip() for field in row)
            assert re.fullmatch(r"\*\*\*-\*\*-\d{4}", ssn), \
                f"Improperly masked SSN in cleaned row {line_no}: {ssn!r}"
            try:
                amount = Decimal(amount_text)
            except InvalidOperation:
                pytest.fail(f"Invalid amount in cleaned row {line_no}: {amount_text!r}")
            actual[(name, ssn, amount)] += 1

    assert actual == expected, \
        "Cleaned CSV is incomplete, contains duplicates/altered fields, or does not include the recovered audio records."

    try:
        agent_sum = Decimal(open(SUM_FILE, "r", encoding="utf-8").read().strip())
    except InvalidOperation:
        pytest.fail(f"Could not parse {SUM_FILE} as a number.")
    assert abs(agent_sum - expected_sum) < Decimal("0.02"), \
        f"Expected hidden-data sum {expected_sum}, but got {agent_sum}."


def test_total_sum_accuracy():
    assert os.path.isfile(SUM_FILE), f"Output file {SUM_FILE} missing."
    with open(SUM_FILE, "r") as f:
        content = f.read().strip()
    try:
        agent_sum = float(content)
    except ValueError:
        pytest.fail(f"Could not parse {SUM_FILE} content as float: {content}")

    assert os.path.isfile(INPUT_CSV), f"CSV file {INPUT_CSV} missing."
    df = pd.read_csv(INPUT_CSV, header=None, names=["Name", "SSN", "TransactionAmount"], skipinitialspace=True)
    df_dedup = df.drop_duplicates(subset=["Name", "SSN", "TransactionAmount"])
    expected_sum = df_dedup["TransactionAmount"].sum()
    assert abs(agent_sum - expected_sum) < 1.0, f"Expected sum approx {expected_sum}, but got {agent_sum}"


def test_cleaned_transactions_output():
    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} missing."
    df = pd.read_csv(OUTPUT_CSV, header=None, names=["Name", "SSN", "TransactionAmount"], skipinitialspace=True)
    ssns = df["SSN"].astype(str)
    unmasked = ssns[~ssns.str.match(r"^\*\*\*-\*\*-\d{4}$")]
    assert len(unmasked) == 0, \
        f"Found {len(unmasked)} unmasked or improperly masked SSNs. Example: {unmasked.iloc[0] if len(unmasked) > 0 else ''}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
