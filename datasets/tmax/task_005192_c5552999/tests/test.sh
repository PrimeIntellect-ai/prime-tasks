#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_reduction.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func identName(e ast.Expr) string {
    if id, ok := e.(*ast.Ident); ok {
        return id.Name
    }
    return ""
}

func isAppendAssignment(s ast.Stmt) (slice, value string, ok bool) {
    a, ok := s.(*ast.AssignStmt)
    if !ok || len(a.Lhs) != 1 || len(a.Rhs) != 1 {
        return "", "", false
    }
    lhs := identName(a.Lhs[0])
    call, ok := a.Rhs[0].(*ast.CallExpr)
    if !ok || identName(call.Fun) != "append" || len(call.Args) != 2 {
        return "", "", false
    }
    if lhs == "" || identName(call.Args[0]) != lhs {
        return "", "", false
    }
    value = identName(call.Args[1])
    return lhs, value, value != ""
}

func isAscendingSort(s ast.Stmt, slice string) bool {
    e, ok := s.(*ast.ExprStmt)
    if !ok {
        return false
    }
    call, ok := e.X.(*ast.CallExpr)
    if !ok {
        return false
    }
    sel, ok := call.Fun.(*ast.SelectorExpr)
    if !ok || identName(sel.X) != "sort" {
        return false
    }

    if sel.Sel.Name == "Float64s" && len(call.Args) == 1 && identName(call.Args[0]) == slice {
        return true
    }

    if sel.Sel.Name == "Sort" && len(call.Args) == 1 {
        conv, ok := call.Args[0].(*ast.CallExpr)
        if !ok || len(conv.Args) != 1 || identName(conv.Args[0]) != slice {
            return false
        }
        convSel, ok := conv.Fun.(*ast.SelectorExpr)
        return ok && identName(convSel.X) == "sort" && convSel.Sel.Name == "Float64Slice"
    }

    if sel.Sel.Name == "Slice" && len(call.Args) == 2 && identName(call.Args[0]) == slice {
        fn, ok := call.Args[1].(*ast.FuncLit)
        if !ok {
            return false
        }
        ascending := false
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            b, ok := n.(*ast.BinaryExpr)
            if !ok || b.Op != token.LSS {
                return true
            }
            left, lok := b.X.(*ast.IndexExpr)
            right, rok := b.Y.(*ast.IndexExpr)
            if lok && rok && identName(left.X) == slice && identName(right.X) == slice {
                ascending = true
            }
            return true
        })
        return ascending
    }
    return false
}

func rangeSum(s ast.Stmt, slice string) (total string, ok bool) {
    r, ok := s.(*ast.RangeStmt)
    if !ok || identName(r.X) != slice {
        return "", false
    }
    value := identName(r.Value)
    if value == "" {
        return "", false
    }
    for _, bodyStmt := range r.Body.List {
        a, ok := bodyStmt.(*ast.AssignStmt)
        if ok && a.Tok == token.ADD_ASSIGN && len(a.Lhs) == 1 && len(a.Rhs) == 1 && identName(a.Rhs[0]) == value {
            total = identName(a.Lhs[0])
            if total != "" {
                return total, true
            }
        }
    }
    return "", false
}

func mutatesTotal(n ast.Node, total string) bool {
    found := false
    ast.Inspect(n, func(n ast.Node) bool {
        a, ok := n.(*ast.AssignStmt)
        if ok && a.Tok == token.ADD_ASSIGN && len(a.Lhs) == 1 && identName(a.Lhs[0]) == total {
            found = true
        }
        return true
    })
    return found
}

