#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import subprocess
import sys
from datetime import datetime

SCRIPT_PATH = "/home/user/analyze_metrics.py"
CSV_PATH = "/home/user/data/metrics.csv"
REPORT_PATH = "/home/user/anomaly_report.md"


def get_time_of_day(dt_str):
    dt = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%SZ")
    hour = dt.hour
    if 6 <= hour < 12:
        return "Morning"
    elif 12 <= hour < 18:
        return "Afternoon"
    return "Night"


def compute_expected_anomalies(csv_path):
    with open(csv_path, "r", newline="") as f:
        rows = list(csv.DictReader(f))

    rows.sort(key=lambda x: x["timestamp"])
    servers = {}
    anomalies = []

    for row in rows:
        srv = row["server_id"]
        cpu = float(row["cpu_usage"])
        ts = row["timestamp"]
        tod = get_time_of_day(ts)
        servers.setdefault(srv, []).append(cpu)
        window = servers[srv][-4:]
        mean = sum(window) / len(window)
        if len(window) < 2:
            std = 0.0
        else:
            variance = sum((x - mean) ** 2 for x in window) / (len(window) - 1)
            std = math.sqrt(variance)

        if cpu > mean + 1.5 * std and cpu > 80.0:
            anomalies.append({
                "timestamp": ts,
                "server_id": srv,
                "cpu_usage": round(cpu, 1),
                "time_of_day": tod,
            })
    return anomalies


def expected_report(anomalies):
    lines = [
        "# Server Anomaly Report",
        "",
        f"## Total Anomalies Detected: {len(anomalies)}",
        "",
        "## Anomaly Details",
        "| Timestamp | Server ID | CPU Usage | Time of Day |",
        "|-----------|-----------|-----------|-------------|",
    ]
    for anomaly in anomalies:
        lines.append(
            f"| {anomaly['timestamp']} | {anomaly['server_id']} | "
            f"{anomaly['cpu_usage']:.1f} | {anomaly['time_of_day']} |"
        )
    return "\n".join(lines)


def assert_exact_report(csv_path=CSV_PATH):
    expected = expected_report(compute_expected_anomalies(csv_path))
    with open(REPORT_PATH, "r", newline="") as f:
        actual = f.read().replace("\r\n", "\n")
    assert actual in (expected, expected + "\n"), (
        "Report does not exactly match the required Markdown structure.\n"
        f"Expected:\n{expected!r}\nActual:\n{actual!r}"
    )


