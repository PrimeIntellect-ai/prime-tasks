#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import stat
import shutil
import secrets
import subprocess
import tempfile
import pytest
from itertools import combinations

RAW_DIR = "/home/user/configs/raw"
REPORT_FILE = "/home/user/reports/anomalies.csv"
SCRIPT_FILE = "/home/user/run_pipeline.sh"
DETECTOR_FILE = "/home/user/drift_detector.py"


def parse_ini(filepath):
    config = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, val = line.split('=', 1)
                key = key.strip().lower()
                val = val.strip()
                config[key] = val
    return set(f"{k}={v}" for k, v in config.items())


def compute_expected_anomalies():
    if not os.path.exists(RAW_DIR):
        return []

    files = [f for f in os.listdir(RAW_DIR) if f.endswith('.ini')]
    parsed_configs = {}
    for fname in files:
        parsed_configs[fname] = parse_ini(os.path.join(RAW_DIR, fname))

    anomalies = []
    for f1, f2 in combinations(sorted(files), 2):
        set1 = parsed_configs[f1]
        set2 = parsed_configs[f2]

        intersection = len(set1.intersection(set2))
        union = len(set1.union(set2))

        if union == 0:
            sim = 0.0
        else:
            sim = intersection / union

        if sim < 0.35:
            anomalies.append((f1, f2, f"{sim:.4f}"))

    anomalies.sort(key=lambda x: (x[0], x[1]))
    return anomalies


def read_report():
    assert os.path.isfile(REPORT_FILE), f"Missing {REPORT_FILE}"
    with open(REPORT_FILE, 'r', newline='') as f:
        return list(csv.reader(f))


def assert_report_matches_expected():
    expected_anomalies = compute_expected_anomalies()
    rows = read_report()
    assert len(rows) > 0, f"The file {REPORT_FILE} is empty"
    assert rows[0] == ['file1', 'file2', 'similarity'], (
        f"Incorrect header in {REPORT_FILE}. Expected "
        f"['file1', 'file2', 'similarity'], got {rows[0]}"
    )
    actual_anomalies = [tuple(row) for row in rows[1:]]
    assert len(actual_anomalies) == len(expected_anomalies), (
        f"Expected {len(expected_anomalies)} anomalous pairs, but found "
        f"{len(actual_anomalies)} in {REPORT_FILE}"
    )
    for expected, actual in zip(expected_anomalies, actual_anomalies):
        assert expected == actual, f"Mismatch in CSV row. Expected {expected}, got {actual}"


def test_anomalies_csv_exists():
    assert os.path.isfile(REPORT_FILE), f"The anomalies report was not found at {REPORT_FILE}"


def test_anomalies_csv_content():
    assert_report_matches_expected()


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR_FILE), f"Detector script not found at {DETECTOR_FILE}"
    assert stat.S_ISREG(os.stat(DETECTOR_FILE).st_mode), f"{DETECTOR_FILE} is not a regular file"


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_FILE), f"Pipeline script not found at {SCRIPT_FILE}"
    st = os.stat(SCRIPT_FILE)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {SCRIPT_FILE} is not executable"


def test_crontab_scheduled():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Ensure a crontab is set up for the user.")

    cron_lines = [line.strip() for line in output.splitlines()
                  if line.strip() and not line.strip().startswith('#')]

    found = False
    for line in cron_lines:
        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "* * * * *" and SCRIPT_FILE in command:
                found = True
                break

    assert found, f"Could not find a crontab entry running {SCRIPT_FILE} every minute (* * * * *)"


