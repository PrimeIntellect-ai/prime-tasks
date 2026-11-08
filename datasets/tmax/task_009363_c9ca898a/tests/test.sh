#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import subprocess
from pathlib import Path

HOME = Path("/home/user")
DATA = HOME / "data/config_changes.csv"
REPORT = HOME / "report.txt"
PROCESS = HOME / "process.go"
CRON = HOME / "cron.txt"


def test_report_txt_content():
    """Keep the original exact assertion for the supplied CSV."""
    assert REPORT.is_file(), f"File {REPORT} does not exist."

    expected_content = (
        "Total Valid Changes: 3\n"
        "Total Cost Impact: 170\n"
        "Masked Authors:\n"
        "- ***@acme.corp\n"
        "- ***@acme.corp\n"
        "- ***@acme.corp"
    )

    content = REPORT.read_text().strip()
    assert content == expected_content.strip(), f"Content of {REPORT} does not match the expected output."


def test_cron_txt_content():
    """Keep the original checks and require the requested complete cron entry."""
    assert CRON.is_file(), f"File {CRON} does not exist."
    content = CRON.read_text()

    assert "0 * * * *" in content, f"File {CRON} does not contain the correct cron schedule '0 * * * *'."
    assert "process.go" in content, f"File {CRON} does not contain the command to run 'process.go'."

    active_lines = [line.strip() for line in content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    expected_line = "0 * * * * cd /home/user && go run process.go"
    assert expected_line in active_lines, f"File {CRON} does not contain the exact required cron entry."


def test_process_go_builds_uses_required_packages_and_regenerates_report():
    assert PROCESS.is_file(), f"File {PROCESS} does not exist."

    # Parse the Go source to ensure both required packages are imported normally,
    # rather than accepting unused blank imports.
    checker = r'''
package main
import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/process.go", nil, 0)
    if err != nil { os.Exit(2) }
    foundCSV, foundTemplate := false, false
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil { os.Exit(2) }
        if p == "encoding/csv" {
            if imp.Name != nil && imp.Name.Name == "_" { os.Exit(3) }
            foundCSV = true
        }
        if p == "text/template" {
            if imp.Name != nil && imp.Name.Name == "_" { os.Exit(3) }
            foundTemplate = true
        }
    }
    if !foundCSV || !foundTemplate { os.Exit(4) }
    _ = ast.File{}
}
'''
    Path("/tmp/check_go_imports.go").write_text(checker)
    subprocess.run(
        ["go", "run", "/tmp/check_go_imports.go"],
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    subprocess.run(
        ["go", "build", "-o", "/tmp/process_submission", "process.go"],
        cwd=HOME,
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    original_data = DATA.read_bytes()
    original_report = REPORT.read_bytes() if REPORT.exists() else None

    token = secrets.token_hex(8)
    rows = [
        ["A1", f"alpha.{token}@example.com", "7", "embedded newline\nand a comma, too"],
        ["A2", f"negative.{token}@invalid.example", "-9", "must be dropped\neven though multiline"],
        ["A3", f"zero.{token}@sub.example.org", "0", "quoted \"message\""],
        ["A4", f"bad.{token}@invalid.example", "not-an-integer", "must be dropped"],
        ["A5", f"final.{token}@example.net", "13", "three\nphysical\nlines"],
    ]
    secrets.SystemRandom().shuffle(rows)

    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(["ChangeID", "AuthorEmail", "CostImpact", "CommitMessage"])
    writer.writerows(rows)
    fixture = stream.getvalue()

    # Derive the expected answer independently from the generated CSV.
    parsed = list(csv.reader(io.StringIO(fixture, newline="")))
    valid = []
    for row in parsed[1:]:
        try:
            cost = int(row[2])
        except ValueError:
            continue
        if cost < 0:
            continue
        valid.append((row[1], cost))

    expected_lines = [
        f"Total Valid Changes: {len(valid)}",
        f"Total Cost Impact: {sum(cost for _, cost in valid)}",
        "Masked Authors:",
    ]
    expected_lines.extend(f"- ***@{email.split('@', 1)[1]}" for email, _ in valid)
    expected = "\n".join(expected_lines)

    try:
        DATA.write_text(fixture)
        if REPORT.exists():
            REPORT.unlink()

        subprocess.run(
            ["go", "run", "process.go"],
            cwd=HOME,
            check=True,
            timeout=60,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert REPORT.is_file(), "Running process.go did not create /home/user/report.txt."
        assert REPORT.read_text().strip() == expected.strip(), "process.go produced an incorrect report for generated multiline CSV input."
    finally:
        DATA.write_bytes(original_data)
        try:
            subprocess.run(
                ["go", "run", "process.go"],
                cwd=HOME,
                check=False,
                timeout=60,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except Exception:
            if original_report is not None:
                REPORT.write_bytes(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
