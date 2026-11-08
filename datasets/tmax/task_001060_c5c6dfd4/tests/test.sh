#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import string
import subprocess
import tempfile
import uuid
from decimal import Decimal
from pathlib import Path

import pytest

FILTER_SCRIPT = "/home/user/filter.sh"
ETL_SCRIPT = "/home/user/etl.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
HEADER = "timestamp,sensor_id,value"


def run_filter(data):
    return subprocess.run(
        [FILTER_SCRIPT], input=data.encode(), capture_output=True, timeout=10
    )


def nonempty(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def test_filter_script_exists_and_executable():
    assert os.path.exists(FILTER_SCRIPT), f"{FILTER_SCRIPT} does not exist."
    assert os.path.isfile(FILTER_SCRIPT), f"{FILTER_SCRIPT} is not a file."
    assert os.access(FILTER_SCRIPT, os.X_OK), f"{FILTER_SCRIPT} is not executable."


def test_filter_adversarial_corpus():
    clean_files = sorted(
        f for f in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    )
    evil_files = sorted(
        f for f in os.listdir(EVIL_CORPUS_DIR)
        if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))
    )

    for filename in clean_files:
        input_lines = nonempty(Path(CLEAN_CORPUS_DIR, filename).read_text())
        result = run_filter("\n".join(input_lines) + "\n")
        assert result.returncode == 0
        output_lines = nonempty(result.stdout.decode(errors="replace"))
        data_lines = [line for line in input_lines if line != HEADER]
        assert output_lines in (data_lines, [HEADER] + data_lines), filename

    for filename in evil_files:
        input_lines = nonempty(Path(EVIL_CORPUS_DIR, filename).read_text())
        result = run_filter("\n".join(input_lines) + "\n")
        assert result.returncode == 0
        output_lines = nonempty(result.stdout.decode(errors="replace"))
        assert output_lines in ([], [HEADER]), filename
        stderr = result.stderr.decode(errors="replace")
        for rejected in [line for line in input_lines if line != HEADER]:
            assert rejected in stderr, f"Rejected row was not logged: {rejected}"


def test_filter_generated_clean_and_malicious_rows():
    alphabet = string.ascii_uppercase + string.digits
    sid1 = "A" + "".join(secrets.choice(alphabet) for _ in range(7))
    sid2 = "B" + "".join(secrets.choice(alphabet) for _ in range(7))
    value = Decimal(secrets.randbelow(15000) - 5000) / Decimal(100)

    valid = [
        f"2024-02-29T23:59:59Z,{sid1},{value}",
        f"2031-06-15T00:00:00Z,{sid2},-50.0",
        f"2031-06-15T12:34:56Z,{sid1},150.0",
    ]
    invalid = [
        f"2023-02-29T12:00:00Z,{sid1},1.0",
        f"2031/06/15 12:00:00,{sid1},1.0",
        f"2031-06-15T12:00:00Z,SHORT,1.0",
        f"2031-06-15T12:00:00Z,ABCDEFGHI,1.0",
        f"2031-06-15T12:00:00Z,ABCD-123,1.0",
        f"2031-06-15T12:00:00Z,{sid1},150.01",
        f"2031-06-15T12:00:00Z,{sid1},-50.01",
        f"2031-06-15T12:00:00Z,{sid1},NaN",
        f"2031-06-15T12:00:00Z,{sid1},1;touch /tmp/pwned",
        f"2031-06-15T12:00:00Z,{sid1}",
        f"2031-06-15T12:00:00Z,{sid1},1.0,extra",
    ]

    mixed = [HEADER]
    for good, bad in zip(valid, invalid):
        mixed.extend([bad, good])
    mixed.extend(invalid[len(valid):])

    result = run_filter("\n".join(mixed) + "\n")
    assert result.returncode == 0
    output = nonempty(result.stdout.decode(errors="replace"))
    assert output in (valid, [HEADER] + valid)

    stderr = result.stderr.decode(errors="replace")
    for rejected in invalid:
        assert rejected in stderr, f"Rejected row was not logged: {rejected}"
    assert not os.path.exists("/tmp/pwned")


