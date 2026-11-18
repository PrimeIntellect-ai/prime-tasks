#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
from pathlib import Path
import pytest


def test_process_log_exists_and_content():
    log_path = "/home/user/process.log"
    assert os.path.isfile(log_path), f"Missing file: {log_path}"

    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == "Records processed: 9", f"Incorrect content in {log_path}. Expected 'Records processed: 9', got '{content}'"


def test_report_txt_exists_and_content():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Missing file: {report_path}"

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_blocks = [
        "Store: Café Paris (ID: 101)\nMonth: jan_2023 -> Sales: 1500",
        "Store: Café Paris (ID: 101)\nMonth: feb_2023 -> Sales: 1650",
        "Store: Café Paris (ID: 101)\nMonth: mar_2023 -> Sales: 1800",
        "Store: El Niño Tacos (ID: 102)\nMonth: jan_2023 -> Sales: 2200",
        "Store: El Niño Tacos (ID: 102)\nMonth: feb_2023 -> Sales: 2100",
        "Store: El Niño Tacos (ID: 102)\nMonth: mar_2023 -> Sales: 2300",
        "Store: München Bratwurst (ID: 103)\nMonth: jan_2023 -> Sales: 1800",
        "Store: München Bratwurst (ID: 103)\nMonth: feb_2023 -> Sales: 1900",
        "Store: München Bratwurst (ID: 103)\nMonth: mar_2023 -> Sales: 1850"
    ]

    # Split the content by double newlines to get individual blocks
    # Handle possible trailing newlines or varying whitespace between blocks slightly
    blocks = [block.strip() for block in content.split("\n\n") if block.strip()]

    assert len(blocks) == 9, f"Expected 9 records in {report_path}, found {len(blocks)}"

    for i, expected_block in enumerate(expected_blocks):
        assert blocks[i] == expected_block, f"Record {i+1} mismatch.\nExpected:\n{expected_block}\nGot:\n{blocks[i]}"

    # Check that there is exactly one blank line between records.
    # We can do this by checking if the original content contains the exact joined string
    joined_expected = "\n\n".join(expected_blocks)
    assert joined_expected in content, "The spacing between records in report.txt is incorrect. Expected exactly one blank line between rendered record blocks."


def test_process_go_executes_dynamic_pipeline():
    base = Path("/home/user")
    process_path = base / "process.go"
    csv_path = base / "sales_wide.csv"
    template_path = base / "report.tmpl"
    report_path = base / "report.txt"
    log_path = base / "process.log"

    assert process_path.is_file(), f"Missing Go program: {process_path}"

    paths_to_restore = [csv_path, template_path, report_path, log_path]
    backups = {path: path.read_bytes() if path.is_file() else None for path in paths_to_restore}

    headers = ["store_id", "store_name", "apr_2024", "holiday_2024", "jan_2025", "bonus_month"]
    rows = [
        ["701", r"Cr\u00e8me House", "17", "29", "31", "43"],
        ["808", r"Boutique \u6771\u4eac", "101", "103", "107", "109"],
    ]

    csv_lines = [",".join(headers)] + [",".join(row) for row in rows]
    dynamic_template = "Record {{.StoreID}} / {{.StoreName}}\nPeriod={{.Month}}; Amount={{.Sales}}\n"

    try:
        csv_path.write_text("\n".join(csv_lines) + "\n", encoding="utf-8")
        template_path.write_text(dynamic_template, encoding="utf-8")
        for output in (report_path, log_path):
            if output.exists():
                output.unlink()

        result = subprocess.run(
            ["go", "run", str(process_path)],
            cwd=str(base),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"go run {process_path} failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert report_path.is_file(), "Go program did not create report.txt"
        assert log_path.is_file(), "Go program did not create process.log"

        expected_blocks = []
        for row in rows:
            store_id = row[0]
            store_name = bytes(row[1], "utf-8").decode("unicode_escape")
            for month, sales in zip(headers[2:], row[2:]):
                expected_blocks.append(
                    f"Record {store_id} / {store_name}\nPeriod={month}; Amount={sales}"
                )

        content = report_path.read_text(encoding="utf-8")
        blocks = [block.strip() for block in content.split("\n\n") if block.strip()]
        assert blocks == expected_blocks, (
            "Dynamic report content is incorrect; process.go must decode names, "
            "process every present month column, and apply the current template"
        )
        joined_expected = "\n\n".join(expected_blocks)
        assert joined_expected in content, "Dynamic report does not have exactly one blank line between record blocks"

        expected_count = len(rows) * (len(headers) - 2)
        assert log_path.read_text(encoding="utf-8").strip() == f"Records processed: {expected_count}"
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
