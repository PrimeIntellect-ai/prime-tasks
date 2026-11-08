#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import string
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
REPORT_PATH = "/home/user/report.html"
APP_PATH = "/home/user/logs/app.json"
SYS_PATH = "/home/user/logs/sys.csv"
TEMPLATE_PATH = "/home/user/template.html"


def run_script():
    subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=20,
    )


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_report_html_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist"


def test_report_html_content():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist"

    with open(REPORT_PATH, "r") as f:
        content = f.read()

    assert "__TABLE_ROWS__" not in content, "Placeholder __TABLE_ROWS__ was not replaced in the report"

    expected_rows = [
        "<tr><td>2023-10-01_10</td><td>ERR-001</td><td>3</td></tr>",
        "<tr><td>2023-10-01_10</td><td>ERR-002</td><td>1</td></tr>",
        "<tr><td>2023-10-01_11</td><td>ERR-002</td><td>2</td></tr>"
    ]

    for row in expected_rows:
        assert row in content.replace(" ", ""), f"Expected row {row} not found in {REPORT_PATH}"

    content_no_spaces = content.replace(" ", "")
    pos1 = content_no_spaces.find(expected_rows[0])
    pos2 = content_no_spaces.find(expected_rows[1])
    pos3 = content_no_spaces.find(expected_rows[2])

    assert pos1 != -1 and pos2 != -1 and pos3 != -1, "Not all expected rows were found"
    assert pos1 < pos2 < pos3, "The generated rows are not sorted correctly by HOUR and ERROR_CODE"


def test_script_regenerates_exact_report_from_new_inputs():
    codes = [f"ERR-{n:03d}" for n in secrets.SystemRandom().sample(range(100, 1000), 3)]
    c1, c2, c3 = codes
    nonce = ''.join(secrets.choice(string.ascii_letters) for _ in range(20))

    app_entries = [
        {"timestamp": "2024-02-03T09:02:00Z", "level": "ERROR", "message": f"App first [{c2}] happened"},
        {"timestamp": "2024-02-03T09:58:00Z", "level": "ERROR", "message": f"App repeat [{c2}] happened"},
        {"timestamp": "2024-02-03T10:01:00Z", "level": "ERROR", "message": f"App event [{c3}] happened"},
        {"timestamp": "2024-02-03T11:20:00Z", "level": "ERROR", "message": f"App event [{c1}] happened"},
        {"timestamp": "2024-02-03T09:03:00Z", "level": "INFO", "message": f"Ignore [{c1}]"},
        {"timestamp": "2024-02-03T10:03:00Z", "level": "ERROR ", "message": f"Ignore [{c1}]"},
    ]
    sys_entries = [
        ["2024-02-03 09:05:00", "ERROR", f"System event [{c1}]"],
        ["2024-02-03 10:15:00", "ERROR", f"System event [{c2}]"],
        ["2024-02-03 10:25:00", "ERROR", f"System repeat [{c2}]"],
        ["2024-02-03 10:35:00", "ERROR", f"System event [{c3}]"],
        ["2024-02-03 11:45:00", "ERROR", f"System event [{c1}]"],
        ["2024-02-03 09:10:00", "WARNING", f"Ignore [{c3}]"],
    ]

    with open(APP_PATH, "w") as f:
        for entry in app_entries:
            f.write(json.dumps(entry) + "\n")
    with open(SYS_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(sys_entries)

    template = (
        f"<!doctype html>\n<html><head><title>{nonce}</title></head>\n"
        f"<body><h2 data-token=\"{nonce}\">Dynamic report</h2>\n"
        "<table>\n<tr><th>Hour</th><th>Error Code</th><th>Count</th></tr>\n"
        "__TABLE_ROWS__\n"
        f"</table><footer>{nonce}</footer></body></html>\n"
    )
    with open(TEMPLATE_PATH, "w") as f:
        f.write(template)

    counts = Counter()
    for entry in app_entries:
        if entry["level"] == "ERROR":
            code = re.search(r"\[([^\]]+)\]", entry["message"]).group(1)
            counts[(entry["timestamp"][:13].replace("T", "_"), code)] += 1
    for timestamp, level, message in sys_entries:
        if level == "ERROR":
            code = re.search(r"\[([^\]]+)\]", message).group(1)
            counts[(timestamp[:13].replace(" ", "_"), code)] += 1

    expected_rows = [
        f"<tr><td>{hour}</td><td>{code}</td><td>{count}</td></tr>"
        for (hour, code), count in sorted(counts.items())
    ]

    run_script()
    assert os.path.isfile(REPORT_PATH), "The script did not create report.html"
    with open(REPORT_PATH, "r") as f:
        report = f.read()

    assert "__TABLE_ROWS__" not in report
    prefix, suffix = template.split("__TABLE_ROWS__")
    assert report.startswith(prefix), "Content before the template placeholder was changed"
    assert report.endswith(suffix), "Content after the template placeholder was changed"
    middle = report[len(prefix):len(report) - len(suffix)]

    row_pattern = re.compile(r"<tr><td>([^<]*)</td><td>([^<]*)</td><td>([^<]*)</td></tr>")
    actual_rows = [match.group(0) for match in row_pattern.finditer(middle)]
    leftover = row_pattern.sub("", middle)
    assert not leftover.strip(), "Unexpected content or malformed table rows were generated"
    assert actual_rows == expected_rows, "Rows were missing, extra, incorrectly counted, or incorrectly sorted"


# Regenerate the original report before retaining the original report assertions.
run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
