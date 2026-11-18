#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import stat
import subprocess
from datetime import datetime, timedelta

RAW = "/home/user/data/raw_logs.csv"
EXTRACTED = "/home/user/data/extracted.csv"
TRANSFORMED = "/home/user/data/transformed.csv"
EXTRACT = "/home/user/etl/extract.sh"
TRANSFORM = "/home/user/etl/transform.sh"
DAG = "/home/user/etl/dag.sh"


def get_raw_data():
    assert os.path.isfile(RAW), "raw_logs.csv is missing"
    with open(RAW, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    return header, rows


def test_scripts_exist_and_executable():
    scripts = [EXTRACT, TRANSFORM, DAG]
    for script in scripts:
        assert os.path.isfile(script), f"Script missing: {script}"
        assert os.access(script, os.X_OK), f"Script not executable: {script}"


def test_extracted_csv():
    assert os.path.isfile(EXTRACTED), "extracted.csv is missing"
    header, rows = get_raw_data()
    expected_lines = [",".join(header)]
    for row in rows:
        ts, level, msg = row
        msg_cleaned = msg.replace("\n", "\\n").replace("\r", "")
        expected_lines.append(f"{ts},{level},{msg_cleaned}")

    with open(EXTRACTED, "r") as f:
        actual_lines = [line.strip("\r\n") for line in f.readlines()]
    assert actual_lines == expected_lines, "extracted.csv does not match expected output"


def expected_transformed(rows):
    if not rows:
        return []
    timestamps = []
    error_counts = {}
    for row in rows:
        dt = datetime.strptime(row[0], "%Y-%m-%d %H:%M:%S").replace(second=0, microsecond=0)
        timestamps.append(dt)
        if row[1] == "ERROR":
            error_counts[dt] = error_counts.get(dt, 0) + 1

    result = []
    current = min(timestamps)
    latest = max(timestamps)
    while current <= latest:
        result.append(f"{current.strftime('%Y-%m-%d %H:%M')},{error_counts.get(current, 0)}")
        current += timedelta(minutes=1)
    return result


def test_transformed_csv():
    assert os.path.isfile(TRANSFORMED), "transformed.csv is missing"
    _, rows = get_raw_data()
    expected_lines = expected_transformed(rows)
    with open(TRANSFORMED, "r") as f:
        actual_lines = [line.strip("\r\n") for line in f.readlines() if line.strip()]
    assert actual_lines == expected_lines, "transformed.csv does not match expected gap-filled output"


def cron_pattern_matches(content):
    pattern1 = r"(?m)^(?:\*/5|0-59/5)\s+\*\s+\*\s+\*\s+\*.*dag\.sh"
    pattern2 = r"(?m)^[0,5,10,15,20,25,30,35,40,45,50,55]+\s+\*\s+\*\s+\*\s+\*.*dag\.sh"
    return re.search(pattern1, content) or re.search(pattern2, content)


def test_cron_backup():
    backup_path = "/home/user/crontab_backup.txt"
    assert os.path.isfile(backup_path), "crontab_backup.txt is missing"
    with open(backup_path, "r") as f:
        content = f.read()
    assert cron_pattern_matches(content), "Crontab backup does not contain valid 5-minute schedule for dag.sh"


def test_cron_is_actually_installed():
    with open("/home/user/crontab_backup.txt", "r") as f:
        backup = f.read().strip()

    installed = []
    for owner in ("user", "root"):
        proc = subprocess.run(
            ["crontab", "-u", owner, "-l"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode == 0:
            installed.append(proc.stdout.strip())

    assert any(text == backup and cron_pattern_matches(text) for text in installed), (
        "The backed-up five-minute DAG schedule is not installed in a crontab"
    )


def run_as_user(path, timeout=15):
    return subprocess.run(
        ["runuser", "-u", "user", "--", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def read_lines(path):
    with open(path, "r") as f:
        return [line.rstrip("\r\n") for line in f.readlines()]


def save_path(path):
    if not os.path.lexists(path):
        return None
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(os.stat(path).st_mode)


def restore_path(path, saved):
    if saved is None:
        if os.path.lexists(path):
            os.unlink(path)
        return
    data, mode = saved
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def test_scripts_execute_pipeline_and_propagate_failures():
    paths = [RAW, EXTRACTED, TRANSFORMED, EXTRACT, TRANSFORM]
    saved = {path: save_path(path) for path in paths}
    token = secrets.token_hex(8)
    extract_marker = f"/tmp/extract-{token}"
    transform_marker = f"/tmp/transform-{token}"

    try:
        base = datetime(2024 + secrets.randbelow(2), 2, 10, 7, secrets.randbelow(30), 0)
        rows = [
            [(base + timedelta(seconds=12)).strftime("%Y-%m-%d %H:%M:%S"), "INFO", f"start,{token}"],
            [(base + timedelta(minutes=1, seconds=3)).strftime("%Y-%m-%d %H:%M:%S"), "ERROR", f"first line {token}\nsecond line, detail\nthird line"],
            [(base + timedelta(minutes=3, seconds=8)).strftime("%Y-%m-%d %H:%M:%S"), "ERROR", "failure A"],
            [(base + timedelta(minutes=3, seconds=44)).strftime("%Y-%m-%d %H:%M:%S"), "ERROR", "failure B"],
            [(base + timedelta(minutes=4, seconds=2)).strftime("%Y-%m-%d %H:%M:%S"), "ERROR ", "not exact"],
            [(base + timedelta(minutes=6, seconds=59)).strftime("%Y-%m-%d %H:%M:%S"), "WARN", "last record"],
        ]
        with open(RAW, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["Timestamp", "Level", "Message"])
            writer.writerows(rows)
        os.chmod(RAW, 0o644)

        for path in (EXTRACTED, TRANSFORMED):
            if os.path.exists(path):
                os.unlink(path)

        proc = run_as_user(EXTRACT)
        assert proc.returncode == 0, f"extract.sh failed when executed: {proc.stderr}"
        expected_extract = ["Timestamp,Level,Message"] + [
            f"{ts},{level},{msg.replace(chr(10), r'\\n').replace(chr(13), '')}"
            for ts, level, msg in rows
        ]
        assert read_lines(EXTRACTED) == expected_extract, "extract.sh did not parse dynamic multiline CSV input"

        proc = run_as_user(TRANSFORM)
        assert proc.returncode == 0, f"transform.sh failed when executed: {proc.stderr}"
        assert [line for line in read_lines(TRANSFORMED) if line] == expected_transformed(rows), (
            "transform.sh did not dynamically filter, aggregate, and gap-fill"
        )

        with open(EXTRACTED, "w") as f:
            f.write("stale\n")
        with open(TRANSFORMED, "w") as f:
            f.write("stale\n")
        os.chmod(EXTRACTED, 0o666)
        os.chmod(TRANSFORMED, 0o666)
        proc = run_as_user(DAG)
        assert proc.returncode == 0, f"dag.sh failed on valid input: {proc.stderr}"
        assert read_lines(EXTRACTED) == expected_extract, "dag.sh did not run extract.sh"
        assert [line for line in read_lines(TRANSFORMED) if line] == expected_transformed(rows), (
            "dag.sh did not run transform.sh after extraction"
        )

        os.unlink(RAW)
        proc = run_as_user(DAG)
        assert proc.returncode == 1, "dag.sh must exit with status 1 when raw_logs.csv is missing"
        with open(RAW, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["Timestamp", "Level", "Message"])
            writer.writerows(rows)
        os.chmod(RAW, 0o644)

        with open(EXTRACT, "w") as f:
            f.write(f"#!/bin/bash\necho ran > {extract_marker}\nexit 7\n")
        with open(TRANSFORM, "w") as f:
            f.write(f"#!/bin/bash\necho ran > {transform_marker}\nexit 0\n")
        os.chmod(EXTRACT, 0o755)
        os.chmod(TRANSFORM, 0o755)
        proc = run_as_user(DAG)
        assert proc.returncode == 1, "dag.sh must convert extract.sh failure to status 1"
        assert os.path.exists(extract_marker), "dag.sh did not execute extract.sh"
        assert not os.path.exists(transform_marker), "dag.sh ran transform.sh after extract.sh failed"

        os.unlink(extract_marker)
        with open(EXTRACT, "w") as f:
            f.write(f"#!/bin/bash\necho ran > {extract_marker}\nexit 0\n")
        with open(TRANSFORM, "w") as f:
            f.write(f"#!/bin/bash\necho ran > {transform_marker}\nexit 9\n")
        os.chmod(EXTRACT, 0o755)
        os.chmod(TRANSFORM, 0o755)
        proc = run_as_user(DAG)
        assert proc.returncode == 1, "dag.sh must convert transform.sh failure to status 1"
        assert os.path.exists(extract_marker) and os.path.exists(transform_marker), (
            "dag.sh did not execute extract.sh followed by transform.sh"
        )
    finally:
        for marker in (extract_marker, transform_marker):
            if os.path.exists(marker):
                os.unlink(marker)
        for path in paths:
            restore_path(path, saved[path])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
