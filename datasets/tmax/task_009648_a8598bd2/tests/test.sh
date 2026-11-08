#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/instrument_tokenize.go
package main

import (
    "fmt"
    "go/ast"
    "go/format"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        panic("usage: instrument_tokenize <prepare_data.go>")
    }
    path := os.Args[1]
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, path, nil, parser.ParseComments)
    if err != nil {
        panic(err)
    }

    synthetic, err := parser.ParseFile(token.NewFileSet(), "probe.go", `package main
var verifierTokenizeCallCount int
func verifierReplacement(text string, vocab map[string]int) []int {
    if text != "hello world this is a test" {
        panic("VERIFIER_WRONG_SAMPLE_STRING")
    }
    if vocab == nil {
        panic("VERIFIER_NIL_DUMMY_VOCAB")
    }
    verifierTokenizeCallCount++
    if verifierTokenizeCallCount >= 5 {
        panic("VERIFIER_TOKENIZE_CALLED_REPEATEDLY")
    }
    return nil
}
`, 0)
    if err != nil {
        panic(err)
    }

    replacement := synthetic.Decls[1].(*ast.FuncDecl).Body
    found := false
    for _, decl := range file.Decls {
        if fn, ok := decl.(*ast.FuncDecl); ok && fn.Recv == nil && fn.Name.Name == "Tokenize" {
            fn.Body = replacement
            found = true
            break
        }
    }
    if !found {
        panic("Tokenize function not found")
    }
    file.Decls = append(file.Decls, synthetic.Decls[0])

    out, err := os.Create(path)
    if err != nil {
        panic(err)
    }
    defer out.Close()
    if err := format.Node(out, fset, file); err != nil {
        panic(err)
    }
    fmt.Println("instrumented")
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "prepare_data.go")
DATASET = os.path.join(HOME, "dataset", "messages.csv")
FEATURES = os.path.join(HOME, "test_features.csv")
BENCHMARK = os.path.join(HOME, "prepare_data_test.go")


def run(cmd, cwd=HOME, timeout=120, check=True):
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True,
        timeout=timeout, check=check
    )


def read_features():
    assert os.path.exists(FEATURES), f"Output file is missing: {FEATURES}"
    assert os.path.isfile(FEATURES), f"Output path is not a file: {FEATURES}"
    with open(FEATURES, "r", encoding="utf-8") as f:
        raw_lines = f.readlines()
    lines = [line.strip() for line in raw_lines if line.strip()]
    parsed = []
    try:
        for line in lines:
            parsed.append([int(x) for x in line.split(",")])
    except ValueError:
        pytest.fail("test_features.csv contains non-integer values or is not comma-separated.")
    return lines, parsed


def expected_features(records):
    train_size = int(0.8 * len(records))
    vocab = {}
    next_id = 1
    for _, text in records[:train_size]:
        for word in text.split():
            if word not in vocab:
                vocab[word] = next_id
                next_id += 1
    return [[vocab.get(word, 0) for word in text.split()]
            for _, text in records[train_size:]]


def write_dataset(records):
    os.makedirs(os.path.dirname(DATASET), exist_ok=True)
    with open(DATASET, "w", newline="", encoding="utf-8") as f:
        csv.writer(f, lineterminator="\n").writerows(records)


def execute_program():
    if os.path.lexists(FEATURES):
        if os.path.isdir(FEATURES) and not os.path.islink(FEATURES):
            shutil.rmtree(FEATURES)
        else:
            os.unlink(FEATURES)
    try:
        run(["go", "run", "prepare_data.go"])
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'go run prepare_data.go' failed with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}")


def test_program_exists_and_generates_original_expected_output():
    assert os.path.exists(SOURCE), f"Program is missing: {SOURCE}"
    assert os.path.isfile(SOURCE), f"Program path is not a file: {SOURCE}"

    original_records = [
        ("ham", "hello friend how are you"),
        ("ham", "i am doing well today"),
        ("spam", "buy cheap watches now"),
        ("ham", "let us meet for lunch"),
        ("ham", "the weather is nice"),
        ("spam", "win a free gift card"),
        ("ham", "call me back when you can"),
        ("ham", "see you tomorrow morning"),
        ("spam", "urgent your account is locked"),
        ("ham", "this is a completely unique test message"),
    ]
    write_dataset(original_records)
    execute_program()
    lines, parsed = read_features()

    assert len(lines) == 2, f"Expected exactly 2 lines in test_features.csv, found {len(lines)}"
    line1_tokens, line2_tokens = parsed

    # Preserve the original assertions for the supplied dataset.
    assert len(line1_tokens) == 5, f"Expected 5 tokens in first test line, got {len(line1_tokens)}"
    assert line1_tokens[0] == 0, "Expected 'urgent' to be UNK (0)"
    assert line1_tokens[1] == 0, "Expected 'your' to be UNK (0)"
    assert line1_tokens[2] == 0, "Expected 'account' to be UNK (0)"
    assert line1_tokens[3] > 0, "Expected 'is' to have a valid vocab ID (>0)"
    assert line1_tokens[4] == 0, "Expected 'locked' to be UNK (0)"

    assert len(line2_tokens) == 7, f"Expected 7 tokens in second test line, got {len(line2_tokens)}"
    assert line2_tokens[0] == 0, "Expected 'this' to be UNK (0)"
    assert line2_tokens[1] > 0, "Expected 'is' to have a valid vocab ID (>0)"
    assert line2_tokens[2] > 0, "Expected 'a' to have a valid vocab ID (>0)"
    assert line2_tokens[3] == 0, "Expected 'completely' to be UNK (0)"
    assert line2_tokens[4] == 0, "Expected 'unique' to be UNK (0)"
    assert line2_tokens[5] == 0, "Expected 'test' to be UNK (0)"
    assert line2_tokens[6] == 0, "Expected 'message' to be UNK (0)"
    assert line1_tokens[3] == line2_tokens[1], "Expected 'is' to have the same vocab ID in both test lines"

    # Also require the exact IDs produced by first-seen training-only vocabulary construction.
    assert parsed == expected_features(original_records), \
        f"Generated features do not match training-only vocabulary IDs: {parsed}"


