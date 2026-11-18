#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import math
import os
import subprocess
import tempfile

EXPECTED_RESULTS = """data_00.csv: STABLE 43
data_01.csv: STABLE 33
data_02.csv: STABLE 19
data_03.csv: SINGULAR 25
data_04.csv: STABLE 25
data_05.csv: STABLE 27
data_06.csv: STABLE 15
data_07.csv: SINGULAR 15
data_08.csv: STABLE 28
data_09.csv: STABLE 26
data_10.csv: STABLE 13
data_11.csv: STABLE 28
data_12.csv: STABLE 7
data_13.csv: STABLE 26
data_14.csv: SINGULAR 44
data_15.csv: STABLE 28
data_16.csv: STABLE 34
data_17.csv: STABLE 7
data_18.csv: SINGULAR 26
data_19.csv: STABLE 22"""

GO_FILE = '/home/user/analyze.go'
RESULTS_FILE = '/home/user/results.txt'
BINARY = '/tmp/analyzer_submission'


def test_analyze_go_exists_and_uses_goroutines():
    go_file = '/home/user/analyze.go'
    assert os.path.isfile(go_file), f"Expected Go source file at {go_file} is missing."

    with open(go_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original check.
    assert "go " in content, "The Go program must use goroutines (could not find 'go ' keyword in analyze.go)."

    # Verify that the token is an actual Go statement rather than a comment/string.
    checker_source = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, parser.AllErrors)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(2)
    }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            found = true
        }
        return true
    })
    if !found {
        fmt.Fprintln(os.Stderr, "no GoStmt found")
        os.Exit(1)
    }
}
'''
    checker_go = '/tmp/check_goroutine_ast.go'
    checker_bin = '/tmp/check_goroutine_ast'
    with open(checker_go, 'w', encoding='utf-8') as f:
        f.write(checker_source)
    build = subprocess.run(
        ['go', 'build', '-o', checker_bin, checker_go],
        text=True, capture_output=True, timeout=60
    )
    assert build.returncode == 0, f"Could not build Go AST checker: {build.stderr}"
    checked = subprocess.run(
        [checker_bin, go_file], text=True, capture_output=True, timeout=10
    )
    assert checked.returncode == 0, (
        "analyze.go must contain a real goroutine statement; a comment or string is insufficient. "
        + checked.stderr
    )


def test_results_txt_matches_expected():
    results_file = '/home/user/results.txt'
    assert os.path.isfile(results_file), f"Expected results file at {results_file} is missing."

    with open(results_file, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_lines = [line.strip() for line in EXPECTED_RESULTS.strip().split('\n') if line.strip()]
    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in results.txt, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch on line {i+1}:\nExpected: {expected}\nGot: {actual}"


def read_nonempty_result_lines():
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} was not created."
    with open(RESULTS_FILE, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def run_analyzer(data_dir):
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    run = subprocess.run(
        [BINARY, data_dir], cwd='/home/user', text=True,
        capture_output=True, timeout=30
    )
    assert run.returncode == 0, (
        f"Compiled analyzer failed for {data_dir}.\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
    )
    return read_nonempty_result_lines()


def test_program_compiles_and_reproduces_fixture_results():
    build = subprocess.run(
        ['go', 'build', '-o', BINARY, GO_FILE], cwd='/home/user',
        text=True, capture_output=True, timeout=120
    )
    assert build.returncode == 0, f"analyze.go did not compile:\n{build.stdout}\n{build.stderr}"

    actual_lines = run_analyzer('/home/user/sensor_data')
    expected_lines = [line.strip() for line in EXPECTED_RESULTS.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        "Running analyze.go on the supplied sensor data did not reproduce the required results.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )


def dft_expected(filename, values):
    n = len(values)
    assert n == 256
    magnitudes = []
    for k in range(128):
        component = sum(
            value * cmath.exp(-2j * math.pi * k * index / n)
            for index, value in enumerate(values)
        )
        magnitudes.append(abs(component))
    dominant = max(range(1, 128), key=lambda k: magnitudes[k])
    flag = 'SINGULAR' if magnitudes[0] > 50.0 * magnitudes[dominant] else 'STABLE'
    return f'{filename}: {flag} {dominant}'


def write_case(directory, filename, offset, components):
    raw_values = []
    for t in range(256):
        value = offset
        for frequency, amplitude, phase in components:
            value += amplitude * math.sin(2.0 * math.pi * frequency * t / 256.0 + phase)
        # Expected values are derived from precisely the decimal values placed in the CSV.
        raw_values.append(float(f'{value:.4f}'))

    path = os.path.join(directory, filename)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('timestamp,value\n')
        f.write('# generated verifier case\n\n')
        for index, value in enumerate(raw_values):
            if index in (17, 103, 211):
                f.write('# an interspersed comment\n\n')
            f.write(f'{index},{value:.4f}\n')
    return dft_expected(filename, raw_values)


def test_program_analyzes_unseen_csv_inputs():
    cases = [
        ('omega.csv', 0.25, [(11, 7.0, 0.17), (49, 0.8, 0.4)]),
        ('alpha.csv', 180.0, [(37, 2.5, 0.31), (8, 0.2, 0.0)]),
        ('middle.csv', -1.75, [(63, 5.0, 0.73), (22, 1.1, 0.2)]),
        ('beta.csv', -220.0, [(19, 3.0, 0.55), (71, 0.4, 0.1)]),
    ]
    with tempfile.TemporaryDirectory(prefix='sensor_verifier_') as data_dir:
        expected = [write_case(data_dir, *case) for case in cases]
        expected.sort(key=lambda line: line.split(':', 1)[0])
        actual = run_analyzer(data_dir)
        assert actual == expected, (
            "analyze.go failed on verifier-generated CSV data. This test requires computing "
            "the FFT results rather than hardcoding the supplied fixture.\n"
            f"Expected: {expected}\nGot: {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
