#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import uuid


def test_chunker_binary_exists_and_executable():
    binary_path = "/home/user/logchunker/chunker"
    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist. Did you compile it?"
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."


def test_chunker_is_go_binary_from_module():
    binary_path = "/home/user/logchunker/chunker"
    result = subprocess.run(["go", "version", "-m", binary_path], capture_output=True, text=True)
    assert result.returncode == 0, f"{binary_path} is not a valid Go binary.\nStderr: {result.stderr}"
    assert re.search(r"(?m)^\s*path\s+logchunker\s*$", result.stdout), (
        f"{binary_path} was not built as the logchunker Go module.\nBuild info:\n{result.stdout}"
    )


def test_chunker_runs_successfully():
    binary_path = "/home/user/logchunker/chunker"
    result = subprocess.run([binary_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {binary_path} failed with exit code {result.returncode}.\nStderr: {result.stderr}"


def test_chunker_binary_processes_controlled_logs():
    binary_path = "/home/user/logchunker/chunker"
    logs_path = "/home/user/server_logs.txt"
    with open(logs_path, "rb") as f:
        original = f.read()

    cases = [
        (["one"], 1),
        (["one", "two", "three", "four"], 2),
        (["a", "b", "c", "d", "e", "f"], 2),
    ]
    try:
        for lines, expected_count in cases:
            with open(logs_path, "w") as f:
                f.write("\n".join(lines) + "\n")
            result = subprocess.run([binary_path], capture_output=True, text=True)
            assert result.returncode == 0, (
                f"Binary failed for {len(lines)} controlled log lines.\nStderr: {result.stderr}"
            )
            assert result.stdout.strip() == f"Processed {expected_count} chunks", (
                f"Wrong binary output for {len(lines)} log lines: {result.stdout!r}"
            )
    finally:
        with open(logs_path, "wb") as f:
            f.write(original)


def test_go_test_passes():
    test_dir = "/home/user/logchunker"
    result = subprocess.run(["go", "test"], cwd=test_dir, capture_output=True, text=True)
    assert result.returncode == 0, f"'go test' failed in {test_dir}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_chunkdata_required_behavior():
    test_dir = "/home/user/logchunker"
    test_name = f"verifier_behavior_{uuid.uuid4().hex}_test.go"
    test_path = os.path.join(test_dir, test_name)
    hidden_test = r'''package main

import (
    "reflect"
    "testing"
)

func TestVerifierChunkDataRequiredCase(t *testing.T) {
    input := []string{"A", "B", "C", "D"}
    got := ChunkData(input, 3)
    want := [][]string{{"A", "B", "C"}, {"D"}}
    if !reflect.DeepEqual(got, want) {
        t.Fatalf("ChunkData(%v, 3) = %#v; want %#v", input, got, want)
    }
}
'''
    try:
        with open(test_path, "w") as f:
            f.write(hidden_test)
        result = subprocess.run(
            ["go", "test", "-count=1", "-run", "^TestVerifierChunkDataRequiredCase$"],
            cwd=test_dir,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            "ChunkData does not correctly chunk the required A-D input without panicking.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
    finally:
        if os.path.exists(test_path):
            os.remove(test_path)


def test_main_test_go_contents():
    test_file = "/home/user/logchunker/main_test.go"
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."

    with open(test_file, "r") as f:
        content = f.read()

    assert "TestChunkData" in content, "main_test.go does not contain a test function named 'TestChunkData'."
    assert "ChunkData" in content, "main_test.go does not call 'ChunkData'."
    assert "A" in content and "B" in content and "C" in content and "D" in content, "main_test.go does not seem to test the required input data."


def test_regression_test_rejects_wrong_chunking():
    source_dir = "/home/user/logchunker"
    with tempfile.TemporaryDirectory() as parent:
        copied_dir = os.path.join(parent, "logchunker")
        shutil.copytree(source_dir, copied_dir)

        mutator = os.path.join(parent, "mutate.go")
        with open(mutator, "w") as f:
            f.write(r'''package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    path := os.Args[1]
    src, err := os.ReadFile(path)
    if err != nil { panic(err) }
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, path, src, 0)
    if err != nil { panic(err) }
    for _, decl := range file.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if ok && fn.Name.Name == "ChunkData" && fn.Body != nil {
            start := fset.Position(fn.Body.Pos()).Offset
            end := fset.Position(fn.Body.End()).Offset
            bad := []byte(`{ return [][]string{{"A", "B", "C", "D"}} }`)
            out := append([]byte{}, src[:start]...)
            out = append(out, bad...)
            out = append(out, src[end:]...)
            if err := os.WriteFile(path, out, 0644); err != nil { panic(err) }
            return
        }
    }
    fmt.Fprintln(os.Stderr, "ChunkData function not found")
    os.Exit(1)
}
''')

        mutation = subprocess.run(
            ["go", "run", mutator, os.path.join(copied_dir, "main.go")],
            cwd=copied_dir,
            capture_output=True,
            text=True,
        )
        assert mutation.returncode == 0, f"Could not inspect ChunkData: {mutation.stderr}"

        result = subprocess.run(
            ["go", "test", "-count=1", "-run", "^TestChunkData$"],
            cwd=copied_dir,
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0, (
            "TestChunkData is vacuous: it still passes when ChunkData returns the required "
            "input as one incorrectly sized chunk."
        )


def test_main_go_fixes():
    main_file = "/home/user/logchunker/main.go"
    assert os.path.isfile(main_file), f"{main_file} is missing."

    with open(main_file, "r") as f:
        content = f.read()

    assert "end = len(data) + 1" not in content, "The algorithmic bug 'end = len(data) + 1' is still present in main.go."
    assert "var count string = len(chunks)" not in content, "The compiler error 'var count string = len(chunks)' is still present in main.go."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
