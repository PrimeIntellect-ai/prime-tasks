#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
import unicodedata
import zipfile

import pytest

HOME = "/home/user"
HEADER = ["EventID", "Date", "Node", "Log_EN", "Log_ZH", "Log_RU"]
LONG_HEADER = ["EventID", "Date", "Node", "Language", "Message"]


def run_pipeline(mode):
    result = subprocess.run(
        [os.path.join(HOME, "pipeline.sh"), mode],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"pipeline.sh {mode} failed:\n{result.stdout}"


def read_archive_rows():
    with zipfile.ZipFile(os.path.join(HOME, "raw_logs.zip"), "r") as zf:
        with zf.open("raw_logs.csv", "r") as raw:
            text = (line.decode("utf-8") for line in raw)
            rows = list(csv.reader(text))
    assert rows and rows[0] == HEADER, "Archived input CSV header is incorrect"
    return rows


def expected_results(wide_rows):
    assert wide_rows and wide_rows[0] == HEADER
    long_rows = []
    multiline_by_node = {}
    nodes = set()

    for row in wide_rows[1:]:
        assert len(row) == 6, f"Malformed input row: {row!r}"
        event_id, date, node = row[:3]
        nodes.add(node)
        for language, message in zip(("EN", "ZH", "RU"), row[3:]):
            if message != "":
                message = unicodedata.normalize("NFC", message)
                long_rows.append([event_id, date, node, language, message])
                if "\n" in message:
                    multiline_by_node[node] = multiline_by_node.get(node, 0) + 1

    multiline_count = sum(multiline_by_node.values())
    if nodes:
        max_count = max(multiline_by_node.get(node, 0) for node in nodes)
        top_node = sorted(node for node in nodes if multiline_by_node.get(node, 0) == max_count)[0]
    else:
        top_node = ""

    report_lines = [
        f"Total Events Processed: {len(wide_rows) - 1}",
        f"Total Long Records: {len(long_rows)}",
        f"Multiline Messages: {multiline_count}",
        f"Node with most multiline messages: {top_node}",
    ]
    return long_rows, report_lines


def assert_outputs_match(wide_rows):
    expected_rows, expected_report = expected_results(wide_rows)

    csv_path = os.path.join(HOME, "reshaped_logs.csv")
    assert os.path.isfile(csv_path), "reshaped_logs.csv is missing"
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        actual = list(csv.reader(f))
    assert actual, "reshaped_logs.csv is empty"
    assert actual[0] == LONG_HEADER, "CSV header is incorrect"
    assert actual[1:] == expected_rows, "Long-format records do not exactly match the input CSV"
    for row in actual[1:]:
        assert len(row) == 5, f"Malformed long-format row: {row!r}"
        assert row[4] == unicodedata.normalize("NFC", row[4]), "Message is not NFC-normalized"

    report_path = os.path.join(HOME, "report.txt")
    assert os.path.isfile(report_path), "report.txt is missing"
    with open(report_path, "r", encoding="utf-8") as f:
        report = f.read()
    assert report.splitlines() == expected_report, "Report does not exactly summarize the generated records"


def remove_artifacts(*names):
    for name in names:
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            os.remove(path)


def test_00_execute_pipeline_and_check_dynamic_input():
    archive_rows = read_archive_rows()

    # Exercise each individual DAG action from the state it is responsible for creating.
    remove_artifacts("raw_logs.csv")
    run_pipeline("extract")
    with open(os.path.join(HOME, "raw_logs.csv"), "r", encoding="utf-8", newline="") as f:
        assert list(csv.reader(f)) == archive_rows, "extract did not reproduce the archived CSV"

    remove_artifacts("analyzer")
    run_pipeline("build")
    assert os.path.isfile(os.path.join(HOME, "analyzer")), "build did not create analyzer"
    assert os.access(os.path.join(HOME, "analyzer"), os.X_OK), "built analyzer is not executable"

    remove_artifacts("reshaped_logs.csv", "report.txt")
    run_pipeline("run")
    assert_outputs_match(archive_rows)

    # Use unpredictable records to reject hard-coded/fabricated outputs and verify
    # embedded newlines, empty entries, NFC normalization, counts, and tie-breaking.
    token = secrets.token_hex(12)
    node_a = "A-" + secrets.token_hex(5)
    node_b = "B-" + secrets.token_hex(5)
    probe_rows = [
        HEADER,
        ["id-" + token, "2042-01-01", node_b, "Cafe\u0301\n" + token, "", "RU-" + token],
        ["id2-" + token, "2042-01-02", node_a, "Line\n" + token, "A\u030a-" + token, ""],
        ["id3-" + token, "2042-01-03", node_b, "", "", ""],
    ]

    try:
        with open(os.path.join(HOME, "raw_logs.csv"), "w", encoding="utf-8", newline="") as f:
            csv.writer(f).writerows(probe_rows)
        remove_artifacts("reshaped_logs.csv", "report.txt")
        run_pipeline("run")
        assert_outputs_match(probe_rows)
    finally:
        # Restore the requested final state and exercise the all action itself.
        remove_artifacts("raw_logs.csv", "analyzer", "reshaped_logs.csv", "report.txt")
        run_pipeline("all")

    assert_outputs_match(archive_rows)


def test_pipeline_script_exists():
    assert os.path.exists("/home/user/pipeline.sh"), "pipeline.sh is missing"
    assert os.access("/home/user/pipeline.sh", os.X_OK), "pipeline.sh is not executable"


def test_analyzer_go_exists():
    assert os.path.exists("/home/user/analyzer.go"), "analyzer.go is missing"


def test_analyzer_executable_exists():
    assert os.path.exists("/home/user/analyzer"), "Compiled analyzer executable is missing"
    assert os.access("/home/user/analyzer", os.X_OK), "analyzer is not executable"


def test_raw_logs_csv_extracted():
    assert os.path.exists("/home/user/raw_logs.csv"), "raw_logs.csv was not extracted"


def test_reshaped_logs_csv():
    csv_path = "/home/user/reshaped_logs.csv"
    assert os.path.exists(csv_path), f"{csv_path} is missing"

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["EventID", "Date", "Node", "Language", "Message"], "CSV header is incorrect"

        rows = list(reader)
        assert len(rows) == 14, f"Expected 14 long records, but found {len(rows)}"

        multiline_beta = [r for r in rows if r[2] == "Beta" and r[3] == "EN" and "\n" in r[4]]
        assert len(multiline_beta) >= 1, "Multiline message for Beta(EN) not found or newline not preserved"


def test_report_txt():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"{report_path} is missing"

    with open(report_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert re.search(r"Total Events Processed:\s*7", content), "Total Events Processed should be 7"
    assert re.search(r"Total Long Records:\s*14", content), "Total Long Records should be 14"
    assert re.search(r"Multiline Messages:\s*5", content), "Multiline Messages should be 5"
    assert re.search(r"Node with most multiline messages:\s*Beta", content), "Node with most multiline messages should be Beta"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
