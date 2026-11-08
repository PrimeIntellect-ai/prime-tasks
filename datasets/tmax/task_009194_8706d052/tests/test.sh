#!/bin/bash
mkdir -p /logs/verifier

(
set -e

SRC=/home/user/process_metrics.go
BIN=/tmp/process_metrics_test_bin

# Restore the specified fixture so the submitted program, rather than pre-created
# output files, is tested against the original task input.
cat << 'EOF' > /home/user/system_metrics.csv
timestamp,server_id,cpu_pct,ram_mb,event_details
2023-10-12 10:00:00,srv-1,45.5,2048,Normal operation
2023-10-12T10:01:00Z,srv-2,99.9,4096,"High load detected
Investigate immediately"
2023-10-12 10:02:00,srv-1,105.0,2048,Invalid CPU spike
2023-10-12T10:03:00Z,srv-3,12.0,-500,Invalid RAM allocation
2023-10-12 10:04:00,srv-1,22.1,8192,"Routine backup started
Lines: 400
Status: OK"
2023-10-12T10:05:00Z,srv-2,50.0,4096,Normal operation
2023-10-12 10:06:00,srv-3,NaN,1024,Broken float
2023-10-12 10:07:00,srv-1,10.0,2048,Idle
2023-10-12 10:08:00,srv-2,15.5,4096,Idle
2023-10-12 10:09:00,srv-3,18.0,1024,Idle
EOF

# Verify that encoding/csv is genuinely imported and that its reader API/type is
# referenced, rather than merely appearing in a comment or blank import.
cat << 'GO_EOF' > /tmp/check_csv_import.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    const source = "/home/user/process_metrics.go"
    f, err := parser.ParseFile(token.NewFileSet(), source, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    aliases := map[string]bool{}
    dotImport := false
    for _, imp := range f.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err != nil || path != "encoding/csv" {
            continue
        }
        if imp.Name == nil {
            aliases["csv"] = true
        } else if imp.Name.Name == "." {
            dotImport = true
        } else if imp.Name.Name != "_" {
            aliases[imp.Name.Name] = true
        }
    }

    usedReader := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.SelectorExpr:
            id, ok := x.X.(*ast.Ident)
            if ok && aliases[id.Name] && (x.Sel.Name == "NewReader" || x.Sel.Name == "Reader") {
                usedReader = true
            }
        case *ast.CallExpr:
            if dotImport {
                if id, ok := x.Fun.(*ast.Ident); ok && id.Name == "NewReader" {
                    usedReader = true
                }
            }
        case *ast.CompositeLit:
            if dotImport {
                if id, ok := x.Type.(*ast.Ident); ok && id.Name == "Reader" {
                    usedReader = true
                }
            }
        }
        return true
    })

    if len(aliases) == 0 && !dotImport {
        fmt.Fprintln(os.Stderr, "process_metrics.go does not import encoding/csv")
        os.Exit(1)
    }
    if !usedReader {
        fmt.Fprintln(os.Stderr, "process_metrics.go does not use encoding/csv's reader API")
        os.Exit(1)
    }
}
GO_EOF

test -f "$SRC"
go run /tmp/check_csv_import.go
go build -o "$BIN" "$SRC"

rm -f /home/user/valid_metrics.csv /home/user/invalid_metrics.csv
set +e
original_stdout=$("$BIN")
original_status=$?
set -e
test "$original_status" -eq 1
test "$(printf '%s' "$original_stdout" | tr -d '\r' | sed -e 's/[[:space:]]*$//')" = "QUALITY_GATE_FAILED"

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_go_program_exists():
    assert os.path.exists("/home/user/process_metrics.go"), "Go program /home/user/process_metrics.go is missing"
    assert os.path.isfile("/home/user/process_metrics.go"), "/home/user/process_metrics.go is not a file"

def test_valid_metrics_csv():
    valid_csv_path = "/home/user/valid_metrics.csv"
    assert os.path.exists(valid_csv_path), f"Output file missing: {valid_csv_path}"

    with open(valid_csv_path, "r", encoding="utf-8") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "valid_metrics.csv is empty"
    assert reader[0] == ["timestamp", "server_id", "cpu_pct", "ram_mb", "event_details"], "Incorrect header in valid_metrics.csv"

    expected_rows = [
        ["2023-10-12T10:00:00Z", "srv-1", "45.5", "2048", "Normal operation"],
        ["2023-10-12T10:01:00Z", "srv-2", "99.9", "4096", "High load detected\nInvestigate immediately"],
        ["2023-10-12T10:04:00Z", "srv-1", "22.1", "8192", "Routine backup started\nLines: 400\nStatus: OK"],
        ["2023-10-12T10:05:00Z", "srv-2", "50.0", "4096", "Normal operation"],
        ["2023-10-12T10:07:00Z", "srv-1", "10.0", "2048", "Idle"],
        ["2023-10-12T10:08:00Z", "srv-2", "15.5", "4096", "Idle"],
        ["2023-10-12T10:09:00Z", "srv-3", "18.0", "1024", "Idle"],
    ]

    assert len(reader) - 1 == len(expected_rows), f"Expected {len(expected_rows)} valid rows, but found {len(reader) - 1}"

    for i, expected_row in enumerate(expected_rows, start=1):
        assert reader[i] == expected_row, f"Row {i} in valid_metrics.csv does not match expected output."

