#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'INSPECT_EOF' > /tmp/inspect_go.go
package main

import (
    "encoding/json"
    "go/ast"
    "go/format"
    "go/parser"
    "go/token"
    "os"
    "strconv"
    "strings"
)

type Result struct {
    SQL           string   `json:"sql"`
    Args          []string `json:"args"`
    QueryCalls    int      `json:"query_calls"`
    PrepareCalls  int      `json:"prepare_calls"`
    OtherDBCalls  int      `json:"other_db_calls"`
}

func main() {
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, "/home/user/generate_report.go", nil, 0)
    if err != nil {
        panic(err)
    }

    env := map[string]string{}
    prepared := map[string]string{}
    result := Result{}

    var evalString func(ast.Expr) (string, bool)
    evalString = func(e ast.Expr) (string, bool) {
        switch v := e.(type) {
        case *ast.BasicLit:
            if v.Kind != token.STRING {
                return "", false
            }
            s, err := strconv.Unquote(v.Value)
            return s, err == nil
        case *ast.Ident:
            s, ok := env[v.Name]
            return s, ok
        case *ast.ParenExpr:
            return evalString(v.X)
        case *ast.BinaryExpr:
            if v.Op != token.ADD {
                return "", false
            }
            a, ok1 := evalString(v.X)
            b, ok2 := evalString(v.Y)
            return a + b, ok1 && ok2
        }
        return "", false
    }

    render := func(e ast.Expr) string {
        var b strings.Builder
        _ = format.Node(&b, fset, e)
        return b.String()
    }

    ast.Inspect(file, func(n ast.Node) bool {
        switch v := n.(type) {
        case *ast.ValueSpec:
            for i, name := range v.Names {
                if i < len(v.Values) {
                    if s, ok := evalString(v.Values[i]); ok {
                        env[name.Name] = s
                    }
                }
            }
        case *ast.AssignStmt:
            if len(v.Rhs) == len(v.Lhs) {
                for i, rhs := range v.Rhs {
                    id, ok := v.Lhs[i].(*ast.Ident)
                    if !ok {
                        continue
                    }
                    if s, ok := evalString(rhs); ok {
                        env[id.Name] = s
                    }
                }
            }
            if len(v.Rhs) == 1 && len(v.Lhs) >= 1 {
                call, ok := v.Rhs[0].(*ast.CallExpr)
                if ok {
                    sel, ok := call.Fun.(*ast.SelectorExpr)
                    id, idok := v.Lhs[0].(*ast.Ident)
                    if ok && idok && (sel.Sel.Name == "Prepare" || sel.Sel.Name == "PrepareContext") {
                        sqlIndex := 0
                        if sel.Sel.Name == "PrepareContext" {
                            sqlIndex = 1
                        }
                        if len(call.Args) > sqlIndex {
                            if s, ok := evalString(call.Args[sqlIndex]); ok {
                                prepared[id.Name] = s
                            }
                        }
                    }
                }
            }
        case *ast.CallExpr:
            sel, ok := v.Fun.(*ast.SelectorExpr)
            if !ok {
                return true
            }
            name := sel.Sel.Name
            if name == "Prepare" || name == "PrepareContext" {
                result.PrepareCalls++
                return true
            }
            if name == "Exec" || name == "ExecContext" || name == "QueryRow" || name == "QueryRowContext" {
                result.OtherDBCalls++
                return true
            }
            if name != "Query" && name != "QueryContext" {
                return true
            }

            result.QueryCalls++
            sqlIndex := 0
            if name == "QueryContext" {
                sqlIndex = 1
            }
            argStart := sqlIndex + 1

            if recv, ok := sel.X.(*ast.Ident); ok {
                if s, found := prepared[recv.Name]; found {
                    result.SQL = s
                    if name == "QueryContext" {
                        argStart = 1
                    } else {
                        argStart = 0
                    }
                } else if len(v.Args) > sqlIndex {
                    result.SQL, _ = evalString(v.Args[sqlIndex])
                }
            } else if len(v.Args) > sqlIndex {
                result.SQL, _ = evalString(v.Args[sqlIndex])
            }
            for _, arg := range v.Args[argStart:] {
                result.Args = append(result.Args, render(arg))
            }
        }
        return true
    })

    _ = json.NewEncoder(os.Stdout).Encode(result)
}
INSPECT_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import shutil
import sqlite3
import subprocess
import uuid

GO_FILE_PATH = "/home/user/generate_report.go"
CSV_FILE_PATH = "/home/user/report.csv"
DB_PATH = "/home/user/ecommerce.db"
WORKSPACE = "/home/user"
EXPECTED_HEADER = ["name", "total_spend", "rank", "running_total"]


def test_go_file_exists():
    assert os.path.exists(GO_FILE_PATH), f"Go source file not found at {GO_FILE_PATH}"
    assert os.path.isfile(GO_FILE_PATH), f"Path {GO_FILE_PATH} is not a file"


