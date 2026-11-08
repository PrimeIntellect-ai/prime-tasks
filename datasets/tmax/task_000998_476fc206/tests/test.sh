#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/etl_filter.sh"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"
AUDIO_PATH = "/app/audio/researcher_note.wav"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_etl_filter_clean_corpus():
    out_dir = "/tmp/test_clean_out"
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)

    result = subprocess.run([SCRIPT_PATH, CLEAN_CORPUS, out_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed on clean corpus with error: {result.stderr}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.csv')]
    out_files = set(os.listdir(out_dir))

    missing_clean = []
    for f in clean_files:
        if f not in out_files:
            missing_clean.append(f)

    if missing_clean:
        pytest.fail(f"{len(missing_clean)} of {len(clean_files)} clean modified (not preserved). Missing files: {', '.join(missing_clean)}")


def test_etl_filter_evil_corpus():
    out_dir = "/tmp/test_evil_out"
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)

    result = subprocess.run([SCRIPT_PATH, EVIL_CORPUS, out_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed on evil corpus with error: {result.stderr}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.csv')]
    out_files = set(os.listdir(out_dir))

    bypassed_evil = []
    for f in evil_files:
        if f in out_files:
            bypassed_evil.append(f)

    if bypassed_evil:
        pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed (not rejected). Offending files: {', '.join(bypassed_evil)}")


def extract_threshold():
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format_tags=comment,title", "-of", "default=nw=1:nk=1", AUDIO_PATH],
        capture_output=True,
        text=True,
        check=True,
    )
    match = re.search(r"duration[^0-9]*([0-9]+(?:\.[0-9]+)?)\s*seconds", result.stdout, re.IGNORECASE)
    assert match, f"Could not derive duration threshold from audio metadata: {result.stdout!r}"
    return Decimal(match.group(1))


def test_generated_corpus_requires_real_csv_validation_and_copying():
    threshold = extract_threshold()
    assert threshold > 0

    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix=f"etl_input_{token}_") as input_dir, tempfile.TemporaryDirectory(prefix=f"etl_output_{token}_") as output_dir:
        input_path = Path(input_dir)
        output_path = Path(output_dir)
        expected_valid = {}
        invalid_names = []
        counter = 0

        def add_file(rows, valid):
            nonlocal counter
            counter += 1
            name = f"run_{token}_{counter}_{secrets.token_hex(5)}.csv"
            content = "id,duration,loss,wer\n" + "\n".join(rows) + "\n"
            (input_path / name).write_text(content, encoding="utf-8")
            if valid:
                expected_valid[name] = content.encode("utf-8")
            else:
                invalid_names.append(name)

        half = threshold / Decimal("2")
        above = threshold + Decimal("0.125")

        add_file([
            f"{secrets.randbelow(900000) + 100000},{threshold},0,100",
            f"{secrets.randbelow(900000) + 100000},0.001,2.75,0",
            f"{secrets.randbelow(900000) + 100000},{half},0.125,37.5",
        ], True)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},1.25,99.99"], True)

        add_file([f"{secrets.randbelow(900000) + 100000},{half},,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},1"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},1,10,extra"], False)
        add_file([f",{half},1,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},0,1,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},-0.1,1,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{above},1,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},12oops,1,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},-0.001,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},not-a-number,10"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},1,-0.01"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},1,100.01"], False)
        add_file([f"{secrets.randbelow(900000) + 100000},{half},1,5percent"], False)
        add_file([
            f"{secrets.randbelow(900000) + 100000},{half},1,10",
            f"{secrets.randbelow(900000) + 100000},{above},1,10",
            f"{secrets.randbelow(900000) + 100000},{half},1,10",
        ], False)

        result = subprocess.run([SCRIPT_PATH, input_dir, output_dir], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on generated corpus: {result.stderr}"

        for name, original_bytes in expected_valid.items():
            produced = output_path / name
            assert produced.is_file(), f"Valid generated CSV was not preserved: {name}"
            assert produced.read_bytes() == original_bytes, f"Valid generated CSV was not copied unchanged: {name}"

        for name in invalid_names:
            assert not (output_path / name).exists(), f"Invalid generated CSV was incorrectly preserved: {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
