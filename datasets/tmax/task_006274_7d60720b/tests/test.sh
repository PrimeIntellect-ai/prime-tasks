#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_template.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path"
    "strconv"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    alias := ""
    dotImport := false
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil || p != "text/template" {
            continue
        }
        if imp.Name == nil {
            alias = path.Base(p)
        } else if imp.Name.Name == "." {
            dotImport = true
        } else if imp.Name.Name != "_" {
            alias = imp.Name.Name
        }
    }
    if alias == "" && !dotImport {
        fmt.Fprintln(os.Stderr, "process.go must non-blank import text/template")
        os.Exit(1)
    }

    usesPackage := dotImport
    executesTemplate := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.SelectorExpr:
            if id, ok := x.X.(*ast.Ident); ok && alias != "" && id.Name == alias {
                usesPackage = true
            }
        case *ast.CallExpr:
            if sel, ok := x.Fun.(*ast.SelectorExpr); ok && (sel.Sel.Name == "Execute" || sel.Sel.Name == "ExecuteTemplate") {
                executesTemplate = true
            }
        }
        return true
    })

    if !usesPackage {
        fmt.Fprintln(os.Stderr, "process.go imports but does not use text/template")
        os.Exit(1)
    }
    if !executesTemplate {
        fmt.Fprintln(os.Stderr, "process.go does not execute a template")
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_template /tmp/check_template.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
from datetime import datetime, timedelta, timezone

PROCESS = "/home/user/process.go"
RAW = "/home/user/raw_sensors.csv"
PROCESSED = "/home/user/processed_sensors.csv"
REPORT = "/home/user/sensor_report.md"


def test_processed_sensors_csv():
    file_path = "/home/user/processed_sensors.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    expected_content = """timestamp,sensor_id,normalized_value
2023-10-01T10:00:00Z,temp_A,0.0000
2023-10-01T10:00:00Z,temp_B,0.0000
2023-10-01T10:00:00Z,temp_C,0.0000
2023-10-01T10:01:00Z,temp_A,0.0000
2023-10-01T10:01:00Z,temp_B,0.2500
2023-10-01T10:01:00Z,temp_C,0.9091
2023-10-01T10:02:00Z,temp_A,0.5000
2023-10-01T10:02:00Z,temp_B,0.2500
2023-10-01T10:02:00Z,temp_C,0.9545
2023-10-01T10:03:00Z,temp_A,1.0000
2023-10-01T10:03:00Z,temp_B,1.0000
2023-10-01T10:03:00Z,temp_C,1.0000"""

    with open(file_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {file_path} does not match expected output."


def test_sensor_report_md():
    file_path = "/home/user/sensor_report.md"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    expected_content = """# Sensor Report

## Sensor temp_A
- Min: 20.5
- Max: 21.5
- Data Points: 4
- Latest Normalized: 1.0000

## Sensor temp_B
- Min: 15.0
- Max: 15.8
- Data Points: 4
- Latest Normalized: 1.0000

## Sensor temp_C
- Min: 0.0
- Max: 11.0
- Data Points: 4
- Latest Normalized: 1.0000"""

    with open(file_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {file_path} does not match expected output."


def test_program_exists_and_uses_text_template():
    assert os.path.isfile(PROCESS), f"File {PROCESS} is missing."
    assert not os.path.islink(PROCESS), f"File {PROCESS} must be a regular source file."
    result = subprocess.run(
        ["/tmp/check_template", PROCESS],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr


def test_program_processes_unseen_csv_input():
    seed = secrets.randbits(64)
    rng = random.Random(seed)
    start = datetime(2025, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=rng.randrange(300), minutes=rng.randrange(1000)
    )
    timestamps = [
        (start + timedelta(minutes=i * 3)).strftime("%Y-%m-%dT%H:%M:%SZ")
        for i in range(5)
    ]

    a = float(rng.randrange(12, 40))
    b = float(rng.randrange(5, 12))
    c = float(rng.randrange(42, 70))
    chronological = {
        "temp_A": [a, None, a + 4.0, a + 2.0, None],
        "temp_B": [None, b, None, b + 3.0, b + 1.0],
        "temp_C": [c, c, c, c, c],
    }

    row_indices = list(range(len(timestamps)))
    rng.shuffle(row_indices)
    with open(RAW, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "temp_A", "temp_B", "temp_C"])
        for i in row_indices:
            writer.writerow([
                timestamps[i],
                "" if chronological["temp_A"][i] is None else f'{chronological["temp_A"][i]:.1f}',
                "" if chronological["temp_B"][i] is None else f'{chronological["temp_B"][i]:.1f}',
                "" if chronological["temp_C"][i] is None else f'{chronological["temp_C"][i]:.1f}',
            ])

    for output in (PROCESSED, REPORT):
        if os.path.lexists(output):
            os.unlink(output)

    result = subprocess.run(
        ["go", "run", PROCESS],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"process.go failed:\n{result.stderr}"
    assert os.path.isfile(PROCESSED), "process.go did not create processed_sensors.csv"
    assert os.path.isfile(REPORT), "process.go did not create sensor_report.md"

    imputed = {}
    normalized = {}
    for sensor in sorted(chronological):
        prior = 0.0
        values = []
        for value in chronological[sensor]:
            if value is None:
                values.append(prior)
            else:
                prior = value
                values.append(value)
        imputed[sensor] = values
        minimum, maximum = min(values), max(values)
        if maximum == minimum:
            normalized[sensor] = [0.0 for _ in values]
        else:
            normalized[sensor] = [
                (value - minimum) / (maximum - minimum) for value in values
            ]

    expected_csv = ["timestamp,sensor_id,normalized_value"]
    for i, timestamp in enumerate(timestamps):
        for sensor in sorted(chronological):
            expected_csv.append(
                f"{timestamp},{sensor},{normalized[sensor][i]:.4f}"
            )

    expected_report = ["# Sensor Report"]
    for sensor in sorted(chronological):
        values = imputed[sensor]
        expected_report.extend([
            "",
            f"## Sensor {sensor}",
            f"- Min: {min(values):.1f}",
            f"- Max: {max(values):.1f}",
            f"- Data Points: {len(values)}",
            f"- Latest Normalized: {normalized[sensor][-1]:.4f}",
        ])

    with open(PROCESSED, "r", encoding="utf-8") as f:
        actual_csv = f.read().strip()
    with open(REPORT, "r", encoding="utf-8") as f:
        actual_report = f.read().strip()

    assert actual_csv == "\n".join(expected_csv), (
        f"processed output was incorrect for unseen input (seed={seed})"
    )
    assert actual_report == "\n".join(expected_report), (
        f"report was incorrect for unseen input (seed={seed})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
