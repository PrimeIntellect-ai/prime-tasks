#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_go_concurrency.go
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
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasExec := false
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p == "os/exec" {
            hasExec = true
        }
    }

    goStatements := 0
    hasSynchronization := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            goStatements++
        case *ast.ChanType:
            hasSynchronization = true
        case *ast.Ident:
            if x.Name == "WaitGroup" {
                hasSynchronization = true
            }
        }
        return true
    })

    if !hasExec || goStatements == 0 || !hasSynchronization {
        fmt.Fprintf(os.Stderr, "orchestrator requirements missing: os/exec=%v goroutine=%v channel-or-WaitGroup=%v\n", hasExec, goStatements > 0, hasSynchronization)
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

BASE_DIR = "/home/user/release_prep"
DATA_DIR = os.path.join(BASE_DIR, "data")


def test_merger_c_exists():
    filepath = os.path.join(BASE_DIR, "merger.c")
    assert os.path.isfile(filepath), f"{filepath} does not exist. The C source file is missing."


def test_merger_executable_exists():
    filepath = os.path.join(BASE_DIR, "merger")
    assert os.path.isfile(filepath), f"{filepath} does not exist. The C program was not compiled."
    assert os.access(filepath, os.X_OK), f"{filepath} is not executable."


def test_test_go_exists():
    filepath = os.path.join(BASE_DIR, "test.go")
    assert os.path.isfile(filepath), f"{filepath} does not exist. The Go test orchestrator is missing."


def test_status_txt_content():
    filepath = os.path.join(BASE_DIR, "status.txt")
    assert os.path.isfile(filepath), f"{filepath} does not exist. The Go program may not have run successfully."

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content == "ALL PASS", f"Expected 'ALL PASS' in {filepath}, but got '{content}'."


def encoded(values):
    if not values:
        return b""
    return ("".join(f"{v}\n" for v in values)).encode()


def exercise_merger(executable):
    cases = [
        ([-19, -4, -4, 0, 31], [-20, -4, 2, 2, 90]),
        ([], [-7, 0, 8]),
        ([1, 1, 5], []),
        ([], []),
    ]
    with tempfile.TemporaryDirectory() as td:
        for number, (left, right) in enumerate(cases):
            a = os.path.join(td, f"a{number}.txt")
            b = os.path.join(td, f"b{number}.txt")
            with open(a, "wb") as f:
                f.write(encoded(left))
            with open(b, "wb") as f:
                f.write(encoded(right))
            result = subprocess.run(
                [executable, a, b], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=5
            )
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            assert result.stdout == encoded(sorted(left + right)), (
                f"incorrect merge for {left} and {right}: {result.stdout!r}"
            )


def test_merger_source_and_executable_behavior():
    merger = os.path.join(BASE_DIR, "merger")
    with open(merger, "rb") as f:
        assert f.read(4) == b"\x7fELF", "merger is not a compiled executable"

    no_args = subprocess.run([merger], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    too_many = subprocess.run(
        [merger, "x", "y", "z"], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert no_args.returncode != 0, "merger must reject calls without exactly two arguments"
    assert too_many.returncode != 0, "merger must reject calls with more than two arguments"
    exercise_merger(merger)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "merger-rebuilt")
        build = subprocess.run(
            ["gcc", os.path.join(BASE_DIR, "merger.c"), "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert build.returncode == 0, build.stderr.decode(errors="replace")
        exercise_merger(rebuilt)


def run_orchestrator():
    return subprocess.run(
        ["go", "run", "test.go"], cwd=BASE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )


def test_orchestrator_concurrency_and_end_to_end_behavior():
    static_check = subprocess.run(
        ["go", "run", "/tmp/check_go_concurrency.go", "--", os.path.join(BASE_DIR, "test.go")],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert static_check.returncode == 0, static_check.stderr.decode(errors="replace")

    names = [f"{prefix}{i}.txt" for i in range(1, 4) for prefix in ("a", "b", "exp")]
    paths = [os.path.join(DATA_DIR, name) for name in names]
    backups = {p: open(p, "rb").read() for p in paths}
    status = os.path.join(BASE_DIR, "status.txt")
    status_existed = os.path.exists(status)
    status_backup = open(status, "rb").read() if status_existed else None

    seed = secrets.randbelow(10000) + 100
    datasets = [
        (sorted([-seed, -3, 4, seed]), sorted([-seed, 0, 4, seed + 1])),
        ([], sorted([-seed - 2, 7, seed + 5])),
        (sorted([-11, 2, 2, seed + 9]), []),
    ]

    try:
        for i, (left, right) in enumerate(datasets, 1):
            with open(os.path.join(DATA_DIR, f"a{i}.txt"), "wb") as f:
                f.write(encoded(left))
            with open(os.path.join(DATA_DIR, f"b{i}.txt"), "wb") as f:
                f.write(encoded(right))
            with open(os.path.join(DATA_DIR, f"exp{i}.txt"), "wb") as f:
                f.write(encoded(sorted(left + right)))

        # Each expected file must actually be consulted. A failed comparison must
        # not produce the success marker.
        for i in range(1, 4):
            exp = os.path.join(DATA_DIR, f"exp{i}.txt")
            correct = open(exp, "rb").read()
            with open(exp, "wb") as f:
                f.write(correct + b"999999937\n")
            if os.path.exists(status):
                os.remove(status)
            run_orchestrator()
            produced = open(status, "rb").read().strip() if os.path.exists(status) else b""
            assert produced != b"ALL PASS", f"test.go ignored a mismatch in exp{i}.txt"
            with open(exp, "wb") as f:
                f.write(correct)

        if os.path.exists(status):
            os.remove(status)
        result = run_orchestrator()
        assert os.path.isfile(status), (
            "test.go did not create status.txt on passing datasets; "
            + result.stderr.decode(errors="replace")
        )
        with open(status, "rb") as f:
            assert f.read() == b"ALL PASS", "test.go must write the exact string ALL PASS"
    finally:
        for path, content in backups.items():
            with open(path, "wb") as f:
                f.write(content)
        if status_existed:
            with open(status, "wb") as f:
                f.write(status_backup)
        elif os.path.exists(status):
            os.remove(status)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
