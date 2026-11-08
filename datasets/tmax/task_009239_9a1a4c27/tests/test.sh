#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp -a /home/user/configs "$BACKUP_DIR/configs"
cp /home/user/math_ops.c "$BACKUP_DIR/math_ops.c"
cp /home/user/math_ops.h "$BACKUP_DIR/math_ops.h"
if [ -e /home/user/results.json ]; then
    cp /home/user/results.json "$BACKUP_DIR/results.json"
    touch "$BACKUP_DIR/had_results"
fi

cleanup() {
    rm -rf /home/user/configs
    cp -a "$BACKUP_DIR/configs" /home/user/configs
    cp "$BACKUP_DIR/math_ops.c" /home/user/math_ops.c
    cp "$BACKUP_DIR/math_ops.h" /home/user/math_ops.h
    if [ -e "$BACKUP_DIR/had_results" ]; then
        cp "$BACKUP_DIR/results.json" /home/user/results.json
    else
        rm -f /home/user/results.json
    fi
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import threading
import time
import pytest

HOME = "/home/user"
EVALUATOR = "/home/user/evaluator.go"
RESULTS = "/home/user/results.json"


def run(cmd, timeout=30):
    return subprocess.run(
        cmd, cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout
    )


def build(output):
    proc = run(["go", "build", "-o", output, "."], timeout=60)
    assert proc.returncode == 0, (
        "evaluator.go did not build as the Go package containing the supplied "
        f"C library.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )


def load_results():
    assert os.path.isfile(RESULTS), f"Expected results file {RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON.")


def test_01_program_executes_and_original_results_are_correct():
    assert os.path.isfile(EVALUATOR), f"Expected Go program {EVALUATOR} does not exist."
    build("/tmp/evaluator_original")
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = run(["/tmp/evaluator_original"], timeout=20)
    assert proc.returncode == 0, (
        f"The evaluator failed when executed.\nstdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )

    data = load_results()
    expected_data = {
        "A.txt": 30,
        "B.txt": 20,
        "C.txt": 10,
        "D.txt": 15,
        "E.txt": 15,
        "F.txt": 100
    }

    for key, expected_value in expected_data.items():
        assert key in data, f"Key '{key}' is missing from {RESULTS}."
        assert data[key] == expected_value, f"Value for '{key}' is incorrect. Expected {expected_value}, got {data[key]}."


def test_02_evaluator_go_exists_and_uses_cgo_and_goroutines():
    evaluator_file = "/home/user/evaluator.go"
    assert os.path.isfile(evaluator_file), f"Expected Go program {evaluator_file} does not exist."

    with open(evaluator_file, "r") as f:
        content = f.read()

    assert 'import "C"' in content or 'import (\n\t"C"' in content or 'import (\n\t"fmt"\n\t"C"' in content or '"C"' in content, \
        f"The Go program {evaluator_file} does not appear to import 'C' (cgo)."

    assert 'go ' in content, f"The Go program {evaluator_file} does not appear to use goroutines ('go ' keyword missing)."

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
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil { panic(err) }
    hasC, hasGo, hasChan, hasSend, hasReceive := false, false, false, false, false
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p == "C" { hasC = true }
    }
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasChan = true
        case *ast.SendStmt:
            hasSend = true
        case *ast.UnaryExpr:
            if x.Op == token.ARROW { hasReceive = true }
        case *ast.RangeStmt:
            hasReceive = true
        }
        return true
    })
    if !(hasC && hasGo && hasChan && hasSend && hasReceive) {
        fmt.Fprintf(os.Stderr, "cgo=%v goroutine=%v channel=%v send=%v receive=%v\n", hasC, hasGo, hasChan, hasSend, hasReceive)
        os.Exit(1)
    }
}
'''
    with open("/tmp/check_evaluator_ast.go", "w") as f:
        f.write(checker)
    compiled = subprocess.run(
        ["go", "build", "-o", "/tmp/check_evaluator_ast", "/tmp/check_evaluator_ast.go"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compiled.returncode == 0, compiled.stderr
    checked = subprocess.run(
        ["/tmp/check_evaluator_ast", EVALUATOR], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert checked.returncode == 0, (
        "The evaluator must contain real cgo, goroutine, and channel syntax, not "
        f"only matching words in comments. Details: {checked.stderr}"
    )


def c_div(a, b):
    return int(a / b) if b != 0 else 0


def expected_values(expressions):
    memo = {}
    def operand(token):
        try:
            return int(token)
        except ValueError:
            return evaluate(token)
    def evaluate(name):
        if name in memo:
            return memo[name]
        parts = expressions[name].split(" ")
        if len(parts) == 1:
            value = int(parts[0])
        else:
            a, op, b = operand(parts[0]), parts[1], operand(parts[2])
            if op == "+": value = a + b + 101
            elif op == "-": value = a - b - 103
            elif op == "*": value = a * b + 107
            elif op == "/": value = c_div(a, b) + 109
            else: raise AssertionError(op)
        memo[name] = value
        return value
    for filename in expressions:
        evaluate(filename)
    return memo


def test_03_dynamic_inputs_use_c_library_and_concurrent_reads():
    # Give the supplied C function deliberately distinguishable behavior. A valid
    # cgo caller automatically observes it; direct Go arithmetic does not.
    with open("/home/user/math_ops.c", "w") as f:
        f.write(r'''#include "math_ops.h"
