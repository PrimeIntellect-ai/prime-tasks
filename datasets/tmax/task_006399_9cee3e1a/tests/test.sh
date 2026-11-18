#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_process_source.go
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
    path := "/home/user/process.go"
    info, err := os.Lstat(path)
    if err != nil || !info.Mode().IsRegular() {
        fmt.Fprintln(os.Stderr, "process.go is missing or is not a regular file")
        os.Exit(1)
    }

    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, "process.go is not valid Go source:", err)
        os.Exit(1)
    }

    hasSQLite := false
    for _, imp := range file.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            os.Exit(1)
        }
        if p == "github.com/mattn/go-sqlite3" {
            hasSQLite = true
        }
    }

    goStatements := 0
    channelMakes := 0
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            goStatements++
        case *ast.CallExpr:
            ident, ok := x.Fun.(*ast.Ident)
            if ok && ident.Name == "make" && len(x.Args) > 0 {
                if _, ok := x.Args[0].(*ast.ChanType); ok {
                    channelMakes++
                }
            }
        }
        return true
    })

    if !hasSQLite {
        fmt.Fprintln(os.Stderr, "process.go must import github.com/mattn/go-sqlite3")
        os.Exit(1)
    }
    if goStatements < 3 {
        fmt.Fprintln(os.Stderr, "process.go does not launch enough goroutines for the pipeline stages")
        os.Exit(1)
    }
    if channelMakes < 3 {
        fmt.Fprintln(os.Stderr, "process.go does not create the three channels needed to connect four stages")
        os.Exit(1)
    }
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import sqlite3
import string
import subprocess

DB_PATH = "/home/user/valid_translations.db"
CSV_PATH = "/home/user/translations.csv"
SOURCE_PATH = "/home/user/process.go"

ORIGINAL_EXPECTED = {
    "row1": ("Hello World", "Bonjour le monde", 13),
    "row3": ("Multiline\nText", "Texte\nMultiligne", 8),
    "row5": ("Settings", "Paramètres", 10),
    "row7": (
        "A long text with\nnewlines\nand stuff",
        "Un long texte avec\ndes retours à la ligne\net des choses",
        33,
    ),
}


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def read_schema(conn):
    return conn.execute("PRAGMA table_info(translations)").fetchall()


def assert_exact_schema(conn):
    table = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='translations'"
    ).fetchone()
    assert table is not None, "Table 'translations' does not exist in the database."

    schema = read_schema(conn)
    assert len(schema) == 4, f"Expected exactly four columns, got: {schema}"
    assert [(r[1], r[2].upper(), r[5]) for r in schema] == [
        ("id", "TEXT", 1),
        ("english", "TEXT", 0),
        ("translated", "TEXT", 0),
        ("distance", "INTEGER", 0),
    ], f"Incorrect translations schema: {schema}"


def test_process_source_and_pipeline_structure():
    assert os.path.isfile(SOURCE_PATH), f"The Go program {SOURCE_PATH} was not created."
    result = subprocess.run(
        ["go", "run", "/tmp/check_process_source.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout


def test_db_exists():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} was not created."


def test_db_schema():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} not found."
    with sqlite3.connect(DB_PATH) as conn:
        # Preserve the original column-presence assertions.
        columns = {row[1]: row[2].upper() for row in read_schema(conn)}
        assert "id" in columns, "Column 'id' missing from translations table."
        assert "english" in columns, "Column 'english' missing from translations table."
        assert "translated" in columns, "Column 'translated' missing from translations table."
        assert "distance" in columns, "Column 'distance' missing from translations table."
        assert_exact_schema(conn)


def test_original_db_contents():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} not found."
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(
            "SELECT id, english, translated, distance FROM translations ORDER BY id"
        ).fetchall()

    assert len(rows) == len(ORIGINAL_EXPECTED), (
        f"Expected {len(ORIGINAL_EXPECTED)} rows in the database, found {len(rows)}."
    )
    for row_id, english, translated, distance in rows:
        assert row_id in ORIGINAL_EXPECTED, f"Unexpected row '{row_id}' found in the database."
        expected_english, expected_translated, expected_distance = ORIGINAL_EXPECTED[row_id]
        assert english == expected_english, f"Incorrect english value for {row_id}."
        assert translated == expected_translated, f"Incorrect translated value for {row_id}."
        assert distance == expected_distance, (
            f"Expected distance {expected_distance} for {row_id}, but got {distance}."
        )


def random_text(length):
    alphabet = string.ascii_lowercase
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_program_on_fresh_unpredictable_csv_with_embedded_newlines():
    prefix = secrets.token_hex(8)
    base4 = random_text(14)
    changed4 = "".join(c.upper() if i < 4 else c for i, c in enumerate(base4))
    base5 = random_text(16)
    changed5 = "".join(c.upper() if i < 5 else c for i, c in enumerate(base5))

    input_rows = [
        (f"{prefix}_same", random_text(13), None),
        (f"{prefix}_four", base4, changed4),
        (f"{prefix}_five", base5, changed5),
        (f"{prefix}_newline", random_text(9) + "\n" + random_text(8),
         random_text(11) + "\n" + random_text(12)),
        (f"{prefix}_different", random_text(10), random_text(22)),
        (f"{prefix}_multiline2", "first\nsecond\nthird", "alpha\nbeta\ngamma\ndelta"),
    ]
    input_rows[0] = (input_rows[0][0], input_rows[0][1], input_rows[0][1])

    expected = {}
    for row_id, english, translated in input_rows:
        distance = levenshtein(english, translated)
        if distance >= 5:
            expected[row_id] = (english, translated, distance)

    assert any(levenshtein(e, t) < 5 for _, e, t in input_rows)
    assert any(levenshtein(e, t) == 5 for _, e, t in input_rows)
    assert any("\n" in e or "\n" in t for _, e, t in input_rows)

    backup = "/tmp/translations.csv.original"
    shutil.copyfile(CSV_PATH, backup)
    try:
        with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "english", "translated"])
            writer.writerows(input_rows)

        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)

        result = subprocess.run(
            ["go", "run", SOURCE_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert result.returncode == 0, f"process.go failed on a fresh CSV:\n{result.stdout}"
        assert os.path.isfile(DB_PATH), "process.go did not create the database when executed."

        with sqlite3.connect(DB_PATH) as conn:
            assert_exact_schema(conn)
            actual_rows = conn.execute(
                "SELECT id, english, translated, distance FROM translations ORDER BY id"
            ).fetchall()

        actual = {
            row_id: (english, translated, distance)
            for row_id, english, translated, distance in actual_rows
        }
        assert actual == expected, f"Fresh execution produced incorrect rows: {actual!r} != {expected!r}"
    finally:
        shutil.copyfile(backup, CSV_PATH)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