def run_go_program(region, limit):
    if os.path.exists(CSV_FILE_PATH):
        os.remove(CSV_FILE_PATH)
    cmd = ["go", "run", "generate_report.go", "-region", region, "-limit", str(limit)]
    result = subprocess.run(cmd, cwd=WORKSPACE, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"Go program failed to run.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert os.path.exists(CSV_FILE_PATH), f"CSV file was not created at {CSV_FILE_PATH} after running the program"


def read_csv():
    with open(CSV_FILE_PATH, "r", newline="") as f:
        return list(csv.reader(f))


def test_go_program_output_north_america_limit_2():
    run_go_program("North America", 2)
    rows = read_csv()
    assert len(rows) > 0, "CSV file is empty"
    assert rows[0] == EXPECTED_HEADER, f"Expected header {EXPECTED_HEADER}, but got {rows[0]}"
    assert len(rows) == 3, f"Expected 1 header + 2 data rows, but got {len(rows)} total rows"
    assert rows[1][0] == "Alice"
    assert float(rows[1][1]) == 600.0
    assert int(rows[1][2]) == 1
    assert float(rows[1][3]) == 600.0
    assert rows[2][0] == "Charlie"
    assert float(rows[2][1]) == 300.0
    assert int(rows[2][2]) == 2
    assert float(rows[2][3]) == 900.0


def test_go_program_output_north_america_limit_3():
    run_go_program("North America", 3)
    rows = read_csv()
    assert len(rows) == 4, f"Expected 1 header + 3 data rows, but got {len(rows)} total rows"
    assert rows[3][0] == "Bob"
    assert float(rows[3][1]) == 150.0
    assert int(rows[3][2]) == 3
    assert float(rows[3][3]) == 1050.0


def test_go_program_output_europe_limit_1():
    run_go_program("Europe", 1)
    rows = read_csv()
    assert len(rows) == 2, f"Expected 1 header + 1 data row, but got {len(rows)} total rows"
    assert rows[1][0] == "Diana"
    assert float(rows[1][1]) == 1000.0
    assert int(rows[1][2]) == 1
    assert float(rows[1][3]) == 1000.0


def test_single_parameterized_window_query():
    result = subprocess.run(
        ["go", "run", "/tmp/inspect_go.go"], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Could not inspect Go source: {result.stderr}"
    info = json.loads(result.stdout)
    assert info["query_calls"] == 1, "Program must execute exactly one Query/QueryContext call"
    assert info["prepare_calls"] <= 1, "Program must not prepare multiple SQL statements"
    assert info["other_db_calls"] == 0, "Program must not use additional Exec or QueryRow database operations"
    assert len(info["args"]) >= 2, "Region and limit must be supplied as bound query arguments"

    sql = info["sql"]
    assert sql, "The SQL passed to Query/Prepare must be statically identifiable"
    bind = r"(?:\?(?:\d+)?|[:@$][A-Za-z_]\w*)"
    assert re.search(r"\bregion\s*=\s*" + bind, sql, re.I), "Region filter must use a SQL bind parameter"
    assert re.search(r"(?:\blimit\s*|\brank\s*<=\s*)" + bind, sql, re.I), "Top-N limit must use a SQL bind parameter"
    assert re.search(r"\brank\s*\(\s*\)\s*over\s*\(", sql, re.I | re.S), "Query must calculate rank with RANK() OVER"
    assert re.search(r"\bsum\s*\([^)]*\)\s*over\s*\(", sql, re.I | re.S), "Query must calculate running_total with SUM(...) OVER"


def assert_report(expected):
    rows = read_csv()
    assert rows and rows[0] == EXPECTED_HEADER
    assert len(rows) == len(expected) + 1
    for actual, wanted in zip(rows[1:], expected):
        assert len(actual) == 4
        assert actual[0] == wanted[0]
        assert math.isclose(float(actual[1]), wanted[1], rel_tol=1e-9, abs_tol=1e-7)
        assert int(actual[2]) == wanted[2]
        assert math.isclose(float(actual[3]), wanted[3], rel_tol=1e-9, abs_tol=1e-7)


def test_reports_are_derived_from_database_for_unseen_inputs():
    backup = "/tmp/ecommerce.db.original"
    shutil.copy2(DB_PATH, backup)
    token = uuid.uuid4().hex
    target = "unseen-' OR 1=1 --" + token
    other = "other-" + token
    rng = random.SystemRandom()

    customers = []
    orders = []
    totals = []
    oid = 1
    for i in range(7):
        name = f"Customer,{i}-{token}"
        cid = i + 101
        total = float(1000 - i * 83) + rng.randint(1, 40) / 100.0
        first = round(total * 0.37, 2)
        second = round(total - first, 2)
        customers.append((cid, name, target))
        orders.extend([(oid, cid, first, "2025-01-01"), (oid + 1, cid, second, "2025-02-01")])
        oid += 2
        totals.append((name, round(first + second, 2)))
    customers.append((999, "Decoy-" + token, other))
    orders.append((oid, 999, 99999.0, "2025-03-01"))

    try:
        os.remove(DB_PATH)
        con = sqlite3.connect(DB_PATH)
        con.executescript("""
            CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
            CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL, order_date TEXT);
        """)
        con.executemany("INSERT INTO customers(id,name,region) VALUES(?,?,?)", customers)
        con.executemany("INSERT INTO orders(id,customer_id,amount,order_date) VALUES(?,?,?,?)", orders)
        con.commit()
        con.close()

        ranked = sorted(totals, key=lambda x: x[1], reverse=True)
        running = 0.0
        expected_all = []
        for rank, (name, total) in enumerate(ranked, 1):
            running += total
            expected_all.append((name, total, rank, running))

        for limit in (2, 5, 7):
            run_go_program(target, limit)
            assert_report(expected_all[:limit])

        run_go_program(other, 1)
        assert_report([("Decoy-" + token, 99999.0, 1, 99999.0)])
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
