#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import secrets
import shutil
import stat
import subprocess
import time
import zlib

import pytest

LEGACY_DIR = "/home/user/legacy_data"
NEW_DIR = "/home/user/new_data"
REPORT_PATH = "/home/user/benchmark_report.json"
MIGRATE_PATH = "/home/user/migrate.py"
PIPELINE_PATH = "/home/user/ci_pipeline.sh"


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Benchmark report {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("benchmark_report.json is not valid JSON.")


def expected_from_legacy():
    valid = []
    invalid = []
    for fname in os.listdir(LEGACY_DIR):
        if not fname.endswith(".jsonl"):
            continue
        with open(os.path.join(LEGACY_DIR, fname), "r") as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                record = json.loads(line)
                data = record["data"]
                expected_crc = record["crc32"]
                computed_crc = format(zlib.crc32(data.encode("utf-8")) & 0xFFFFFFFF, "08x")
                if computed_crc == expected_crc:
                    valid.append(data)
                else:
                    invalid.append(data)
    return valid, invalid


def assert_migration_matches_legacy():
    valid, invalid = expected_from_legacy()
    expected_files = set()

    for data in valid:
        sha256_hash = hashlib.sha256(data.encode("utf-8")).hexdigest()
        expected_file = os.path.join(NEW_DIR, sha256_hash[:2], f"{sha256_hash}.json")
        expected_files.add(os.path.normpath(expected_file))
        assert os.path.isfile(expected_file), f"Missing migrated file for valid record: {expected_file}"
        with open(expected_file, "r") as new_f:
            new_record = json.load(new_f)
        assert new_record.get("record_id") == sha256_hash, f"Incorrect record_id in {expected_file}"
        assert new_record.get("content") == data, f"Incorrect content in {expected_file}"
        assert set(new_record.keys()) == {"record_id", "content"}, f"Unexpected schema in {expected_file}"

    actual_files = set()
    for root, dirs, files in os.walk(NEW_DIR):
        for name in files:
            actual_files.add(os.path.normpath(os.path.join(root, name)))

    assert actual_files == expected_files, (
        f"new_data contains missing or extra files. "
        f"Missing: {sorted(expected_files - actual_files)}; "
        f"Extra: {sorted(actual_files - expected_files)}"
    )

    for data in invalid:
        sha256_hash = hashlib.sha256(data.encode("utf-8")).hexdigest()
        corrupt_path = os.path.join(NEW_DIR, sha256_hash[:2], f"{sha256_hash}.json")
        assert not os.path.exists(corrupt_path), f"Corrupt record was migrated: {corrupt_path}"

    report = load_report()
    assert report["total_valid"] == len(valid), f"Expected {len(valid)} total_valid, got {report['total_valid']}"
    assert report["total_invalid"] == len(invalid), f"Expected {len(invalid)} total_invalid, got {report['total_invalid']}"
    return report, len(valid), len(invalid)


def test_scripts_exist_and_executable():
    """Test that the required scripts exist and have correct permissions."""
    assert os.path.isfile(MIGRATE_PATH), "/home/user/migrate.py is missing."
    assert os.path.isfile(PIPELINE_PATH), "/home/user/ci_pipeline.sh is missing."
    assert os.access(PIPELINE_PATH, os.X_OK), "/home/user/ci_pipeline.sh is not executable."


def test_pipeline_execution():
    """Test running the CI pipeline script."""
    result = subprocess.run([PIPELINE_PATH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"ci_pipeline.sh failed with exit code {result.returncode}.\nStderr: {result.stderr}"
    assert "CI SUCCESS" in result.stdout, "ci_pipeline.sh did not print 'CI SUCCESS' to standard output."


def test_benchmark_report_structure():
    """Test the structure and types of the benchmark report."""
    report = load_report()
    assert "total_valid" in report, "Missing 'total_valid' in benchmark report."
    assert "total_invalid" in report, "Missing 'total_invalid' in benchmark report."
    assert "records_per_second" in report, "Missing 'records_per_second' in benchmark report."
    assert set(report.keys()) == {"total_valid", "total_invalid", "records_per_second"}, "Benchmark report has unexpected fields."
    assert isinstance(report["total_valid"], int) and not isinstance(report["total_valid"], bool), "'total_valid' must be an integer."
    assert isinstance(report["total_invalid"], int) and not isinstance(report["total_invalid"], bool), "'total_invalid' must be an integer."
    assert isinstance(report["records_per_second"], (int, float)) and not isinstance(report["records_per_second"], bool), "'records_per_second' must be a float."
    assert math.isfinite(report["records_per_second"]), "'records_per_second' must be finite."
    assert report["records_per_second"] > 0, "'records_per_second' should be greater than 0."


def test_data_migration_correctness():
    """Test that the data was migrated correctly according to the rules."""
    report, expected_valid, expected_invalid = assert_migration_matches_legacy()
    assert report["total_valid"] == expected_valid
    assert report["total_invalid"] == expected_invalid


def test_migrate_on_unseen_randomized_data():
    """Execute migrate.py directly against unpredictable data and reject stale or extra output."""
    shutil.rmtree(LEGACY_DIR, ignore_errors=True)
    shutil.rmtree(NEW_DIR, ignore_errors=True)
    os.makedirs(LEGACY_DIR)
    os.makedirs(NEW_DIR)
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    records = []
    valid_count = 137
    invalid_count = 43
    for i in range(valid_count + invalid_count):
        data = f"verification-{secrets.token_hex(24)}-{i}"
        crc_value = zlib.crc32(data.encode("utf-8")) & 0xFFFFFFFF
        if i >= valid_count:
            crc_value ^= 1
        records.append({"id": secrets.randbits(31), "data": data, "crc32": format(crc_value, "08x")})

    # Split records among unpredictable file names so the implementation must enumerate all JSONL files.
    for part in range(3):
        path = os.path.join(LEGACY_DIR, f"{secrets.token_hex(8)}.jsonl")
        with open(path, "w") as f:
            for record in records[part::3]:
                f.write(json.dumps(record) + "\n")

    started = time.monotonic()
    result = subprocess.run(["python3", MIGRATE_PATH], capture_output=True, text=True, timeout=30)
    elapsed = time.monotonic() - started
    assert result.returncode == 0, f"migrate.py failed on randomized input.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    report, derived_valid, derived_invalid = assert_migration_matches_legacy()
    assert derived_valid == valid_count
    assert derived_invalid == invalid_count
    assert set(report.keys()) == {"total_valid", "total_invalid", "records_per_second"}
    rate = report["records_per_second"]
    assert isinstance(rate, (int, float)) and not isinstance(rate, bool)
    assert math.isfinite(rate) and rate > 0

    # The reported rate must imply a nonzero processing duration plausibly bounded by observed wall time.
    possible_durations = [valid_count / rate, (valid_count + invalid_count) / rate]
    assert any(elapsed * 0.001 <= duration <= elapsed * 1.25 for duration in possible_durations), (
        f"records_per_second={rate} is inconsistent with processing {valid_count + invalid_count} "
        f"records in {elapsed:.6f} seconds"
    )


def test_ci_pipeline_runs_migrate_and_enforces_both_count_branches():
    """Use controlled migrate.py outputs to verify that CI executes it and reads its report."""
    original = open(MIGRATE_PATH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(MIGRATE_PATH).st_mode)
    marker = f"/tmp/migrate-marker-{secrets.token_hex(12)}"

    def install_stub(valid, invalid, token):
        stub = f'''import json\nwith open({marker!r}, "w") as f:\n    f.write({token!r})\nwith open({REPORT_PATH!r}, "w") as f:\n    json.dump({{"total_valid": {valid}, "total_invalid": {invalid}, "records_per_second": 1.0}}, f)\n'''
        with open(MIGRATE_PATH, "w") as f:
            f.write(stub)

    try:
        success_token = secrets.token_hex(16)
        install_stub(9, 2, success_token)
        success = subprocess.run([PIPELINE_PATH], capture_output=True, text=True, timeout=30)
        assert os.path.isfile(marker), "ci_pipeline.sh did not run /home/user/migrate.py."
        assert open(marker).read() == success_token, "ci_pipeline.sh did not execute the installed migration script."
        assert success.returncode == 0, f"Pipeline should succeed when total_invalid < total_valid: {success.stderr}"
        assert "CI SUCCESS" in success.stdout, "Successful pipeline did not print CI SUCCESS."

        os.remove(marker)
        failure_token = secrets.token_hex(16)
        install_stub(4, 4, failure_token)
        failure = subprocess.run([PIPELINE_PATH], capture_output=True, text=True, timeout=30)
        assert os.path.isfile(marker), "ci_pipeline.sh did not run migrate.py for the failure case."
        assert open(marker).read() == failure_token
        assert failure.returncode == 1, f"Pipeline must exit 1 when total_invalid >= total_valid; got {failure.returncode}."
        assert "CI SUCCESS" not in failure.stdout, "Failing pipeline must not print CI SUCCESS."
    finally:
        with open(MIGRATE_PATH, "wb") as f:
            f.write(original)
        os.chmod(MIGRATE_PATH, original_mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
