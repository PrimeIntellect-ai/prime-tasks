#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess

import pytest

PROJECT = "/home/user/fin_recover"
JOURNAL = "/home/user/transactions.journal"
OUTPUT = "/home/user/recovered_total.txt"


@pytest.fixture(scope="session", autouse=True)
def restore_input_and_output():
    journal_before = open(JOURNAL, "rb").read() if os.path.isfile(JOURNAL) else None
    output_before = open(OUTPUT, "rb").read() if os.path.isfile(OUTPUT) else None
    yield
    if journal_before is None:
        if os.path.exists(JOURNAL):
            os.remove(JOURNAL)
    else:
        with open(JOURNAL, "wb") as f:
            f.write(journal_before)
    if output_before is None:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
    else:
        with open(OUTPUT, "wb") as f:
            f.write(output_before)


def test_recovered_total_exists():
    path = "/home/user/recovered_total.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The tool may not have been run or failed to write the output."


def test_recovered_total_content():
    path = "/home/user/recovered_total.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_value = "1000048.64"
    assert content == expected_value, f"Expected {path} to contain '{expected_value}', but found '{content}'. Precision loss might not be completely fixed."


def test_cargo_toml_has_regex():
    path = "/home/user/fin_recover/Cargo.toml"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "regex" in content, f"Expected 'regex' dependency in {path}."


def test_main_rs_uses_f64():
    path = "/home/user/fin_recover/src/main.rs"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "f64" in content, f"Expected 'f64' to be used in {path} to fix precision loss."


def money(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def run_tool(journal, expected):
    with open(JOURNAL, "w") as f:
        f.write(journal)

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust project failed to build or run.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "Running the tool did not create recovered_total.txt"
    with open(OUTPUT, "r") as f:
        actual = f.read().strip()
    assert re.fullmatch(r"[0-9]+\.[0-9]{2}", actual), (
        f"Output must be a number formatted to exactly two decimal places, got {actual!r}"
    )
    assert actual == expected, f"Expected computed total {expected}, got {actual}"


def test_project_builds_and_processes_journals():
    target = os.path.join(PROJECT, "target")
    if os.path.isdir(target):
        shutil.rmtree(target)

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, (
        "The Rust project does not compile.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    run_tool(
        "TXN:1001 AMOUNT:50.05 FEES:1.20\n"
        "TXN:1002 AMOUNT:1000000.00 FEES:0.50\n"
        "TXN:1003 CORRUPTED_DATA - ERROR ERROR\n"
        "TXN:1004 AMOUNT:0.30 FEES:0.01\n",
        "1000048.64",
    )

    # This value is large enough that f32 cannot retain its cents.
    run_tool(
        "TXN:2001 AMOUNT:10000000.37 FEES:0.11\n"
        "TXN:2002 CORRUPTED_DATA - ERROR ERROR\n",
        "10000000.26",
    )

    rng = random.SystemRandom()
    rows = ["TXN:3000 CORRUPTED_DATA - ERROR ERROR"]
    total_cents = 0
    for i in range(1, 18):
        amount = rng.randrange(100_000_000, 1_000_000_000)
        fee = rng.randrange(1, 50_000)
        total_cents += amount - fee
        rows.append(f"TXN:{3000 + i} AMOUNT:{money(amount)} FEES:{money(fee)}")
        if i in (5, 12):
            rows.append(f"TXN:BAD{i} CORRUPTED_DATA - ERROR ERROR")
    rng.shuffle(rows)
    run_tool("\n".join(rows) + "\n", money(total_cents))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
