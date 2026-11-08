#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/audit_submission.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strings"
)

const root = "/home/user/analysis"

func containsIdent(n ast.Node, name string) bool {
    found := false
    ast.Inspect(n, func(x ast.Node) bool {
        if id, ok := x.(*ast.Ident); ok && id.Name == name { found = true }
        return !found
    })
    return found
}

func callName(c *ast.CallExpr) string {
    if id, ok := c.Fun.(*ast.Ident); ok { return id.Name }
    return ""
}

func hasFailureCall(n ast.Node) bool {
    found := false
    ast.Inspect(n, func(x ast.Node) bool {
        c, ok := x.(*ast.CallExpr)
        if !ok { return true }
        s, ok := c.Fun.(*ast.SelectorExpr)
        if ok {
            switch s.Sel.Name {
            case "Error", "Errorf", "Fatal", "Fatalf", "Fail", "FailNow":
                found = true
            }
        }
        return !found
    })
    return found
}

func main() {
    fset := token.NewFileSet()
    pkgs, err := parser.ParseDir(fset, root, nil, 0)
    if err != nil { panic(err) }

    funcs := map[string]*ast.FuncDecl{}
    var testFile *ast.File
    hasGo, hasChan, hasWG := false, false, false

    for _, pkg := range pkgs {
        for filename, file := range pkg.Files {
            if filepath.Base(filename) == "analyzer_test.go" { testFile = file }
            ast.Inspect(file, func(n ast.Node) bool {
                switch x := n.(type) {
                case *ast.GoStmt:
                    hasGo = true
                case *ast.ChanType, *ast.SendStmt:
                    hasChan = true
                case *ast.UnaryExpr:
                    if x.Op == token.ARROW { hasChan = true }
                case *ast.SelectorExpr:
                    if x.Sel.Name == "WaitGroup" || x.Sel.Name == "Add" || x.Sel.Name == "Done" || x.Sel.Name == "Wait" { hasWG = true }
                case *ast.Ident:
                    if x.Name == "WaitGroup" { hasWG = true }
                }
                return true
            })
            if !strings.HasSuffix(filename, "_test.go") {
                for _, d := range file.Decls {
                    if fn, ok := d.(*ast.FuncDecl); ok && fn.Recv == nil { funcs[fn.Name] = fn }
                }
            }
        }
    }
    if testFile == nil { panic("analyzer_test.go could not be parsed") }

    tested := ""
    for _, d := range testFile.Decls {
        fn, ok := d.(*ast.FuncDecl)
        if !ok || !strings.HasPrefix(fn.Name.Name, "Test") || fn.Body == nil { continue }
        tableSize := 0
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            if c, ok := n.(*ast.CompositeLit); ok && len(c.Elts) > tableSize { tableSize = len(c.Elts) }
            return true
        })
        if tableSize < 3 { continue }

        ast.Inspect(fn.Body, func(n ast.Node) bool {
            r, ok := n.(*ast.RangeStmt)
            if !ok || tested != "" { return true }
            rangeName := ""
            if id, ok := r.Value.(*ast.Ident); ok { rangeName = id.Name }
            if rangeName == "" {
                if id, ok := r.Key.(*ast.Ident); ok { rangeName = id.Name }
            }
            if rangeName == "" { return true }

            assigned := map[string]string{}
            ast.Inspect(r.Body, func(y ast.Node) bool {
                a, ok := y.(*ast.AssignStmt)
                if !ok { return true }
                for i, rhs := range a.Rhs {
                    c, ok := rhs.(*ast.CallExpr)
                    if !ok || !containsIdent(c, rangeName) { continue }
                    name := callName(c)
                    if _, exists := funcs[name]; !exists { continue }
                    if i < len(a.Lhs) {
                        if id, ok := a.Lhs[i].(*ast.Ident); ok { assigned[id.Name] = name }
                    } else if len(a.Lhs) == 1 {
                        if id, ok := a.Lhs[0].(*ast.Ident); ok { assigned[id.Name] = name }
                    }
                }
                return true
            })
            ast.Inspect(r.Body, func(y ast.Node) bool {
                iff, ok := y.(*ast.IfStmt)
                if !ok || !containsIdent(iff.Cond, rangeName) || !hasFailureCall(iff.Body) { return true }
                for resultName, prodName := range assigned {
                    if containsIdent(iff.Cond, resultName) { tested = prodName; return false }
                }
                ast.Inspect(iff.Cond, func(z ast.Node) bool {
                    c, ok := z.(*ast.CallExpr)
                    if ok {
                        name := callName(c)
                        if _, exists := funcs[name]; exists && containsIdent(c, rangeName) { tested = name; return false }
                    }
                    return tested == ""
                })
                return tested == ""
            })
            return tested == ""
        })
        if tested != "" { break }
    }
    if tested == "" { panic("no non-vacuous table-driven test of a production GC function with at least 3 cases was found") }

    var reaches func(ast.Node, map[string]bool) bool
    reaches = func(n ast.Node, seen map[string]bool) bool {
        reached := false
        ast.Inspect(n, func(x ast.Node) bool {
            c, ok := x.(*ast.CallExpr)
            if !ok { return !reached }
            name := callName(c)
            if name == tested { reached = true; return false }
            if fn := funcs[name]; fn != nil && !seen[name] {
                seen[name] = true
                if reaches(fn.Body, seen) { reached = true; return false }
            }
            return !reached
        })
        return reached
    }

    concurrentGC := false
    for _, fn := range funcs {
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            g, ok := n.(*ast.GoStmt)
            if ok && reaches(g.Call, map[string]bool{}) { concurrentGC = true; return false }
            return !concurrentGC
        })
        if concurrentGC { break }
    }
    if !hasGo || !(hasChan || hasWG) || !concurrentGC {
        panic("the GC function exercised by the regression test is not reachable from a real goroutine using channels or a WaitGroup")
    }
    fmt.Println("AST audit passed")
    _ = os.Stdout
}
GO_EOF

