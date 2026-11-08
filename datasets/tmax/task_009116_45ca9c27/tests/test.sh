#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import shutil
import subprocess
import tarfile
from pathlib import Path

import pytest

MASTER = "/home/user/backups/master_backup.tar"
PARSED = Path("/home/user/parsed")
LOG_PATH = PARSED / "critical_alerts.log"
SPLIT_DIR = PARSED / "split"
EXPECTED_SPLIT_COUNTS = {
    "crit_part_aa": 10,
    "crit_part_ab": 10,
    "crit_part_ac": 10,
    "crit_part_ad": 10,
    "crit_part_ae": 2,
}


def reconstruct_expected():
    chunks = []
    with tarfile.open(MASTER, "r:") as master:
        nested = [m for m in master.getmembers() if m.isfile() and m.name.endswith(".tar.gz")]
        for member in nested:
            extracted = master.extractfile(member)
            assert extracted is not None
            with tarfile.open(fileobj=io.BytesIO(extracted.read()), mode="r:gz") as inner:
                for chunk_member in inner.getmembers():
                    basename = os.path.basename(chunk_member.name)
                    if not chunk_member.isfile() or not basename.startswith("chunk_"):
                        continue
                    suffix = basename.rsplit("_", 1)[-1]
                    if not suffix.isdigit():
                        continue
                    chunk_file = inner.extractfile(chunk_member)
                    assert chunk_file is not None
                    chunks.append((int(suffix), chunk_file.read()))

    assert chunks, "No numbered log chunks found in the master archive"
    chunks.sort(key=lambda item: item[0])
    assert len({number for number, _ in chunks}) == len(chunks), "Duplicate chunk suffixes"

    merged = b"".join(data for _, data in chunks)
    critical = []
    for line in merged.splitlines(keepends=True):
        record = json.loads(line.decode("utf-8"))
        if record.get("severity") == "CRITICAL":
            critical.append(line)
    return b"".join(critical), critical


EXPECTED_LOG, EXPECTED_LINES = reconstruct_expected()


def expected_split_data():
    result = {}
    for index in range(0, len(EXPECTED_LINES), 10):
        suffix_index = index // 10
        suffix = chr(ord("a") + suffix_index // 26) + chr(ord("a") + suffix_index % 26)
        result[f"crit_part_{suffix}"] = b"".join(EXPECTED_LINES[index:index + 10])
    return result


EXPECTED_SPLITS = expected_split_data()


def output_is_exact():
    try:
        if not LOG_PATH.is_file() or LOG_PATH.read_bytes() != EXPECTED_LOG:
            return False
        if not SPLIT_DIR.is_dir():
            return False
        actual_names = sorted(p.name for p in SPLIT_DIR.iterdir() if p.is_file())
        if actual_names != sorted(EXPECTED_SPLITS):
            return False
        for name, expected in EXPECTED_SPLITS.items():
            if (SPLIT_DIR / name).read_bytes() != expected:
                return False
        link = PARSED / "latest_alert_part"
        expected_target = str(SPLIT_DIR / sorted(EXPECTED_SPLITS)[-1])
        return link.is_symlink() and os.readlink(link) == expected_target
    except OSError:
        return False


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if os.path.join(root, d) not in {
            "/home/user/backups", "/home/user/parsed"
        }]
        for filename in files:
            if filename.endswith(".py"):
                path = os.path.join(root, filename)
                if os.path.isfile(path):
                    scripts.append(path)
    preferred = "/home/user/process_backups.py"
    return sorted(scripts, key=lambda path: (path != preferred, path))


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_script():
    scripts = find_python_scripts()
    assert scripts, "No Python script was found under /home/user"

    failures = []
    for script in scripts:
        shutil.rmtree(PARSED, ignore_errors=True)
        SPLIT_DIR.mkdir(parents=True, exist_ok=True)
        try:
            result = subprocess.run(
                ["python3", script],
                cwd=os.path.dirname(script),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append(f"{script}: {exc}")
            continue

        if result.returncode == 0 and output_is_exact():
            return
        failures.append(f"{script}: exit status {result.returncode}")

    pytest.fail("No submitted Python script produced the required outputs when executed. " + "; ".join(failures))


def test_critical_alerts_log_exists_and_line_count():
    log_path = "/home/user/parsed/critical_alerts.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        lines = f.readlines()
    assert len(lines) == 42, f"Expected 42 lines in {log_path}, but found {len(lines)}."


def test_critical_alerts_log_content():
    log_path = "/home/user/parsed/critical_alerts.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {log_path} is not valid JSON: {line.strip()}")
            assert "severity" in record, f"Line {line_num} missing 'severity' key."
            assert record["severity"] == "CRITICAL", f"Line {line_num} has severity '{record['severity']}', expected 'CRITICAL'."


def test_critical_alerts_exactly_matches_archive():
    assert LOG_PATH.read_bytes() == EXPECTED_LOG, "critical_alerts.log does not exactly match the filtered archive data"


def test_split_files_exist_and_line_counts():
    split_dir = "/home/user/parsed/split"
    assert os.path.isdir(split_dir), f"Directory {split_dir} does not exist."
    for filename, expected_lines in EXPECTED_SPLIT_COUNTS.items():
        file_path = os.path.join(split_dir, filename)
        assert os.path.isfile(file_path), f"Expected split file {file_path} does not exist."
        with open(file_path, "r") as f:
            lines = f.readlines()
        assert len(lines) == expected_lines, f"Expected {expected_lines} lines in {filename}, but found {len(lines)}."


def test_split_files_exactly_partition_filtered_log():
    actual_names = sorted(p.name for p in SPLIT_DIR.iterdir() if p.is_file())
    assert actual_names == sorted(EXPECTED_SPLITS), "Split directory contains missing, extra, or incorrectly named files"
    concatenated = b""
    for name in actual_names:
        data = (SPLIT_DIR / name).read_bytes()
        assert data == EXPECTED_SPLITS[name], f"{name} does not contain the expected consecutive log lines"
        concatenated += data
    assert concatenated == EXPECTED_LOG, "Concatenated split files do not equal critical_alerts.log"


def test_symlink_latest_alert_part():
    symlink_path = "/home/user/parsed/latest_alert_part"
    expected_target = "/home/user/parsed/split/crit_part_ae"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert target == expected_target, f"Symlink points to {target}, expected {expected_target}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
