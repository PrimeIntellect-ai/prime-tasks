#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'GO_EOF' > /tmp/check_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
    "strings"
)

func main() {
    path := os.Args[len(os.Args)-1]
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    values := map[string]string{}
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.ValueSpec:
            for i, name := range x.Names {
                if i < len(x.Values) {
                    if s, ok := evalString(x.Values[i], values); ok {
                        values[name.Name] = s
                    }
                }
            }
        case *ast.AssignStmt:
            for i, lhs := range x.Lhs {
                if i >= len(x.Rhs) {
                    continue
                }
                id, ok := lhs.(*ast.Ident)
                if !ok {
                    continue
                }
                if s, ok := evalString(x.Rhs[i], values); ok {
                    values[id.Name] = s
                }
            }
        }
        return true
    })

    found := false
    ast.Inspect(file, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if !ok {
            return true
        }
        queryIndex := -1
        switch sel.Sel.Name {
        case "Query", "QueryRow":
            queryIndex = 0
        case "QueryContext", "QueryRowContext":
            queryIndex = 1
        default:
            return true
        }
        if len(call.Args) <= queryIndex+1 {
            return true
        }
        query, ok := evalString(call.Args[queryIndex], values)
        if !ok {
            return true
        }
        upper := strings.ToUpper(query)
        placeholder := strings.Contains(query, "?") || strings.Contains(query, "$1") || strings.Contains(query, "@")
        if strings.Contains(upper, "LAG(") && placeholder {
            found = true
        }
        return true
    })

    if !found {
        fmt.Fprintln(os.Stderr, "no database query call was found that both uses LAG() and binds a parameter placeholder")
        os.Exit(1)
    }
}

func evalString(expr ast.Expr, values map[string]string) (string, bool) {
    switch x := expr.(type) {
    case *ast.BasicLit:
        if x.Kind != token.STRING {
            return "", false
        }
        s, err := strconv.Unquote(x.Value)
        return s, err == nil
    case *ast.Ident:
        s, ok := values[x.Name]
        return s, ok
    case *ast.ParenExpr:
        return evalString(x.X, values)
    case *ast.BinaryExpr:
        if x.Op != token.ADD {
            return "", false
        }
        left, lok := evalString(x.X, values)
        right, rok := evalString(x.Y, values)
        if !lok || !rok {
            return "", false
        }
        return left + right, true
    }
    return "", false
}
GO_EOF

cat <<'GO_EOF' > /tmp/poison_lag.go
package main

import (
    "go/ast"
    "go/format"
    "go/parser"
    "go/token"
    "os"
    "regexp"
    "strconv"
)

func main() {
    in := os.Args[len(os.Args)-2]
    out := os.Args[len(os.Args)-1]
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, in, nil, parser.ParseComments)
    if err != nil {
        panic(err)
    }
    re := regexp.MustCompile(`(?i)LAG`)
    ast.Inspect(file, func(n ast.Node) bool {
        lit, ok := n.(*ast.BasicLit)
        if !ok || lit.Kind != token.STRING {
            return true
        }
        value, err := strconv.Unquote(lit.Value)
        if err == nil && re.MatchString(value) {
            lit.Value = strconv.Quote(re.ReplaceAllString(value, "AUDIT_NO_SUCH_WINDOW_FUNC"))
        }
        return true
    })
    f, err := os.Create(out)
    if err != nil {
        panic(err)
    }
    defer f.Close()
    if err := format.Node(f, fset, file); err != nil {
        panic(err)
    }
}
GO_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess

import pytest

REPORT = "/home/user/report.json"
SOURCE = "/home/user/analyze.go"
DATABASE = "/home/user/backups.db"


def load_report():
    assert os.path.exists(REPORT), f"Report file {REPORT} does not exist."
    assert os.path.isfile(REPORT), f"{REPORT} is not a file."
    with open(REPORT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT} does not contain valid JSON.")


def test_report_json_exists_and_content():
    data = load_report()
    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert len(data) == 2, f"Expected 2 entries in the JSON array, got {len(data)}."

    expected_data = [
        {
            "database_name": "auth_db",
            "latest_backup_time": "2023-10-04 10:00:00",
            "latest_size_bytes": 1100,
            "size_diff_from_previous": 50,
        },
        {
            "database_name": "payments_db",
            "latest_backup_time": "2023-10-02 11:00:00",
            "latest_size_bytes": 4800,
            "size_diff_from_previous": -200,
        },
    ]

    data_sorted = sorted(data, key=lambda x: x.get("database_name", ""))
    expected_sorted = sorted(expected_data, key=lambda x: x["database_name"])
    for i, (actual, expected) in enumerate(zip(data_sorted, expected_sorted)):
        assert actual.get("database_name") == expected["database_name"], f"Mismatch in database_name at index {i}"
        assert actual.get("latest_backup_time") == expected["latest_backup_time"], f"Mismatch in latest_backup_time at index {i}"
        assert actual.get("latest_size_bytes") == expected["latest_size_bytes"], f"Mismatch in latest_size_bytes at index {i}"
        assert actual.get("size_diff_from_previous") == expected["size_diff_from_previous"], f"Mismatch in size_diff_from_previous at index {i}"


