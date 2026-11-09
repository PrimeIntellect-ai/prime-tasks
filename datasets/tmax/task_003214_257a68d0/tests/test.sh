#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import sqlite3
import struct
import subprocess
import tempfile

import pytest

HOME = "/home/user"
EXE = os.path.join(HOME, "wav_validator")


def run_validator(path):
    return subprocess.run([EXE, path], capture_output=True, timeout=5).returncode


def chunk(kind, payload):
    assert len(kind) == 4
    return kind + struct.pack("<I", len(payload)) + payload + (b"\x00" if len(payload) & 1 else b"")


def riff(chunks):
    body = b"WAVE" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def pcm_fmt(channels=1, sample_rate=8000, bits=8, audio_format=1,
            byte_rate=None, block_align=None):
    expected_align = channels * bits // 8
    if block_align is None:
        block_align = expected_align
    if byte_rate is None:
        byte_rate = sample_rate * block_align
    return struct.pack("<HHIIHH", audio_format, channels, sample_rate,
                       byte_rate, block_align, bits)


def test_migration_script_creates_database():
    script = "/home/user/migrate.sh"
    db_path = "/home/user/metadata.db"
    assert os.path.isfile(script), f"Migration script not found: {script}"

    if os.path.exists(db_path):
        os.remove(db_path)
    result = subprocess.run(["bash", script], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr or result.stdout
    assert os.path.isfile(db_path), "migrate.sh did not create /home/user/metadata.db"


def test_database_schema():
    db_path = "/home/user/metadata.db"
    assert os.path.isfile(db_path), f"Database file not found: {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='audio_logs';")
    table_exists = cursor.fetchone()
    assert table_exists, "Table 'audio_logs' does not exist in the database."

    cursor.execute("PRAGMA table_info(audio_logs);")
    columns_info = cursor.fetchall()

    expected_columns = ["id", "filename", "sample_rate", "channels", "bit_depth", "is_safe"]
    actual_columns = [col[1] for col in columns_info]
    actual_types = [col[2].upper() for col in columns_info]

    assert actual_columns == expected_columns, f"Expected columns {expected_columns}, but got {actual_columns}"
    for col_type in actual_types:
        assert col_type == "TEXT", f"Expected all columns to be TEXT, but found {col_type}"
    conn.close()


def test_build_system():
    makefile = "/home/user/Makefile"
    source = "/home/user/wav_validator.c"
    assert os.path.isfile(makefile), f"Makefile not found: {makefile}"
    assert os.path.isfile(source), f"Source file not found: {source}"

    dry = subprocess.run(["make", "-Bn", "wav_validator"], cwd=HOME,
                         capture_output=True, text=True, timeout=15)
    commands = dry.stdout + "\n" + dry.stderr
    assert dry.returncode == 0, commands
    assert "-Wall" in commands, "Makefile does not compile with -Wall"
    assert "-Werror" in commands, "Makefile does not compile with -Werror"
    assert re.search(r"(^|\s)(?:/usr/bin/)?gcc(?:\s|$)", commands, re.MULTILINE), \
        "Makefile does not invoke gcc"

    if os.path.exists(EXE):
        os.remove(EXE)
    built = subprocess.run(["make", "-B", "wav_validator"], cwd=HOME,
                           capture_output=True, text=True, timeout=30)
    assert built.returncode == 0, built.stderr or built.stdout
    assert os.path.isfile(EXE), "Makefile did not create wav_validator"
    assert os.access(EXE, os.X_OK), "Makefile output is not executable"


def test_executable_exists():
    assert os.path.isfile(EXE), f"Executable not found: {EXE}"
    assert os.access(EXE, os.X_OK), f"File is not executable: {EXE}"


def test_wav_validator_generated_adversarial_cases():
    fmt_mono = pcm_fmt()
    fmt_stereo = pcm_fmt(channels=2, sample_rate=44100, bits=16)

    clean = [
        riff([chunk(b"fmt ", fmt_mono), chunk(b"data", os.urandom(32))]),
        riff([chunk(b"fmt ", fmt_stereo), chunk(b"data", os.urandom(80))]),
        riff([chunk(b"JUNK", b"abc"), chunk(b"fmt ", fmt_mono),
              chunk(b"LIST", b"INFO"), chunk(b"data", os.urandom(17))]),
    ]

    base = clean[0]
    wrong_riff = b"RIFX" + base[4:]
    wrong_wave = base[:8] + b"AVI " + base[12:]
    bad_riff_size = bytearray(base)
    bad_riff_size[4:8] = struct.pack("<I", len(base) - 9)

    truncated_fmt_body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + b"\x01\x00\x01\x00"
    truncated_fmt = b"RIFF" + struct.pack("<I", len(truncated_fmt_body)) + truncated_fmt_body

    missing_pad_body = (b"WAVE" + b"JUNK" + struct.pack("<I", 1) + b"x" +
                        chunk(b"fmt ", fmt_mono) + chunk(b"data", b"1234"))
    missing_pad = b"RIFF" + struct.pack("<I", len(missing_pad_body)) + missing_pad_body

    evil = [
        b"",
        b"RIFF\x04\x00\x00\x00WAVE",
        wrong_riff,
        wrong_wave,
        bytes(bad_riff_size),
        riff([chunk(b"data", b"not a fmt chunk")]),
        riff([chunk(b"fmt ", b"\x01\x00\x01\x00"), chunk(b"data", b"1234")]),
        truncated_fmt,
        missing_pad,
        riff([chunk(b"fmt ", pcm_fmt(channels=0)), chunk(b"data", b"1234")]),
        riff([chunk(b"fmt ", pcm_fmt(sample_rate=0)), chunk(b"data", b"1234")]),
        riff([chunk(b"fmt ", pcm_fmt(bits=0)), chunk(b"data", b"1234")]),
        riff([chunk(b"fmt ", pcm_fmt(block_align=7)), chunk(b"data", b"1234")]),
        riff([chunk(b"fmt ", pcm_fmt(byte_rate=123)), chunk(b"data", b"1234")]),
    ]

    with tempfile.TemporaryDirectory(prefix="wav-check-") as directory:
        for index, contents in enumerate(clean):
            path = os.path.join(directory, f"sample-{os.urandom(6).hex()}-{index}.bin")
            with open(path, "wb") as handle:
                handle.write(contents)
            assert run_validator(path) == 0, f"Generated valid WAV rejected (case {index})"

        for index, contents in enumerate(evil):
            path = os.path.join(directory, f"sample-{os.urandom(6).hex()}-{index}.bin")
            with open(path, "wb") as handle:
                handle.write(contents)
            assert run_validator(path) == 1, f"Generated malformed WAV accepted (case {index})"


def test_wav_validator_adversarial_corpus():
    assert os.path.isfile(EXE), f"Executable not found: {EXE}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    clean_failures = []
    for path in clean_files:
        if run_validator(path) != 0:
            clean_failures.append(os.path.basename(path))

    evil_failures = []
    for path in evil_files:
        if run_validator(path) == 0:
            evil_failures.append(os.path.basename(path))

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")
    assert not error_msg, " | ".join(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
