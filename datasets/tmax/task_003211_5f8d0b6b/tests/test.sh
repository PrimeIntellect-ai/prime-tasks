#!/bin/bash
set -e
mkdir -p /logs/verifier

VERIFIER_TEST="/home/user/telemetry/zz_verifier_behavior_test.go"
cleanup() {
    rm -f "$VERIFIER_TEST"
}
trap cleanup EXIT

cat << 'GO_TEST_EOF' > "$VERIFIER_TEST"
package telemetry

import (
    "math"
    "testing"
)

func TestVerifierPointFieldsAreFloat64(t *testing.T) {
    var _ float64 = Point{}.Lat
    var _ float64 = Point{}.Lon
    var _ float64 = Point{}.Alt
}

func TestVerifierParseLineValidInput(t *testing.T) {
    p, err := ParseLine("2024-05-06T07:08:09Z,45.123456789,-90.987654321,123.456789")
    if err != nil {
        t.Fatalf("ParseLine rejected valid input: %v", err)
    }
    if p == nil {
        t.Fatal("ParseLine returned a nil point for valid input")
    }
    if p.Lat != 45.123456789 || p.Lon != -90.987654321 || p.Alt != 123.456789 {
        t.Fatalf("unexpected parsed point: %#v", p)
    }
}

func TestVerifierParseLineRejectsMalformedInput(t *testing.T) {
    cases := []string{
        "",
        "timestamp",
        "timestamp,1",
        "timestamp,1,2",
        "timestamp,bad,2,3",
        "timestamp,1,bad,3",
        "timestamp,1,2,bad",
    }
    for _, input := range cases {
        input := input
        t.Run(input, func(t *testing.T) {
            defer func() {
                if r := recover(); r != nil {
                    t.Fatalf("ParseLine panicked for %q: %v", input, r)
                }
            }()
            if _, err := ParseLine(input); err == nil {
                t.Fatalf("ParseLine(%q) returned no error", input)
            }
        })
    }
}

func TestVerifierDistanceUsesFloat64Values(t *testing.T) {
    cases := []struct {
        a, b Point
    }{
        {Point{Lat: 45.123456789, Lon: -90.123456789, Alt: 100.000000001}, Point{Lat: 45.123456700, Lon: -90.123456700, Alt: 100.0}},
        {Point{Lat: -12.345678901, Lon: 67.890123456, Alt: 0.000000123}, Point{Lat: -12.345678999, Lon: 67.890123400, Alt: -0.000000321}},
        {Point{Lat: 1.000000001, Lon: 2.000000002, Alt: 3.000000003}, Point{Lat: 1.0, Lon: 2.0, Alt: 3.0}},
    }
    for i, tc := range cases {
        dx := tc.a.Lat - tc.b.Lat
        dy := tc.a.Lon - tc.b.Lon
        dz := tc.a.Alt - tc.b.Alt
        want := math.Sqrt(dx*dx + dy*dy + dz*dz)
        got := Distance(&tc.a, &tc.b)
        if got != want {
            t.Fatalf("case %d: Distance returned %.17g, want %.17g", i, got, want)
        }
    }
}
GO_TEST_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import subprocess
import tempfile


