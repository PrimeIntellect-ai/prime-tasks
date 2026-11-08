#!/bin/bash
set -u
mkdir -p /logs/verifier

WORKSPACE=/home/user/workspace
BACKUP_DIR=$(mktemp -d)
cp -a "$WORKSPACE/loc_views.csv" "$BACKUP_DIR/loc_views.csv"
cp -a "$WORKSPACE/loc_edits.json" "$BACKUP_DIR/loc_edits.json"
if [ -f "$WORKSPACE/loc_daily_metrics.csv" ]; then
    cp -a "$WORKSPACE/loc_daily_metrics.csv" "$BACKUP_DIR/loc_daily_metrics.csv"
    HAD_OUTPUT=1
else
    HAD_OUTPUT=0
fi

restore_files() {
    cp -a "$BACKUP_DIR/loc_views.csv" "$WORKSPACE/loc_views.csv"
    cp -a "$BACKUP_DIR/loc_edits.json" "$WORKSPACE/loc_edits.json"
    if [ "$HAD_OUTPUT" -eq 1 ]; then
        cp -a "$BACKUP_DIR/loc_daily_metrics.csv" "$WORKSPACE/loc_daily_metrics.csv"
    else
        rm -f "$WORKSPACE/loc_daily_metrics.csv"
    fi
    rm -rf "$BACKUP_DIR"
}
trap restore_files EXIT

cat << 'GO_EOF' > /tmp/check_pipeline.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
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

    goroutines, channels, sends, receives, ranges := 0, 0, 0, 0, 0
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            goroutines++
        case *ast.ChanType:
            channels++
        case *ast.SendStmt:
            sends++
        case *ast.UnaryExpr:
            if x.Op == token.ARROW {
                receives++
            }
        case *ast.RangeStmt:
            ranges++
        }
        return true
    })

    if goroutines < 1 || channels < 1 || sends < 1 || (receives < 1 && ranges < 1) {
        fmt.Fprintf(os.Stderr, "source lacks required goroutine/channel pipeline structure (go=%d chan=%d send=%d receive=%d range=%d)\n", goroutines, channels, sends, receives, ranges)
        os.Exit(1)
    }
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import os
import random
import secrets
import subprocess

WORKSPACE_DIR = "/home/user/workspace"
GO_FILE = os.path.join(WORKSPACE_DIR, "process_loc.go")
VIEWS_FILE = os.path.join(WORKSPACE_DIR, "loc_views.csv")
EDITS_FILE = os.path.join(WORKSPACE_DIR, "loc_edits.json")
OUTPUT_FILE = os.path.join(WORKSPACE_DIR, "loc_daily_metrics.csv")
PROGRAM = "/tmp/process_loc_submission"
ANALYZER = "/tmp/check_pipeline"

EXPECTED_OUTPUT = """date,lang,total_views,total_edits
2023-10-01,de,200,0
2023-10-01,es,0,2
2023-10-01,fr,200,5
2023-10-02,de,0,10
2023-10-02,fr,100,0
2023-10-03,es,300,15
2023-10-03,fr,0,0"""


def test_go_program_exists():
    assert os.path.isfile(GO_FILE), f"Go program {GO_FILE} does not exist."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist. Did you run the Go program?"


def test_output_file_content():
    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()
    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in EXPECTED_OUTPUT.splitlines() if line.strip()]
    assert content_lines == expected_lines, (
        f"Output file {OUTPUT_FILE} content does not match expected output.\n"
        f"Expected:\n{EXPECTED_OUTPUT}\n\nGot:\n{content}"
    )


def test_program_compiles_and_contains_channel_pipeline():
    result = subprocess.run(
        ["go", "build", "-o", PROGRAM, GO_FILE],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Go program does not compile:\n{result.stderr}"

    result = subprocess.run(
        ["go", "build", "-o", ANALYZER, "/tmp/check_pipeline.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    result = subprocess.run(
        [ANALYZER, GO_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr


def make_case(rng):
    start = datetime.date(2024 + rng.randrange(2), rng.randrange(1, 10), rng.randrange(1, 20))
    dates = [(start + datetime.timedelta(days=i)).isoformat() for i in range(4)]
    tag = secrets.token_hex(3)
    langs = [f"aa_{tag}", f"de_{tag}", f"fr_{tag}", f"zz_{tag}"]
    rng.shuffle(langs)
    a, b, c, d = langs

    def ts(day, hour, minute):
        return f"{day}T{hour:02d}:{minute:02d}:00Z"

    views = [
        (ts(dates[0], 1, 7), b, rng.randrange(10, 100)),
        (ts(dates[0], 23, 58), b, rng.randrange(10, 100)),
        (ts(dates[1], 9, 11), a, rng.randrange(10, 100)),
        (ts(dates[3], 4, 25), d, rng.randrange(10, 100)),
        (ts(dates[3], 18, 39), c, rng.randrange(10, 100)),
    ]
    edits = [
        {"time": ts(dates[0], 12, 3), a: rng.randrange(1, 30), b: None},
        {"time": ts(dates[1], 15, 17), b: rng.randrange(1, 30)},
        {"time": ts(dates[2], 6, 45), d: rng.randrange(1, 30), c: None},
        {"time": ts(dates[3], 10, 5), d: rng.randrange(1, 30), a: rng.randrange(1, 30)},
        {"time": ts(dates[3], 22, 51), d: rng.randrange(1, 30)},
    ]
    return views, edits


def expected_rows(views, edits):
    totals = {}

    def entry(day, lang):
        return totals.setdefault((day, lang), [0, 0])

    for timestamp, lang, views_count in views:
        entry(timestamp[:10], lang)[0] += views_count
    for record in edits:
        day = record["time"][:10]
        for lang, value in record.items():
            if lang == "time":
                continue
            entry(day, lang)[1] += 0 if value is None else value

    rows = [["date", "lang", "total_views", "total_edits"]]
    for day, lang in sorted(totals):
        views_count, edits_count = totals[(day, lang)]
        rows.append([day, lang, str(views_count), str(edits_count)])
    return rows


def write_inputs(views, edits):
    with open(VIEWS_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "lang", "views"])
        writer.writerows(views)
    with open(EDITS_FILE, "w") as f:
        json.dump(edits, f)


def test_program_recomputes_randomized_inputs():
    rng = random.SystemRandom()
    for _ in range(2):
        views, edits = make_case(rng)
        expected = expected_rows(views, edits)
        write_inputs(views, edits)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        result = subprocess.run(
            [PROGRAM],
            cwd=WORKSPACE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Program failed on verifier-generated inputs.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT_FILE), "Program did not generate loc_daily_metrics.csv"

        with open(OUTPUT_FILE, newline="") as f:
            actual = list(csv.reader(f))
        assert actual == expected, (
            "Output for verifier-generated inputs was incorrect.\n"
            f"Expected: {expected}\nGot: {actual}"
        )
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
