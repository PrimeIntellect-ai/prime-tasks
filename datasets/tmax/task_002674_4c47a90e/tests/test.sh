#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import csv
import json
import os
import re
import secrets
import subprocess
from datetime import datetime

RAW_CSV = "/home/user/raw_sensors.csv"
CLEAN_CSV = "/home/user/clean_sensors.csv"
LOG_FILE = "/home/user/cleaning_pipeline.log"
REPORT_FILE = "/home/user/report.md"
TEMPLATE_FILE = "/home/user/report_template.txt"
MANIFEST = "/home/user/pipeline/Cargo.toml"
SOURCE_DIR = "/home/user/pipeline/src"
ARTIFACTS = [RAW_CSV, CLEAN_CSV, LOG_FILE, REPORT_FILE, TEMPLATE_FILE]
DECIMAL_RE = re.compile(r"^-?\d+\.\d{2}$")


def process_data(raw_path=RAW_CSV):
    if not os.path.exists(raw_path):
        return [], [], 0, 0, 0, 0.0

    valid_rows = []
    rejected_logs = []
    total_processed = 0

    with open(raw_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=1):
            total_processed = i
            t_str = row["recorded_at"]
            parsed_time = None
            try:
                parsed_time = datetime.strptime(t_str, "%Y-%m-%dT%H:%M:%SZ").strftime("%Y-%m-%dT%H:%M:%SZ")
            except ValueError:
                try:
                    parsed_time = datetime.strptime(t_str, "%m/%d/%Y %H:%M").strftime("%Y-%m-%dT%H:%M:%SZ")
                except ValueError:
                    pass

            if not parsed_time:
                rejected_logs.append(f"[REJECTED] Row {i}: TIME_PARSE_ERROR")
                continue

            try:
                val = float(row["value"])
            except (ValueError, TypeError):
                rejected_logs.append(f"[REJECTED] Row {i}: PARSE_ERROR")
                continue

            unit = row["unit"].strip().upper()
            if unit == "F":
                val_c = (val - 32) * 5 / 9
            else:
                val_c = val

            val_c_rounded = round(val_c, 2)
            if val_c_rounded < -50.00 or val_c_rounded > 50.00:
                rejected_logs.append(f"[REJECTED] Row {i}: OUT_OF_BOUNDS")
                continue

            valid_rows.append({
                "sensor_id": row["sensor_id"],
                "recorded_at": parsed_time,
                "value_celsius": f"{val_c_rounded:.2f}",
            })

    total_valid = len(valid_rows)
    total_rejected = len(rejected_logs)
    avg_temp = sum(float(r["value_celsius"]) for r in valid_rows) / total_valid if total_valid else 0.0
    return valid_rows, rejected_logs, total_processed, total_valid, total_rejected, avg_temp


def check_outputs(template, expected):
    expected_valid, expected_logs, total_processed, total_valid, total_rejected, avg_temp = expected

    assert os.path.isfile(CLEAN_CSV), f"Missing output file: {CLEAN_CSV}"
    with open(CLEAN_CSV, "r", newline="", encoding="utf-8") as f:
        csv_rows = list(csv.reader(f))
    assert csv_rows, "Clean CSV is empty"
    assert csv_rows[0] == ["sensor_id", "recorded_at", "value_celsius"], \
        f"Expected exact CSV headers sensor_id,recorded_at,value_celsius, got {csv_rows[0]}"

    with open(CLEAN_CSV, "r", newline="", encoding="utf-8") as f:
        dict_reader = csv.DictReader(f)
        assert dict_reader.fieldnames == ["sensor_id", "recorded_at", "value_celsius"]
        actual_rows = list(dict_reader)

    assert len(actual_rows) == len(expected_valid), \
        f"Expected {len(expected_valid)} valid rows in clean CSV, got {len(actual_rows)}"
    for i, (actual, wanted) in enumerate(zip(actual_rows, expected_valid), start=1):
        assert set(actual) == {"sensor_id", "recorded_at", "value_celsius"}
        assert actual["sensor_id"] == wanted["sensor_id"], \
            f"Row {i}: expected sensor_id {wanted['sensor_id']}, got {actual['sensor_id']}"
        assert actual["recorded_at"] == wanted["recorded_at"], \
            f"Row {i}: expected recorded_at {wanted['recorded_at']}, got {actual['recorded_at']}"
        assert DECIMAL_RE.fullmatch(actual["value_celsius"] or ""), \
            f"Row {i}: value_celsius must have exactly two decimal places, got {actual['value_celsius']!r}"
        actual_val = float(actual["value_celsius"])
        expected_val = float(wanted["value_celsius"])
        assert abs(actual_val - expected_val) < 0.01, \
            f"Row {i}: expected value_celsius {expected_val}, got {actual_val}"

    assert os.path.isfile(LOG_FILE), f"Missing output file: {LOG_FILE}"
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        actual_logs = [line.strip() for line in f if line.strip()]
    assert len(actual_logs) == len(expected_logs), \
        f"Expected {len(expected_logs)} logs, got {len(actual_logs)}"
    for i, (actual, wanted) in enumerate(zip(actual_logs, expected_logs), start=1):
        assert actual == wanted, f"Log line {i} mismatch. Expected '{wanted}', got '{actual}'"

    assert os.path.isfile(REPORT_FILE), f"Missing output file: {REPORT_FILE}"
    expected_report = template.replace("{{TOTAL_PROCESSED}}", str(total_processed)) \
                              .replace("{{TOTAL_VALID}}", str(total_valid)) \
                              .replace("{{TOTAL_REJECTED}}", str(total_rejected)) \
                              .replace("{{AVG_TEMP_C}}", f"{avg_temp:.2f}")
    with open(REPORT_FILE, "r", encoding="utf-8") as f:
        actual_report = f.read()
    assert actual_report.strip() == expected_report.strip(), \
        f"Report content mismatch. Expected:\n{expected_report.strip()}\n\nGot:\n{actual_report.strip()}"


