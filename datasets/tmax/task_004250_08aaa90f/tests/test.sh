#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import json
import os
import random
import secrets
import shutil
import subprocess
import textwrap

import pytest

CLASSIFIER = "/home/user/classifier.go"
GRAPH_MODULE = "github.com/dominikbraun/graph"


def run_classifier(command, csv_file):
    return subprocess.run(
        command + [csv_file],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )


def assert_classification(result, expected, csv_file):
    expected_code = 0 if expected == "CLEAN" else 1
    assert result.returncode == expected_code, (
        f"{csv_file}: expected exit {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"{csv_file}: expected stdout {expected!r}, got {result.stdout!r}"
    )


def test_vendored_package_fixed():
    graph_go_path = "/app/graph/graph.go"
    assert os.path.isfile(graph_go_path), f"File {graph_go_path} is missing."
    with open(graph_go_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "package graph" in content and "package grraph" not in content, (
        f"The typo 'package grraph' in {graph_go_path} was not correctly fixed."
    )


def test_classifier_uses_local_graph_module():
    assert os.path.isfile(CLASSIFIER), f"Classifier program not found at {CLASSIFIER}"
    assert os.path.isfile("/home/user/go.mod"), "/home/user/go.mod is missing"

    module_result = subprocess.run(
        ["go", "list", "-m", "-json", GRAPH_MODULE],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert module_result.returncode == 0, module_result.stderr
    module_info = json.loads(module_result.stdout)
    replacement = module_info.get("Replace") or {}
    assert replacement.get("Dir"), "graph module does not have a local replacement"
    assert os.path.realpath(replacement["Dir"]) == os.path.realpath("/app/graph"), (
        f"graph module replacement points to {replacement.get('Dir')!r}, not /app/graph"
    )

    checker = "/tmp/check_graph_import.go"
    with open(checker, "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(r'''
            package main

            import (
                "go/ast"
                "go/parser"
                "go/token"
                "os"
                "strconv"
            )

            func main() {
                filename := os.Args[len(os.Args)-1]
                file, err := parser.ParseFile(token.NewFileSet(), filename, nil, 0)
                if err != nil { panic(err) }
                alias := ""
                dotImport := false
                for _, imp := range file.Imports {
                    path, _ := strconv.Unquote(imp.Path.Value)
                    if path != "github.com/dominikbraun/graph" { continue }
                    if imp.Name == nil { alias = "graph" } else if imp.Name.Name == "." { dotImport = true } else if imp.Name.Name != "_" { alias = imp.Name.Name }
                }
                used := false
                ast.Inspect(file, func(n ast.Node) bool {
                    if sel, ok := n.(*ast.SelectorExpr); ok {
                        if id, ok := sel.X.(*ast.Ident); ok && alias != "" && id.Name == alias { used = true }
                    }
                    if dotImport {
                        if id, ok := n.(*ast.Ident); ok && (id.Name == "New" || id.Name == "Directed") { used = true }
                    }
                    return true
                })
                if !used { os.Exit(1) }
            }
        '''))
    import_result = subprocess.run(
        ["go", "run", checker, "--", CLASSIFIER],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert import_result.returncode == 0, (
        "classifier.go must import and use github.com/dominikbraun/graph"
    )


def test_adversarial_corpus():
    classifier_path = CLASSIFIER
    assert os.path.isfile(classifier_path), f"Classifier program not found at {classifier_path}"

    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    clean_csvs = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_csvs = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_csvs) > 0, "No clean CSV files found in truth corpus."
    assert len(evil_csvs) > 0, "No evil CSV files found in truth corpus."

    clean_failures = []
    for csv_file in clean_csvs:
        result = subprocess.run(["go", "run", classifier_path, csv_file], capture_output=True, text=True)
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            clean_failures.append(os.path.basename(csv_file))

    evil_failures = []
    for csv_file in evil_csvs:
        result = subprocess.run(["go", "run", classifier_path, csv_file], capture_output=True, text=True)
        if result.returncode != 1 or "EVIL" not in result.stdout:
            evil_failures.append(os.path.basename(csv_file))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_csvs)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_csvs)} evil bypassed: {', '.join(evil_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_generated_corpora_at_unlabelled_paths():
    token = secrets.token_hex(12)
    workdir = f"/tmp/{token}"
    os.makedirs(workdir)
    binary = os.path.join(workdir, "runner")

    build = subprocess.run(
        ["go", "build", "-o", binary, CLASSIFIER],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"classifier failed to build: {build.stderr}"

    rng = random.SystemRandom()
    cases = []

    # Re-test the supplied inputs after moving them to unpredictable, unlabelled paths.
    supplied = []
    supplied.extend((p, "CLEAN") for p in glob.glob("/home/user/corpora/clean/*.csv"))
    supplied.extend((p, "EVIL") for p in glob.glob("/home/user/corpora/evil/*.csv"))
    rng.shuffle(supplied)
    for source, expected in supplied:
        destination = os.path.join(workdir, secrets.token_hex(10) + ".csv")
        shutil.copyfile(source, destination)
        cases.append((destination, expected))

    # Generate fresh forests and cyclic directed graphs. Expected answers come from
    # the construction, not from filenames or a stored answer corpus.
    for expected in (["CLEAN"] * 20 + ["EVIL"] * 20):
        n = rng.randint(2, 18)
        labels = [f"n_{secrets.token_hex(6)}" for _ in range(n)]
        rows = []
        if expected == "CLEAN":
            for i, node in enumerate(labels):
                if i == 0 or rng.random() < 0.25:
                    parent = ""
                else:
                    parent = rng.choice(labels[:i])
                rows.append((node, parent))
        else:
            cycle_size = rng.randint(1, min(n, 7))
            for i in range(cycle_size):
                rows.append((labels[i], labels[(i + 1) % cycle_size]))
            for i in range(cycle_size, n):
                rows.append((labels[i], rng.choice(labels[:i])))
        rng.shuffle(rows)

        path = os.path.join(workdir, secrets.token_hex(10) + ".csv")
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "parent_id"])
            writer.writerows(rows)
        cases.append((path, expected))

    rng.shuffle(cases)
    for path, expected in cases:
        assert_classification(run_classifier([binary], path), expected, path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