def test_detector_and_pipeline_on_unseen_inputs():
    token = secrets.token_hex(8)
    names = [f"{prefix}_{token}.ini" for prefix in ("a", "b", "c", "d")]
    work = tempfile.mkdtemp(prefix="drift-verifier-")
    raw_backup = os.path.join(work, "raw")
    detector_backup = os.path.join(work, "drift_detector.py")
    sentinel = os.path.join(work, "pipeline-invoked-detector")
    report_existed = os.path.exists(REPORT_FILE)
    report_backup = os.path.join(work, "anomalies.csv")
    detector_wrapped = False

    shutil.copytree(RAW_DIR, raw_backup)
    if report_existed:
        shutil.copy2(REPORT_FILE, report_backup)

    shared_values = [f"{token}_shared_{i}" for i in range(7)]
    shared_values[1] += "=tail"

    def normalized_a_lines(styled=False):
        lines = []
        if styled:
            lines.extend(["   # ignored comment", "", " SHARED0 = obsolete_value "])
        for i, value in enumerate(shared_values):
            key = f"shared{i}"
            if styled:
                key = key.upper() if i % 2 == 0 else key.title()
                lines.append(f"  {key}  =  {value}  ")
            else:
                lines.append(f"{key}={value}")
        for i in range(6):
            key = f"a_unique_{i}"
            value = f"{token}_a_{i}"
            if styled:
                lines.append(f" {key.upper()} = {value} ")
            else:
                lines.append(f"{key}={value}")
        return lines

    try:
        shutil.rmtree(RAW_DIR)
        os.makedirs(RAW_DIR)

        with open(os.path.join(RAW_DIR, names[0]), 'w') as f:
            f.write("\n".join(normalized_a_lines(False)) + "\n")
        with open(os.path.join(RAW_DIR, names[1]), 'w') as f:
            for i in range(3):
                f.write(f"b_unique_{i}={token}_b_{i}\n")
        with open(os.path.join(RAW_DIR, names[2]), 'w') as f:
            f.write("\n".join(normalized_a_lines(True)) + "\n")
        with open(os.path.join(RAW_DIR, names[3]), 'w') as f:
            for i, value in enumerate(shared_values):
                f.write(f"shared{i}={value}\n")
            for i in range(7):
                f.write(f"d_unique_{i}={token}_d_{i}\n")

        direct = subprocess.run(
            ["python3", DETECTOR_FILE], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert direct.returncode == 0, (
            f"Running {DETECTOR_FILE} failed with code {direct.returncode}. "
            f"stdout: {direct.stdout}\nstderr: {direct.stderr}"
        )
        assert_report_matches_expected()
        first_report = open(REPORT_FILE, 'rb').read()

        # Change an anomalous configuration into an exact normalized match. The
        # pipeline must regenerate the report, and must actually invoke the
        # required detector path rather than being a dummy executable.
        with open(os.path.join(RAW_DIR, names[1]), 'w') as f:
            f.write("\n".join(normalized_a_lines(True)) + "\n")

        os.replace(DETECTOR_FILE, detector_backup)
        detector_wrapped = True
        with open(DETECTOR_FILE, 'w') as f:
            f.write("#!/usr/bin/env python3\n")
            f.write("import os, sys\n")
            f.write(f"open({sentinel!r}, 'w').write('invoked')\n")
            f.write(f"os.execv(sys.executable, [sys.executable, {detector_backup!r}])\n")
        os.chmod(DETECTOR_FILE, 0o755)

        pipeline = subprocess.run(
            [SCRIPT_FILE], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert pipeline.returncode == 0, (
            f"Running {SCRIPT_FILE} failed with code {pipeline.returncode}. "
            f"stdout: {pipeline.stdout}\nstderr: {pipeline.stderr}"
        )
        assert os.path.isfile(sentinel), (
            f"{SCRIPT_FILE} did not execute the required {DETECTOR_FILE} script"
        )
        assert_report_matches_expected()
        second_report = open(REPORT_FILE, 'rb').read()
        assert second_report != first_report, "The pipeline did not regenerate the report after inputs changed"
    finally:
        if detector_wrapped:
            try:
                if os.path.lexists(DETECTOR_FILE):
                    os.remove(DETECTOR_FILE)
            finally:
                if os.path.exists(detector_backup):
                    os.replace(detector_backup, DETECTOR_FILE)
        if os.path.exists(RAW_DIR):
            shutil.rmtree(RAW_DIR)
        shutil.copytree(raw_backup, RAW_DIR)
        if report_existed:
            shutil.copy2(report_backup, REPORT_FILE)
        elif os.path.exists(REPORT_FILE):
            os.remove(REPORT_FILE)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
