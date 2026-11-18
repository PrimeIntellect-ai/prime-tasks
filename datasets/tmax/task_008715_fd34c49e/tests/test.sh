#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import subprocess
import tempfile


def calibrated(value, unit):
    volts = value / 1000.0 if unit == "mV" else value
    return f"{volts * volts + 0.5 * volts:.4f}"


def test_files_exist_and_executable():
    assert os.path.isfile("/home/user/normalize.c"), "/home/user/normalize.c does not exist."

    executable_path = "/home/user/normalize"
    assert os.path.isfile(executable_path), f"{executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."

    script_path = "/home/user/process.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_clean_data_csv():
    csv_path = "/home/user/clean_data.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist. Did you run process.sh?"

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "A1,3.0000",
        "B2,7.5000",
        "C3,0.5000",
        "D4,0.8400",
        "E5,0.0000"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {csv_path}, but found {len(lines)}."

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} in {csv_path} is incorrect. Expected '{expected}', got '{lines[i]}'."


def test_report_md():
    report_path = "/home/user/report.md"
    assert os.path.isfile(report_path), f"{report_path} does not exist. Did you run process.sh?"

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert "Total records processed: 5" in content, f"Expected 'Total records processed: 5' in {report_path}."
    assert "{{COUNT}}" not in content, f"Placeholder {{{{COUNT}}}} was not replaced in {report_path}."


def test_cron_schedule():
    cron_path = "/home/user/cron_schedule.txt"
    assert os.path.isfile(cron_path), f"{cron_path} does not exist."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    parts = content.split()
    assert len(parts) >= 6, f"{cron_path} does not contain a valid cron expression."

    assert parts[0] == "0", f"Minute field in cron expression should be 0, got {parts[0]}"
    assert parts[1] == "0", f"Hour field in cron expression should be 0, got {parts[1]}"
    assert parts[2] == "*", f"Day of month field in cron expression should be *, got {parts[2]}"
    assert parts[3] == "*", f"Month field in cron expression should be *, got {parts[3]}"
    assert parts[4] == "*", f"Day of week field in cron expression should be *, got {parts[4]}"

    command = " ".join(parts[5:])
    assert "/home/user/process.sh" in command, f"Cron command should execute /home/user/process.sh, got '{command}'"


def test_normalize_program_and_source_implement_calibration():
    cases = [
        ("T17", 1750.0, "mV"),
        ("N8", -2.25, "V"),
        ("F4", 0.125, "V"),
        ("S9", 1.0, "mV"),
    ]
    input_text = "".join(f"{ident} {value:g} {unit}\n" for ident, value, unit in cases)
    expected = [f"{ident},{calibrated(value, unit)}" for ident, value, unit in cases]

    def check_executable(executable):
        result = subprocess.run(
            [executable], input=input_text, text=True, capture_output=True,
            timeout=10, check=False
        )
        assert result.returncode == 0, f"{executable} failed: {result.stderr}"
        actual = result.stdout.splitlines()
        assert actual == expected, f"Incorrect normalization from {executable}: expected {expected}, got {actual}"

    check_executable("/home/user/normalize")

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "normalize_from_source")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "/home/user/normalize.c", "-o", rebuilt],
            text=True, capture_output=True, timeout=20, check=False
        )
        assert compile_result.returncode == 0, f"normalize.c does not compile: {compile_result.stderr}"
        check_executable(rebuilt)


def test_process_pipeline_on_changed_sensor_log_and_template():
    paths = [
        pathlib.Path("/home/user/sensor_data.log"),
        pathlib.Path("/home/user/report.tmpl"),
        pathlib.Path("/home/user/clean_data.csv"),
        pathlib.Path("/home/user/report.md"),
    ]
    backups = {path: path.read_bytes() if path.exists() else None for path in paths}

    records = [
        ("QX7", 3200.0, "mV"),
        ("N2", -0.75, "V"),
        ("M3", 12.0, "mV"),
    ]
    changed_log = """[2041-07-09 01:02] ID:QX7 VALUE:3200 mV changing metadata
ERROR [2041-07-09 01:03] ID:BAD1 VALUE:9 V must be ignored
[2041-07-09 01:04] ID:N2 VALUE:-0.75 V trailing text
WARNING: ID:BAD2 VALUE:2 V
[2041-07-09 01:05] ID:BROKEN VALUE:not-a-number V
[2041-07-09 01:06] ID:M3 VALUE:12 mV
[2041-07-09 01:07] ID:U8 VALUE:4 kV unsupported unit
"""
    template = "# Verification Report\nAudit records: {{COUNT}}\nEnd of report.\n"

    try:
        paths[0].write_text(changed_log)
        paths[1].write_text(template)

        result = subprocess.run(
            ["/home/user/process.sh"], cwd="/home/user", text=True,
            capture_output=True, timeout=20, check=False
        )
        assert result.returncode == 0, f"process.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

        expected_csv = [
            f"{ident},{calibrated(value, unit)}"
            for ident, value, unit in records
        ]
        actual_csv = paths[2].read_text().splitlines()
        assert actual_csv == expected_csv, f"Pipeline output is incorrect: expected {expected_csv}, got {actual_csv}"

        expected_report = template.replace("{{COUNT}}", str(len(records)))
        actual_report = paths[3].read_text()
        assert actual_report == expected_report, f"Report was not generated from the changed template: {actual_report!r}"
        assert "{{COUNT}}" not in actual_report
    finally:
        for path, data in backups.items():
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
