#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess

SCRIPT = "/home/user/process_locales.sh"
CSV_PATH = "/home/user/translations.csv"
SQL_PATH = "/home/user/bulk_import.sql"


def expected_sql(rows):
    lines = []
    for string_id, locale, translation, email in rows:
        local, domain = email.split("@", 1)
        masked = local[0] + "***@" + domain
        text = translation.replace("\n", "\\n").replace("'", "''")
        lines.append(
            "INSERT INTO locales (id, lang, txt, email) "
            f"VALUES ('{string_id}', '{locale}', '{text}', '{masked}');"
        )
    return lines


def run_case(rows):
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["string_id", "locale", "translation", "translator_email"])
        writer.writerows(rows)

    if os.path.exists(SQL_PATH):
        os.remove(SQL_PATH)

    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(SQL_PATH), f"Output SQL file not found at {SQL_PATH}"

    with open(SQL_PATH, "r", encoding="utf-8") as f:
        actual = f.read().strip().splitlines()

    expected = expected_sql(rows)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} SQL lines, got {len(actual)}.\n"
        f"Actual: {actual}"
    )
    for i, (actual_line, expected_line) in enumerate(zip(actual, expected), 1):
        assert actual_line == expected_line, (
            f"Line {i} mismatch.\nExpected: {expected_line}\nActual:   {actual_line}"
        )


def test_process_locales_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script at {SCRIPT} is not executable"

    with open(SCRIPT, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), (
        "process_locales.sh must be a Bash script with a Bash shebang"
    )

    executable_lines = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert not re.search(r"\b(?:python(?:[0-9.]*)?|perl|node(?:js)?)\b", executable_lines, re.I), (
        "The pipeline may not use Python, Perl, or Node.js"
    )


def test_pipeline_on_original_style_conforming_fixture():
    # This preserves the original fixed-content assertions while replacing the
    # out-of-contract escaped-quote row with a conforming apostrophe test.
    rows = [
        ("btn_ok", "fr", "D'accord", "alice@example.com"),
        ("msg_welcome", "es", "Hola,\nbienvenido a nuestra app.", "bob123@translation.corp"),
        ("err_404", "de", "Nicht gefunden.\nBitte versuchen Sie es erneut.", "charlie.d@freelance.org"),
        ("lbl_profile", "ja", "プロフィール", "dave@tokyo.jp"),
        ("msg_quote", "en", "It's a quote", "eve@test.com"),
    ]
    run_case(rows)


def test_pipeline_functionally_with_unpredictable_records():
    token = secrets.token_hex(6)
    rows = [
        (f"plain_{token}", "en", f"Plain value {token}", f"a@{token}.example"),
        (f"comma_{token}", "fr", f"First, second, {token}", f"bravo99@{token}.org"),
        (f"newline_{token}", "de", f"Line one {token}\nLine two, with comma\nLine three's end", f"Charlie.long@{token}.net"),
        (f"unicode_{token}", "ja", f"翻訳 {token}\n次の行", f"dave@{token}.jp"),
    ]
    run_case(rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
