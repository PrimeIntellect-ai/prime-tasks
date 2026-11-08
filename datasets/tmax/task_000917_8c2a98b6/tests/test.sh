#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/process_translations.sh"
RAW_CSV = "/home/user/raw_translations.csv"
CLEAN_CSV = "/home/user/clean_translations.csv"
METRICS_FILE = "/home/user/gate_metrics.txt"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_exit_code():
    # Remove output files if they exist to ensure we test the script's execution
    if os.path.exists(CLEAN_CSV):
        os.remove(CLEAN_CSV)
    if os.path.exists(METRICS_FILE):
        os.remove(METRICS_FILE)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script exited with code {result.returncode}, expected 0. stderr: {result.stderr}"


def test_gate_metrics():
    assert os.path.exists(METRICS_FILE), f"{METRICS_FILE} was not created."
    with open(METRICS_FILE, "r") as f:
        content = f.read().strip()
    assert content == "3", f"Expected gate_metrics.txt to contain '3', but got '{content}'."


def test_clean_translations():
    assert os.path.exists(CLEAN_CSV), f"{CLEAN_CSV} was not created."
    with open(CLEAN_CSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines in {CLEAN_CSV}, got {len(lines)}."

    expected_lines = [
        "HOME_BTN,en-US,Home,1600000000,APPROVED",
        "SUBMIT_BTN,fr-FR,Soumettre,1600000010,APPROVED",
        "SETTINGS,en-US,Settings,1600000050,APPROVED",
        "HELP_BTN,en-US,Help me,1600000065,APPROVED",
        "DASHBOARD,es-ES,Tablero de mandos,1600000080,DRAFT"
    ]

    assert sorted(lines) == sorted(expected_lines), "The contents of clean_translations.csv do not match the expected output."


def reference_result(rows):
    valid = []
    for row in rows:
        key, locale, text, timestamp, state = row
        if not re.fullmatch(r"[a-z]{2}-[A-Z]{2}", locale):
            continue
        if text == "":
            continue
        if state not in ("APPROVED", "DRAFT"):
            continue
        valid.append(row)

    selected = {}
    for row in valid:
        group = (row[0], row[1])
        if group not in selected or int(row[3]) > int(selected[group][3]):
            selected[group] = row

    output = [",".join(row) for row in selected.values()]
    metric = sum(1 for row in selected.values()
                 if row[1] == "en-US" and row[4] == "APPROVED")
    return sorted(output), metric


def run_case(rows, expected_status):
    with open(RAW_CSV, "w") as f:
        for row in rows:
            f.write(",".join(row) + "\n")

    for path in (CLEAN_CSV, METRICS_FILE):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == expected_status, (
        f"Expected exit status {expected_status}, got {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.exists(CLEAN_CSV), f"{CLEAN_CSV} was not created."
    assert os.path.exists(METRICS_FILE), f"{METRICS_FILE} was not created."

    with open(CLEAN_CSV) as f:
        actual_lines = sorted(line.strip() for line in f if line.strip())
    with open(METRICS_FILE) as f:
        actual_metric = f.read().strip()

    expected_lines, expected_metric = reference_result(rows)
    assert actual_lines == expected_lines, (
        f"Dynamic cleaned output mismatch. Expected {expected_lines}, got {actual_lines}."
    )
    assert actual_metric == str(expected_metric), (
        f"Dynamic metric mismatch. Expected {expected_metric}, got {actual_metric!r}."
    )


def test_dynamic_validation_deduplication_and_quality_gate():
    with open(RAW_CSV, "rb") as f:
        original_raw = f.read()

    tag = secrets.token_hex(6).upper()
    base = random.SystemRandom().randint(1700000000, 1900000000)
    s = lambda n: str(base + n)

    pass_rows = [
        (f"A_{tag}", "en-US", "OldA", s(1), "APPROVED"),
        (f"A_{tag}", "en-US", "NewA", s(20), "DRAFT"),
        (f"B_{tag}", "en-US", "OldB", s(2), "DRAFT"),
        (f"B_{tag}", "en-US", "NewB", s(30), "APPROVED"),
        (f"C_{tag}", "en-US", "TextC", s(3), "APPROVED"),
        (f"D_{tag}", "en-US", "TextD", s(4), "APPROVED"),
        (f"FOREIGN_{tag}", "fr-FR", "Bonjour", s(5), "APPROVED"),
        # Validation occurs before deduplication: the newer invalid row must not win.
        (f"VALIDFIRST_{tag}", "de-DE", "Gueltig", s(6), "DRAFT"),
        (f"VALIDFIRST_{tag}", "de-DE", "InvalidNew", s(60), "REVIEW"),
        (f"BADLOCALE1_{tag}", "EN-US", "Bad", s(7), "APPROVED"),
        (f"BADLOCALE2_{tag}", "en-us", "Bad", s(8), "APPROVED"),
        (f"BADLOCALE3_{tag}", "en", "Bad", s(9), "APPROVED"),
        (f"EMPTY_{tag}", "en-US", "", s(10), "APPROVED"),
        (f"BADSTATE_{tag}", "en-US", "Review", s(11), "REVIEW"),
    ]

    fail_rows = [
        (f"P_{tag}", "en-US", "ApprovedP", s(101), "APPROVED"),
        (f"Q_{tag}", "en-US", "ApprovedQ", s(102), "APPROVED"),
        (f"R_{tag}", "en-US", "WasApproved", s(103), "APPROVED"),
        (f"R_{tag}", "en-US", "NowDraft", s(130), "DRAFT"),
        (f"S_{tag}", "es-ES", "Aprobado", s(104), "APPROVED"),
        (f"INVALID_{tag}", "en-US", "", s(105), "APPROVED"),
    ]

    random.SystemRandom().shuffle(pass_rows)
    random.SystemRandom().shuffle(fail_rows)

    try:
        expected_pass_lines, expected_pass_metric = reference_result(pass_rows)
        assert expected_pass_metric == 3
        assert expected_pass_lines
        run_case(pass_rows, 0)

        expected_fail_lines, expected_fail_metric = reference_result(fail_rows)
        assert expected_fail_metric == 2
        assert expected_fail_lines
        run_case(fail_rows, 1)
    finally:
        with open(RAW_CSV, "wb") as f:
            f.write(original_raw)
        subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
