#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /home/user/build_report.json /tmp/go_implementation_ok

cat << 'GO_EOF' > /tmp/check_go_implementation.go
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(1)
    }

    packages, err := parser.ParseDir(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        os.Exit(1)
    }

    pkg, ok := packages["main"]
    if !ok {
        os.Exit(1)
    }

    hasMain := false
    hasGoroutine := false
    hasChannel := false

    for _, file := range pkg.Files {
        ast.Inspect(file, func(node ast.Node) bool {
            switch n := node.(type) {
            case *ast.FuncDecl:
                if n.Recv == nil && n.Name.Name == "main" {
                    hasMain = true
                }
            case *ast.GoStmt:
                hasGoroutine = true
            case *ast.ChanType:
                hasChannel = true
            }
            return true
        })
    }

    if !hasMain || !hasGoroutine || !hasChannel {
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_go_implementation /tmp/check_go_implementation.go
if [ $? -eq 0 ]; then
    mapfile -d '' candidate_dirs < <(find /home/user -type f -name '*.go' -printf '%h\0' 2>/dev/null | sort -zu)
    for candidate_dir in "${candidate_dirs[@]}"; do
        /tmp/check_go_implementation "$candidate_dir" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            continue
        fi

        rm -f /home/user/build_report.json
        (
            cd "$candidate_dir" || exit 1
            GO111MODULE=off timeout 90s go run .
        ) >/tmp/agent_go_stdout.txt 2>/tmp/agent_go_stderr.txt

        if [ $? -eq 0 ] && [ -f /home/user/build_report.json ]; then
            touch /tmp/go_implementation_ok
            break
        fi
    done
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_go_implementation_was_executed():
    """Require an executable Go implementation using goroutines and channels."""
    assert os.path.isfile('/tmp/go_implementation_ok'), (
        "No working Go main package using both a goroutine and a channel was found and executed."
    )

def test_build_report_exists():
    """Check that the output file exists."""
    assert os.path.isfile('/home/user/build_report.json'), "The output file /home/user/build_report.json is missing."

def test_build_report_format_and_value():
    """Verify the format and the correctness of the total_metric calculated."""
    report_path = '/home/user/build_report.json'

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} is not valid JSON.")

    assert "total_metric" in report_data, f"The file {report_path} must contain the key 'total_metric'."
    actual_total = report_data["total_metric"]
    assert isinstance(actual_total, int), "The value of 'total_metric' must be an integer."

    # Calculate the expected value directly from the artifact files to ensure robustness
    expected_total = 0
    for i in range(1000):
        manifest_path = f'/home/user/artifacts/manifest_{i}.json'
        assert os.path.isfile(manifest_path), f"Input file {manifest_path} is missing."

        with open(manifest_path, 'r') as f:
            data = json.load(f)

        for j, dep in enumerate(data.get("dependencies", [])):
            size = dep.get("size_bytes", 0)
            expected_total += (size * (j + 1)) % 9973

    assert actual_total == expected_total, f"Expected total_metric to be {expected_total}, but got {actual_total}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
