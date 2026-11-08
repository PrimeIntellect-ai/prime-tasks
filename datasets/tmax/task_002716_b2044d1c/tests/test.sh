#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import pytest

CLASSIFIER_BIN = "/home/user/qa-env/wsprocessor/bin/classifier"
CLEAN_CORPUS_DIR = "/home/user/corpora/clean"
EVIL_CORPUS_DIR = "/home/user/corpora/evil"
WS_DIR = "/home/user/qa-env/wsprocessor"
ORACLE = "/app/seq_oracle"


def run_classifier(path):
    return subprocess.run(
        [CLASSIFIER_BIN, path], capture_output=True, text=True, timeout=2
    )


def oracle_clean(seq):
    payload = " ".join(str(n) for n in seq)
    if payload:
        payload += "\n"
    result = subprocess.run(
        [ORACLE], input=payload, capture_output=True, text=True, timeout=2
    )
    assert result.returncode in (0, 1), f"Oracle failed with code {result.returncode}: {result.stderr}"
    return result.returncode == 0


def fresh_cases():
    cases = [
        [], [0], [-7], [1, 2], [1, 11], [1, 12], [4, 4],
        [-20, -10, 0, 10], [30, 20, 10, 0], [5, -5, 15],
        [100, 91, 82, 73], [3, 13, 23, 34], [9, 1, 19, 29],
    ]
    rng = random.SystemRandom()
    for _ in range(90):
        length = rng.randrange(0, 18)
        cases.append([rng.randrange(-10000, 10001) for _ in range(length)])
    # Add generated near-boundary sequences so both classes and subtle gap cases occur.
    for _ in range(35):
        length = rng.randrange(2, 15)
        value = rng.randrange(-5000, 5001)
        seq = [value]
        for _ in range(length - 1):
            value += rng.randrange(1, 11)
            seq.append(value)
        rng.shuffle(seq)
        cases.append(seq)
    for _ in range(20):
        base = rng.randrange(-5000, 5001)
        seq = [base, base + rng.choice([0, 11, 12, 25])]
        seq.extend(rng.randrange(-5000, 5001) for _ in range(rng.randrange(0, 8)))
        cases.append(seq)
    return cases


def test_classifier_binary_exists():
    assert os.path.isfile(CLASSIFIER_BIN), f"Classifier binary not found at {CLASSIFIER_BIN}"
    assert os.access(CLASSIFIER_BIN, os.X_OK), f"Classifier binary at {CLASSIFIER_BIN} is not executable"


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")
    files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(files) > 0, "Clean corpus is empty."
    modified_files = []
    for name in files:
        try:
            result = run_classifier(os.path.join(CLEAN_CORPUS_DIR, name))
            if result.stdout.strip() != "CLEAN":
                modified_files.append(name)
        except Exception:
            modified_files.append(name)
    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(files)} clean modified/rejected. Offending files: {', '.join(modified_files)}")


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")
    files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(files) > 0, "Evil corpus is empty."
    bypassed_files = []
    for name in files:
        try:
            result = run_classifier(os.path.join(EVIL_CORPUS_DIR, name))
            if result.stdout.strip() != "EVIL":
                bypassed_files.append(name)
        except Exception:
            bypassed_files.append(name)
    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")


def test_go_build_success():
    try:
        result = subprocess.run(["go", "build", "./..."], cwd=WS_DIR, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"go build failed: {result.stderr}"
    except Exception as exc:
        pytest.fail(f"Failed to run go build: {exc}")


def test_classifier_on_fresh_oracle_derived_inputs():
    assert os.path.isfile(ORACLE) and os.access(ORACLE, os.X_OK), "Sequence oracle is unavailable"
    cases = fresh_cases()
    expected = [oracle_clean(seq) for seq in cases]
    assert any(expected) and not all(expected), "Generated tests did not cover both classifications"
    with tempfile.TemporaryDirectory(prefix="seq-verifier-") as directory:
        for index, (seq, clean) in enumerate(zip(cases, expected)):
            path = os.path.join(directory, f"input-{index}-{random.SystemRandom().getrandbits(64):016x}.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(" ".join(str(n) for n in seq))
                handle.write("\n")
            result = run_classifier(path)
            wanted = "CLEAN" if clean else "EVIL"
            assert result.stdout.strip() == wanted, (
                f"Classifier disagreed with oracle for generated sequence {seq}: "
                f"wanted {wanted}, got stdout={result.stdout!r}, stderr={result.stderr!r}"
            )


def test_filter_classify_api_matches_oracle():
    cases = fresh_cases()
    expected = [oracle_clean(seq) for seq in cases]
    probe_source = r'''
package main

import (
    "bufio"
    "encoding/json"
    "fmt"
    "os"
    "wsprocessor/filter"
)

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    for scanner.Scan() {
        var seq []int
        if err := json.Unmarshal(scanner.Bytes(), &seq); err != nil {
            panic(err)
        }
        fmt.Println(filter.Classify(seq))
    }
    if err := scanner.Err(); err != nil {
        panic(err)
    }
}
'''
    with open("/tmp/filter_api_probe.go", "w", encoding="utf-8") as handle:
        handle.write(probe_source)
    build = subprocess.run(
        ["go", "build", "-o", "/tmp/filter_api_probe", "/tmp/filter_api_probe.go"],
        cwd=WS_DIR, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"filter.Classify API could not be compiled: {build.stderr}"
    payload = "".join(json.dumps(seq) + "\n" for seq in cases)
    result = subprocess.run(
        ["/tmp/filter_api_probe"], input=payload, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"filter.Classify probe failed: {result.stderr}"
    outputs = result.stdout.splitlines()
    assert len(outputs) == len(cases), "filter.Classify probe returned the wrong number of results"
    for seq, wanted, output in zip(cases, expected, outputs):
        assert output == ("true" if wanted else "false"), (
            f"filter.Classify disagreed with oracle for {seq}: got {output!r}"
        )


def test_main_integrates_filter_with_websocket_statuses():
    main_path = os.path.join(WS_DIR, "main.go")
    assert os.path.isfile(main_path), "main.go is missing"
    checker = r'''
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
    path := "/home/user/qa-env/wsprocessor/main.go"
    file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    aliases := map[string]bool{}
    dot := false
    imported := false
    for _, imp := range file.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p != "wsprocessor/filter" { continue }
        imported = true
        if imp.Name == nil { aliases["filter"] = true
        } else if imp.Name.Name == "." { dot = true
        } else if imp.Name.Name != "_" { aliases[imp.Name.Name] = true }
    }
    called := false
    values := map[string]bool{}
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.CallExpr:
            switch fun := x.Fun.(type) {
            case *ast.SelectorExpr:
                if fun.Sel.Name == "Classify" {
                    if id, ok := fun.X.(*ast.Ident); ok && aliases[id.Name] { called = true }
                }
            case *ast.Ident:
                if dot && fun.Name == "Classify" { called = true }
            }
        case *ast.BasicLit:
            if x.Kind == token.STRING {
                if s, err := strconv.Unquote(x.Value); err == nil { values[s] = true }
            }
        }
        return true
    })
    if !imported || !called || !values["status"] || !values["rejected"] || !values["accepted"] {
        fmt.Fprintln(os.Stderr, "main.go must import and call filter.Classify and contain accepted/rejected status responses")
        os.Exit(1)
    }
}
'''
    with open("/tmp/check_ws_integration.go", "w", encoding="utf-8") as handle:
        handle.write(checker)
    result = subprocess.run(
        ["go", "run", "/tmp/check_ws_integration.go"],
        cwd=WS_DIR, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, result.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
