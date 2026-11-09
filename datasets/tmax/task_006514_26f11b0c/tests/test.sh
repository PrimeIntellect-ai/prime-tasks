#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import os
import pwd
import stat
import subprocess
import time
import pytest

PROCESSED_CSV = "/home/user/data/processed.csv"
INCOMING_CSV = "/home/user/data/incoming.csv"
SCRIPT = "/home/user/clean_pipeline.py"


def test_processed_file_exists():
    assert os.path.exists(PROCESSED_CSV), f"Expected output file {PROCESSED_CSV} does not exist."
    assert os.path.isfile(PROCESSED_CSV), f"Path {PROCESSED_CSV} is not a file."


def test_processed_file_utf8_encoding_and_content():
    assert os.path.exists(INCOMING_CSV), f"Input file {INCOMING_CSV} is missing."
    with open(INCOMING_CSV, "r", encoding="cp1252", newline="") as f:
        incoming_rows = list(csv.DictReader(f))

    expected_rows = []
    for row in incoming_rows:
        expected_row = row.copy()
        expected_row["email"] = hashlib.sha256(row["email"].encode("utf-8")).hexdigest()

        ssn = row["ssn"]
        if len(ssn) >= 11 and ssn[3] == "-" and ssn[6] == "-":
            expected_row["ssn"] = f"***-**-{ssn[7:]}"

        if not row["temperature"].strip():
            expected_row["temperature"] = "98.6"

        expected_rows.append(expected_row)

    try:
        with open(PROCESSED_CSV, "r", encoding="utf-8", newline="") as f:
            processed_rows = list(csv.DictReader(f))
    except UnicodeDecodeError as e:
        pytest.fail(f"Output file {PROCESSED_CSV} is not valid UTF-8: {e}")

    assert len(processed_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} data rows, found {len(processed_rows)}"
    )

    for i, (proc_row, exp_row) in enumerate(zip(processed_rows, expected_rows)):
        assert proc_row["id"] == exp_row["id"], f"Row {i+1}: 'id' was altered."
        assert proc_row["name"] == exp_row["name"], f"Row {i+1}: 'name' was altered."
        assert proc_row["email"] == exp_row["email"], f"Row {i+1}: 'email' not correctly hashed."
        assert proc_row["ssn"] == exp_row["ssn"], f"Row {i+1}: 'ssn' not correctly masked. Got {proc_row['ssn']}"
        assert proc_row["temperature"] == exp_row["temperature"], f"Row {i+1}: 'temperature' not correctly imputed. Got {proc_row['temperature']}"
        assert proc_row["notes"] == exp_row["notes"], f"Row {i+1}: 'notes' do not match expected UTF-8 decoded text."


def test_script_exists_and_uses_streaming_operations():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as e:
        pytest.fail(f"{SCRIPT} is not valid Python: {e}")

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            method = node.func.attr
            if method in {"readlines", "read_text", "read_bytes"}:
                pytest.fail(f"{SCRIPT} uses {method}(), which loads the complete input instead of streaming it.")
            if method == "read" and (not node.args or (isinstance(node.args[0], ast.Constant) and node.args[0].value == -1)):
                pytest.fail(f"{SCRIPT} uses an unbounded read(), which loads the complete input instead of streaming it.")
            if method == "read_csv":
                chunksize = next((kw.value for kw in node.keywords if kw.arg == "chunksize"), None)
                if chunksize is None or (isinstance(chunksize, ast.Constant) and chunksize.value is None):
                    pytest.fail("pandas.read_csv must be called with chunksize for large-file streaming.")


