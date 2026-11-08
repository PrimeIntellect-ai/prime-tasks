#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import subprocess
from datetime import datetime, timezone, timedelta


def test_c_source_file_exists():
    path = "/home/user/process_logs.c"
    assert os.path.exists(path), f"C source file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a regular file."


def test_c_executable_exists():
    path = "/home/user/process_logs"
    assert os.path.exists(path), f"Compiled executable {path} is missing."
    assert os.path.isfile(path), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"Compiled file {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_csv_output_exists():
    path = "/home/user/sampled_metrics.csv"
    assert os.path.exists(path), f"Output CSV {path} is missing."
    assert os.path.isfile(path), f"{path} is not a regular file."


def expected_rows_from_file(raw_logs_path):
    expected_data = {}
    with open(raw_logs_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split('|')
            if len(parts) < 3:
                continue

            time_str = parts[0].strip()
            region = parts[1].strip()
            message = parts[2].strip()
            dt = datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            epoch = int(dt.timestamp())
            window_epoch = epoch - (epoch % 600)

            cpu_match = re.search(r'CPU:(\d+)%', message)
            if not cpu_match:
                continue
            cpu = int(cpu_match.group(1))

            key = (window_epoch, region)
            if key not in expected_data:
                expected_data[key] = cpu

    return {(str(window_epoch), region, str(cpu))
            for (window_epoch, region), cpu in expected_data.items()}


def assert_csv_matches(csv_path, expected_rows):
    actual_rows = set()
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["WindowEpoch", "Region", "CPU_Percent"], f"CSV header is incorrect. Got: {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"Invalid row format in CSV: {row}"
            actual_rows.add(tuple(row))

    missing = expected_rows - actual_rows
    extra = actual_rows - expected_rows
    error_msg = []
    if missing:
        error_msg.append(f"Missing expected rows: {missing}")
    if extra:
        error_msg.append(f"Unexpected extra rows: {extra}")
    assert not missing and not extra, "\n".join(error_msg)


def test_csv_output_content():
    raw_logs_path = "/home/user/raw_logs.txt"
    csv_path = "/home/user/sampled_metrics.csv"

    assert os.path.exists(raw_logs_path), "Raw logs file missing, cannot compute expected state."
    assert os.path.exists(csv_path), "CSV file missing, cannot verify content."
    assert_csv_matches(csv_path, expected_rows_from_file(raw_logs_path))


def make_generated_input():
    year = 2024 + secrets.randbelow(2)
    month = 1 + secrets.randbelow(12)
    day = 1 + secrets.randbelow(20)
    hour = secrets.randbelow(22)
    base = datetime(year, month, day, hour, 0, 0, tzinfo=timezone.utc)
    dynamic_region = "X" + secrets.token_hex(3).upper()
    records = [
        (7, "JP", "サーバー正常", 1 + secrets.randbelow(98)),
        (83, "JP", "後続の記録", 1 + secrets.randbelow(98)),
        (248, "US", "System operating normally", 1 + secrets.randbelow(98)),
        (599, dynamic_region, "Operación exitosa", 1 + secrets.randbelow(98)),
        (603, "JP", "警告: 高負荷", 1 + secrets.randbelow(98)),
        (742, "JP", "同じ窓の後続", 1 + secrets.randbelow(98)),
        (1177, "ES", "Latencia detectada", 1 + secrets.randbelow(98)),
        (1204, dynamic_region, "Система работает", 1 + secrets.randbelow(98)),
    ]
    lines = []
    for offset, region, message, cpu in records:
        stamp = (base + timedelta(seconds=offset)).strftime("%Y-%m-%d %H:%M:%S")
        lines.append(f"{stamp} | {region} | {message} CPU:{cpu}%\n")
    return ''.join(lines)


def run_generated_case(binary, raw_path, csv_path):
    generated = make_generated_input()
    with open(raw_path, "w", encoding="utf-8") as f:
        f.write(generated)
    expected = expected_rows_from_file(raw_path)
    if os.path.lexists(csv_path):
        os.unlink(csv_path)

    env = os.environ.copy()
    env["TZ"] = "UTC"
    result = subprocess.run([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10, env=env)
    assert result.returncode == 0, (
        f"{binary} failed on generated input with code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(csv_path), f"{binary} did not create {csv_path}."
    assert_csv_matches(csv_path, expected)


def test_executable_and_source_process_unseen_inputs():
    source = "/home/user/process_logs.c"
    executable = "/home/user/process_logs"
    raw_path = "/home/user/raw_logs.txt"
    csv_path = "/home/user/sampled_metrics.csv"
    rebuilt = "/tmp/process_logs_rebuilt"
    held_executable = "/tmp/process_logs_agent_executable"

    compile_result = subprocess.run(
        ["gcc", source, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"C source does not compile with gcc. stdout={compile_result.stdout!r}, "
        f"stderr={compile_result.stderr!r}"
    )
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    with open(raw_path, "rb") as f:
        saved_raw = f.read()
    saved_csv = None
    if os.path.isfile(csv_path):
        with open(csv_path, "rb") as f:
            saved_csv = f.read()

    try:
        # Exercise the submitted executable on data unavailable during the agent run.
        run_generated_case(executable, raw_path, csv_path)

        # Exercise a fresh build from the submitted source while the submitted
        # executable is unavailable, tying the source itself to the behavior.
        if os.path.lexists(held_executable):
            os.unlink(held_executable)
        os.rename(executable, held_executable)
        try:
            run_generated_case(rebuilt, raw_path, csv_path)
        finally:
            if os.path.lexists(executable):
                os.unlink(executable)
            os.rename(held_executable, executable)
    finally:
        with open(raw_path, "wb") as f:
            f.write(saved_raw)
        if saved_csv is None:
            if os.path.lexists(csv_path):
                os.unlink(csv_path)
        else:
            with open(csv_path, "wb") as f:
                f.write(saved_csv)
        if os.path.lexists(rebuilt):
            os.unlink(rebuilt)
        if os.path.lexists(held_executable):
            if os.path.lexists(executable):
                os.unlink(executable)
            os.rename(held_executable, executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