func printsTotal(s ast.Stmt, total string) bool {
    found := false
    ast.Inspect(s, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok || len(call.Args) < 2 {
            return true
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if !ok || identName(sel.X) != "fmt" || sel.Sel.Name != "Printf" {
            return true
        }
        lit, ok := call.Args[0].(*ast.BasicLit)
        if !ok || lit.Kind != token.STRING || identName(call.Args[1]) != total {
            return true
        }
        format, err := strconv.Unquote(lit.Value)
        if err == nil && format == "%.10f\n" {
            found = true
        }
        return true
    })
    return found
}

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintln(os.Stderr, "usage: check_reduction source.go")
        os.Exit(2)
    }
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    var mainBody *ast.BlockStmt
    for _, d := range file.Decls {
        if fn, ok := d.(*ast.FuncDecl); ok && fn.Name.Name == "main" {
            mainBody = fn.Body
            break
        }
    }
    if mainBody == nil {
        fmt.Fprintln(os.Stderr, "main function not found")
        os.Exit(1)
    }

    for collectIndex, stmt := range mainBody.List {
        r, ok := stmt.(*ast.RangeStmt)
        if !ok {
            continue
        }
        channelValue := identName(r.Value)
        if channelValue == "" {
            continue
        }
        slice := ""
        for _, bodyStmt := range r.Body.List {
            candidate, appended, ok := isAppendAssignment(bodyStmt)
            if ok && appended == channelValue {
                slice = candidate
                break
            }
        }
        if slice == "" {
            continue
        }

        for sortIndex := collectIndex + 1; sortIndex < len(mainBody.List); sortIndex++ {
            if !isAscendingSort(mainBody.List[sortIndex], slice) {
                continue
            }
            for sumIndex := sortIndex + 1; sumIndex < len(mainBody.List); sumIndex++ {
                total, ok := rangeSum(mainBody.List[sumIndex], slice)
                if !ok || mutatesTotal(r.Body, total) {
                    continue
                }
                for printIndex := sumIndex + 1; printIndex < len(mainBody.List); printIndex++ {
                    if printsTotal(mainBody.List[printIndex], total) {
                        return
                    }
                }
            }
        }
    }

    fmt.Fprintln(os.Stderr, "main must collect channel values into a slice, sort that slice numerically ascending, then sequentially sum and print it")
    os.Exit(1)
}
GO_EOF

go build -o /tmp/check_reduction /tmp/check_reduction.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess

GO_PATH = "/home/user/gc_calc.go"
DATA_PATH = "/home/user/data.fasta"
RESULT_PATH = "/home/user/fixed_result.txt"


def run_program():
    proc = subprocess.run(
        ["go", "run", GO_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    assert proc.returncode == 0, f"gc_calc.go failed to compile or run:\n{proc.stderr}"
    assert re.fullmatch(r"-?\d+\.\d{10}\n", proc.stdout), (
        f"Program output must be exactly one number with 10 decimal places; got {proc.stdout!r}"
    )
    return proc.stdout


def calc_weight(seq):
    total = 0.0
    for i, c in enumerate(seq):
        total += (1.0 if c in "GC" else 0.5) / float(i + 1)
    return total


def test_fixed_result_exists_and_correct():
    assert os.path.isfile(RESULT_PATH), f"Expected output file {RESULT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(RESULT_PATH).st_mode), f"{RESULT_PATH} must be a regular file."
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    assert content == "23.3993048391", (
        f"The output in {RESULT_PATH} is incorrect. Expected '23.3993048391', got {content!r}."
    )


def test_go_code_modified_for_sorting():
    assert os.path.isfile(GO_PATH), f"Go source file {GO_PATH} is missing."
    assert stat.S_ISREG(os.stat(GO_PATH).st_mode), f"{GO_PATH} must be a regular file."
    with open(GO_PATH, "r") as f:
        content = f.read()
    assert re.search(r'"sort"', content), (
        "The 'sort' package does not seem to be imported in the Go code, which is required for sorting the slice."
    )
    assert '%.10f' in content, "The output format specifier '%.10f' is missing in the Go code."

    proc = subprocess.run(
        ["/tmp/check_reduction", GO_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr.strip()


def test_program_runs_and_result_came_from_program():
    output = run_program()
    with open(RESULT_PATH, "r") as f:
        saved = f.read().strip()
    assert output.strip() == saved, (
        "fixed_result.txt does not match the output produced by the submitted Go program on data.fasta"
    )


def test_program_on_fresh_derived_input():
    with open(DATA_PATH, "rb") as f:
        original = f.read()

    rng = random.SystemRandom()
    alphabet = "ACGT"
    sequences = []
    for _ in range(rng.randrange(35, 70)):
        length = rng.randrange(7, 180)
        sequences.append("".join(rng.choice(alphabet) for _ in range(length)))

    fasta_parts = []
    for i, seq in enumerate(sequences):
        fasta_parts.append(f">generated_{i}\n")
        cut = rng.randrange(1, len(seq) + 1)
        fasta_parts.append(seq[:cut] + "\n")
        if cut < len(seq):
            fasta_parts.append(seq[cut:] + "\n")

    expected_weights = sorted(calc_weight(seq) for seq in sequences)
    expected = f"{sum(expected_weights):.10f}\n"

    try:
        with open(DATA_PATH, "w") as f:
            f.write("".join(fasta_parts))
        actual = run_program()
        assert actual == expected, (
            f"Program failed on verifier-generated FASTA input: expected {expected!r}, got {actual!r}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
