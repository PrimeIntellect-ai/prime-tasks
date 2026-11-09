#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import subprocess
import tempfile


def test_go_mod_exists():
    path = "/home/user/go.mod"
    assert os.path.isfile(path), f"File {path} is missing. Did you initialize the Go module?"


def test_trace_txt_exists_and_valid():
    path = "/home/user/trace.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did the script run successfully?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."

    try:
        val = float(content)
    except ValueError:
        assert False, f"Content of {path} is not a valid floating-point number: {content}"


def test_generate_go_modified():
    path = "/home/user/generate.go"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Retain the original ridge-token assertion.
    has_ridge = "1e-4" in content or "0.0001" in content or ".0001" in content
    assert has_ridge, f"File {path} does not seem to contain the ridge value 1e-4 or 0.0001."


def run(cmd, cwd=None, timeout=180):
    result = subprocess.run(
        cmd, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=timeout
    )
    assert result.returncode == 0, f"Command failed: {' '.join(cmd)}\n{result.stdout}"
    return result.stdout


def copy_module_files(dst):
    shutil.copy2("/home/user/go.mod", os.path.join(dst, "go.mod"))
    if os.path.isfile("/home/user/go.sum"):
        shutil.copy2("/home/user/go.sum", os.path.join(dst, "go.sum"))