def run_pipeline_and_require_input_read():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing or not a regular file."
    before = open(CSV_PATH, "rb").read()
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)

    wrapper = r'''
import os
import runpy

wanted = os.path.realpath("/home/user/data/metrics.csv")
seen_read = False

def hook(event, args):
    global seen_read
    if event != "open" or not args:
        return
    try:
        path = os.path.realpath(os.fspath(args[0]))
    except (TypeError, ValueError):
        return
    if path != wanted:
        return
    mode = args[1] if len(args) > 1 else "r"
    flags = args[2] if len(args) > 2 else 0
    if isinstance(mode, str):
        if "r" in mode or "+" in mode:
            seen_read = True
    elif mode is None and isinstance(flags, int):
        if (flags & os.O_ACCMODE) in (os.O_RDONLY, os.O_RDWR):
            seen_read = True

runpy.run_path("/home/user/analyze_metrics.py", run_name="__main__")
if not seen_read:
    raise RuntimeError("analyze_metrics.py did not read /home/user/data/metrics.csv")
'''
    result = subprocess.run(
        [sys.executable, "-c", wrapper],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "Executing analyze_metrics.py failed or it did not read the required input.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Executing the script did not generate anomaly_report.md"
    assert open(CSV_PATH, "rb").read() == before, "The pipeline modified its input CSV"


def test_00_script_exists_and_contains_pipeline_logic():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    source = open(SCRIPT_PATH, "r", encoding="utf-8").read()
    assert source.strip(), "analyze_metrics.py is empty"
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        raise AssertionError(f"analyze_metrics.py is not valid Python: {exc}")

    dump = ast.dump(tree, include_attributes=False).lower()
    names = {
        node.id.lower() for node in ast.walk(tree) if isinstance(node, ast.Name)
    }
    attrs = {
        node.attr.lower() for node in ast.walk(tree) if isinstance(node, ast.Attribute)
    }
    strings = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    all_strings = "\n".join(strings)

    for required in ("timestamp", "server_id", "cpu_usage", "time_of_day"):
        assert required in all_strings or required in names, f"Script does not implement required field {required!r}"
    for label in ("Morning", "Afternoon", "Night"):
        assert label in all_strings, f"Script does not implement the {label} time-of-day label"

    assert ({"sort_values", "sort", "sort_index"} & attrs) or "sorted" in names, \
        "Script contains no chronological sorting operation"
    assert "groupby" in attrs or ({"servers", "history", "window", "windows"} & names), \
        "Script contains no recognizable per-server rolling state/grouping"
    assert "rolling" in attrs or "window" in names or "deque" in names, \
        "Script contains no recognizable rolling-window calculation"
    assert "mean" in attrs or "mean" in names or ("sum" in names and "div" in dump), \
        "Script contains no rolling-mean calculation"
    assert ({"std", "stdev", "pstdev"} & (attrs | names)) or "sqrt" in (attrs | names), \
        "Script contains no standard-deviation calculation"
    assert "ddof" in dump or "stdev" in (attrs | names) or ("sqrt" in dump and "sub" in dump), \
        "Script contains no recognizable sample-standard-deviation calculation"
    assert "constant(value=4" in dump, "Script does not specify the required 4-period window"
    assert "constant(value=1.5" in dump and ("constant(value=80" in dump or "constant(value=80.0" in dump), \
        "Script does not contain both anomaly thresholds"
    assert "gt" in dump and "and" in dump, "Script does not implement both strict anomaly conditions"
    assert ("jinja" in dump or "template" in dump or "render" in dump or
            "joinedstr" in dump or "format" in attrs), \
        "Script contains no recognizable template-based report generation"
    assert "# Server Anomaly Report" in all_strings and "## Anomaly Details" in all_strings, \
        "Script does not contain the required report template"


def test_01_execute_pipeline():
    run_pipeline_and_require_input_read()


def test_anomaly_report_exists_and_correct():
    csv_path = CSV_PATH
    report_path = REPORT_PATH

    assert os.path.exists(csv_path), f"Input data missing at {csv_path}"
    assert os.path.exists(report_path), f"Report missing at {report_path}"

    expected_anomalies = compute_expected_anomalies(csv_path)

    with open(report_path, "r") as f:
        report_content = f.read()

    expected_total_str = f"## Total Anomalies Detected: {len(expected_anomalies)}"
    assert expected_total_str in report_content, f"Report must contain the correct total anomalies count string: '{expected_total_str}'"
    assert "| Timestamp | Server ID | CPU Usage | Time of Day |" in report_content, "Report is missing the correct markdown table headers."
    assert "|-----------|-----------|-----------|-------------|" in report_content, "Report is missing the markdown table separator."

    for anomaly in expected_anomalies:
        lines = report_content.split("\n")
        found = False
        for line in lines:
            if anomaly["timestamp"] in line and anomaly["server_id"] in line and str(anomaly["cpu_usage"]) in line and anomaly["time_of_day"] in line:
                found = True
                break
        assert found, f"Expected anomaly not found in report: {anomaly}"

    assert_exact_report(csv_path)


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."


def test_pipeline_on_independently_derived_probe_input():
    original_csv = open(CSV_PATH, "rb").read()
    probe = b"""timestamp,server_id,cpu_usage,mem_usage
2024-02-01T18:30:00Z,beta,99.0,10.0
2024-02-01T05:00:00Z,alpha,10.0,20.0
2024-02-01T12:00:00Z,alpha,90.0,30.0
2024-02-01T06:00:00Z,beta,15.0,40.0
2024-02-01T17:59:00Z,alpha,20.0,50.0
2024-02-01T11:59:00Z,beta,16.0,60.0
2024-02-01T23:00:00Z,alpha,100.0,70.0
"""
    try:
        with open(CSV_PATH, "wb") as f:
            f.write(probe)
        run_pipeline_and_require_input_read()
        assert_exact_report(CSV_PATH)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        run_pipeline_and_require_input_read()
        assert_exact_report(CSV_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