cat << 'GO_EOF' > /tmp/check_png.go
package main

import (
    "fmt"
    "image"
    _ "image/png"
    "os"
)

func main() {
    if len(os.Args) != 2 { panic("PNG path required") }
    f, err := os.Open(os.Args[1])
    if err != nil { panic(err) }
    defer f.Close()
    img, format, err := image.Decode(f)
    if err != nil || format != "png" { panic("file is not a decodable PNG") }
    b := img.Bounds()
    if b.Dx() < 100 || b.Dy() < 100 { panic("plot image is implausibly small") }
    colors := map[string]bool{}
    nonWhite := 0
    for y := b.Min.Y; y < b.Max.Y; y++ {
        for x := b.Min.X; x < b.Max.X; x++ {
            r, g, bl, a := img.At(x, y).RGBA()
            colors[fmt.Sprintf("%d,%d,%d,%d", r, g, bl, a)] = true
            if r < 0xf000 || g < 0xf000 || bl < 0xf000 { nonWhite++ }
        }
    }
    if len(colors) < 3 || nonWhite < 100 { panic("PNG does not contain a substantive chart") }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import pytest

ANALYSIS = '/home/user/analysis'
FASTA = '/home/user/data/input.fasta'
EXPECTED_KEYS = {"group_a_mean", "group_b_mean", "difference", "significant", "num_group_a", "num_group_b"}

def calculate_ground_truth(fasta_path):
    group_a = []
    group_b = []
    with open(fasta_path, 'r') as f:
        seq = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if seq:
                    gc = (seq.count('G') + seq.count('C')) / len(seq) * 100
                    (group_a if 'ATGCATGC' in seq else group_b).append(gc)
                seq = ""
            else:
                seq += line
        if seq:
            gc = (seq.count('G') + seq.count('C')) / len(seq) * 100
            (group_a if 'ATGCATGC' in seq else group_b).append(gc)
    mean_a = sum(group_a) / len(group_a) if group_a else 0.0
    mean_b = sum(group_b) / len(group_b) if group_b else 0.0
    diff = abs(mean_a - mean_b)
    return {"group_a_mean": mean_a, "group_b_mean": mean_b, "difference": diff,
            "significant": diff > 5.0, "num_group_a": len(group_a), "num_group_b": len(group_b)}

def assert_results(path, truth):
    with open(path) as f:
        results = json.load(f)
    assert set(results) == EXPECTED_KEYS, "results.json has the wrong structure"
    assert results["num_group_a"] == truth["num_group_a"]
    assert results["num_group_b"] == truth["num_group_b"]
    assert results["significant"] is truth["significant"]
    for key in ("group_a_mean", "group_b_mean", "difference"):
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool)
        assert math.isfinite(results[key])
        assert math.isclose(results[key], truth[key], abs_tol=0.00051), f"incorrect rounded {key}"