def _run_script_with_memory_monitor(limit_mb=160, timeout=120):
    account = pwd.getpwnam("user")

    def become_user():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    proc = subprocess.Popen(
        ["python3", SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=become_user,
    )
    deadline = time.time() + timeout
    peak_kb = 0
    exceeded = False

    while proc.poll() is None:
        if time.time() > deadline:
            proc.kill()
            proc.wait()
            pytest.fail(f"{SCRIPT} did not finish within {timeout} seconds.")
        try:
            with open(f"/proc/{proc.pid}/status", "r") as status:
                for line in status:
                    if line.startswith("VmRSS:"):
                        peak_kb = max(peak_kb, int(line.split()[1]))
                        break
        except FileNotFoundError:
            pass
        if peak_kb > limit_mb * 1024:
            exceeded = True
            proc.kill()
            break
        time.sleep(0.01)

    returncode = proc.wait()
    assert not exceeded, (
        f"{SCRIPT} exceeded {limit_mb} MiB RSS while processing the large input; "
        "the input must be processed line-by-line or in chunks."
    )
    assert returncode == 0, f"Executing {SCRIPT} returned exit status {returncode}."


def test_script_executes_on_derived_large_input_and_streams():
    original_input = open(INCOMING_CSV, "rb").read()
    original_output = open(PROCESSED_CSV, "rb").read() if os.path.exists(PROCESSED_CSV) else None
    fields = ["id", "name", "email", "ssn", "temperature", "notes"]
    row_count = 120000

    try:
        with open(INCOMING_CSV, "w", encoding="cp1252", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(fields)
            for i in range(row_count):
                writer.writerow([
                    str(900000 + i),
                    f"Derived Patient {i}",
                    f"derived-{i}@example.test",
                    f"{i % 1000:03d}-{i % 100:02d}-{i % 10000:04d}",
                    "" if i % 4 == 0 else f"{97.0 + (i % 30) / 10:.1f}",
                    f"derived-note-{i}-" + ("x" * 480),
                ])

        if os.path.exists(PROCESSED_CSV):
            os.unlink(PROCESSED_CSV)
        _run_script_with_memory_monitor()

        assert os.path.isfile(PROCESSED_CSV), f"Executing {SCRIPT} did not create {PROCESSED_CSV}."
        try:
            with open(PROCESSED_CSV, "r", encoding="utf-8", newline="") as f:
                reader = csv.DictReader(f)
                assert reader.fieldnames == fields, "The original CSV header was not preserved."
                seen = 0
                for i, row in enumerate(reader):
                    email = f"derived-{i}@example.test"
                    expected_temp = "98.6" if i % 4 == 0 else f"{97.0 + (i % 30) / 10:.1f}"
                    assert row["id"] == str(900000 + i)
                    assert row["name"] == f"Derived Patient {i}"
                    assert row["email"] == hashlib.sha256(email.encode("utf-8")).hexdigest()
                    assert row["ssn"] == f"***-**-{i % 10000:04d}"
                    assert row["temperature"] == expected_temp
                    assert row["notes"] == f"derived-note-{i}-" + ("x" * 480)
                    seen += 1
                assert seen == row_count, f"Expected {row_count} rows after execution, found {seen}."
        except UnicodeDecodeError as e:
            pytest.fail(f"Output produced by {SCRIPT} is not valid UTF-8: {e}")
    finally:
        with open(INCOMING_CSV, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(PROCESSED_CSV):
                os.unlink(PROCESSED_CSV)
        else:
            with open(PROCESSED_CSV, "wb") as f:
                f.write(original_output)


def test_cron_job_setup():
    try:
        crontab_output = subprocess.check_output(["crontab", "-l", "-u", "user"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Could not read crontab for user 'user'.")

    lines = [line.strip() for line in crontab_output.splitlines() if line.strip() and not line.strip().startswith("#")]

    cron_found = False
    for line in lines:
        if "15 3 * * *" in line and "clean_pipeline.py" in line:
            cron_found = True
            break
    assert cron_found, f"Cron job for clean_pipeline.py at 03:15 AM not correctly set up. Crontab contents:\n{crontab_output}"

    exact_found = False
    for line in lines:
        parts = line.split(None, 5)
        if len(parts) == 6 and parts[:5] == ["15", "3", "*", "*", "*"] and parts[5].strip() == "python3 /home/user/clean_pipeline.py":
            exact_found = True
            break
    assert exact_found, (
        "The user crontab must execute exactly 'python3 /home/user/clean_pipeline.py' "
        f"at 03:15 every day. Crontab contents:\n{crontab_output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
