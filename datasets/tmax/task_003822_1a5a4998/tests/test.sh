#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/log-sanitiser"
VENDOR_DIR = "/app/vendor/github.com/buger/jsonparser"
BINARY_PATH = "/tmp/log-sanitiser"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kwargs)


def test_vendored_package_fixed():
    makefile_path = os.path.join(VENDOR_DIR, "Makefile")
    assert os.path.exists(makefile_path), f"Makefile missing at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "GOOS=windows" not in content, "The vendored Makefile still contains the GOOS=windows perturbation."
    assert "BUILD_TAG=broken" not in content, "The vendored Makefile still contains the BUILD_TAG=broken perturbation."

    env = os.environ.copy()
    env.update({"GOOS": "linux", "GOARCH": "amd64"})

    dry_test = run(["make", "-Bn", "test"], cwd=VENDOR_DIR, env=env)
    assert dry_test.returncode == 0, f"Makefile test target is broken:\n{dry_test.stderr}"
    assert "go test" in dry_test.stdout, "Makefile test target does not run go test."

    dry_build = run(["make", "-Bn", "build"], cwd=VENDOR_DIR, env=env)
    assert dry_build.returncode == 0, f"Makefile build target is broken:\n{dry_build.stderr}"
    assert "go build" in dry_build.stdout, "Makefile build target does not run go build."

    test_result = run(["make", "-B", "test"], cwd=VENDOR_DIR, env=env)
    assert test_result.returncode == 0, (
        "Vendored jsonparser tests failed through its Makefile:\n"
        + test_result.stdout + test_result.stderr
    )

    build_result = run(["make", "-B", "build"], cwd=VENDOR_DIR, env=env)
    assert build_result.returncode == 0, (
        "Vendored jsonparser failed to build through its Makefile for linux/amd64:\n"
        + build_result.stdout + build_result.stderr
    )


def test_log_sanitiser_builds():
    main_go_path = os.path.join(PROJECT_DIR, "main.go")
    assert os.path.exists(main_go_path), f"main.go missing at {main_go_path}"

    build_cmd = ["go", "build", "-o", BINARY_PATH, "main.go"]
    result = run(build_cmd, cwd=PROJECT_DIR)
    assert result.returncode == 0, f"Failed to build main.go:\n{result.stderr}"


def test_main_uses_vendored_jsonparser():
    checker = r'''
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[len(os.Args)-1], nil, 0)
    if err != nil { os.Exit(2) }
    alias := ""
    dotImport := false
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil || p != "github.com/buger/jsonparser" { continue }
        alias = "jsonparser"
        if imp.Name != nil {
            if imp.Name.Name == "_" { os.Exit(3) }
            if imp.Name.Name == "." { dotImport = true } else { alias = imp.Name.Name }
        }
    }
    if alias == "" { os.Exit(4) }
    if dotImport { return }
    used := false
    ast.Inspect(f, func(n ast.Node) bool {
        s, ok := n.(*ast.SelectorExpr)
        if !ok { return true }
        id, ok := s.X.(*ast.Ident)
        if ok && id.Name == alias { used = true }
        return true
    })
    if !used { os.Exit(5) }
}
'''
    checker_path = "/tmp/check_jsonparser_import.go"
    with open(checker_path, "w") as f:
        f.write(checker)

    result = run(["go", "run", checker_path, "--", os.path.join(PROJECT_DIR, "main.go")], cwd=PROJECT_DIR)
    assert result.returncode == 0, "main.go must import and use github.com/buger/jsonparser."

    deps = run(["go", "list", "-deps", "."], cwd=PROJECT_DIR)
    assert deps.returncode == 0, f"Could not inspect project dependencies:\n{deps.stderr}"
    assert "github.com/buger/jsonparser" in deps.stdout.splitlines(), (
        "The built sanitiser does not depend on the provided jsonparser package."
    )


def test_adversarial_corpus():
    assert os.path.exists(BINARY_PATH), "Binary not built, skipping corpus tests."

    clean_dir = "/home/user/corpus/clean/"
    evil_dir = "/home/user/corpus/evil/"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    failed_clean = []
    failed_evil = []

    for cfile in clean_files:
        if not os.path.isfile(cfile):
            continue
        with open(cfile, "r") as f:
            expected_output = f.read().strip()
        result = run([BINARY_PATH, cfile])
        if result.returncode != 0:
            failed_clean.append(f"{os.path.basename(cfile)} (non-zero exit code: {result.returncode})")
        elif result.stdout.strip() != expected_output:
            failed_clean.append(f"{os.path.basename(cfile)} (output mismatch)")

    for efile in evil_files:
        if not os.path.isfile(efile):
            continue
        result = run([BINARY_PATH, efile])
        if result.returncode != 0:
            failed_evil.append(f"{os.path.basename(efile)} (non-zero exit code: {result.returncode})")
        elif result.stdout.strip() != "":
            failed_evil.append(f"{os.path.basename(efile)} (output not empty)")

    error_msgs = []
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: " + ", ".join(failed_evil))
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified: " + ", ".join(failed_clean))
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_unseen_logs():
    assert os.path.exists(BINARY_PATH), "Binary was not built."

    for _ in range(5):
        token = secrets.token_hex(12)
        records = [
            ({"metric_name": "cpu_" + token, "metric_value": random.randint(-100000, 100000), "host": token}, True),
            ({"metric_name": "latency_" + token, "metric_value": random.random() * 1000}, True),
            ({"metric_name": "drop_me_" + token, "metric_value": 0}, True),
            ({"metric_value": random.randint(1, 999), "extra": token}, True),
            ({"metric_name": token + "DROP_ME", "metric_value": random.randint(1, 999)}, False),
            ({"metric_name": "mem_" + token, "metric_value": str(random.randint(1, 999))}, False),
            ({"metric_name": "disk_" + token, "host": token}, False),
            ({"metric_name": "DROP_ME_" + token, "metric_value": "bad"}, False),
        ]
        random.SystemRandom().shuffle(records)

        rendered = []
        expected = []
        for obj, clean in records:
            if random.choice([True, False]):
                line = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
            else:
                line = json.dumps(obj, ensure_ascii=False)
            rendered.append(line)
            if clean:
                expected.append(line)

        fd, path = tempfile.mkstemp(prefix="unseen-" + secrets.token_hex(6) + "-", suffix=".metrics")
        try:
            with os.fdopen(fd, "w") as f:
                f.write("\n".join(rendered) + "\n")
            result = run([BINARY_PATH, path])
            assert result.returncode == 0, f"Sanitiser exited {result.returncode}: {result.stderr}"
            expected_output = "".join(line + "\n" for line in expected)
            assert result.stdout == expected_output, (
                "Sanitiser did not correctly filter a generated, previously unseen mixed log file."
            )
        finally:
            os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