def test_etl_script_exists_and_executable():
    assert os.path.exists(ETL_SCRIPT), f"{ETL_SCRIPT} does not exist."
    assert os.path.isfile(ETL_SCRIPT), f"{ETL_SCRIPT} is not a file."
    assert os.access(ETL_SCRIPT, os.X_OK), f"{ETL_SCRIPT} is not executable."


def test_etl_generated_pipeline_behavior():
    ocr = subprocess.run(
        ["tesseract", "/app/calibration.png", "stdout"],
        capture_output=True, text=True, timeout=20, check=True
    ).stdout
    match = re.search(r"OFFSET\s*=\s*([+-]?\d+(?:\.\d+)?)", ocr, re.I)
    assert match, f"Could not derive calibration offset from image OCR: {ocr!r}"
    offset = Decimal(match.group(1))

    alphabet = string.ascii_uppercase + string.digits
    sid_a = "A" + "".join(secrets.choice(alphabet) for _ in range(7))
    sid_z = "Z" + "".join(secrets.choice(alphabet) for _ in range(7))
    year = 2026 + secrets.randbelow(8)
    day = 10 + secrets.randbelow(10)
    date = f"{year}-07-{day:02d}"
    v1 = Decimal(secrets.randbelow(31) - 10)
    v2 = Decimal(secrets.randbelow(31) + 20)
    v3 = Decimal(secrets.randbelow(41) - 20)
    v4 = Decimal(secrets.randbelow(31) - 10)
    v5 = Decimal(secrets.randbelow(31) + 20)

    row1 = f"{date}T08:05:00Z,{sid_z},{v1}"
    duplicate = f"{date}T08:05:00Z,{sid_z},149"
    row2 = f"{date}T08:45:00Z,{sid_z},{v2}"
    row3 = f"{date}T08:15:00Z,{sid_a},{v3}"
    row4 = f"{date}T09:10:00Z,{sid_a},{v4}"
    row5 = f"{date}T09:50:00Z,{sid_a},{v5}"
    rejected = f"{date}T09:20:00Z,BAD,25"

    with tempfile.TemporaryDirectory() as td:
        input_dir = Path(td, "input")
        input_dir.mkdir()
        (input_dir / "a.csv").write_text(
            "\n".join([HEADER, row1, duplicate, row2, rejected]) + "\n"
        )
        (input_dir / "b.csv").write_text(
            "\n".join([HEADER, row3, row4, row5]) + "\n"
        )
        poison = f"{date}T00:00:00Z,{sid_a},100"
        (input_dir / "not_csv.txt").write_text(poison + "\n")
        output_file = Path(td, "result.csv")
        capture_file = Path(td, "filter-input.log")

        backup = f"/tmp/filter-backup-{uuid.uuid4().hex}"
        os.replace(FILTER_SCRIPT, backup)
        try:
            Path(FILTER_SCRIPT).write_text(
                "#!/bin/bash\n"
                f"tee -a {str(capture_file)!r} | {backup!r} \"$@\"\n"
            )
            os.chmod(FILTER_SCRIPT, 0o755)
            result = subprocess.run(
                [ETL_SCRIPT, str(input_dir), str(output_file)],
                capture_output=True, text=True, timeout=30
            )
        finally:
            if os.path.exists(FILTER_SCRIPT):
                os.unlink(FILTER_SCRIPT)
            os.replace(backup, FILTER_SCRIPT)

        assert result.returncode == 0, result.stderr
        assert output_file.is_file(), "ETL did not create its requested output file"
        assert capture_file.is_file(), "ETL did not invoke /home/user/filter.sh"
        captured = capture_file.read_text(errors="replace").splitlines()
        for row in [row1, duplicate, row2, row3, row4, row5, rejected]:
            assert row in captured, f"CSV row was not streamed through filter.sh: {row}"
        assert poison not in captured, "ETL processed a non-CSV file"

        expected = [
            f"{date}T08,{sid_a},{(v3 + offset):.2f}",
            f"{date}T08,{sid_z},{(((v1 + v2) / Decimal(2)) + offset):.2f}",
            f"{date}T09,{sid_a},{(((v4 + v5) / Decimal(2)) + offset):.2f}",
        ]
        actual = nonempty(output_file.read_text(errors="replace"))
        assert actual == expected


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
