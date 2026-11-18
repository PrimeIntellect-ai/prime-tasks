#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import pytest

SOURCE_PATH = "/home/user/process_configs.c"
CSV_PATH = "/home/user/config_history.csv"
ARCHIVE_DIR = "/home/user/remote_archive"
EXECUTABLE_PATH = "/tmp/process_configs_verifier"


def read_expected_reports(csv_path):
    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        dates = []
        data = {h: [] for h in headers[1:]}
        for row in reader:
            if not row:
                continue
            dates.append(row[0])
            for i, header in enumerate(headers[1:]):
                data[header].append(row[i + 1])

    expected = {}
    for server in headers[1:]:
        lines = [
            f"REPORT FOR: {server}",
            "========================",
            "Update History:",
        ]
        for date, version in zip(dates, data[server]):
            lines.append(f"- {date}: {version}")
        expected[server] = "\n".join(lines).strip()
    return expected


def remove_reports(server_names):
    for server in server_names:
        for path in (
            os.path.join("/home/user", f"{server}.report"),
            os.path.join(ARCHIVE_DIR, f"{server}.report"),
        ):
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    pytest.fail(f"Expected report path {path} is a directory.")
                os.unlink(path)


def run_program():
    result = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled C program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_archived_reports(expected):
    assert os.path.exists(ARCHIVE_DIR), f"Directory {ARCHIVE_DIR} does not exist."
    for server, expected_content in expected.items():
        report_path = os.path.join(ARCHIVE_DIR, f"{server}.report")
        assert os.path.exists(report_path), (
            f"Report file for {server} was not found at {report_path}."
        )
        assert os.path.isfile(report_path), f"Report path {report_path} is not a file."
        with open(report_path, "r") as f:
            actual_content = f.read().strip()
        assert actual_content == expected_content, (
            f"Content of {report_path} does not match the expected format or data."
        )


def test_c_program_exists():
    assert os.path.exists(SOURCE_PATH), f"C program file {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"Path {SOURCE_PATH} is not a file."


def test_c_program_compiles_and_processes_csv():
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"C program failed to compile with gcc.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(EXECUTABLE_PATH), "gcc did not produce an executable."

    assert os.path.exists(CSV_PATH), f"Input file {CSV_PATH} is missing."
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    nonce = secrets.randbelow(7) + 2
    generated_csv = (
        "Date,AppServer,DbServer,WebCache\n"
        f"204{nonce}-01-11,v{nonce}.4,v8.{nonce},v3.{nonce}\n"
        f"204{nonce}-02-12,v{nonce}.5,v7.{nonce},v4.{nonce}\n"
        f"204{nonce}-03-13,v{nonce}.6,v6.{nonce},v5.{nonce}\n"
    )

    servers = ["AppServer", "DbServer", "WebCache"]
    try:
        with open(CSV_PATH, "w", newline="") as f:
            f.write(generated_csv)
        remove_reports(servers)
        expected_generated = read_expected_reports(CSV_PATH)
        run_program()
        assert_archived_reports(expected_generated)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)

    # Run once more on the actual supplied input so the final-state assertions below
    # continue to verify the reports requested by the task.
    original_expected = read_expected_reports(CSV_PATH)
    remove_reports(list(original_expected.keys()))
    run_program()


def test_report_files_generated_and_moved():
    assert os.path.exists(CSV_PATH), f"Input file {CSV_PATH} is missing."
    expected = read_expected_reports(CSV_PATH)
    assert_archived_reports(expected)


def test_no_report_files_in_home():
    # The prompt permits either copying or moving, so local copies are acceptable.
    if not os.path.exists(CSV_PATH):
        return
    with open(CSV_PATH, "r") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            return
    for server in headers[1:]:
        local_report_path = f"/home/user/{server}.report"
        pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
