#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

HOME = Path('/home/user')
SOURCE = HOME / 'finops_report.go'
SCRIPT = HOME / 'run_report.sh'
BINARY = HOME / 'finops_report'
REPORT = HOME / 'report.csv'
LOG = HOME / 'logs/run.log'
STORAGE = HOME / 'cloud_storage'
SUCCESS = 'REPORT_GENERATED_SUCCESSFULLY'


def success_count():
    if not LOG.is_file():
        return 0
    return sum(line.rstrip('\n') == SUCCESS for line in LOG.read_text().splitlines())


def expected_sizes():
    result = {}
    for team_dir in STORAGE.iterdir():
        if not team_dir.is_dir():
            continue
        result[team_dir.name] = sum(
            entry.stat().st_size
            for entry in team_dir.iterdir()
            if entry.is_file()
        )
    return result


def allowed_new_york_timestamps(before, after):
    current = before - timedelta(seconds=2)
    end = after + timedelta(seconds=2)
    allowed = set()
    while current <= end:
        allowed.add(current.astimezone(ZoneInfo('America/New_York')).strftime('%Y-%m-%d %H:%M:%S %Z'))
        current += timedelta(seconds=1)
    return allowed


def validate_report(rate, sizes, before, after):
    assert REPORT.is_file(), 'Report file does not exist.'
    with REPORT.open(newline='') as f:
        rows = list(csv.reader(f))

    assert rows, 'CSV is empty.'
    assert rows[0] == ['Team', 'TotalBytes', 'Cost', 'Timestamp'], f'Incorrect CSV header: {rows[0]}'
    data = rows[1:]
    assert all(len(row) == 4 for row in data), f'Invalid CSV rows: {data}'
    assert [row[0] for row in data] == sorted(sizes), 'CSV must contain every team exactly once in alphabetical order.'
    assert len(data) == len(sizes), 'CSV contains missing or duplicate team rows.'

    allowed_times = allowed_new_york_timestamps(before, after)
    for team, total_bytes, cost, timestamp in data:
        expected_bytes = sizes[team]
        assert total_bytes == str(expected_bytes), f'Incorrect bytes for {team}'
        assert cost == f'{(expected_bytes / 1048576) * rate:.2f}', f'Incorrect cost for {team}'
        assert timestamp in allowed_times, f'Timestamp is not the current America/New_York time: {timestamp}'


def run_wrapper():
    env = os.environ.copy()
    env['TZ'] = 'UTC'
    env['COST_PER_MB'] = '9.99'
    before = datetime.now(timezone.utc)
    proc = subprocess.run([str(SCRIPT)], cwd=str(HOME), env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    after = datetime.now(timezone.utc)
    return proc, before, after


def test_program_and_wrapper_behavior():
    assert SOURCE.is_file(), f'Go source {SOURCE} does not exist.'
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'

    token = secrets.token_hex(8)
    team_a = STORAGE / f'audit_{token}_alpha'
    team_z = STORAGE / f'audit_{token}_zeta'
    team_a.mkdir()
    team_z.mkdir()
    (team_a / 'one.bin').write_bytes(b'A' * 123457)
    (team_a / 'two.bin').write_bytes(b'B' * 76543)
    (team_z / 'asset.bin').write_bytes(b'C' * 234567)
    nested = team_z / 'nested'
    nested.mkdir()
    (nested / 'must_not_be_counted.bin').write_bytes(b'X' * 345678)
    sizes = expected_sizes()

    built = Path('/tmp') / f'finops_report_{token}'
    compile_proc = subprocess.run(
        ['go', 'build', '-o', str(built), str(SOURCE)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert compile_proc.returncode == 0, f'Go source did not compile:\n{compile_proc.stderr}'
    assert built.is_file() and os.access(built, os.X_OK), 'go build did not create an executable.'

    custom_rate = 0.137
    env = os.environ.copy()
    env['COST_PER_MB'] = str(custom_rate)
    env['TZ'] = 'UTC'
    before = datetime.now(timezone.utc)
    direct = subprocess.run([str(built)], cwd=str(HOME), env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    after = datetime.now(timezone.utc)
    assert direct.returncode == 0, f'Compiled Go program failed:\n{direct.stderr}'
    validate_report(custom_rate, sizes, before, after)

    BINARY.unlink(missing_ok=True)
    initial_logs = success_count()
    proc, before, after = run_wrapper()
    assert proc.returncode == 0, f'Wrapper failed:\n{proc.stderr}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Wrapper did not create the required executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'Required compiled executable is not an ELF binary.'
    assert success_count() == initial_logs + 1, 'A successful run must append exactly one success line.'
    validate_report(0.05, sizes, before, after)

    proc, before, after = run_wrapper()
    assert proc.returncode == 0, f'Second wrapper run failed:\n{proc.stderr}'
    assert success_count() == initial_logs + 2, 'The idempotent wrapper must append one line per successful run.'
    validate_report(0.05, sizes, before, after)

    original_source = SOURCE.read_bytes()
    original_mode = SOURCE.stat().st_mode
    before_failure_logs = success_count()
    try:
        SOURCE.write_text('package main\nimport "os"\nfunc main() { os.Exit(7) }\n')
        BINARY.unlink(missing_ok=True)
        subprocess.run([str(SCRIPT)], cwd=str(HOME), env=os.environ.copy(), text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        assert success_count() == before_failure_logs, 'Wrapper logged success when the Go program failed.'
    finally:
        SOURCE.write_bytes(original_source)
        os.chmod(SOURCE, original_mode)

    BINARY.unlink(missing_ok=True)
    proc, before, after = run_wrapper()
    assert proc.returncode == 0, f'Wrapper failed after source restoration:\n{proc.stderr}'
    assert success_count() == before_failure_logs + 1
    validate_report(0.05, sizes, before, after)


def test_run_report_script_executable():
    script_path = "/home/user/run_report.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_run_log_exists_and_content():
    log_path = "/home/user/logs/run.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    assert "REPORT_GENERATED_SUCCESSFULLY" in content, f"Log file {log_path} does not contain 'REPORT_GENERATED_SUCCESSFULLY'."


def test_report_csv_content():
    csv_path = "/home/user/report.csv"
    assert os.path.isfile(csv_path), f"Report file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 4, "CSV file does not contain enough rows (header + 3 teams)."

    header = lines[0]
    assert header == "Team,TotalBytes,Cost,Timestamp", f"Incorrect CSV header: {header}"

    expected_data = {
        "engineering": {"bytes": "15728640", "cost": "0.75"},
        "marketing": {"bytes": "2097152", "cost": "0.10"},
        "sales": {"bytes": "3145728", "cost": "0.15"}
    }

    timestamp_regex = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} (EST|EDT)$")

    actual_teams = []
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 4, f"Invalid CSV row format: {line}"
        team, total_bytes, cost, timestamp = parts
        actual_teams.append(team)

        if team in expected_data:
            assert total_bytes == expected_data[team]["bytes"], f"Incorrect bytes for {team}: expected {expected_data[team]['bytes']}, got {total_bytes}"
            assert cost == expected_data[team]["cost"], f"Incorrect cost for {team}: expected {expected_data[team]['cost']}, got {cost}"
            assert timestamp_regex.match(timestamp), f"Invalid timestamp format for {team}: {timestamp}"

    assert actual_teams == sorted(actual_teams), "CSV rows are not sorted alphabetically by Team name."

    for expected_team in expected_data.keys():
        assert expected_team in actual_teams, f"Team {expected_team} missing from CSV."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
