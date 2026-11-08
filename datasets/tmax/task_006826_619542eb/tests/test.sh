#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import uuid

import pytest

SOURCE = "/home/user/process.c"
BINARY = "/tmp/submission_process"
RAW = "/home/user/translations_raw.csv"
WIDE = "/home/user/translations_wide.csv"
SAMPLE = "/home/user/sample_qa.csv"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.exists(SOURCE), f"Required C source file {SOURCE} is missing."
    source_stat = os.stat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} must be a regular C source file."
    assert source_stat.st_size > 0, f"{SOURCE} is empty."

    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not compile {SOURCE}:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not produce an executable."

    for path in (WIDE, SAMPLE):
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"The compiled processing program failed:\n{result.stderr}"


def test_translations_wide_csv():
    file_path = WIDE
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you save the wide format data?"

    expected_content = (
        "key,en,fr,es\n"
        "BTN_CANCEL,Cancel,Annuler!,\n"
        "BTN_OK,Okay,D'accord,Aceptar\n"
        "ERR_404,Not Found,,No Encontrado\n"
        "TITLE_MAIN,Main Menu,Menu Principal,Menu Principal\n"
    )

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {file_path} does not match the expected reshaped data."


def test_sample_qa_csv():
    file_path = SAMPLE
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you save the QA sample data?"

    expected_content = (
        "key,en,fr,es\n"
        "BTN_OK,Okay,D'accord,Aceptar\n"
        "TITLE_MAIN,Main Menu,Menu Principal,Menu Principal\n"
    )

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {file_path} does not match the expected QA sample data."


def test_zz_program_processes_new_input_correctly():
    suffix = uuid.uuid4().hex[:10].upper()
    token = uuid.uuid4().hex[:12]
    base = random.SystemRandom().randint(1700000000, 1900000000)

    keys = [f"ALPHA_{suffix}", f"BETA_{suffix}", f"GAMMA_{suffix}", f"OMEGA_{suffix}"]
    records = [
        (keys[0], "en", f"old_en_{token}", base),
        (keys[0], "en", f"new_en_{token}", base + 9),
        (keys[0], "fr", f"fr_a_{token}", base + 2),
        (keys[0], "es", f"es_a_{token}", base + 3),
        (keys[1], "en", f"en_b_{token}", base + 4),
        (keys[1], "es", f"old_es_b_{token}", base + 1),
        (keys[1], "es", f"new_es_b_{token}", base + 12),
        (keys[2], "en", f"en_c_{token}", base + 5),
        (keys[2], "fr", f"old_fr_c_{token}", base + 2),
        (keys[2], "fr", f"new_fr_c_{token}", base + 15),
        (keys[2], "es", f"es_c_{token}", base + 6),
        (keys[3], "en", f"en_d_{token}", base + 7),
        (keys[3], "fr", f"fr_d_{token}", base + 8),
        (keys[3], "es", f"es_d_{token}", base + 9),
    ]
    random.SystemRandom().shuffle(records)

    with open(RAW, "w", encoding="utf-8", newline="") as f:
        f.write("key,lang,text,timestamp\n")
        for key, lang, text, timestamp in records:
            f.write(f"{key},{lang},{text},{timestamp}\n")

    latest = {}
    for key, lang, text, timestamp in records:
        previous = latest.get((key, lang))
        if previous is None or timestamp > previous[0]:
            latest[(key, lang)] = (timestamp, text)

    sorted_keys = sorted({key for key, _, _, _ in records})

    def output_line(key):
        values = [latest.get((key, lang), (None, ""))[1] for lang in ("en", "fr", "es")]
        return ",".join([key] + values)

    expected_wide = "\n".join(["key,en,fr,es"] + [output_line(key) for key in sorted_keys])
    complete = [key for key in sorted_keys if all((key, lang) in latest for lang in ("en", "fr", "es"))]
    assert len(complete) >= 2
    expected_sample = "\n".join(["key,en,fr,es"] + [output_line(key) for key in complete[:2]])

    for path in (WIDE, SAMPLE):
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"The program failed on a new valid input:\n{result.stderr}"
    assert os.path.isfile(WIDE), f"The program did not create {WIDE} for the new input."
    assert os.path.isfile(SAMPLE), f"The program did not create {SAMPLE} for the new input."

    with open(WIDE, "r", encoding="utf-8") as f:
        actual_wide = f.read()
    with open(SAMPLE, "r", encoding="utf-8") as f:
        actual_sample = f.read()

    assert actual_wide.strip() == expected_wide.strip(), "The program produced an incorrect wide file for a new input."
    assert actual_sample.strip() == expected_sample.strip(), "The program produced an incorrect QA sample for a new input."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
