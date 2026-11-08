#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROCESS = Path('/home/user/process.py')
PIPELINE = Path('/home/user/pipeline.sh')
RAW_DIR = Path('/home/user/data/raw')
CSV_FILE = Path('/home/user/data/timeseries.csv')


def test_scripts_exist_and_executable():
    """Check if process.py and pipeline.sh exist and are executable."""
    scripts = [
        "/home/user/process.py",
        "/home/user/pipeline.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} is missing."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_cron_job_configuration():
    """Check if pipeline_cron contains the correct schedule."""
    cron_file = "/home/user/pipeline_cron"
    assert os.path.isfile(cron_file), f"Cron configuration file {cron_file} is missing."

    with open(cron_file, "r") as f:
        content = f.read().strip()

    # Preserve the original checks.
    assert "30 2 * * *" in content, f"Cron schedule '30 2 * * *' not found in {cron_file}."
    assert "/home/user/pipeline.sh" in content, f"Script path '/home/user/pipeline.sh' not found in {cron_file}."

    # It must be just one valid crontab line, not comments or extra commands.
    raw_content = Path(cron_file).read_text()
    lines = raw_content.splitlines()
    assert len(lines) == 1, f"{cron_file} must contain exactly one crontab line."
    assert re.fullmatch(
        r"[ \t]*30[ \t]+2[ \t]+\*[ \t]+\*[ \t]+\*[ \t]+/home/user/pipeline\.sh[ \t]*",
        lines[0],
    ), f"Invalid crontab line in {cron_file}: {lines[0]!r}"


def test_timeseries_csv_content():
    """Check if timeseries.csv exists and contains the correct sorted data."""
    csv_file = "/home/user/data/timeseries.csv"
    assert os.path.isfile(csv_file), f"Output file {csv_file} is missing."

    with open(csv_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "timestamp,value",
        "2023-10-01 10:00:00,15.2",
        "2023-10-02 10:00:00,16.8",
        "2023-10-03 10:00:00,14.9"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {csv_file}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."


def make_cases():
    year = 2040 + secrets.randbelow(40)
    values = [f"{secrets.randbelow(70) + 10}.{secrets.randbelow(9) + 1}" for _ in range(4)]
    return [
        ("later.dat", f"{year}-11-23 21:17:09", values[0], "utf-8", "Current system report"),
        ("first.dat", f"{year}-01-04 03:08:12", values[1], "utf-16le", "Legacy little endian report"),
        ("third.dat", f"{year}-07-19 12:41:33", values[2], "utf-16", "Wide character report"),
        ("second.dat", f"{year}-03-15 09:26:45", values[3], "iso-8859-1", "Résumé café report"),
    ]


def report_bytes(timestamp, value, encoding, prefix):
    text = f"{prefix}. Noise before data. Readout: [{timestamp}] -> {value} units. End of report."
    return text.encode(encoding)


def test_process_script_executes_and_handles_encodings():
    cases = make_cases()
    with tempfile.TemporaryDirectory() as td:
        for name, timestamp, value, encoding, prefix in cases:
            path = Path(td) / name
            path.write_bytes(report_bytes(timestamp, value, encoding, prefix))
            result = subprocess.run(
                [sys.executable, str(PROCESS), str(path)],
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, f"process.py failed for {encoding}: {result.stderr}"
            assert result.stdout.strip() == f"{timestamp},{value}", (
                f"process.py produced the wrong output for {encoding}: {result.stdout!r}"
            )


def test_pipeline_executes_on_dynamic_files_and_sorts_output():
    cases = make_cases()
    backup_root = Path(tempfile.mkdtemp(prefix='pipeline-verifier-'))
    raw_backup = backup_root / 'raw-original'
    csv_existed = CSV_FILE.exists()
    csv_backup = CSV_FILE.read_bytes() if csv_existed else None

    try:
        shutil.move(str(RAW_DIR), str(raw_backup))
        RAW_DIR.mkdir(parents=True)

        for name, timestamp, value, encoding, prefix in cases:
            (RAW_DIR / name).write_bytes(report_bytes(timestamp, value, encoding, prefix))

        # A non-.dat report must not be processed.
        ignored_ts = f"{2090 + secrets.randbelow(8)}-12-31 23:59:59"
        (RAW_DIR / 'ignore.txt').write_text(
            f"Readout: [{ignored_ts}] -> 999.9 units.", encoding='utf-8'
        )

        result = subprocess.run(
            [str(PIPELINE)],
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, f"pipeline.sh failed: {result.stderr}"
        assert CSV_FILE.is_file(), "pipeline.sh did not create timeseries.csv"

        actual = CSV_FILE.read_text().splitlines()
        expected = ["timestamp,value"] + [
            f"{timestamp},{value}"
            for _, timestamp, value, _, _ in sorted(cases, key=lambda item: item[1])
        ]
        assert actual == expected, f"Dynamic pipeline output mismatch. Expected {expected!r}, got {actual!r}"
        assert sum(line == "timestamp,value" for line in actual) == 1
    finally:
        if RAW_DIR.exists():
            shutil.rmtree(RAW_DIR)
        shutil.move(str(raw_backup), str(RAW_DIR))
        if csv_existed:
            CSV_FILE.write_bytes(csv_backup)
        elif CSV_FILE.exists():
            CSV_FILE.unlink()
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
