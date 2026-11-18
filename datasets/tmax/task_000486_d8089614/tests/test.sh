#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_detector_source.go
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
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    aliases := map[string]bool{}
    dotImport := false
    imported := false
    for _, imp := range f.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err != nil || path != "go-graphdoc" {
            continue
        }
        imported = true
        if imp.Name == nil {
            aliases["graphdoc"] = true
        } else if imp.Name.Name == "." {
            dotImport = true
        } else if imp.Name.Name != "_" {
            aliases[imp.Name.Name] = true
        }
    }

    called := false
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        switch fun := call.Fun.(type) {
        case *ast.SelectorExpr:
            id, ok := fun.X.(*ast.Ident)
            if ok && aliases[id.Name] && fun.Sel.Name == "ParsePipeline" {
                called = true
            }
        case *ast.Ident:
            if dotImport && fun.Name == "ParsePipeline" {
                called = true
            }
        }
        return true
    })

    if !imported || !called {
        fmt.Fprintln(os.Stderr, "detector.go must import go-graphdoc and call its ParsePipeline function")
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_detector_source /tmp/check_detector_source.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import uuid


def test_detector_executable_exists():
    assert os.path.isfile("/home/user/detector"), "The compiled tool /home/user/detector is missing."
    assert os.access("/home/user/detector", os.X_OK), "/home/user/detector is not executable."


def test_detector_accuracy():
    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"

    clean_files = [os.path.basename(f) for f in glob.glob(os.path.join(clean_dir, "*.json"))]
    evil_files = [os.path.basename(f) for f in glob.glob(os.path.join(evil_dir, "*.json"))]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    with tempfile.TemporaryDirectory() as temp_input_dir:
        for f in clean_files:
            shutil.copy(os.path.join(clean_dir, f), os.path.join(temp_input_dir, f))
        for f in evil_files:
            shutil.copy(os.path.join(evil_dir, f), os.path.join(temp_input_dir, f))

        temp_output_log = os.path.join(temp_input_dir, "results.log")
        cmd = ["/home/user/detector", "-input", temp_input_dir, "-output", temp_output_log]
        result = subprocess.run(cmd, capture_output=True, text=True)

        assert result.returncode == 0, f"Detector failed to run. stderr: {result.stderr}"
        assert os.path.isfile(temp_output_log), "Detector did not create the output log file."

        with open(temp_output_log, "r") as f:
            log_lines = f.read().strip().splitlines()

        results_map = {}
        for line in log_lines:
            parts = line.split(":")
            if len(parts) == 2:
                filename = parts[0].strip()
                status = parts[1].strip()
                results_map[filename] = status

        clean_modified = []
        for cf in clean_files:
            if results_map.get(cf) != "CLEAN":
                clean_modified.append(cf)

        evil_bypassed = []
        for ef in evil_files:
            if results_map.get(ef) != "EVIL":
                evil_bypassed.append(ef)

        error_msg = []
        if clean_modified:
            error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (flagged as EVIL or missing): {', '.join(clean_modified)}")
        if evil_bypassed:
            error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (flagged as CLEAN or missing): {', '.join(evil_bypassed)}")

        assert not clean_modified and not evil_bypassed, " | ".join(error_msg)


def test_graphdoc_package_is_repaired():
    package_dir = "/app/vendor/go-graphdoc"
    assert os.path.isfile(os.path.join(package_dir, "parser.go")), "go-graphdoc parser.go is missing"

    test_path = os.path.join(package_dir, "zz_verifier_repair_test.go")
    test_source = textwrap.dedent(r'''
        package graphdoc

        import (
            "os"
            "testing"
        )

        func TestVerifierPackageRepair(t *testing.T) {
            os.Unsetenv("GRAPH_ENV")
            data := []byte(`[{
                "$match": {"gene2": "active"}
            }]`)
            stages, err := ParsePipeline(data)
            if err != nil {
                t.Fatalf("ParsePipeline rejected a valid pipeline without a hardcoded environment: %v", err)
            }
            if len(stages) != 1 {
                t.Fatalf("expected one parsed stage, got %d", len(stages))
            }
            if !fieldRegex.MatchString("gene2") || !fieldRegex.MatchString("expression_level9") {
                t.Fatal("field-name regex still rejects valid names containing digits")
            }
        }
    ''')
    try:
        with open(test_path, "w") as f:
            f.write(test_source)
        env = os.environ.copy()
        env.pop("GRAPH_ENV", None)
        result = subprocess.run(
            ["go", "test", "."], cwd=package_dir, env=env,
            capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, f"go-graphdoc is not repaired or does not build:\n{result.stdout}\n{result.stderr}"
    finally:
        if os.path.exists(test_path):
            os.remove(test_path)


def test_detector_source_exists_uses_graphdoc_and_builds():
    source = "/home/user/detector.go"
    assert os.path.isfile(source), "/home/user/detector.go is missing"

    checked = subprocess.run(
        ["/tmp/check_detector_source", source], capture_output=True, text=True
    )
    assert checked.returncode == 0, checked.stderr

    built = "/tmp/detector_from_source"
    result = subprocess.run(
        ["go", "build", "-o", built, source], cwd="/home/user",
        capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"detector.go does not compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(built) and os.access(built, os.X_OK)


def exercise_generated_queries(binary):
    nonce = uuid.uuid4().hex
    cases = [
        ([{"$match": {"sample9": "active"}}, {"$project": {"gene2": 1, "expression_level9": 1}}], "CLEAN"),
        ([{"$graphLookup": {"from": "nodes", "startWith": "$node2", "connectFromField": "node2", "connectToField": "parent2", "as": "tree2", "maxDepth": 5}}], "CLEAN"),
        ([{"$lookup": {"from": "genes", "localField": "gene2", "foreignField": "gene2", "as": "joined", "maxDepth": 3}}], "CLEAN"),
        ([{"$project": {"admin_notes": 1, "public_value": 1}}], "EVIL"),
        ([{"$match": {"auth_token": "secret"}}], "EVIL"),
        ([{"$project": {"_internal_patient_id": 1}}], "EVIL"),
        ([{"$graphLookup": {"from": "nodes", "startWith": "$node", "connectFromField": "node", "connectToField": "parent", "as": "tree"}}], "EVIL"),
        ([{"$lookup": {"from": "genes", "localField": "gene", "foreignField": "gene", "as": "joined", "maxDepth": 6}}], "EVIL"),
        ([{"$lookup": {"from": "genes", "localField": "gene", "foreignField": "gene", "as": "joined"}}], "EVIL"),
    ]

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        expected = set()
        for index, (query, status) in enumerate(cases):
            filename = f"query_{nonce}_{index}.json"
            with open(os.path.join(input_dir, filename), "w") as f:
                json.dump(query, f)
            expected.add(f"{filename} : {status}")

        output = os.path.join(output_dir, "generated-results.log")
        result = subprocess.run(
            [binary, "-input", input_dir, "-output", output],
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"Detector failed on generated queries: {result.stderr}"
        assert os.path.isfile(output), "Detector did not create output for generated queries"
        with open(output) as f:
            actual_lines = f.read().splitlines()

        assert len(actual_lines) == len(expected), "Detector must emit exactly one line per JSON file"
        assert set(actual_lines) == expected, f"Incorrect generated-query results. Expected {expected}, got {set(actual_lines)}"


def test_detector_generalizes_beyond_fixed_corpus():
    exercise_generated_queries("/home/user/detector")
    exercise_generated_queries("/tmp/detector_from_source")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
