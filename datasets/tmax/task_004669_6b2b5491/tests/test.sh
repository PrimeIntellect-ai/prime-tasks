#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess


def get_expected_values():
    data_file = "/home/user/etl_data.csv"
    assert os.path.exists(data_file), f"Input file {data_file} is missing."

    records = []
    with open(data_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            records.append(row)

    # Sort chronologically by timestamp
    records.sort(key=lambda x: x['timestamp'])

    # Deduplicate by record_id (keep first occurrence)
    seen_ids = set()
    deduped = []
    for r in records:
        if r['record_id'] not in seen_ids:
            seen_ids.add(r['record_id'])
            deduped.append(r)

    # Forward fill missing sensor_values and compute metrics
    total_sum = 0.0
    anomalies = 0
    last_val = None

    for r in deduped:
        val_str = r['sensor_value'].strip()
        if val_str:
            val = float(val_str)
            last_val = val
        else:
            val = last_val

        total_sum += val
        if val > 100.0:
            anomalies += 1

    avg = total_sum / len(deduped) if deduped else 0.0
    avg_rounded = f"{avg:.2f}"
    return avg_rounded, anomalies


def run_script():
    script_path = "/home/user/process_etl.sh"
    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_current_report_matches_template():
    report_path = "/home/user/final_report.txt"
    assert os.path.exists(report_path), f"Final report {report_path} does not exist."

    avg_val, anomaly_count = get_expected_values()

    template_path = "/home/user/report_template.txt"
    assert os.path.exists(template_path), f"Template {template_path} is missing."
    with open(template_path, 'r') as f:
        template = f.read()

    expected_report = template.replace("{{AVG_VALUE}}", str(avg_val)).replace(
        "{{ANOMALY_COUNT}}", str(anomaly_count)
    )
    with open(report_path, 'r') as f:
        actual_report = f.read()

    assert actual_report.strip() == expected_report.strip(), (
        f"Content of {report_path} is incorrect.\n"
        f"Expected:\n{expected_report}\nGot:\n{actual_report}"
    )


def test_01_process_etl_script_exists_and_executable():
    script_path = "/home/user/process_etl.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_02_final_report_content_after_execution():
    report_path = "/home/user/final_report.txt"
    if os.path.lexists(report_path):
        os.remove(report_path)
    run_script()
    assert_current_report_matches_template()


def test_03_script_processes_unseen_input_and_template():
    data_path = "/home/user/etl_data.csv"
    template_path = "/home/user/report_template.txt"
    report_path = "/home/user/final_report.txt"

    with open(data_path, "rb") as f:
        original_data = f.read()
    with open(template_path, "rb") as f:
        original_template = f.read()
    report_existed = os.path.exists(report_path)
    original_report = None
    if report_existed:
        with open(report_path, "rb") as f:
            original_report = f.read()

    token = secrets.token_hex(8)
    low = secrets.randbelow(31) + 10
    high = secrets.randbelow(40) + 111
    tail = secrets.randbelow(31) + 50
    ids = [f"{token}_{n}" for n in range(1, 7)]

    # The later duplicate is deliberately placed before its earlier occurrence
    # in file order, so correct chronological sorting is required.
    rows = [
        ["2042-07-19T08:04:00", ids[1], "999.0"],
        ["2042-07-19T08:03:00", ids[3], f"{high}.0"],
        ["2042-07-19T08:01:00", ids[1], ""],
        ["2042-07-19T08:06:00", ids[5], f"{tail}.0"],
        ["2042-07-19T08:00:00", ids[0], f"{low}.0"],
        ["2042-07-19T08:05:00", ids[4], ""],
        ["2042-07-19T08:02:00", ids[2], "100.0"],
        ["2042-07-19T08:07:00", ids[3], "1.0"],
    ]
    template = (
        f"Unseen ETL run {token}\n"
        "Computed average={{AVG_VALUE}}\n"
        "Computed anomalies={{ANOMALY_COUNT}}\n"
    )

    try:
        with open(data_path, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "record_id", "sensor_value"])
            writer.writerows(rows)
        with open(template_path, "w") as f:
            f.write(template)
        if os.path.lexists(report_path):
            os.remove(report_path)

        run_script()
        assert_current_report_matches_template()
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        with open(template_path, "wb") as f:
            f.write(original_template)
        if report_existed:
            with open(report_path, "wb") as f:
                f.write(original_report)
        elif os.path.lexists(report_path):
            os.remove(report_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
