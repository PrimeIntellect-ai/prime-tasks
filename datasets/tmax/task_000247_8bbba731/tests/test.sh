#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess
import tempfile
import time
import pytest

QUOTA = 52428800


def get_dir_size(path):
    total = 0
    for entry in os.scandir(path):
        if entry.is_file():
            total += entry.stat().st_size
    return total


def test_scripts_exist_and_executable():
    scripts = [
        "/home/user/storage_optimizer.sh",
        "/home/user/run_finops_pipeline.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_staging_environment_state():
    staging_artifacts = "/home/user/staging_artifacts"
    staging_archive = "/home/user/staging_archive"

    assert os.path.isdir(staging_archive), f"Directory {staging_archive} was not created."

    archived_file = os.path.join(staging_archive, "build_1.tar.gz")
    assert os.path.isfile(archived_file), f"File {archived_file} was not archived."

    for filename in ["build_2.tar.gz", "build_3.tar.gz"]:
        filepath = os.path.join(staging_artifacts, filename)
        assert os.path.isfile(filepath), f"File {filepath} should not have been archived."

    total_size = get_dir_size(staging_artifacts)
    assert total_size == 52428800, f"Staging artifacts directory size is {total_size}, expected 52428800."


def test_prod_environment_state():
    prod_artifacts = "/home/user/prod_artifacts"
    prod_archive = "/home/user/prod_archive"

    assert os.path.isdir(prod_archive), f"Directory {prod_archive} was not created."

    for filename in ["log_old.log", "log_mid.log"]:
        archived_file = os.path.join(prod_archive, filename)
        assert os.path.isfile(archived_file), f"File {archived_file} was not archived."

    for filename in ["app_v1.jar", "app_v2.jar"]:
        filepath = os.path.join(prod_artifacts, filename)
        assert os.path.isfile(filepath), f"File {filepath} should not have been archived."

    total_size = get_dir_size(prod_artifacts)
    assert total_size == 41943040, f"Prod artifacts directory size is {total_size}, expected 41943040."


def test_prod_finops_csv_report():
    report_file = "/home/user/prod_finops.csv"
    assert os.path.isfile(report_file), f"Report file {report_file} does not exist."

    with open(report_file, "r") as f:
        content = f.read().strip()

    lines = [line for line in content.split("\n") if line.strip()]

    log_old_pattern = re.compile(r"^\d+,log_old\.log,41943040,/home/user/prod_artifacts,/home/user/prod_archive$")
    log_mid_pattern = re.compile(r"^\d+,log_mid\.log,20971520,/home/user/prod_artifacts,/home/user/prod_archive$")

    found_log_old = any(log_old_pattern.match(line) for line in lines)
    found_log_mid = any(log_mid_pattern.match(line) for line in lines)

    assert found_log_old, f"Report {report_file} missing or incorrect entry for log_old.log."
    assert found_log_mid, f"Report {report_file} missing or incorrect entry for log_mid.log."


def test_storage_optimizer_on_derived_alternative_inputs():
    optimizer = "/home/user/storage_optimizer.sh"

    with tempfile.TemporaryDirectory(prefix="finops verifier ") as root:
        target = os.path.join(root, "alternative target")
        archive = os.path.join(root, "alternative archive")
        report = os.path.join(root, "alternative report.csv")
        nested = os.path.join(target, "nested")
        os.makedirs(nested)

        # Files directly in TARGET_DIR total 65 MiB. The nested file must not count.
        files = [
            ("old file.bin", 10 * 1048576, 1000000000),
            ("middle.bin", 25 * 1048576, 1100000000),
            ("new.bin", 30 * 1048576, 1200000000),
        ]
        for name, size, mtime in files:
            path = os.path.join(target, name)
            with open(path, "wb") as f:
                f.truncate(size)
            os.utime(path, (mtime, mtime))

        nested_path = os.path.join(nested, "ignored.bin")
        with open(nested_path, "wb") as f:
            f.truncate(80 * 1048576)

        assert subprocess.run([optimizer], timeout=10).returncode != 0
        assert subprocess.run([optimizer, target, archive, report, "extra"], timeout=10).returncode != 0

        started = int(time.time())
        result = subprocess.run(
            [optimizer, target, archive, report],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        finished = int(time.time())
        assert result.returncode == 0, result.stderr

        assert os.path.isdir(archive)
        assert os.path.isfile(os.path.join(archive, "old file.bin"))
        assert os.path.isfile(os.path.join(archive, "middle.bin"))
        assert os.path.isfile(os.path.join(target, "new.bin"))
        assert os.path.isfile(nested_path)
        assert get_dir_size(target) == 30 * 1048576
        assert get_dir_size(target) <= QUOTA

        with open(report, newline="") as f:
            rows = list(csv.reader(f))
        assert len(rows) == 2
        expected = [
            ["old file.bin", str(10 * 1048576)],
            ["middle.bin", str(25 * 1048576)],
        ]
        for row, (name, size) in zip(rows, expected):
            assert len(row) == 5
            assert row[0].isdigit()
            assert started <= int(row[0]) <= finished
            assert row[1] == name
            assert row[2] == size
            assert row[3] == os.path.abspath(target)
            assert row[4] == os.path.abspath(archive)


def _report_contains(path, filename, size, source, destination):
    if not os.path.isfile(path):
        return False
    with open(path, newline="") as f:
        for row in csv.reader(f):
            if len(row) == 5 and row[0].isdigit() and row[1:] == [filename, str(size), source, destination]:
                return True
    return False


def test_pipeline_executes_both_stages_and_stops_after_staging_failure():
    pipeline = "/home/user/run_finops_pipeline.sh"
    optimizer = "/home/user/storage_optimizer.sh"
    staging_target = "/home/user/staging_artifacts"
    staging_archive = "/home/user/staging_archive"
    staging_report = "/home/user/staging_finops.csv"
    prod_target = "/home/user/prod_artifacts"
    prod_archive = "/home/user/prod_archive"
    prod_report = "/home/user/prod_finops.csv"

    stage_name = "verifier_pipeline_stage_old.bin"
    prod_name = "verifier_pipeline_prod_old.bin"
    stage_path = os.path.join(staging_target, stage_name)
    prod_path = os.path.join(prod_target, prod_name)
    stage_archived = os.path.join(staging_archive, stage_name)
    prod_archived = os.path.join(prod_archive, prod_name)

    for path in [stage_path, prod_path, stage_archived, prod_archived]:
        assert not os.path.exists(path), f"Unexpected pre-existing verifier fixture: {path}"

    with open(stage_path, "wb") as f:
        f.truncate(2 * 1048576)
    with open(prod_path, "wb") as f:
        f.truncate(13 * 1048576)
    os.utime(stage_path, (900000000, 900000000))
    os.utime(prod_path, (900000000, 900000000))

    result = subprocess.run(
        [pipeline], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(stage_archived) and not os.path.exists(stage_path)
    assert os.path.isfile(prod_archived) and not os.path.exists(prod_path)
    assert get_dir_size(staging_target) == QUOTA
    assert get_dir_size(prod_target) == 40 * 1048576
    assert _report_contains(staging_report, stage_name, 2 * 1048576, staging_target, staging_archive)
    assert _report_contains(prod_report, prod_name, 13 * 1048576, prod_target, prod_archive)

    # Instrument the optimizer to ensure a failed staging invocation is propagated
    # and production is not invoked afterward.
    backup = optimizer + ".verifier-backup"
    call_log = "/tmp/finops_pipeline_calls.log"
    assert not os.path.exists(backup)
    try:
        if os.path.exists(call_log):
            os.unlink(call_log)
        os.replace(optimizer, backup)
        with open(optimizer, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf '%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" >> " + call_log + "\n")
            f.write("exit 7\n")
        os.chmod(optimizer, 0o755)

        failed = subprocess.run(
            [pipeline], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert failed.returncode != 0
        with open(call_log) as f:
            calls = [line.strip() for line in f if line.strip()]
        assert calls == [f"{staging_target}|{staging_archive}|{staging_report}"]
    finally:
        if os.path.exists(backup):
            if os.path.exists(optimizer):
                os.unlink(optimizer)
            os.replace(backup, optimizer)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
