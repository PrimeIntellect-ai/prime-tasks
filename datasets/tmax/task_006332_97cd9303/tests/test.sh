#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/process_logs.sh")
RAW_DIR = Path("/home/user/raw_logs")
OUTPUT = Path("/home/user/normalized_configs.csv")


def run_script():
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(SCRIPT)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_logs.sh failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert OUTPUT.is_file(), "The script did not generate /home/user/normalized_configs.csv."


def test_script_is_executable():
    script_path = "/home/user/process_logs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_generates_baseline_output():
    run_script()


def test_normalized_configs_exists():
    output_path = "/home/user/normalized_configs.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."


def test_normalized_configs_content():
    output_path = "/home/user/normalized_configs.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_rows = [
        ["ServerID", "EpochTimestamp", "ConfigKey", "NotesLength"],
        ["srv-C", "1698170400", "feature_flag_x", "7"],
        ["srv-A", "1698273000", "max_connections", "47"],
        ["srv-B", "1698273000", "cache_size", "101"],
        ["srv-C", "1698273000", "worker_threads", "12"],
        ["srv-A", "1698340500", "timeout", "10"],
        ["srv-B", "1698393600", "log_level", "12"]
    ]

    with open(output_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def test_normalized_configs_sorting():
    output_path = "/home/user/normalized_configs.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        data = list(reader)

    try:
        sorted_data = sorted(data, key=lambda x: (int(x[1]), x[0]))
    except ValueError:
        pytest.fail("EpochTimestamp column contains non-integer values.")

    assert data == sorted_data, "The CSV rows are not correctly sorted by EpochTimestamp then ServerID."


def write_csv(path, encoding, rows):
    import io

    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["ServerID", "Timestamp", "ConfigKey", "Notes"])
    writer.writerows(rows)
    path.write_bytes(buffer.getvalue().encode(encoding))


def test_script_processes_changed_multiencoding_multiline_inputs():
    token = secrets.token_hex(6)
    backup_root = Path(tempfile.mkdtemp(prefix="raw_logs_backup_"))
    backup_raw = backup_root / "raw_logs"
    shutil.copytree(RAW_DIR, backup_raw)

    pst_note = f'First {token}\n second "quoted" line'
    latin_note = f"café {token}\nline two"
    utf16_note = f"snowman ☃ {token}\nfinal line"

    server_early = f"mid-{token}"
    server_first_tie = f"aa-{token}"
    server_second_tie = f"zz-{token}"

    utc = datetime.timezone.utc
    expected = [
        ["ServerID", "EpochTimestamp", "ConfigKey", "NotesLength"],
        [
            server_early,
            str(int(datetime.datetime(2024, 1, 2, 3, 4, 0, tzinfo=utc).timestamp())),
            f"latin_{token}",
            str(len(latin_note)),
        ],
        [
            server_first_tie,
            str(int(datetime.datetime(2024, 1, 2, 3, 4, 5, tzinfo=utc).timestamp())),
            f"pst_{token}",
            str(len(pst_note)),
        ],
        [
            server_second_tie,
            str(int(datetime.datetime(2024, 1, 2, 3, 4, 5, tzinfo=utc).timestamp())),
            f"utf16_{token}",
            str(len(utf16_note)),
        ],
    ]

    try:
        shutil.rmtree(RAW_DIR)
        RAW_DIR.mkdir(parents=True)

        write_csv(
            RAW_DIR / f"changed_utf8_{token}.csv",
            "utf-8",
            [[server_first_tie, "2024-01-01 19:04:05 PST", f"pst_{token}", pst_note]],
        )
        write_csv(
            RAW_DIR / f"changed_latin1_{token}.csv",
            "iso-8859-1",
            [[server_early, "01/02/2024 03:04 AM GMT", f"latin_{token}", latin_note]],
        )
        write_csv(
            RAW_DIR / f"changed_utf16_{token}.csv",
            "utf-16le",
            [[server_second_tie, "2024-01-02T03:04:05Z", f"utf16_{token}", utf16_note]],
        )

        run_script()
        with OUTPUT.open("r", encoding="utf-8", newline="") as f:
            actual = list(csv.reader(f))

        assert actual == expected, (
            "The script did not correctly process changed CSV files with UTF-8, "
            "ISO-8859-1, UTF-16LE, embedded newlines, varied timestamps, and tie sorting. "
            f"Expected {expected!r}, got {actual!r}."
        )
    finally:
        if RAW_DIR.exists():
            shutil.rmtree(RAW_DIR)
        shutil.copytree(backup_raw, RAW_DIR)
        subprocess.run([str(SCRIPT)], cwd="/home/user", timeout=30, check=False)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