int evaluate_op(int a, int b, char op) {
    if (op == '+') return a + b + 101;
    if (op == '-') return a - b - 103;
    if (op == '*') return a * b + 107;
    if (op == '/') return b != 0 ? a / b + 109 : 0;
    return 0;
}
''')
    build("/tmp/evaluator_instrumented")

    expressions = {
        "seed.txt": "7",
        "plus.txt": "seed.txt + 5",
        "product.txt": "plus.txt * 3",
        "difference.txt": "product.txt - seed.txt",
        "quotient.txt": "difference.txt / 2",
        "negative.txt": "10 - 30",
        "negative_div.txt": "negative.txt / 5",
        "literal_product.txt": "2 * 4"
    }
    expected = expected_values(expressions)

    config_dir = "/home/user/configs"
    for entry in os.listdir(config_dir):
        os.remove(os.path.join(config_dir, entry))
    for name in expressions:
        os.mkfifo(os.path.join(config_dir, name))

    release = threading.Event()
    errors = []
    def writer(path, contents):
        try:
            with open(path, "w") as stream:
                if not release.wait(12):
                    return
                stream.write(contents + "\n")
                stream.flush()
        except Exception as exc:
            errors.append(exc)

    threads = []
    for name, contents in expressions.items():
        thread = threading.Thread(
            target=writer,
            args=(os.path.join(config_dir, name), contents),
            daemon=True
        )
        thread.start()
        threads.append(thread)

    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.Popen(
        ["/tmp/evaluator_instrumented"], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    # FIFO writers withhold all contents. A sequential reader can have only one
    # FIFO open and blocks there; two simultaneous config FDs prove actual
    # overlapping reads rather than a keyword or dead goroutine.
    concurrent = False
    deadline = time.time() + 10
    while time.time() < deadline and proc.poll() is None:
        opened = set()
        try:
            for fd in os.listdir(f"/proc/{proc.pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{proc.pid}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith(config_dir + "/"):
                    opened.add(target)
        except FileNotFoundError:
            break
        if len(opened) >= 2:
            concurrent = True
            break
        time.sleep(0.02)

    release.set()
    if not concurrent:
        proc.kill()
        stdout, stderr = proc.communicate(timeout=5)
        pytest.fail(
            "The evaluator did not read configuration files concurrently. "
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )

    try:
        stdout, stderr = proc.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        pytest.fail(f"The evaluator timed out. stdout:\n{stdout}\nstderr:\n{stderr}")
    assert proc.returncode == 0, (
        f"Dynamic evaluator run failed.\nstdout:\n{stdout}\nstderr:\n{stderr}"
    )
    assert not errors, f"FIFO writers failed: {errors}"
    data = load_results()
    assert data == expected, f"Expected dynamic results {expected}, got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