def test_invalid_metrics_csv():
    invalid_csv_path = "/home/user/invalid_metrics.csv"
    assert os.path.exists(invalid_csv_path), f"Output file missing: {invalid_csv_path}"

    with open(invalid_csv_path, "r", encoding="utf-8") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "invalid_metrics.csv is empty"
    assert reader[0] == ["timestamp", "server_id", "cpu_pct", "ram_mb", "event_details"], "Incorrect header in invalid_metrics.csv"

    expected_rows = [
        ["2023-10-12 10:02:00", "srv-1", "105.0", "2048", "Invalid CPU spike"],
        ["2023-10-12T10:03:00Z", "srv-3", "12.0", "-500", "Invalid RAM allocation"],
        ["2023-10-12 10:06:00", "srv-3", "NaN", "1024", "Broken float"],
    ]

    assert len(reader) - 1 == len(expected_rows), f"Expected {len(expected_rows)} invalid rows, but found {len(reader) - 1}"

    for i, expected_row in enumerate(expected_rows, start=1):
        assert reader[i] == expected_row, f"Row {i} in invalid_metrics.csv does not match expected output."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short

# Exercise the compiled artifact on fresh inputs, including embedded newlines and
# both sides of the strict 20 percent quality-gate boundary.
cat << 'PY_EOF' > /tmp/test_dynamic.py
import csv
import os
import random
import secrets
import subprocess

BIN = "/tmp/process_metrics_test_bin"
INPUT = "/home/user/system_metrics.csv"
VALID = "/home/user/valid_metrics.csv"
INVALID = "/home/user/invalid_metrics.csv"
HEADER = ["timestamp", "server_id", "cpu_pct", "ram_mb", "event_details"]
original_input = open(INPUT, "rb").read()


def read_csv(path):
    assert os.path.isfile(path), f"missing output: {path}"
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def make_case(invalid_count):
    rng = random.SystemRandom()
    bad_indices = set(rng.sample(range(10), invalid_count))
    bad_kinds = ["timestamp", "cpu_high", "ram_zero", "nan"]
    rows = []
    expected_valid = []
    expected_invalid = []

    for i in range(10):
        minute = rng.randrange(0, 60)
        if i == 0:
            timestamp = f"2025-04-17 08:{minute:02d}:00"
            normalized = f"2025-04-17T08:{minute:02d}:00Z"
            cpu = "0.0"
        elif i == 1:
            timestamp = f"2025-04-17T09:{minute:02d}:00+02:00"
            normalized = timestamp
            cpu = "100.0"
        elif i % 2:
            timestamp = f"2025-04-17T08:{minute:02d}:00Z"
            normalized = timestamp
            cpu = f"{rng.uniform(0.1, 99.9):.3f}"
        else:
            timestamp = f"2025-04-17 08:{minute:02d}:00"
            normalized = f"2025-04-17T08:{minute:02d}:00Z"
            cpu = f"{rng.uniform(0.1, 99.9):.3f}"

        ram = str(rng.randrange(1, 32769))
        event = f"event-{secrets.token_hex(5)}"
        if i in (2, 7):
            event += "\nembedded detail " + secrets.token_hex(4)

        row = [timestamp, f"srv-{secrets.token_hex(3)}", cpu, ram, event]
        if i in bad_indices:
            kind = bad_kinds[i % len(bad_kinds)]
            if kind == "timestamp":
                row[0] = "not-a-timestamp-" + secrets.token_hex(3)
            elif kind == "cpu_high":
                row[2] = str(100.01 + rng.random() * 50)
            elif kind == "ram_zero":
                row[3] = "0"
            else:
                row[2] = "NaN"
            expected_invalid.append(row.copy())
        else:
            out = row.copy()
            out[0] = normalized
            expected_valid.append(out)
        rows.append(row)

    return rows, expected_valid, expected_invalid


def run_case(invalid_count, expected_status, expected_message):
    rows, expected_valid, expected_invalid = make_case(invalid_count)
    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(HEADER)
        writer.writerows(rows)

    for path in (VALID, INVALID):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run([BIN], text=True, capture_output=True)
    assert result.returncode == expected_status, (result.returncode, result.stdout, result.stderr)
    assert result.stdout.strip() == expected_message, repr(result.stdout)
    assert read_csv(VALID) == [HEADER] + expected_valid
    assert read_csv(INVALID) == [HEADER] + expected_invalid


try:
    # Exactly 20% invalid must pass.
    run_case(2, 0, "QUALITY_GATE_PASSED")
    # Strictly more than 20% invalid must fail.
    run_case(3, 1, "QUALITY_GATE_FAILED")
finally:
    with open(INPUT, "wb") as f:
        f.write(original_input)
    subprocess.run([BIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY_EOF

python3 /tmp/test_dynamic.py
)
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