def test_program_behavior_and_actual_trace():
    # Independently derive the deterministic result from the required matrix,
    # ridge, seed, and sample count.
    with tempfile.TemporaryDirectory() as oracle_dir:
        copy_module_files(oracle_dir)
        oracle = r'''package main
import (
    "fmt"
    "math/rand"
    "gonum.org/v1/gonum/mat"
)
func main() {
    data := []float64{
        1.0, 0.9999999, 0.5,
        0.9999999, 1.0, 0.5,
        0.5, 0.5, 1.0,
    }
    cov := mat.NewSymDense(3, data)
    for i := 0; i < 3; i++ {
        cov.SetSym(i, i, cov.At(i, i)+1e-4)
    }
    var chol mat.Cholesky
    if !chol.Factorize(cov) { panic("matrix is not positive definite") }
    var L mat.Dense
    chol.LTo(&L)
    rnd := rand.New(rand.NewSource(42))
    sumMC := 0.0
    for j := 0; j < 100000; j++ {
        z := mat.NewVecDense(3, []float64{rnd.NormFloat64(), rnd.NormFloat64(), rnd.NormFloat64()})
        var x mat.VecDense
        x.MulVec(&L, z)
        sumMC += x.AtVec(0) + x.AtVec(1) + x.AtVec(2)
    }
    fmt.Printf("%.6f\n", sumMC)
}
'''
        with open(os.path.join(oracle_dir, "main.go"), "w") as f:
            f.write(oracle)
        expected = run(["go", "run", "."], cwd=oracle_dir).strip()

    assert re.fullmatch(r"[-+]?\d+\.\d{6}", expected), f"Invalid oracle output: {expected!r}"
    assert math.isfinite(float(expected))

    # The trace left by the agent must already be the actual Monte Carlo result.
    with open("/home/user/trace.txt") as f:
        submitted_trace = f.read().strip()
    assert submitted_trace == expected, (
        f"trace.txt is not the required Monte Carlo result: got {submitted_trace!r}, "
        f"expected {expected!r}"
    )

    # Build an AST-based source instrumenter. It verifies the preserved seed and
    # sample-count literals and intercepts the real Factorize call to inspect cov.
    checker_source = r'''package main
import (
    "bytes"
    "fmt"
    "go/ast"
    "go/format"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func text(fset *token.FileSet, n ast.Node) string {
    var b bytes.Buffer
    if err := format.Node(&b, fset, n); err != nil { panic(err) }
    return b.String()
}
func intValue(e ast.Expr) (int64, bool) {
    lit, ok := e.(*ast.BasicLit)
    if !ok || lit.Kind != token.INT { return 0, false }
    v, err := strconv.ParseInt(lit.Value, 0, 64)
    return v, err == nil
}
func main() {
    if len(os.Args) != 3 { panic("usage: checker input output") }
    src, err := os.ReadFile(os.Args[1]); if err != nil { panic(err) }
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], src, parser.ParseComments)
    if err != nil { panic(err) }
    seed42 := 0
    loops100000 := 0
    var target *ast.CallExpr
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.CallExpr:
            if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
                if sel.Sel.Name == "NewSource" && len(x.Args) == 1 {
                    if v, ok := intValue(x.Args[0]); ok && v == 42 { seed42++ }
                }
                if sel.Sel.Name == "Factorize" && len(x.Args) == 1 {
                    if target != nil { panic("multiple Cholesky Factorize calls") }
                    target = x
                }
            }
        case *ast.ForStmt:
            if b, ok := x.Cond.(*ast.BinaryExpr); ok && b.Op == token.LSS {
                if v, ok := intValue(b.Y); ok && v == 100000 { loops100000++ }
            }
        }
        return true
    })
    if seed42 != 1 { panic("the program must retain exactly one rand.NewSource(42) call") }
    if loops100000 != 1 { panic("the program must retain the 100000-sample loop") }
    if target == nil { panic("missing Cholesky Factorize call") }
    sel := target.Fun.(*ast.SelectorExpr)
    recv := text(fset, sel.X)
    arg := text(fset, target.Args[0])
    replacement := fmt.Sprintf(`func() bool {
        __verifiedCov := %s
        if __verifiedCov.SymmetricDim() != 3 { panic("covariance dimension changed") }
        __expected := [][]float64{
            {1.0001, 0.9999999, 0.5},
            {0.9999999, 1.0001, 0.5},
            {0.5, 0.5, 1.0001},
        }
        for __i := 0; __i < 3; __i++ {
            for __j := 0; __j < 3; __j++ {
                __d := __verifiedCov.At(__i, __j) - __expected[__i][__j]
                if __d < -1e-12 || __d > 1e-12 {
                    panic("cov must equal the original covariance with exactly 1e-4 added to every diagonal")
                }
            }
        }
        return %s.Factorize(__verifiedCov)
    }()`, arg, recv)
    start := fset.Position(target.Pos()).Offset
    end := fset.Position(target.End()).Offset
    out := append([]byte{}, src[:start]...)
    out = append(out, []byte(replacement)...)
    out = append(out, src[end:]...)
    if err := os.WriteFile(os.Args[2], out, 0644); err != nil { panic(err) }
}
'''
    checker_go = "/tmp/rewrite_check.go"
    checker_bin = "/tmp/rewrite_check"
    with open(checker_go, "w") as f:
        f.write(checker_source)
    run(["go", "build", "-o", checker_bin, checker_go])

    with tempfile.TemporaryDirectory() as instrumented_dir:
        copy_module_files(instrumented_dir)
        instrumented_go = os.path.join(instrumented_dir, "generate.go")
        run([checker_bin, "/home/user/generate.go", instrumented_go])

        # Execute the submitted artifact itself and require it to regenerate the
        # independently computed trace without panicking.
        os.remove("/home/user/trace.txt")
        run(["go", "run", "/home/user/generate.go"], cwd="/home/user")
        assert os.path.isfile("/home/user/trace.txt"), "generate.go did not create trace.txt"
        with open("/home/user/trace.txt") as f:
            actual = f.read().strip()
        assert actual == expected, f"generate.go produced {actual!r}, expected {expected!r}"

        # Execute the instrumented copy to prove the exact required covariance
        # reaches Cholesky factorization, including all three diagonal entries.
        os.remove("/home/user/trace.txt")
        run(["go", "run", "."], cwd=instrumented_dir)
        assert os.path.isfile("/home/user/trace.txt"), "instrumented program did not create trace.txt"
        with open("/home/user/trace.txt") as f:
            checked_actual = f.read().strip()
        assert checked_actual == expected, (
            f"instrumented program produced {checked_actual!r}, expected {expected!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
