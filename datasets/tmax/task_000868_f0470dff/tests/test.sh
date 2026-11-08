#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import random
import re
import resource
import secrets
import subprocess
import tempfile
import uuid

import pytest

BINARY_PATH = "/home/user/pipeline/target/release/filter"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
REFERENCE_VIDEO = "/app/reference.mp4"


def test_cron_job_configured():
    setup_script = "/home/user/setup_cron.sh"
    assert os.path.isfile(setup_script), f"Setup script missing at {setup_script}"

    subprocess.run(["bash", setup_script], check=True)

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    crontab_output = result.stdout.strip()

    pattern = r"^0\s+\*\s+\*\s+\*\s+\*\s+/home/user/pipeline/target/release/filter\s+/var/data/incoming\.csv\s+/var/data/clean\.csv"
    match_found = any(re.match(pattern, line.strip()) for line in crontab_output.splitlines())
    assert match_found, f"Cron job not correctly configured. Current crontab:\n{crontab_output}"


def test_rust_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Rust binary missing at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Rust binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled filter is not an ELF executable"


def count_csv_rows(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        return sum(1 for _ in f)


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".csv")]
    failed_files = []

    for filename in clean_files:
        input_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        original_rows = count_csv_rows(input_path)

        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            output_path = tmp.name

        try:
            subprocess.run([BINARY_PATH, input_path, output_path], check=True, capture_output=True)
            output_rows = count_csv_rows(output_path)
            if output_rows != original_rows:
                failed_files.append((filename, original_rows, output_rows))
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    if failed_files:
        details = ", ".join([f"{f} (expected {e}, got {g})" for f, e, g in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {details}")


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".csv")]
    failed_files = []

    for filename in evil_files:
        input_path = os.path.join(EVIL_CORPUS_DIR, filename)

        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            output_path = tmp.name

        try:
            subprocess.run([BINARY_PATH, input_path, output_path], check=True, capture_output=True)
            output_rows = count_csv_rows(output_path)
            if output_rows != 1:
                failed_files.append((filename, output_rows))
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    if failed_files:
        details = ", ".join([f"{f} (got {g} rows, expected 1)" for f, g in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {details}")


def video_frame_count():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
            "-show_entries", "stream=nb_read_frames",
            "-of", "default=nokey=1:noprint_wrappers=1", REFERENCE_VIDEO,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    value = result.stdout.strip()
    assert value.isdigit(), f"Could not derive video frame count: {value!r}"
    return int(value)


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\r\n")
        writer.writerows(rows)


def test_dynamic_csv_filtering_and_exact_output():
    frame_count = video_frame_count()
    marker = secrets.token_hex(12)
    header = ["id", "timestamp", "user_agent", "description"]

    cases = [
        (True, [str(uuid.uuid4()), "2001", f"agent,{marker}", f"ordinary payload {marker}"]),
        (True, [str(uuid.uuid4()), "2002", 'agent "quoted"', "evaluation scripted preeval eval! <script>"]),
        (True, [str(uuid.uuid4()), "2003", "multiline-agent", f"alpha\tbeta\n{marker} gamma"]),
        (True, [str(uuid.uuid4()), "2004", "boundary", " ".join([marker] * frame_count)]),
        (False, [str(uuid.uuid4()), "2005", "blocked", f"before EvAl after {marker}"]),
        (False, [str(uuid.uuid4()), "2006", "blocked", f"{marker}\tScRiPt\nlast"]),
        (False, [str(uuid.uuid4()), "2007", "too-many", " ".join([marker] * (frame_count + 1))]),
        (True, [str(uuid.uuid4()), "2008", "empty", ""]),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"filter-{marker}-") as td:
        input_path = os.path.join(td, f"input-{uuid.uuid4()}.csv")
        output_path = os.path.join(td, f"output-{uuid.uuid4()}.csv")
        expected_path = os.path.join(td, f"expected-{uuid.uuid4()}.csv")

        write_csv(input_path, [header] + [row for _, row in cases])
        write_csv(expected_path, [header] + [row for keep, row in cases if keep])

        subprocess.run(
            [BINARY_PATH, input_path, output_path],
            check=True,
            capture_output=True,
            timeout=30,
        )

        assert os.path.isfile(output_path), "Filter did not create the requested output file"
        with open(output_path, "rb") as actual, open(expected_path, "rb") as expected:
            assert actual.read() == expected.read(), (
                "Output did not preserve the header and accepted CSV records exactly, "
                "or did not apply token normalization/frame-count filtering correctly"
            )


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.digest()


def limit_address_space():
    limit = 64 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def test_streams_large_input_under_memory_limit():
    marker = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix=f"stream-{marker}-") as td:
        input_path = os.path.join(td, f"large-{uuid.uuid4()}.csv")
        output_path = os.path.join(td, f"clean-{uuid.uuid4()}.csv")

        description = "x" * 180
        with open(input_path, "wb") as f:
            f.write(b"id,timestamp,user_agent,description\r\n")
            for i in range(300000):
                f.write(f"{i},1700000000,ua-{marker},{description}\r\n".encode("ascii"))

        assert os.path.getsize(input_path) > 64 * 1024 * 1024
        subprocess.run(
            [BINARY_PATH, input_path, output_path],
            check=True,
            capture_output=True,
            timeout=120,
            preexec_fn=limit_address_space,
        )
        assert file_sha256(output_path) == file_sha256(input_path), (
            "Large clean input was not streamed and preserved exactly"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
