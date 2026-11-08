#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path
import pytest

REPO_DIR = Path("/app/vendored/go-cache-server")


def test_bad_commit_hash():
    """The leak was introduced by the second commit after v1.0.0."""
    try:
        output = subprocess.check_output(
            ["git", "rev-list", "--reverse", "v1.0.0..HEAD"],
            cwd=REPO_DIR,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to inspect git history in {REPO_DIR}: {e}")

    commits = [line.strip() for line in output.splitlines() if line.strip()]
    if len(commits) < 2:
        pytest.fail(f"Expected at least 2 commits after v1.0.0, found {len(commits)}")
    expected_bad_commit = commits[1]

    bad_commit_file = Path("/home/user/bad_commit.txt")
    assert bad_commit_file.exists(), f"Expected {bad_commit_file} to exist."
    assert bad_commit_file.is_file(), f"Expected {bad_commit_file} to be a file."

    actual_bad_commit = bad_commit_file.read_text().strip()
    assert re.fullmatch(r"[0-9a-f]{40}", actual_bad_commit), \
        "bad_commit.txt must contain one full lowercase 40-character SHA"
    assert actual_bad_commit == expected_bad_commit, \
        f"Incorrect bad commit hash. Expected {expected_bad_commit}, but got {actual_bad_commit}"


def test_go_code_fixed():
    """Compile the package and run a real test that checks all WithCancel paths cancel."""
    verifier_test = REPO_DIR / "zz_verifier_goroutine_test.go"
    verifier_test.write_text(r'''package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "testing"
)

func isCancelCall(expr ast.Expr, name string) bool {
    call, ok := expr.(*ast.CallExpr)
    if !ok {
        return false
    }
    ident, ok := call.Fun.(*ast.Ident)
    return ok && ident.Name == name
}

func blockGuaranteesCancel(stmts []ast.Stmt, name string) bool {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
        case *ast.ExprStmt:
            if isCancelCall(s.X, name) {
                return true
            }
        case *ast.DeferStmt:
            ident, ok := s.Call.Fun.(*ast.Ident)
            if ok && ident.Name == name {
                return true
            }
        case *ast.IfStmt:
            left := blockGuaranteesCancel(s.Body.List, name)
            right := false
            switch e := s.Else.(type) {
            case *ast.BlockStmt:
                right = blockGuaranteesCancel(e.List, name)
            case *ast.IfStmt:
                right = blockGuaranteesCancel([]ast.Stmt{e}, name)
            }
            if left && right {
                return true
            }
        case *ast.ReturnStmt:
            return false
        }
    }
    return false
}

func TestGoroutineLeak(t *testing.T) {
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, "server.go", nil, 0)
    if err != nil {
        t.Fatalf("cannot parse server.go: %v", err)
    }

    for _, decl := range file.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Name.Name != "HandleRequest" || fn.Body == nil {
            continue
        }

        for i, stmt := range fn.Body.List {
            assign, ok := stmt.(*ast.AssignStmt)
            if !ok || len(assign.Lhs) < 2 || len(assign.Rhs) != 1 {
                continue
            }
            call, ok := assign.Rhs[0].(*ast.CallExpr)
            if !ok {
                continue
            }
            sel, ok := call.Fun.(*ast.SelectorExpr)
            pkg, pkgOK := sel.X.(*ast.Ident)
            if !ok || !pkgOK || pkg.Name != "context" || sel.Sel.Name != "WithCancel" {
                continue
            }
            cancel, ok := assign.Lhs[1].(*ast.Ident)
            if !ok {
                t.Fatal("WithCancel cancellation function is not assigned to an identifier")
            }
            if !blockGuaranteesCancel(fn.Body.List[i+1:], cancel.Name) {
                t.Fatalf("the cancellation function %q is not called or deferred on every path", cancel.Name)
            }
            return
        }

        // Removing the unnecessary WithCancel entirely also removes this leak.
        return
    }
    t.Fatal("HandleRequest was not found in server.go")
}
''')
    try:
        result = subprocess.run(
            ["go", "test", "-run", "^TestGoroutineLeak$", "-count=1", "-v", "."],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
        )
    finally:
        verifier_test.unlink(missing_ok=True)

    assert result.returncode == 0, \
        f"Go test failed.\nStdout:\n{result.stdout}\nStderr:\n{result.stderr}"
    assert "=== RUN   TestGoroutineLeak" in result.stdout, \
        f"The required Go test did not run.\nStdout:\n{result.stdout}"


def test_detector_adversarial_corpus(tmp_path):
    detector_source = Path("/home/user/detector.go")
    detector_path = Path("/home/user/detector")
    assert detector_source.exists() and detector_source.is_file(), \
        f"Go detector source not found at {detector_source}"
    assert detector_path.exists() and detector_path.is_file(), \
        f"Detector executable not found at {detector_path}"
    assert os.access(detector_path, os.X_OK), \
        f"Detector at {detector_path} is not executable."

    rebuilt_detector = tmp_path / "detector"
    build = subprocess.run(
        ["go", "build", "-o", str(rebuilt_detector), str(detector_source)],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, \
        f"detector.go is not a buildable Go program.\nStdout:\n{build.stdout}\nStderr:\n{build.stderr}"

    evil_dir = Path("/app/corpus/evil")
    clean_dir = Path("/app/corpus/clean")
    assert evil_dir.exists() and evil_dir.is_dir(), f"Evil corpus directory missing at {evil_dir}"
    assert clean_dir.exists() and clean_dir.is_dir(), f"Clean corpus directory missing at {clean_dir}"

    evil_files = [f for f in evil_dir.iterdir() if f.is_file()]
    clean_files = [f for f in clean_dir.iterdir() if f.is_file()]
    assert evil_files, f"No files found in evil corpus directory {evil_dir}"
    assert clean_files, f"No files found in clean corpus directory {clean_dir}"

    errors = []
    for binary in (detector_path, rebuilt_detector):
        evil_bypassed = [
            f.name for f in evil_files
            if subprocess.run([str(binary), str(f)], capture_output=True).returncode != 1
        ]
        clean_modified = [
            f.name for f in clean_files
            if subprocess.run([str(binary), str(f)], capture_output=True).returncode != 0
        ]
        if evil_bypassed:
            errors.append(f"{binary}: evil requests bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"{binary}: clean requests rejected: {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
