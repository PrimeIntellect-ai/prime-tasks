#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
from decimal import Decimal


def test_process_data_executable_exists():
    """Test that the C++ source and executable exist."""
    cpp_path = "/home/user/process_data.cpp"
    exe_path = "/home/user/process_data"

    assert os.path.exists(cpp_path), f"Source file {cpp_path} does not exist."
    assert os.path.exists(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exe_path} is not a compiled executable."


def test_report_content():
    """Test that the report.txt file contains the correct output."""
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_content = (
        "Data Report\n"
        "-----------\n"
        "Cleaned Metadata: T?mpSensor\n"
        "Total Records: 6\n"
        "Min: 10.50\n"
        "Max: 15.00\n"
        "Mean: 12.67"
    )

    # Normalize line endings
    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert content_lines == expected_lines, f"Report content mismatch.\nExpected:\n{expected_content}\nGot:\n{content}"


def _expected_report(rows):
    filled_values = []
    previous_hour = None
    previous_value = None

    for hour, value_text, metadata in rows:
        value = Decimal(value_text)
        if previous_hour is not None:
            for _ in range(previous_hour + 1, hour):
                filled_values.append(previous_value)
        filled_values.append(value)
        previous_hour = hour
        previous_value = value

    cleaned_last_metadata = "".join(
        "?" if byte < 32 or byte > 127 else chr(byte)
        for byte in rows[-1][2]
    )
    mean = sum(filled_values, Decimal("0")) / Decimal(len(filled_values))

    return (
        "Data Report\n"
        "-----------\n"
        f"Cleaned Metadata: {cleaned_last_metadata}\n"
        f"Total Records: {len(filled_values)}\n"
        f"Min: {min(filled_values):.2f}\n"
        f"Max: {max(filled_values):.2f}\n"
        f"Mean: {mean:.2f}"
    )


def _write_input(rows):
    with open("/home/user/raw_data.tsv", "wb") as f:
        for hour, value_text, metadata in rows:
            f.write(str(hour).encode("ascii"))
            f.write(b"\t")
            f.write(value_text.encode("ascii"))
            f.write(b"\t")
            f.write(metadata)
            f.write(b"\n")


def _exercise(executable, rows):
    report_path = "/home/user/report.txt"
    _write_input(rows)
    if os.path.exists(report_path):
        os.unlink(report_path)

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. "
        f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(report_path), f"{executable} did not create /home/user/report.txt"

    try:
        actual = open(report_path, "rb").read().decode("ascii")
    except UnicodeDecodeError as exc:
        raise AssertionError("The generated report contains non-ASCII bytes") from exc

    actual = actual.rstrip("\r\n")
    expected = _expected_report(rows)
    assert actual == expected, f"Behavioral report mismatch.\nExpected:\n{expected}\nGot:\n{actual}"


def test_program_processes_modified_inputs(tmp_path):
    """Run both the submitted executable and a fresh build on derived test cases."""
    raw_path = "/home/user/raw_data.tsv"
    report_path = "/home/user/report.txt"
    raw_backup = tmp_path / "raw_data.tsv"
    report_backup = tmp_path / "report.txt"
    shutil.copyfile(raw_path, raw_backup)
    had_report = os.path.exists(report_path)
    if had_report:
        shutil.copyfile(report_path, report_backup)

    rebuilt = tmp_path / "process_data_from_source"
    compile_result = subprocess.run(
        ["g++", "-O2", "/home/user/process_data.cpp", "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "process_data.cpp does not compile with the required command: "
        + compile_result.stderr.decode("utf-8", errors="replace")
    )

    cases = [
        [
            (3, "-2.25", b"Alpha"),
            (5, "4.5", b"B\xe9ta"),
            (8, "1.0", b"Last\xffName"),
        ],
        [
            (0, "100.0", b"Start"),
            (2, "-10", b"Middle"),
            (3, "5.20", b"Final\x1fSensor"),
        ],
    ]

    try:
        for executable in ("/home/user/process_data", str(rebuilt)):
            for rows in cases:
                _exercise(executable, rows)
    finally:
        shutil.copyfile(raw_backup, raw_path)
        if had_report:
            shutil.copyfile(report_backup, report_path)
        elif os.path.exists(report_path):
            os.unlink(report_path)


def test_crontab_configured():
    """Test that the crontab is configured to run the executable at 03:15 AM daily."""
    try:
        # Try to get crontab for current user (which is typically where the agent configures it)
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        crontab_output = result.stdout

        # If running as root but the agent configured it for 'user', it might be in /var/spool/cron/crontabs/user
        if not crontab_output and os.path.exists("/var/spool/cron/crontabs/user"):
            with open("/var/spool/cron/crontabs/user", "r") as f:
                crontab_output = f.read()
    except Exception:
        crontab_output = ""
        if os.path.exists("/var/spool/cron/crontabs/root"):
            with open("/var/spool/cron/crontabs/root", "r") as f:
                crontab_output += f.read()
        if os.path.exists("/var/spool/cron/crontabs/user"):
            with open("/var/spool/cron/crontabs/user", "r") as f:
                crontab_output += f.read()

    found = False
    for line in crontab_output.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            minute, hour, dom, mon, dow = parts[:5]
            command = " ".join(parts[5:])
            if minute == "15" and hour == "3" and dom == "*" and mon == "*" and dow == "*":
                if "/home/user/process_data" in command:
                    found = True
                    break

    assert found, "Crontab is not properly configured to run /home/user/process_data at 03:15 AM."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
