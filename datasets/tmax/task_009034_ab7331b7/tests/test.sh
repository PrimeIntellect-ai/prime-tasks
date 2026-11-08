#!/bin/bash
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_structure.go
package main

import (
    "bytes"
    "fmt"
    "go/ast"
    "go/parser"
    "go/printer"
    "go/token"
    "os"
    "strings"
)

func compact(fset *token.FileSet, n interface{}) string {
    var b bytes.Buffer
    if err := printer.Fprint(&b, fset, n); err != nil {
        return ""
    }
    return strings.Join(strings.Fields(b.String()), "")
}

func ident(e ast.Expr, name string) bool {
    id, ok := e.(*ast.Ident)
    return ok && id.Name == name
}

func basic(e ast.Expr, value string) bool {
    lit, ok := e.(*ast.BasicLit)
    return ok && lit.Value == value
}

func incOf(s ast.Stmt, name string) bool {
    x, ok := s.(*ast.IncDecStmt)
    return ok && x.Tok == token.INC && ident(x.X, name)
}

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintln(os.Stderr, "usage: check_structure file.go")
        os.Exit(1)
    }

    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    var mainFn, simFn *ast.FuncDecl
    for _, d := range file.Decls {
        if fn, ok := d.(*ast.FuncDecl); ok {
            if fn.Name.Name == "main" {
                mainFn = fn
            } else if fn.Name.Name == "simulateODE" {
                simFn = fn
            }
        }
    }
    if mainFn == nil || mainFn.Body == nil {
        fmt.Fprintln(os.Stderr, "main function is missing")
        os.Exit(1)
    }

    // Ensure the original Euler implementation was not replaced by a constant oracle.
    validSim := simFn != nil && simFn.Body != nil && len(simFn.Body.List) == 3
    if validSim {
        init, ok := simFn.Body.List[0].(*ast.AssignStmt)
        validSim = ok && init.Tok == token.DEFINE && len(init.Lhs) == 1 && len(init.Rhs) == 1 && ident(init.Lhs[0], "y") && ident(init.Rhs[0], "y0")
    }
    if validSim {
        loop, ok := simFn.Body.List[1].(*ast.ForStmt)
        validSim = ok && compact(fset, loop.Init) == "i:=0" && compact(fset, loop.Cond) == "i<steps" && incOf(loop.Post, "i") && len(loop.Body.List) == 1
        if validSim {
            update, ok := loop.Body.List[0].(*ast.AssignStmt)
            validSim = ok && update.Tok == token.ASSIGN && len(update.Lhs) == 1 && len(update.Rhs) == 1 && ident(update.Lhs[0], "y") && compact(fset, update.Rhs[0]) == "y-k*y*dt"
        }
    }
    if validSim {
        ret, ok := simFn.Body.List[2].(*ast.ReturnStmt)
        validSim = ok && len(ret.Results) == 1 && ident(ret.Results[0], "y")
    }
    if !validSim {
        fmt.Fprintln(os.Stderr, "simulateODE must retain the original Euler calculation")
        os.Exit(1)
    }

    sliceName := ""
    slicePos := -1
    for pos, stmt := range mainFn.Body.List {
        as, ok := stmt.(*ast.AssignStmt)
        if !ok || as.Tok != token.DEFINE || len(as.Lhs) != 1 || len(as.Rhs) != 1 {
            continue
        }
        call, ok := as.Rhs[0].(*ast.CallExpr)
        if !ok || !ident(call.Fun, "make") || len(call.Args) != 2 || !ident(call.Args[1], "N") {
            continue
        }
        typ, ok := call.Args[0].(*ast.ArrayType)
        if ok && typ.Len == nil && ident(typ.Elt, "float64") {
            if id, ok := as.Lhs[0].(*ast.Ident); ok {
                sliceName, slicePos = id.Name, pos
                break
            }
        }
    }
    if sliceName == "" {
        fmt.Fprintln(os.Stderr, "main must allocate a []float64 result slice of length N")
        os.Exit(1)
    }

    spawnPos := -1
    validWorker := false
    for pos, stmt := range mainFn.Body.List {
        loop, ok := stmt.(*ast.ForStmt)
        if !ok || compact(fset, loop.Init) != "i:=1" || compact(fset, loop.Cond) != "i<=N" || !incOf(loop.Post, "i") {
            continue
        }
        ast.Inspect(loop.Body, func(n ast.Node) bool {
            gs, ok := n.(*ast.GoStmt)
            if !ok {
                return true
            }
            lit, ok := gs.Call.Fun.(*ast.FuncLit)
            if !ok || len(gs.Call.Args) != 1 || !ident(gs.Call.Args[0], "i") || lit.Type.Params == nil || len(lit.Type.Params.List) != 1 || len(lit.Type.Params.List[0].Names) != 1 {
                return true
            }
            idName := lit.Type.Params.List[0].Names[0].Name
            simulatedVars := map[string]bool{}
            ast.Inspect(lit.Body, func(x ast.Node) bool {
                as, ok := x.(*ast.AssignStmt)
                if !ok || len(as.Lhs) != 1 || len(as.Rhs) != 1 {
                    return true
                }
                call, ok := as.Rhs[0].(*ast.CallExpr)
                if ok && ident(call.Fun, "simulateODE") && len(call.Args) == 4 && (basic(call.Args[0], "100.0") || basic(call.Args[0], "100")) && ident(call.Args[1], "k") && ident(call.Args[2], "steps") && ident(call.Args[3], "dt") {
                    if v, ok := as.Lhs[0].(*ast.Ident); ok {
                        simulatedVars[v.Name] = true
                    }
                }
                return true
            })
            ast.Inspect(lit.Body, func(x ast.Node) bool {
                as, ok := x.(*ast.AssignStmt)
                if !ok || as.Tok != token.ASSIGN || len(as.Lhs) != 1 || len(as.Rhs) != 1 {
                    return true
                }
                idx, ok := as.Lhs[0].(*ast.IndexExpr)
                if !ok || !ident(idx.X, sliceName) || compact(fset, idx.Index) != idName+"-1" {
                    return true
                }
                rhs, ok := as.Rhs[0].(*ast.Ident)
                if ok && simulatedVars[rhs.Name] {
                    validWorker = true
                }
                return true
            })
            return true
        })
        if validWorker {
            spawnPos = pos
            break
        }
    }
    if !validWorker || spawnPos <= slicePos {
        fmt.Fprintln(os.Stderr, "each goroutine must store its simulated yFinal at results[id-1]")
        os.Exit(1)
    }

    waitPos := -1
    for pos, stmt := range mainFn.Body.List {
        es, ok := stmt.(*ast.ExprStmt)
        if !ok {
            continue
        }
        call, ok := es.X.(*ast.CallExpr)
        if !ok {
            continue
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if ok && sel.Sel.Name == "Wait" {
            waitPos = pos
            break
        }
    }
    if waitPos <= spawnPos {
        fmt.Fprintln(os.Stderr, "the program must wait for all goroutines before reducing results")
        os.Exit(1)
    }

    reductionPos := -1
    totalName := ""
    for pos, stmt := range mainFn.Body.List {
        if pos <= waitPos {
            continue
        }
        loop, ok := stmt.(*ast.ForStmt)
        if !ok || compact(fset, loop.Init) != "i:=0" || compact(fset, loop.Cond) != "i<N" || !incOf(loop.Post, "i") {
            continue
        }
        for _, bodyStmt := range loop.Body.List {
            as, ok := bodyStmt.(*ast.AssignStmt)
            if !ok || as.Tok != token.ADD_ASSIGN || len(as.Lhs) != 1 || len(as.Rhs) != 1 {
                continue
            }
            lhs, lok := as.Lhs[0].(*ast.Ident)
            idx, rok := as.Rhs[0].(*ast.IndexExpr)
            if lok && rok && ident(idx.X, sliceName) && ident(idx.Index, "i") {
                totalName = lhs.Name
                reductionPos = pos
            }
        }
    }
    if reductionPos < 0 {
        fmt.Fprintln(os.Stderr, "results must be summed sequentially from index 0 to N-1 after Wait")
        os.Exit(1)
    }

    meanName := ""
    for pos, stmt := range mainFn.Body.List {
        if pos <= reductionPos {
            continue
        }
        as, ok := stmt.(*ast.AssignStmt)
        if !ok || len(as.Lhs) != 1 || len(as.Rhs) != 1 {
            continue
        }
        if compact(fset, as.Rhs[0]) == totalName+"/float64(N)" {
            if id, ok := as.Lhs[0].(*ast.Ident); ok {
                meanName = id.Name
                break
            }
        }
    }
    if meanName == "" {
        fmt.Fprintln(os.Stderr, "the reported mean must be derived from the sequential total")
        os.Exit(1)
    }

    printsMean := false
    ast.Inspect(mainFn.Body, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if !ok || !ident(sel.X, "fmt") || (sel.Sel.Name != "Printf" && sel.Sel.Name != "Println" && sel.Sel.Name != "Fprintf") {
            return true
        }
        for _, arg := range call.Args {
            if ident(arg, meanName) {
                printsMean = true
            }
        }
        return true
    })
    if !printsMean {
        fmt.Fprintln(os.Stderr, "printed output must use the mean produced by the sequential reduction")
        os.Exit(1)
    }
}
GO_EOF