def check_original_assertions():
    assert os.path.exists(TEMPLATE_FILE), f"Missing template file: {TEMPLATE_FILE}"
    with open(TEMPLATE_FILE, "r", encoding="utf-8") as f:
        template = f.read()
    check_outputs(template, process_data())


def build_rust_binary():
    assert os.path.isfile(MANIFEST), f"Missing Rust Cargo manifest: {MANIFEST}"
    assert os.path.isdir(SOURCE_DIR), f"Missing Rust source directory: {SOURCE_DIR}"

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", MANIFEST],
        cwd="/home/user/pipeline", text=True, capture_output=True, timeout=60,
    )
    assert metadata_run.returncode == 0, f"cargo metadata failed:\n{metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    manifest_real = os.path.realpath(MANIFEST)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert packages, "Cargo manifest does not define a package"
    package = packages[0]
    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Cargo package has no Rust binary target"

    default_run = package.get("default_run")
    if default_run:
        selected = next((t for t in bins if t["name"] == default_run), None)
    else:
        selected = next((t for t in bins if t["name"] == package["name"]), None)
        if selected is None and len(bins) == 1:
            selected = bins[0]
    assert selected is not None, "Unable to identify the application's default Rust binary"
    assert selected["src_path"].endswith(".rs") and os.path.isfile(selected["src_path"]), \
        "Rust binary source file is missing"

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", MANIFEST, "--bin", selected["name"], "--message-format=json"],
        cwd="/home/user/pipeline", text=True, capture_output=True, timeout=180,
    )
    assert build.returncode == 0, f"Rust application failed to compile:\n{build.stderr}\n{build.stdout}"

    executable = None
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (message.get("reason") == "compiler-artifact"
                and message.get("target", {}).get("name") == selected["name"]
                and message.get("executable")):
            executable = message["executable"]
    assert executable and os.path.isfile(executable), "Cargo did not produce the expected executable"
    assert os.access(executable, os.X_OK), "Compiled Rust artifact is not executable"
    return executable


def write_fixture(rows, template):
    with open(RAW_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["sensor_id", "recorded_at", "value", "unit"])
        writer.writerows(rows)
    with open(TEMPLATE_FILE, "w", encoding="utf-8") as f:
        f.write(template)
    for path in (CLEAN_CSV, LOG_FILE, REPORT_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_dynamic_cases(executable):
    nonce = secrets.token_hex(8)
    day = 3 + secrets.randbelow(20)
    hour = secrets.randbelow(20)
    c_value = 5 + secrets.randbelow(30) + 0.137
    f_value = 41 + secrets.randbelow(45)

    cases = [
        ([
            [f"A-{nonce}", f"2024-11-{day:02d}T{hour:02d}:07:00Z", f"{f_value}.0", "F"],
            [f"B-{nonce}", f"11/{day:02d}/2024 {hour:02d}:31", f"{c_value:.3f}", "C"],
            [f"C-{nonce}", "NOT_A_TIME", "ERR", "C"],
            [f"D-{nonce}", f"11/{day:02d}/2024 22:15", "ERR", "C"],
            [f"E-{nonce}", "2024-11-20T10:00:00Z", "212", "F"],
            [f"F-{nonce}", "2024-11-20T11:00:00Z", "-50", "C"],
            [f"G-{nonce}", "2024-11-20T12:00:00Z", "50", "C"],
            [f"H-{nonce}", "2024-11-20T13:00:00Z", "-50.02", "C"],
        ], f"Dynamic report {nonce}\nProcessed={{TOTAL_PROCESSED}}\nValid={{TOTAL_VALID}}\nRejected={{TOTAL_REJECTED}}\nAverage={{AVG_TEMP_C}}\n"),
        ([
            [f"X-{nonce}", "2025-01-02T03:04:05Z", "32", "F"],
            [f"Y-{nonce}", "01/03/2025 04:05", "18.764", "C"],
            [f"Z-{nonce}", "01/04/2025 05:06", "", "C"],
            [f"Q-{nonce}", "BAD", "999", "F"],
            [f"R-{nonce}", "2025-01-06T07:08:09Z", "130", "F"],
        ], f"{nonce}: {{TOTAL_VALID}} of {{TOTAL_PROCESSED}}; bad={{TOTAL_REJECTED}}; avg={{AVG_TEMP_C}}\n"),
    ]

    for rows, template in cases:
        write_fixture(rows, template)
        expected = process_data()
        run = subprocess.run(
            [executable], cwd="/home/user/pipeline", text=True,
            capture_output=True, timeout=30,
        )
        assert run.returncode == 0, \
            f"Compiled Rust application failed when executed:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
        check_outputs(template, expected)


def main():
    snapshots = {}
    for path in ARTIFACTS:
        snapshots[path] = open(path, "rb").read() if os.path.exists(path) else None

    try:
        check_original_assertions()
        executable = build_rust_binary()
        run_dynamic_cases(executable)
    finally:
        for path, content in snapshots.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
