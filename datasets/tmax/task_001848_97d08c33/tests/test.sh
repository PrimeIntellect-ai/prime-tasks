#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import subprocess
import csv
from pathlib import Path
from collections import defaultdict

PACKAGE = Path("/app/fastlog_etl-1.0.0")
SOURCE = PACKAGE / "src/process.c"
MAKEFILE = PACKAGE / "Makefile"
BINARY = PACKAGE / "bin/fastlog_etl"
INPUT = Path("/home/user/api_logs.csv")
SUMMARY = Path("/home/user/summary.csv")
REPORT = Path("/home/user/report.html")


def expected_rows():
    endpoints_data = defaultdict(lambda: {"count": 0, "total_latency": 0})
    with INPUT.open("r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 3:
                ep = parts[1]
                lat = int(parts[2])
                endpoints_data[ep]["count"] += 1
                endpoints_data[ep]["total_latency"] += lat

    rows = []
    for ep in sorted(endpoints_data.keys()):
        count = endpoints_data[ep]["count"]
        avg_lat = endpoints_data[ep]["total_latency"] // count
        rows.append((ep, count, avg_lat))
    return rows


def expected_csv_text():
    return "".join(f"{ep},{count},{avg}\n" for ep, count, avg in expected_rows())


def expected_html_text():
    lines = [
        "<html>",
        "<body>",
        "  <h1>ETL Pipeline Report</h1>",
        "  <ul>",
    ]
    lines.extend(
        f"    <li>Endpoint: {ep} | Count: {count} | Avg Latency: {avg}ms</li>"
        for ep, count, avg in expected_rows()
    )
    lines.extend(["  </ul>", "</body>", "</html>"])
    return "\n".join(lines) + "\n"


def strip_c_comments_and_literals(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"'(?:\\.|[^'\\])*'", "''", text)
    return text


def test_source_makefile_and_rebuild():
    assert SOURCE.is_file(), f"Source file not found at {SOURCE}"
    assert MAKEFILE.is_file(), f"Makefile not found at {MAKEFILE}"

    source = strip_c_comments_and_literals(SOURCE.read_text())
    assert re.search(r"\bqsort\s*\(\s*records\s*,\s*(?:\([^)]*\)\s*)?count\b", source), (
        "src/process.c must sort the records with the standard-library qsort"
    )
    assert not re.search(r"\bbubble_sort\b", source), (
        "src/process.c still contains or calls bubble_sort"
    )
    assert not re.search(r"^\s*#\s*define\s+qsort\b", source, flags=re.M), (
        "qsort must not be replaced by a macro"
    )

    makefile = MAKEFILE.read_text()
    assert re.search(r"(?<!\S)-O3(?!\S)", makefile), "Makefile does not enable -O3"
    assert not re.search(r"(?<!\S)-O0(?!\S)", makefile), "Makefile still enables -O0"

    clean = subprocess.run(
        ["make", "clean"], cwd=PACKAGE, capture_output=True, text=True
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = subprocess.run(
        ["make", "all"], cwd=PACKAGE, capture_output=True, text=True
    )
    build_output = build.stdout + build.stderr
    assert build.returncode == 0, f"Rebuild failed:\n{build_output}"
    assert re.search(r"(?<!\S)-O3(?!\S)", build_output), (
        f"The actual compiler command did not use -O3:\n{build_output}"
    )
    assert not re.search(r"(?<!\S)-O0(?!\S)", build_output), (
        f"The actual compiler command used -O0:\n{build_output}"
    )
    assert BINARY.is_file(), f"Binary not found at {BINARY} after rebuilding"
    assert os.access(BINARY, os.X_OK), f"Binary is not executable: {BINARY}"
    with BINARY.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "fastlog_etl is not an ELF executable"


def test_execution_time():
    binary_path = str(BINARY)
    input_path = str(INPUT)

    assert os.path.exists(binary_path), f"Binary not found at {binary_path}"
    assert os.path.exists(input_path), f"Input file not found at {input_path}"

    start_time = time.perf_counter()
    with open(input_path, "r") as f:
        result = subprocess.run([binary_path], stdin=f, capture_output=True, text=True)
    end_time = time.perf_counter()

    assert result.returncode == 0, f"Binary execution failed with stderr: {result.stderr}"
    assert result.stdout == expected_csv_text(), (
        "fastlog_etl output does not contain the correctly sorted aggregation"
    )

    execution_time = end_time - start_time
    threshold = 1.5
    assert execution_time <= threshold, (
        f"Execution time {execution_time:.3f}s exceeds threshold of {threshold}s. "
        "Ensure qsort is used and -O3 optimization is enabled."
    )
    assert execution_time < 1.0, (
        f"Execution time {execution_time:.3f}s is not strictly under 1.0 second"
    )


def test_pipeline_log():
    log_path = "/home/user/pipeline.log"
    assert os.path.exists(log_path), f"Log file not found at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[INFO] ETL extraction completed successfully.",
        "[INFO] HTML report generated."
    ]

    assert lines == expected_lines, f"Expected pipeline.log to contain exactly {expected_lines}, but got {lines}"
    expected_log = "\n".join(expected_lines) + "\n"
    assert Path(log_path).read_text() == expected_log, (
        "pipeline.log must contain exactly the two required lines and no extra content"
    )


def test_report_generating_script():
    candidates = []
    for root in (Path("/home/user"), PACKAGE):
        for path in root.rglob("*"):
            if not path.is_file() or path in {INPUT, SUMMARY, REPORT, SOURCE, MAKEFILE, BINARY}:
                continue
            try:
                text = path.read_text()
            except (UnicodeDecodeError, OSError):
                continue
            first_line = text.splitlines()[0] if text.splitlines() else ""
            if (path.suffix == ".sh" or re.search(r"^#!.*\b(?:ba)?sh\b", first_line)) and re.search(r"\b(?:g?awk)\b", text):
                candidates.append(path)

    assert candidates, "No Bash/AWK report-generating script was found"

    wanted_csv = expected_csv_text()
    wanted_html = expected_html_text()
    errors = []
    generated = False
    for script in candidates:
        SUMMARY.write_text(wanted_csv)
        if REPORT.exists():
            REPORT.unlink()
        result = subprocess.run(
            ["bash", str(script)], cwd=script.parent, capture_output=True, text=True,
            timeout=10
        )
        if result.returncode == 0 and REPORT.is_file() and REPORT.read_text() == wanted_html:
            generated = True
            break
        errors.append(f"{script}: exit={result.returncode}, stderr={result.stderr.strip()}")

    assert generated, (
        "No submitted Bash/AWK script generated the required exact HTML report. "
        + "; ".join(errors)
    )


def test_summary_csv_and_html_report():
    input_path = "/home/user/api_logs.csv"
    summary_path = "/home/user/summary.csv"
    report_path = "/home/user/report.html"

    assert os.path.exists(summary_path), f"Summary CSV not found at {summary_path}"
    assert os.path.exists(report_path), f"HTML report not found at {report_path}"

    endpoints_data = defaultdict(lambda: {"count": 0, "total_latency": 0})
    with open(input_path, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 3:
                ep = parts[1]
                lat = int(parts[2])
                endpoints_data[ep]["count"] += 1
                endpoints_data[ep]["total_latency"] += lat

    expected_summary = []
    for ep in sorted(endpoints_data.keys()):
        count = endpoints_data[ep]["count"]
        avg_lat = endpoints_data[ep]["total_latency"] // count
        expected_summary.append((ep, count, avg_lat))

    actual_summary = []
    with open(summary_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 3:
                actual_summary.append((row[0], int(row[1]), int(row[2])))

    assert actual_summary == expected_summary, f"Summary CSV contents {actual_summary} do not match expected {expected_summary}"
    assert Path(summary_path).read_text() == expected_csv_text(), (
        "summary.csv must exactly match the optimized binary's raw CSV output"
    )

    with open(report_path, "r") as f:
        html_content = f.read()

    assert "<html>" in html_content and "</html>" in html_content, "HTML report missing <html> tags"
    assert "<body>" in html_content and "</body>" in html_content, "HTML report missing <body> tags"
    assert "<h1>ETL Pipeline Report</h1>" in html_content, "HTML report missing expected <h1> header"
    assert "<ul>" in html_content and "</ul>" in html_content, "HTML report missing <ul> tags"

    for ep, count, avg_lat in expected_summary:
        expected_li = f"<li>Endpoint: {ep} | Count: {count} | Avg Latency: {avg_lat}ms</li>"
        assert expected_li in html_content, f"HTML report missing expected list item: {expected_li}"

    assert html_content == expected_html_text(), (
        "HTML report does not exactly match the required template structure"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