def test_analyze_go_requirements():
    assert os.path.exists(SOURCE), f"Go source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    with open(SOURCE, "r") as f:
        content = f.read()

    has_placeholder = "?" in content or "$1" in content or "@" in content
    assert has_placeholder, "The Go program does not appear to use parameterized queries (e.g., '?' or '$1')."
    assert "LAG" in content.upper(), "The Go program does not appear to use the 'LAG' window function."

    checked = subprocess.run(
        ["go", "run", "/tmp/check_ast.go", "--", SOURCE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert checked.returncode == 0, checked.stderr


def expected_for(cluster):
    con = sqlite3.connect(DATABASE)
    try:
        rows = con.execute(
            """
            WITH successful AS (
                SELECT d.id AS db_id, d.name AS database_name,
                       b.job_id, b.run_time, b.size_bytes,
                       LAG(b.size_bytes) OVER (
                           PARTITION BY d.id ORDER BY b.run_time, b.job_id
                       ) AS previous_size
                FROM target_dbs AS d
                JOIN backup_jobs AS b ON b.db_id = d.id
                WHERE d.cluster_name = ? AND b.status = 'SUCCESS'
            ), ranked AS (
                SELECT *, ROW_NUMBER() OVER (
                    PARTITION BY db_id ORDER BY run_time DESC, job_id DESC
                ) AS rn
                FROM successful
            )
            SELECT database_name, run_time, size_bytes,
                   COALESCE(size_bytes - previous_size, 0)
            FROM ranked
            WHERE rn = 1
            ORDER BY database_name
            """,
            (cluster,),
        ).fetchall()
    finally:
        con.close()
    return [
        {
            "database_name": row[0],
            "latest_backup_time": row[1],
            "latest_size_bytes": row[2],
            "size_diff_from_previous": row[3],
        }
        for row in rows
    ]


def run_program(cluster):
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["go", "run", SOURCE, cluster],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"program failed for {cluster!r}:\n{result.stderr}"
    data = load_report()
    assert isinstance(data, list), "Report JSON root must be a list."
    return data


def test_program_executes_against_database_and_uses_lag():
    token = secrets.token_hex(8)
    unusual_cluster = f"audit_{token}' OR 1=1 --"
    db_backup = f"/tmp/backups-{token}.db"
    source_backup = f"/tmp/analyze-{token}.go"
    shutil.copy2(DATABASE, db_backup)
    shutil.copy2(SOURCE, source_backup)

    try:
        con = sqlite3.connect(DATABASE)
        try:
            cur = con.cursor()
            names = [f"zeta_{token}", f"alpha_{token}", f"middle_{token}"]
            ids = []
            for name in names:
                cur.execute("INSERT INTO target_dbs(name, cluster_name) VALUES (?, ?)", (name, unusual_cluster))
                ids.append(cur.lastrowid)

            jobs = [
                (ids[0], "2042-01-01 01:00:00", "SUCCESS", 7311),
                (ids[0], "2042-01-02 01:00:00", "FAILED", 999999),
                (ids[0], "2042-01-03 01:00:00", "SUCCESS", 8127),
                (ids[1], "2042-02-01 02:00:00", "SUCCESS", 4401),
                (ids[2], "2042-03-01 03:00:00", "SUCCESS", 9000),
                (ids[2], "2042-03-02 03:00:00", "SUCCESS", 8500),
                (ids[2], "2042-03-03 03:00:00", "SUCCESS", 8777),
            ]
            cur.executemany(
                "INSERT INTO backup_jobs(db_id, run_time, status, size_bytes) VALUES (?, ?, ?, ?)",
                jobs,
            )
            cur.execute(
                "INSERT INTO backup_jobs(db_id, run_time, status, size_bytes) VALUES (?, ?, ?, ?)",
                (1, "2099-12-31 23:59:59", "SUCCESS", 100000 + int(token[:4], 16)),
            )
            con.commit()
        finally:
            con.close()

        expected_unusual = expected_for(unusual_cluster)
        actual_unusual = run_program(unusual_cluster)
        assert actual_unusual == expected_unusual, "Report did not match the randomized cluster or was not alphabetically sorted."

        expected_eu = expected_for("eu-central-1")
        actual_eu = run_program("eu-central-1")
        assert actual_eu == expected_eu, "Program did not react to changed backup data."

        poisoned = subprocess.run(
            ["go", "run", "/tmp/poison_lag.go", "--", SOURCE, "/tmp/poisoned-analyze.go"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert poisoned.returncode == 0, poisoned.stderr
        shutil.copy2("/tmp/poisoned-analyze.go", SOURCE)
        if os.path.lexists(REPORT):
            os.remove(REPORT)
        result = subprocess.run(
            ["go", "run", SOURCE, unusual_cluster],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        poisoned_data = None
        if result.returncode == 0 and os.path.isfile(REPORT):
            try:
                with open(REPORT) as f:
                    poisoned_data = json.load(f)
            except (json.JSONDecodeError, OSError):
                pass
        assert result.returncode != 0 or poisoned_data != expected_unusual, \
            "Replacing LAG() in SQL had no effect; the required window function does not drive the report."
    finally:
        shutil.copy2(source_backup, SOURCE)
        shutil.copy2(db_backup, DATABASE)
        for path in (db_backup, source_backup, "/tmp/poisoned-analyze.go"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