if ! go build -o /tmp/check_structure /tmp/check_structure.go; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/workspace"
GO_SCRIPT = os.path.join(WORKSPACE_DIR, "simulate_network.go")
OUTPUT_FILE = os.path.join(WORKSPACE_DIR, "stable_output.txt")

def get_golden_value():
    golden_go = """
package main
import "fmt"
func simulateODE(y0 float64, k float64, steps int, dt float64) float64 {
    y := y0
    for i := 0; i < steps; i++ { y -= k*y*dt }
    return y
}
func main() {
    var total float64
    for i := 1; i <= 1000; i++ {
        total += simulateODE(100.0, 0.1 + float64(i)*0.0001, 1000, 0.01)
    }
    fmt.Printf("%.15f\\n", total/1000.0)
}
"""
    with tempfile.NamedTemporaryFile(suffix=".go", mode="w", delete=False) as f:
        f.write(golden_go)
        temp_name = f.name
    try:
        result = subprocess.run(["go", "run", temp_name], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    finally:
        os.remove(temp_name)

def test_go_script_modified_correctly():
    assert os.path.isfile(GO_SCRIPT), f"File {GO_SCRIPT} does not exist."
    with open(GO_SCRIPT, "r") as f:
        content = f.read()
    assert "mu.Lock()" not in content, "The script still contains mu.Lock(), which should have been removed."
    assert "sync.Mutex" not in content, "The script still imports/uses sync.Mutex."

    result = subprocess.run(["/tmp/check_structure", GO_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr.strip() or "The required deterministic indexed reduction was not found."

def test_output_file_exists_and_correct():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    with open(OUTPUT_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 5, f"Expected exactly 5 lines of output, found {len(lines)}."
    golden_val = get_golden_value()
    for i, line in enumerate(lines):
        assert line == golden_val, f"Line {i+1} does not match the expected deterministic output. Expected {golden_val}, got {line}."

def test_script_compiles_and_runs():
    result = subprocess.run(["go", "run", GO_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to run. Stderr: {result.stderr}"
    output = result.stdout.strip()
    golden_val = get_golden_value()
    assert output == golden_val, f"Script output {output} does not match golden value {golden_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
