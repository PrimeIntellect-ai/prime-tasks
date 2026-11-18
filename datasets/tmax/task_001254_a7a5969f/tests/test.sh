#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'ANALYZER_EOF' > /tmp/analyze_go.go
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
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    values := map[string]int{}
    ast.Inspect(file, func(n ast.Node) bool {
        spec, ok := n.(*ast.ValueSpec)
        if !ok {
            return true
        }
        for i, name := range spec.Names {
            if i >= len(spec.Values) {
                continue
            }
            if lit, ok := spec.Values[i].(*ast.BasicLit); ok && lit.Kind == token.INT {
                if v, err := strconv.Atoi(lit.Value); err == nil {
                    values[name.Name] = v
                }
            }
        }
        return true
    })

    evalInt := func(expr ast.Expr) (int, bool) {
        switch e := expr.(type) {
        case *ast.BasicLit:
            if e.Kind == token.INT {
                v, err := strconv.Atoi(e.Value)
                return v, err == nil
            }
        case *ast.Ident:
            v, ok := values[e.Name]
            return v, ok
        }
        return 0, false
    }

    goroutines := 0
    hasChannel := false
    ast.Inspect(file, func(n ast.Node) bool {
        switch n.(type) {
        case *ast.GoStmt:
            goroutines++
        case *ast.ChanType:
            hasChannel = true
        }
        return true
    })

    // A single go statement inside a canonical zero-to-N loop launches N
    // goroutines, not one. Account for that common worker-pool form.
    ast.Inspect(file, func(n ast.Node) bool {
        loop, ok := n.(*ast.ForStmt)
        if !ok || loop.Init == nil || loop.Cond == nil || loop.Post == nil {
            return true
        }
        init, ok := loop.Init.(*ast.AssignStmt)
        if !ok || len(init.Lhs) != 1 || len(init.Rhs) != 1 {
            return true
        }
        id, ok := init.Lhs[0].(*ast.Ident)
        if !ok {
            return true
        }
        zero, ok := evalInt(init.Rhs[0])
        if !ok || zero != 0 {
            return true
        }
        cond, ok := loop.Cond.(*ast.BinaryExpr)
        if !ok || cond.Op != token.LSS {
            return true
        }
        condID, ok := cond.X.(*ast.Ident)
        if !ok || condID.Name != id.Name {
            return true
        }
        limit, ok := evalInt(cond.Y)
        if !ok || limit < 0 {
            return true
        }
        post, ok := loop.Post.(*ast.IncDecStmt)
        if !ok || post.Tok != token.INC {
            return true
        }
        postID, ok := post.X.(*ast.Ident)
        if !ok || postID.Name != id.Name {
            return true
        }
        inLoop := 0
        ast.Inspect(loop.Body, func(child ast.Node) bool {
            if _, ok := child.(*ast.GoStmt); ok {
                inLoop++
            }
            return true
        })
        goroutines += (limit - 1) * inLoop
        return true
    })

    fmt.Printf("goroutines=%d channel=%t\n", goroutines, hasChannel)
}
ANALYZER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import shlex
import subprocess
from pathlib import Path


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=90, **kwargs)


