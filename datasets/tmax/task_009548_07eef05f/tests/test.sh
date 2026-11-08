#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/process_errors.sh"
INCOMING_PATH = Path("/home/user/incoming")
UNIQUE_ERRORS_PATH = Path("/home/user/unique_errors.txt")
HASHES_PATH = Path("/home/user/processed_hashes.log")

EXPECTED_ERRORS = [
    "ERROR_CODE:500 MESSAGE:Internal Server Error",
    "ERROR_CODE:404 MESSAGE:Not Found",
    "ERROR_CODE:403 MESSAGE:Forbidden Access",
]


def run_script():
    try:
        subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, check=True, timeout=20
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {SCRIPT_PATH} failed with error:\n{e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {SCRIPT_PATH} timed out.")


def read_lines(path):
    assert path.is_file(), f"File {path} was not created."
    return path.read_text().splitlines()


def expected_hash(error):
    return hashlib.sha256(error.encode("utf-8")).hexdigest()


def assert_outputs(errors, hashes=None):
    unique_lines = read_lines(UNIQUE_ERRORS_PATH)
    assert len(unique_lines) == len(errors), (
        f"Expected exactly {len(errors)} unique errors, found {len(unique_lines)}."
    )
    assert set(unique_lines) == set(errors), (
        f"Unexpected unique error contents: {unique_lines}"
    )

    expected_hashes = set(hashes if hashes is not None else map(expected_hash, errors))
    hash_lines = read_lines(HASHES_PATH)
    assert len(hash_lines) == len(expected_hashes), (
        f"Expected exactly {len(expected_hashes)} hashes, found {len(hash_lines)}."
    )
    assert set(hash_lines) == expected_hashes, (
        f"Unexpected processed hash contents: {hash_lines}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), (
        f"Script {SCRIPT_PATH} is not executable by the user."
    )


def test_crontab_configured():
    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it configured?")

    expected_cron = f"0 * * * * {SCRIPT_PATH}"
    cron_lines = [line.strip() for line in crontab_content.splitlines()]
    assert expected_cron in cron_lines, (
        f"Crontab does not contain the expected entry: '{expected_cron}'"
    )


def test_script_execution_and_output():
    run_script()

    unique_errors_content = read_lines(UNIQUE_ERRORS_PATH)
    assert len(unique_errors_content) == len(EXPECTED_ERRORS), (
        f"Expected exactly {len(EXPECTED_ERRORS)} unique errors, "
        f"found {len(unique_errors_content)}."
    )
    for error in EXPECTED_ERRORS:
        assert error in unique_errors_content, (
            f"Expected error '{error}' not found in {UNIQUE_ERRORS_PATH}."
        )

    hashes_content = read_lines(HASHES_PATH)
    assert len(hashes_content) == len(EXPECTED_ERRORS), (
        f"Expected exactly {len(EXPECTED_ERRORS)} hashes, "
        f"found {len(hashes_content)}."
    )
    expected_hashes = [expected_hash(error) for error in EXPECTED_ERRORS]
    for digest in expected_hashes:
        assert digest in hashes_content, (
            f"Expected hash '{digest}' not found in {HASHES_PATH}."
        )


def test_dynamic_inputs_hash_deduplication_and_repeated_runs():
    backup_dir = Path(tempfile.mkdtemp(prefix="incoming-backup-"))
    original_logs = list(INCOMING_PATH.glob("*.log"))
    for path in original_logs:
        shutil.move(str(path), backup_dir / path.name)

    ignored_path = INCOMING_PATH / "ignored.txt"
    ignored_existed = ignored_path.exists()
    ignored_backup = ignored_path.read_bytes() if ignored_existed else None

    try:
        for path in (UNIQUE_ERRORS_PATH, HASHES_PATH):
            path.unlink(missing_ok=True)

        token = secrets.token_hex(12)
        error_a = f"ERROR_CODE:73101 MESSAGE:Dynamic Alpha {token}"
        error_b = f"ERROR_CODE:73102 MESSAGE:Dynamic Beta {token}"
        error_c = f"ERROR_CODE:73103 MESSAGE:Dynamic Gamma {token}"
        ignored_error = f"ERROR_CODE:73999 MESSAGE:Ignored {token}"

        (INCOMING_PATH / "dynamic-a.log").write_text(
            "ordinary noise\n"
            f"[prefix] {error_a}\n"
            f"duplicate prefix {error_a}\n"
            "ERROR_CODE:notdigits MESSAGE:Malformed\n"
            f"context {error_b}\n"
        )
        (INCOMING_PATH / "dynamic-b.log").write_text(
            f"{error_c}\n"
            f"another duplicate {error_b}\n"
            "ERROR_CODE:12345MESSAGE:Missing required space\n"
        )
        ignored_path.write_text(ignored_error + "\n")

        run_script()
        assert_outputs([error_a, error_b, error_c])
        assert ignored_error not in read_lines(UNIQUE_ERRORS_PATH)

        first_unique_bytes = UNIQUE_ERRORS_PATH.read_bytes()
        first_hash_bytes = HASHES_PATH.read_bytes()
        run_script()
        assert UNIQUE_ERRORS_PATH.read_bytes() == first_unique_bytes, (
            "A repeated run appended duplicate errors."
        )
        assert HASHES_PATH.read_bytes() == first_hash_bytes, (
            "A repeated run appended duplicate hashes."
        )

        # Seed only the hash of a new error. A compliant implementation must
        # consult processed_hashes.log and skip that error even though it is
        # absent from unique_errors.txt.
        seeded_error = f"ERROR_CODE:74201 MESSAGE:Already Hashed {token}"
        fresh_error = f"ERROR_CODE:74202 MESSAGE:Fresh Error {token}"
        later_error = f"ERROR_CODE:74203 MESSAGE:Later Error {token}"
        seeded_hash = expected_hash(seeded_error)

        UNIQUE_ERRORS_PATH.unlink()
        HASHES_PATH.write_text(seeded_hash + "\n")
        for path in INCOMING_PATH.glob("*.log"):
            path.unlink()
        active_log = INCOMING_PATH / "seeded-state.log"
        active_log.write_text(
            f"prefix {seeded_error}\n"
            f"prefix {fresh_error}\n"
            f"duplicate {fresh_error}\n"
        )

        run_script()
        assert_outputs(
            [fresh_error],
            hashes=[seeded_hash, expected_hash(fresh_error)],
        )

        seeded_unique_bytes = UNIQUE_ERRORS_PATH.read_bytes()
        seeded_hash_bytes = HASHES_PATH.read_bytes()
        run_script()
        assert UNIQUE_ERRORS_PATH.read_bytes() == seeded_unique_bytes
        assert HASHES_PATH.read_bytes() == seeded_hash_bytes

        with active_log.open("a") as stream:
            stream.write(f"new input {later_error}\n")
            stream.write(f"old input {seeded_error}\n")
        run_script()
        assert_outputs(
            [fresh_error, later_error],
            hashes=[
                seeded_hash,
                expected_hash(fresh_error),
                expected_hash(later_error),
            ],
        )
    finally:
        for path in INCOMING_PATH.glob("*.log"):
            path.unlink()
        for path in backup_dir.glob("*.log"):
            shutil.move(str(path), INCOMING_PATH / path.name)
        shutil.rmtree(backup_dir)
        if ignored_existed:
            ignored_path.write_bytes(ignored_backup)
        else:
            ignored_path.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