def run_application_and_check():
    for name in ('results.json', 'gc_plot.png'):
        path = os.path.join(ANALYSIS, name)
        if os.path.exists(path): os.remove(path)
    result = subprocess.run(['go', 'run', '.'], cwd=ANALYSIS, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"application failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(os.path.join(ANALYSIS, 'results.json'))
    assert os.path.isfile(os.path.join(ANALYSIS, 'gc_plot.png'))
    assert_results(os.path.join(ANALYSIS, 'results.json'), calculate_ground_truth(FASTA))
    png = subprocess.run(['go', 'run', '/tmp/check_png.go', os.path.join(ANALYSIS, 'gc_plot.png')],
                         capture_output=True, text=True, timeout=60)
    assert png.returncode == 0, f"invalid/substantively empty plot:\n{png.stdout}\n{png.stderr}"

def test_00_application_executes_on_derived_inputs():
    with open(FASTA, 'rb') as f:
        original = f.read()
    cases = [
        b'>a1\nATGCATGCGGGG\n>a2\nAAAAATGCATGCAAAA\n>b1\nAAAAAAAAAAAA\n>b2\nCCCCCCCCCCCC\n',
        b'>x1\nGGGGATGC\nATGCGGGG\n>x2\nATGCATGCAATT\n>y1\nATATATATATAT\n>y2\nCCCCAATTCC\n>y3\nGATTACAGATTA\n'
    ]
    try:
        for data in cases:
            with open(FASTA, 'wb') as f: f.write(data)
            run_application_and_check()
    finally:
        with open(FASTA, 'wb') as f: f.write(original)
    run_application_and_check()

def test_results_json():
    results_path = '/home/user/analysis/results.json'
    assert os.path.isfile(results_path), f"Missing {results_path}"
    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON")
    truth = calculate_ground_truth('/home/user/data/input.fasta')
    assert results.get("num_group_a") == truth["num_group_a"], "Incorrect count for Group A"
    assert results.get("num_group_b") == truth["num_group_b"], "Incorrect count for Group B"
    assert results.get("significant") == truth["significant"], "Incorrect significance boolean"
    assert math.isclose(results.get("group_a_mean", 0), truth["group_a_mean"], abs_tol=0.005), "Incorrect Group A mean"
    assert math.isclose(results.get("group_b_mean", 0), truth["group_b_mean"], abs_tol=0.005), "Incorrect Group B mean"
    assert math.isclose(results.get("difference", 0), truth["difference"], abs_tol=0.005), "Incorrect difference"

def test_plot_exists():
    plot_path = '/home/user/analysis/gc_plot.png'
    assert os.path.isfile(plot_path), f"Missing {plot_path}"
    with open(plot_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"File {plot_path} is not a valid PNG image"
    result = subprocess.run(['go', 'run', '/tmp/check_png.go', plot_path], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stderr

def test_go_test_passes():
    test_file = '/home/user/analysis/analyzer_test.go'
    assert os.path.isfile(test_file), f"Missing {test_file}"
    with open(test_file, 'r') as f:
        content = f.read()
        assert "func Test" in content, f"No tests found in {test_file}"
    result = subprocess.run(['go', 'test'], cwd=ANALYSIS, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"go test failed:\n{result.stdout}\n{result.stderr}"
    audit = subprocess.run(['go', 'run', '/tmp/audit_submission.go'], cwd=ANALYSIS,
                           capture_output=True, text=True, timeout=60)
    assert audit.returncode == 0, f"source audit failed:\n{audit.stdout}\n{audit.stderr}"

def test_concurrency_used():
    main_file = '/home/user/analysis/main.go'
    assert os.path.isfile(main_file), f"Missing {main_file}"
    with open(main_file, 'r') as f:
        content = f.read()
        has_go = "go " in content
        has_chan = "chan " in content
        has_wg = "WaitGroup" in content
        assert has_go and (has_chan or has_wg), "Concurrency primitives (goroutines and channels/WaitGroups) not found in main.go"
    audit = subprocess.run(['go', 'run', '/tmp/audit_submission.go'], cwd=ANALYSIS,
                           capture_output=True, text=True, timeout=60)
    assert audit.returncode == 0, f"concurrency/source audit failed:\n{audit.stdout}\n{audit.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
