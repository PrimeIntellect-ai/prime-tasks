#!/bin/bash
set +e
mkdir -p /logs/verifier

python3 <<'PY'
import datetime
import json
import os
import secrets
import subprocess
import sys
from collections import defaultdict

raw_path = "/home/user/raw_logs.txt"
source_path = "/home/user/analyzer.go"
summary_path = "/home/user/summary.md"
binary_path = "/tmp/analyzer-under-test"

expected_original = """# Log Summary

## Hour: 2023-11-01T08:00:00Z
- auth_fail: 3
- db_timeout: 1
- rate_limit: 2

## Hour: 2023-11-01T09:00:00Z
- db_timeout: 7

## Hour: 2023-11-01T10:00:00Z
- auth_fail: 5
- rate_limit: 4"""

original_raw = open(raw_path, "rb").read()
summary_existed = os.path.exists(summary_path)
original_summary = open(summary_path, "rb").read() if summary_existed else None


def run_analyzer():
    if os.path.exists(summary_path):
        os.remove(summary_path)
    subprocess.run([binary_path], cwd="/home/user", check=True, timeout=15)
    assert os.path.exists(summary_path), f"File {summary_path} is missing."
    assert os.path.isfile(summary_path), f"{summary_path} is not a file."
    with open(summary_path, "r") as f:
        return f.read().strip()


def expected_report(raw_text):
    totals = defaultdict(lambda: defaultdict(int))
    for line in raw_text.splitlines():
        timestamp, _ip, counts_json = [part.strip() for part in line.split("|", 2)]
        parsed_time = datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        hour = parsed_time.replace(minute=0, second=0, microsecond=0)
        for error_type, count in json.loads(counts_json).items():
            totals[hour][error_type] += count

    lines = ["# Log Summary"]
    for hour in sorted(totals):
        positive = [(name, totals[hour][name]) for name in sorted(totals[hour]) if totals[hour][name] > 0]
        if not positive:
            continue
        hour_text = hour.isoformat().replace("+00:00", "Z")
        lines.extend(["", f"## Hour: {hour_text}"])
        lines.extend(f"- {name}: {count}" for name, count in positive)
    return "\n".join(lines)


try:
    # Preserve the original verifier's existence and exact-content assertions.
    assert os.path.exists(summary_path), f"File {summary_path} is missing."
    assert os.path.isfile(summary_path), f"{summary_path} is not a file."
    with open(summary_path, "r") as f:
        content = f.read().strip()
    assert content == expected_original, f"The content of {summary_path} does not match the expected Markdown report."

    assert os.path.exists(source_path), f"File {source_path} is missing."
    assert os.path.isfile(source_path), f"{source_path} is not a file."

    # Compile the submitted artifact itself.
    subprocess.run(
        ["go", "build", "-o", binary_path, source_path],
        cwd="/home/user",
        check=True,
        timeout=30,
    )

    # Check through Go's parser that text/template is imported and an Execute
    # operation is present, rather than accepting a comment or string match.
    ast_checker = r'''package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path"
    "strconv"
)
func main() {
    filename := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), filename, nil, 0)
    if err != nil { panic(err) }
    imported := false
    packageUse := false
    executes := false
    alias := "template"
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p == "text/template" {
            imported = true
            alias = path.Base(p)
            if imp.Name != nil { alias = imp.Name.Name }
            if alias == "_" { imported = false }
        }
    }
    ast.Inspect(f, func(n ast.Node) bool {
        if s, ok := n.(*ast.SelectorExpr); ok {
            if id, ok := s.X.(*ast.Ident); ok && id.Name == alias { packageUse = true }
            if s.Sel.Name == "Execute" || s.Sel.Name == "ExecuteTemplate" { executes = true }
        }
        return true
    })
    if alias == "." { packageUse = true }
    if !imported || !packageUse || !executes {
        fmt.Fprintln(os.Stderr, "analyzer.go must use text/template to execute the report template")
        os.Exit(1)
    }
}
'''
    checker_source = "/tmp/check_template_ast.go"
    checker_binary = "/tmp/check_template_ast"
    with open(checker_source, "w") as f:
        f.write(ast_checker)
    subprocess.run(["go", "build", "-o", checker_binary, checker_source], check=True, timeout=30)
    subprocess.run([checker_binary, source_path], check=True, timeout=10)

    # A newly compiled analyzer must regenerate the original report; a stale
    # summary.md alone is not sufficient.
    regenerated = run_analyzer()
    assert regenerated == expected_original, "The compiled analyzer did not regenerate the required fixture report."

    # Exercise parsing, normalization, bucketing, arbitrary wide-to-long keys,
    # aggregation, zero filtering, and both required sort orders on fresh data.
    suffix = secrets.token_hex(5)
    alpha = "alpha_" + suffix
    middle = "middle_" + suffix
    zeta = "zeta_" + suffix
    dynamic_raw = f""" 2024-07-18T12:44:51Z   | 10.2.0.9 | {{\"{zeta}\": 2, \"{alpha}\": 0}}
2024-07-18T11:59:59Z|192.0.2.8|{{\"{middle}\": 4, \"{alpha}\": 1}}
 2024-07-18T12:01:03Z | 198.51.100.3    | {{\"{alpha}\": 5, \"{zeta}\": 3, \"{middle}\": 0}}
2024-07-19T00:00:01Z | 203.0.113.7 | {{\"{middle}\": 7, \"{alpha}\": 2}}
2024-07-18T11:02:00Z | 192.0.2.9 | {{\"{alpha}\": 6, \"{middle}\": 1, \"{zeta}\": 0}}
"""
    with open(raw_path, "w") as f:
        f.write(dynamic_raw)
    actual_dynamic = run_analyzer()
    assert actual_dynamic == expected_report(dynamic_raw), "The analyzer failed the generated log-processing test."

except Exception as exc:
    print(f"VERIFICATION FAILED: {exc}", file=sys.stderr)
    raise
finally:
    with open(raw_path, "wb") as f:
        f.write(original_raw)
    if summary_existed:
        with open(summary_path, "wb") as f:
            f.write(original_summary)
    elif os.path.exists(summary_path):
        os.remove(summary_path)
PY
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
