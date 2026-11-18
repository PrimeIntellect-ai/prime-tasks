#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_mcparser_use.go
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(1)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        os.Exit(1)
    }

    aliases := map[string]bool{}
    dotImport := false
    for _, imp := range f.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err != nil || path != "mcparser" {
            continue
        }
        if imp.Name == nil {
            aliases["mcparser"] = true
        } else if imp.Name.Name == "." {
            dotImport = true
        } else if imp.Name.Name != "_" {
            aliases[imp.Name.Name] = true
        }
    }

    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "Parse" {
            if id, ok := sel.X.(*ast.Ident); ok && aliases[id.Name] {
                found = true
            }
        }
        if dotImport {
            if id, ok := call.Fun.(*ast.Ident); ok && id.Name == "Parse" {
                found = true
            }
        }
        return true
    })
    if !found {
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import struct
import subprocess
import tempfile
import uuid

import pytest


def test_detect_go_exists():
    assert os.path.isfile("/home/user/detect.go"), "/home/user/detect.go does not exist."


def test_mcparser_fixed():
    path = "/app/mcparser/parser.go"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "[]flot64" not in content, "The typo '[]flot64' is still present in parser.go."
    assert "[]float64" in content, "The return type was not fixed to '[]float64'."


def test_mcparser_compiles_and_parse_works(tmp_path):
    values = [random.SystemRandom().uniform(-1000.0, 1000.0) for _ in range(23)]
    trace = tmp_path / (uuid.uuid4().hex + ".dat")
    with open(trace, "wb") as f:
        for value in values:
            f.write(struct.pack("<d", value))

    helper = tmp_path / "helper"
    helper.mkdir()
    (helper / "go.mod").write_text(
        "module verifierparser\n\n"
        "go 1.21\n\n"
        "require mcparser v0.0.0\n"
        "replace mcparser => /app/mcparser\n"
    )
    (helper / "main.go").write_text(r'''package main
import (
    "encoding/json"
    "mcparser"
    "os"
)
func main() {
    values, err := mcparser.Parse(os.Args[1])
    if err != nil { panic(err) }
    if err := json.NewEncoder(os.Stdout).Encode(values); err != nil { panic(err) }
}
''')
    res = subprocess.run(
        ["go", "run", ".", str(trace)],
        cwd=helper,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert res.returncode == 0, f"mcparser did not compile or Parse failed: {res.stderr}"
    assert json.loads(res.stdout) == values, "mcparser.Parse returned incorrect float64 data."


def test_detect_calls_mcparser_parse(tmp_path):
    checker = tmp_path / "check_mcparser_use"
    build = subprocess.run(
        ["go", "build", "-o", str(checker), "/tmp/check_mcparser_use.go"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Could not build verifier helper: {build.stderr}"
    res = subprocess.run([str(checker), "/home/user/detect.go"], capture_output=True, text=True)
    assert res.returncode == 0, "detect.go must import mcparser and call mcparser.Parse."


def test_adversarial_corpus():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.bin"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.bin"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        res = subprocess.run(
            ["go", "run", "/home/user/detect.go", f],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
        )
        if res.returncode != 0 or res.stdout.strip() != "EVIL":
            evil_bypassed.append(os.path.basename(f))

    for f in clean_files:
        res = subprocess.run(
            ["go", "run", "/home/user/detect.go", f],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
        )
        if res.returncode != 0 or res.stdout.strip() != "CLEAN":
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_unseen_traces(tmp_path):
    binary = tmp_path / ("detector_" + uuid.uuid4().hex)
    build = subprocess.run(
        ["go", "build", "-o", str(binary), "/home/user/detect.go"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"detect.go does not compile: {build.stderr}"

    rng = random.SystemRandom()
    cases = []
    targets = [rng.uniform(0.02, 1.95) for _ in range(8)]
    targets += [rng.uniform(5.05, 24.0) for _ in range(8)]
    rng.shuffle(targets)

    for target in targets:
        n = rng.randint(31, 257)
        values = [rng.uniform(-500.0, 500.0)]
        step = math.sqrt(target)
        for _ in range(n - 1):
            values.append(values[-1] + (step if rng.randrange(2) else -step))

        roughness = sum(
            (values[i] - values[i - 1]) ** 2 for i in range(1, len(values))
        ) / (len(values) - 1)
        expected = "CLEAN" if roughness < 2.0 else "EVIL" if roughness > 5.0 else None
        assert expected is not None

        path = tmp_path / (uuid.uuid4().hex + ".dat")
        with open(path, "wb") as f:
            for value in values:
                f.write(struct.pack("<d", value))
        cases.append((path, expected, roughness))

    rng.shuffle(cases)
    for path, expected, roughness in cases:
        res = subprocess.run(
            [str(binary), str(path)],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert res.returncode == 0, (
            f"Detector exited {res.returncode} for an unseen trace with R={roughness}: {res.stderr}"
        )
        assert res.stdout.strip() == expected, (
            f"Expected {expected} for unseen trace with R={roughness}, got {res.stdout!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
