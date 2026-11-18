#!/bin/bash
mkdir -p /logs/verifier

verify() {
    cat << 'AST_EOF' > /tmp/check_orchestrator_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    path := "/home/user/project/orchestrator.go"
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasGoroutine := false
    hasChannel := false
    hasChannelOperation := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGoroutine = true
        case *ast.ChanType:
            hasChannel = true
        case *ast.SendStmt:
            hasChannelOperation = true
        case *ast.UnaryExpr:
            if x.Op == token.ARROW {
                hasChannelOperation = true
            }
        }
        return true
    })

    if !hasGoroutine || !hasChannel || !hasChannelOperation {
        fmt.Fprintf(os.Stderr, "orchestrator must use goroutines and channel communication (goroutine=%v channel=%v operation=%v)\n", hasGoroutine, hasChannel, hasChannelOperation)
        os.Exit(1)
    }
}
AST_EOF

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import time
import pytest

PROJECT = "/home/user/project"
PACKAGES = os.path.join(PROJECT, "packages")
BINARY = "/tmp/orchestrator-under-test"


def compare_versions(v1, v2):
    p1 = list(map(int, v1.split('.')))
    p2 = list(map(int, v2.split('.')))
    for i in range(3):
        if p1[i] > p2[i]: return 1
        if p1[i] < p2[i]: return -1
    return 0


def evaluate_condition(actual_ver, operator, target_ver):
    cmp = compare_versions(actual_ver, target_ver)
    if operator == '==': return cmp == 0
    if operator == '>=': return cmp >= 0
    if operator == '<=': return cmp <= 0
    return False


def evaluate_expression(actual_ver, expr):
    parts = [p.strip() for p in expr.split('&&')]
    for part in parts:
        tokens = part.split(' ')
        if len(tokens) == 2:
            op, target = tokens
            if not evaluate_condition(actual_ver, op, target):
                return False
    return True