def test_program_on_unseen_random_dataset():
    nonce = secrets.token_hex(8)
    def w(name):
        return f"{name}_{nonce}"

    records = [
        ("x", f"{w('alpha')} {w('shared')} {w('beta')}"),
        ("x", f"{w('gamma')}\t{w('delta')}"),
        ("x", f"{w('shared')} {w('epsilon')}"),
        ("x", f"{w('zeta')} {w('eta')} {w('theta')}"),
        ("x", f"{w('iota')} {w('kappa')}"),
        ("x", f"{w('lambda')} {w('mu')} {w('shared')}"),
        ("x", f"{w('nu')} {w('xi')}"),
        ("x", f"{w('omicron')} {w('pi')}"),
        ("x", f"{w('rho')} {w('sigma')}"),
        ("x", f"{w('tau')} {w('upsilon')}"),
        ("x", f"{w('testonly1')} {w('shared')} {w('testonly2')}"),
        ("x", f"{w('alpha')}\t{w('testonly3')} {w('tau')}"),
        ("x", f"{w('testonly4')} {w('testonly5')}"),
    ]
    write_dataset(records)
    execute_program()
    lines, actual = read_features()
    expected = expected_features(records)
    assert len(lines) == len(expected), \
        f"Expected {len(expected)} test rows, found {len(lines)}"
    assert actual == expected, \
        f"Program did not derive test features from the training-only vocabulary. Expected {expected}, got {actual}"


def test_go_benchmark_file_exists():
    assert os.path.exists(BENCHMARK), f"Benchmark file is missing: {BENCHMARK}"
    assert os.path.isfile(BENCHMARK), f"Benchmark path is not a file: {BENCHMARK}"
    with open(BENCHMARK, "r", encoding="utf-8") as f:
        content = f.read()
    assert "BenchmarkTokenize" in content, "BenchmarkTokenize function is missing from prepare_data_test.go"


def test_go_benchmark_runs():
    try:
        result = run(["go", "test", "-bench", "."])
        assert "BenchmarkTokenize" in result.stdout, "Benchmark did not run or output 'BenchmarkTokenize'."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'go test -bench .' failed with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}")
    except FileNotFoundError:
        pytest.fail("The 'go' command was not found. Is Go installed and in PATH?")


def test_benchmark_repeatedly_calls_tokenize_with_required_arguments():
    with tempfile.TemporaryDirectory(prefix="benchmark_probe_") as td:
        for name in os.listdir(HOME):
            src = os.path.join(HOME, name)
            dst = os.path.join(td, name)
            if os.path.isfile(src) and (name.endswith(".go") or name in ("go.mod", "go.sum")):
                shutil.copy2(src, dst)

        copied_source = os.path.join(td, "prepare_data.go")
        assert os.path.isfile(copied_source), "prepare_data.go was not available for benchmark probing"
        patch = run(["go", "run", "/tmp/instrument_tokenize.go", copied_source], cwd="/tmp")
        assert "instrumented" in patch.stdout

        result = run(
            ["go", "test", "-run", "^$", "-bench", "^BenchmarkTokenize$", "-benchtime=7x"],
            cwd=td, check=False
        )
        combined = result.stdout + "\n" + result.stderr
        assert "VERIFIER_WRONG_SAMPLE_STRING" not in combined, \
            "BenchmarkTokenize does not call Tokenize with the required sample string"
        assert "VERIFIER_NIL_DUMMY_VOCAB" not in combined, \
            "BenchmarkTokenize does not provide a dummy vocabulary"
        assert result.returncode != 0 and "VERIFIER_TOKENIZE_CALLED_REPEATEDLY" in combined, \
            "BenchmarkTokenize must repeatedly call Tokenize inside the benchmark workload"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