def test_files_exist():
    expected_files = [
        "/home/user/semver_filter.cpp",
        "/home/user/deploy_workers.go",
        "/home/user/ci_pipeline.sh",
        "/home/user/valid_versions.txt",
        "/home/user/deploy_log.txt"
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Expected file {f} is missing."


def test_cpp_program_on_derived_inputs(tmp_path):
    binary = tmp_path / "semver_filter"
    built = run([
        "g++", "-std=c++17", "/home/user/semver_filter.cpp",
        "-o", str(binary)
    ])
    assert built.returncode == 0, built.stderr

    cases = [
        (
            "1.0.0-beta",
            ["0.9.9", "1.0.0-alpha", "1.0.0-beta", "1.0.0-rc1",
             "1.0.0", "1.0.1", "2.0.0-alpha"],
            ["1.0.0-beta", "1.0.0-rc1", "1.0.0", "1.0.1", "2.0.0-alpha"],
        ),
        (
            "10.2.3",
            ["10.2.2", "9.99.99", "10.2.3-alpha", "10.2.3",
             "10.3.0", "11.0.0-a", "2.100.100"],
            ["10.2.3", "10.3.0", "11.0.0-a"],
        ),
        (
            "3.4.5-m",
            ["3.4.5-z", "3.4.5-a", "3.4.5", "3.4.4", "3.4.5-m"],
            ["3.4.5-z", "3.4.5", "3.4.5-m"],
        ),
    ]
    for index, (minimum, versions, expected) in enumerate(cases):
        source = tmp_path / f"versions-{index}.txt"
        output = tmp_path / f"valid-{index}.txt"
        source.write_text("\n".join(versions) + "\n")
        result = run([str(binary), minimum, str(source), str(output)])
        assert result.returncode == 0, result.stderr
        assert output.is_file(), "The C++ program did not create its output file"
        assert output.read_text().splitlines() == expected


def test_go_worker_pool_implementation():
    go_file = "/home/user/deploy_workers.go"
    with open(go_file, "r") as f:
        content = f.read()

    # Preserve the original implementation assertions.
    assert "chan" in content, f"The Go program {go_file} does not appear to use channels ('chan' keyword missing)."
    assert re.search(r'\bgo\s+', content), f"The Go program {go_file} does not appear to use goroutines ('go' keyword missing)."

    analyzed = run(["go", "run", "/tmp/analyze_go.go", go_file])
    assert analyzed.returncode == 0, analyzed.stderr
    assert "channel=true" in analyzed.stdout, "The Go source does not declare a channel."
    match = re.search(r"goroutines=(\d+)", analyzed.stdout)
    assert match and int(match.group(1)) == 3, (
        "The Go source must launch exactly three worker goroutines; "
        f"analysis reported: {analyzed.stdout.strip()}"
    )


def test_go_program_processes_runtime_input(tmp_path):
    versions = [f"7.{i // 10}.{i}-rc{i % 4}" for i in range(37)]
    versions += ["8.0.0", "8.0.0", "9.1.2-alpha"]
    source = tmp_path / "runtime_versions.txt"
    logfile = tmp_path / "runtime_deploy.log"
    source.write_text("\n".join(versions) + "\n")

    result = run([
        "go", "run", "-race", "/home/user/deploy_workers.go",
        str(source), str(logfile)
    ])
    assert result.returncode == 0, result.stdout + result.stderr
    assert "DATA RACE" not in result.stderr
    assert logfile.is_file(), "The Go program did not create its log file"

    actual = logfile.read_text().splitlines()
    expected = [f"Deployed version: {version}" for version in versions]
    assert len(actual) == len(expected)
    assert collections.Counter(actual) == collections.Counter(expected)


def test_pipeline_executes_required_tools_and_fixture():
    for path in [
        "/home/user/semver_filter",
        "/home/user/valid_versions.txt",
        "/home/user/deploy_log.txt",
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run(["bash", "-x", "/home/user/ci_pipeline.sh"], cwd="/home/user")
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile("/home/user/semver_filter"), "Pipeline did not build /home/user/semver_filter"

    commands = []
    for line in result.stderr.splitlines():
        stripped = line.lstrip("+ ")
        try:
            commands.append(shlex.split(stripped))
        except ValueError:
            pass

    compile_commands = [c for c in commands if c and os.path.basename(c[0]) in ("g++", "c++")]
    assert any(
        "/home/user/semver_filter.cpp" in c and
        "-o" in c and
        c[c.index("-o") + 1] == "/home/user/semver_filter"
        for c in compile_commands if "-o" in c and c.index("-o") + 1 < len(c)
    ), "Pipeline trace did not compile semver_filter.cpp to the required binary"

    assert any(
        c and c[0] == "/home/user/semver_filter" and
        c[1:] == ["2.0.0-rc1", "/home/user/versions.txt", "/home/user/valid_versions.txt"]
        for c in commands
    ), "Pipeline trace did not run semver_filter with the required arguments"

    assert any(
        len(c) >= 5 and os.path.basename(c[0]) == "go" and c[1] == "run" and
        "/home/user/deploy_workers.go" in c and
        c[-2:] == ["/home/user/valid_versions.txt", "/home/user/deploy_log.txt"]
        for c in commands
    ), "Pipeline trace did not run the Go deployment program with the required arguments"


def test_valid_versions_content():
    valid_versions_file = "/home/user/valid_versions.txt"
    expected_versions = {
        "2.0.0-rc1",
        "2.0.0-rc2",
        "2.0.0",
        "2.0.1",
        "3.0.0-beta"
    }

    with open(valid_versions_file, "r") as f:
        content = set(line.strip() for line in f if line.strip())

    assert content == expected_versions, f"Content of {valid_versions_file} does not match the expected valid versions."


def test_deploy_log_content():
    deploy_log_file = "/home/user/deploy_log.txt"
    expected_lines = {
        "Deployed version: 2.0.0",
        "Deployed version: 2.0.0-rc1",
        "Deployed version: 2.0.0-rc2",
        "Deployed version: 2.0.1",
        "Deployed version: 3.0.0-beta"
    }

    with open(deploy_log_file, "r") as f:
        content = sorted([line.strip() for line in f if line.strip()])

    assert len(content) == 5, f"Expected exactly 5 lines in {deploy_log_file}, but found {len(content)}."
    assert set(content) == expected_lines, f"Content of {deploy_log_file} does not match expected deployed versions."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