@pytest.fixture(scope="module")
def expected_state():
    manifest_path = os.path.join(PROJECT, "manifest.txt")
    expected_report_lines = []
    expected_artifacts = []
    unexpected_artifacts = []

    if not os.path.exists(manifest_path):
        return [], [], []

    with open(manifest_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            first_space = line.find(' ')
            if first_space == -1:
                continue

            pkg_name = line[:first_space]
            expr = line[first_space + 1:].strip()
            pkg_dir = os.path.join(PACKAGES, pkg_name)
            version_file = os.path.join(pkg_dir, "version.txt")
            artifact_file = os.path.join(pkg_dir, "out.artifact")

            if not os.path.exists(pkg_dir) or not os.path.exists(version_file):
                expected_report_lines.append(f"FAIL: {pkg_name} (missing)")
                unexpected_artifacts.append(artifact_file)
            else:
                with open(version_file, 'r') as vf:
                    actual_ver = vf.read().strip()
                if evaluate_expression(actual_ver, expr):
                    expected_report_lines.append(f"SUCCESS: {pkg_name} {actual_ver}")
                    expected_artifacts.append(artifact_file)
                else:
                    expected_report_lines.append(f"FAIL: {pkg_name} {actual_ver} (unsatisfied)")
                    unexpected_artifacts.append(artifact_file)

    expected_report_lines.sort()
    return expected_report_lines, expected_artifacts, unexpected_artifacts


def test_orchestrator_go_exists():
    path = os.path.join(PROJECT, "orchestrator.go")
    assert os.path.isfile(path), f"Missing Go orchestrator file: {path}"


def test_build_report_content(expected_state):
    expected_report_lines, _, _ = expected_state
    report_path = os.path.join(PROJECT, "build_report.txt")
    assert os.path.isfile(report_path), f"Missing build report: {report_path}"
    with open(report_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_report_lines, \
        f"Build report content does not match expected.\nExpected: {expected_report_lines}\nActual: {actual_lines}"


def test_artifacts_created(expected_state):
    _, expected_artifacts, unexpected_artifacts = expected_state
    for artifact in expected_artifacts:
        assert os.path.isfile(artifact), f"Expected artifact missing, meaning build script was not run for satisfied package: {artifact}"
    for artifact in unexpected_artifacts:
        assert not os.path.exists(artifact), f"Unexpected artifact found, meaning build script was run for unsatisfied/missing package: {artifact}"


def write_package(name, version, script):
    pkg = os.path.join(PACKAGES, name)
    os.makedirs(pkg, exist_ok=True)
    if version is not None:
        with open(os.path.join(pkg, "version.txt"), "w") as f:
            f.write(version)
    with open(os.path.join(pkg, "build.sh"), "w") as f:
        f.write(script)
    os.chmod(os.path.join(pkg, "build.sh"), 0o755)


def test_dynamic_semver_build_invocation_missing_cases_and_concurrency():
    nonce = secrets.token_hex(16)
    names = ["t_above", "t_conca", "t_concb", "t_equal", "t_low", "t_missingdir", "t_noversion", "t_tendigit"]
    for name in names:
        shutil.rmtree(os.path.join(PACKAGES, name), ignore_errors=True)

    simple_script = lambda: f'''#!/bin/bash\nprintf '%s' '{nonce}' > "$PWD/out.artifact"\n'''
    forbidden_script = f'''#!/bin/bash\nprintf '%s' '{nonce}' > "$PWD/out.artifact"\n'''

    write_package("t_equal", "3.1.4", simple_script())
    write_package("t_low", "1.2.9", forbidden_script)
    write_package("t_above", "10.0.0", forbidden_script)
    write_package("t_tendigit", "1.10.0", simple_script())
    write_package("t_noversion", None, forbidden_script)

    for name, peer in (("t_conca", "t_concb"), ("t_concb", "t_conca")):
        script = f'''#!/bin/bash
touch "$PWD/started"
for i in $(seq 1 60); do
    if [ -f "/home/user/project/packages/{peer}/started" ]; then
        printf '%s' '{nonce}' > "$PWD/out.artifact"
        exit 0
    fi
    sleep 0.1
done
exit 9
'''
        write_package(name, "2.5.0", script)

    manifest = [
        "t_above <= 9.99.99",
        "t_conca >= 2.0.0 && <= 3.0.0",
        "t_concb >= 2.0.0 && <= 3.0.0",
        "t_equal == 3.1.4",
        "t_low >= 1.3.0",
        "t_missingdir == 1.0.0",
        "t_noversion >= 0.0.1",
        "t_tendigit >= 1.9.9",
    ]
    with open(os.path.join(PROJECT, "manifest.txt"), "w") as f:
        f.write("\n".join(manifest) + "\n")

    report = os.path.join(PROJECT, "build_report.txt")
    if os.path.exists(report):
        os.remove(report)

    completed = subprocess.run([BINARY], cwd=PROJECT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, timeout=15)
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert os.path.isfile(report), "Orchestrator did not generate build_report.txt"

    expected = sorted([
        "FAIL: t_above 10.0.0 (unsatisfied)",
        "SUCCESS: t_conca 2.5.0",
        "SUCCESS: t_concb 2.5.0",
        "SUCCESS: t_equal 3.1.4",
        "FAIL: t_low 1.2.9 (unsatisfied)",
        "FAIL: t_missingdir (missing)",
        "FAIL: t_noversion (missing)",
        "SUCCESS: t_tendigit 1.10.0",
    ])
    with open(report) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Dynamic report mismatch. Expected {expected}, got {actual}"

    for name in ("t_equal", "t_tendigit", "t_conca", "t_concb"):
        artifact = os.path.join(PACKAGES, name, "out.artifact")
        assert os.path.isfile(artifact), f"Build script was not successfully invoked for {name}"
        with open(artifact) as f:
            assert f.read() == nonce, f"Artifact for {name} was not produced by the verifier-supplied build script"

    for name in ("t_low", "t_above", "t_noversion", "t_missingdir"):
        assert not os.path.exists(os.path.join(PACKAGES, name, "out.artifact")), \
            f"Build script incorrectly ran for {name}"
TEST_EOF

    test -f /home/user/project/orchestrator.go || return 1
    go build -o /tmp/orchestrator-under-test /home/user/project/orchestrator.go || return 1
    go build -o /tmp/check-orchestrator-ast /tmp/check_orchestrator_ast.go || return 1
    /tmp/check-orchestrator-ast || return 1

    rm -f /home/user/project/build_report.txt
    if [ -d /home/user/project/packages ]; then
        find /home/user/project/packages -type f -name out.artifact -delete || return 1
    fi
    timeout 15s /tmp/orchestrator-under-test || return 1

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