def run(cmd, cwd=None, timeout=30):
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        assert False, f"Command not found: {cmd[0]}"
    assert result.returncode == 0, (
        f"Command failed: {' '.join(cmd)}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result


def run_verify_with_module(module_dir):
    shutil.copyfile("/home/user/verify.go", os.path.join(module_dir, "main.go"))
    result_file = "/home/user/distance_result.txt"
    if os.path.exists(result_file):
        os.remove(result_file)
    run(["go", "run", "."], cwd=module_dir, timeout=30)
    assert os.path.isfile(result_file), f"Expected result file {result_file} is missing."
    with open(result_file, "r") as f:
        return f.read().strip()


def test_distance_result_created_and_correct():
    verify_path = "/home/user/verify.go"
    assert os.path.isfile(verify_path), f"The script {verify_path} is missing."

    # First execute verify.go against an instrumented telemetry package. This
    # proves that it parses the required lines and writes Distance's result,
    # rather than merely hardcoding the known answer.
    with tempfile.TemporaryDirectory() as td:
        fake = os.path.join(td, "telemetry")
        os.mkdir(fake)
        with open(os.path.join(td, "go.mod"), "w") as f:
            f.write("module verifiermain\n\ngo 1.20\n\nrequire telemetry v0.0.0\nreplace telemetry => ./telemetry\n")
        with open(os.path.join(fake, "go.mod"), "w") as f:
            f.write("module telemetry\n\ngo 1.20\n")
        with open(os.path.join(fake, "telemetry.go"), "w") as f:
            f.write(r'''package telemetry

import "fmt"

type Point struct { id int }

func ParseLine(line string) (*Point, error) {
    switch line {
    case "2023-01-01T00:00:00Z,45.123456789,-90.123456789,100.0":
        return &Point{id: 1}, nil
    case "2023-01-01T00:00:01Z,45.123456700,-90.123456700,100.0":
        return &Point{id: 2}, nil
    default:
        return nil, fmt.Errorf("verify.go parsed an unexpected line: %q", line)
    }
}

func Distance(p1, p2 *Point) float64 {
    if p1 == nil || p2 == nil || p1.id != 1 || p2.id != 2 {
        panic("Distance was not called with points parsed from the required lines")
    }
    return 0.3141592653589793
}
''')
        content = run_verify_with_module(td)
        assert content == "0.3141592653589793", (
            "verify.go did not write the value returned by telemetry.Distance formatted with %v"
        )

    # Execute the submitted script against the real package and retain the
    # original result-file and precision assertion.
    with tempfile.TemporaryDirectory() as td:
        with open(os.path.join(td, "go.mod"), "w") as f:
            f.write("module verifiermain\n\ngo 1.20\n\nrequire telemetry v0.0.0\nreplace telemetry => /home/user/telemetry\n")
        content = run_verify_with_module(td)

    try:
        distance = float(content)
    except ValueError:
        assert False, f"Content of /home/user/distance_result.txt is not a valid float: {content}"

    expected_distance = math.sqrt(
        (45.123456789 - 45.123456700) ** 2
        + (-90.123456789 - -90.123456700) ** 2
        + (100.0 - 100.0) ** 2
    )
    assert math.isclose(distance, expected_distance, rel_tol=1e-5), (
        f"Distance {distance} does not match expected float64 precision distance ~{expected_distance}. "
        "Did you correctly update to float64?"
    )


def test_parser_uses_float64():
    parser_path = "/home/user/telemetry/parser.go"
    assert os.path.isfile(parser_path), f"File {parser_path} is missing."
    with open(parser_path, "r") as f:
        content = f.read()
    assert "float64" in content, "The parser.go file must use float64."
    assert "float32" not in content, "All instances of float32 should be removed from parser.go."


def test_fuzz_test_exists_and_targets_parse_line():
    test_path = "/home/user/telemetry/parser_test.go"
    assert os.path.isfile(test_path), f"Fuzz test file {test_path} is missing."
    with open(test_path, "r") as f:
        content = f.read()
    assert "FuzzParseLine" in content, "The FuzzParseLine function is missing in parser_test.go."

    analyzer = r'''package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/telemetry/parser_test.go", nil, 0)
    if err != nil { panic(err) }
    found := false
    for _, d := range f.Decls {
        fn, ok := d.(*ast.FuncDecl)
        if !ok || fn.Name.Name != "FuzzParseLine" || fn.Body == nil { continue }
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            call, ok := n.(*ast.CallExpr)
            if !ok { return true }
            sel, ok := call.Fun.(*ast.SelectorExpr)
            if !ok || sel.Sel.Name != "Fuzz" { return true }
            for _, arg := range call.Args {
                lit, ok := arg.(*ast.FuncLit)
                if !ok { continue }
                ast.Inspect(lit.Body, func(inner ast.Node) bool {
                    c, ok := inner.(*ast.CallExpr)
                    if !ok { return true }
                    id, ok := c.Fun.(*ast.Ident)
                    if ok && id.Name == "ParseLine" { found = true }
                    return true
                })
            }
            return true
        })
    }
    if !found {
        fmt.Fprintln(os.Stderr, "FuzzParseLine must call ParseLine from its fuzz callback")
        os.Exit(1)
    }
}
'''
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "check.go")
        with open(path, "w") as f:
            f.write(analyzer)
        run(["go", "run", path], timeout=30)


def test_go_test_passes():
    run(["go", "test"], cwd="/home/user/telemetry", timeout=30)


def test_fuzzer_runs_without_panicking():
    run(
        ["go", "test", "-run=^$", "-fuzz=^FuzzParseLine$", "-fuzztime=2s"],
        cwd="/home/user/telemetry",
        timeout=45,
    )


def test_verify_go_exists():
    verify_path = "/home/user/verify.go"
    assert os.path.isfile(verify_path), f"The script {verify_path} is missing."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
