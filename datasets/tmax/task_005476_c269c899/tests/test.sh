#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import re
import subprocess
from pathlib import Path

import pytest

EXPECTED = [
    [2.0, 3.5, 5.5],
    [2.1, 3.4, 5.5],
    [1.9, 3.6, 5.5],
    [2.2, 3.3, 5.5],
    [2.0, 3.5, 5.5],
    [1.8, 3.7, 5.5],
    [2.3, 3.2, 5.5],
    [1.9, 3.5, 5.4],
    [2.1, 3.6, 5.7],
    [2.0, 3.4, 5.4],
]
RAW_EXPECTED = [
    [1001, 2.0, 3.5, 5.5],
    [1002, 2.1, 3.4, 5.5],
    [1003, 1.9, 3.6, 5.5],
    [1004, 2.2, 3.3, 5.5],
    [1005, 2.0, 3.5, 5.5],
    [1006, 1.8, 3.7, 5.5],
    [1007, 2.3, 3.2, 5.5],
    [1008, 1.9, 3.5, 5.4],
    [1009, 2.1, 3.6, 5.7],
    [1010, 2.0, 3.4, 5.4],
]
GO = '/usr/local/go/bin/go'
REBUILT = '/tmp/rebuilt-sim-tool'
ORACLE = '/tmp/verifier-oracle'


def read_processed():
    path = '/home/user/processed.csv'
    assert os.path.isfile(path), f'File not found: {path}'
    with open(path, newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) == 10, f'Expected 10 lines in {path}, got {len(rows)}'
    assert all(len(row) == 3 for row in rows), 'Every processed row must have exactly 3 columns'
    try:
        numeric = [[float(value) for value in row] for row in rows]
    except ValueError as exc:
        pytest.fail(f'processed.csv contains a non-numeric value: {exc}')
    return numeric


def run_number(binary, n):
    result = subprocess.run(
        [binary, '-n', str(n)], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'{binary} failed for n={n}: stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    output = result.stdout.strip()
    assert output and len(output.splitlines()) == 1, f'Expected one numeric output line, got {output!r}'
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f'Output for n={n} is not a number: {output!r}')
    assert math.isfinite(value), f'Output for n={n} is not finite: {output!r}'
    return value


def build_rebuilt_source():
    result = subprocess.run(
        [GO, 'build', '-o', REBUILT, 'main.go'],
        cwd='/home/user/sim', capture_output=True, text=True, timeout=120
    assert result.returncode == 0, f'main.go does not compile: {result.stdout}\n{result.stderr}'
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def build_oracle():
    module_dirs = sorted(glob.glob('/root/go/pkg/mod/gonum.org/v1/gonum@v*'))
    assert module_dirs, 'The verifier could not locate the installed gonum module'
    version = os.path.basename(module_dirs[-1]).split('@', 1)[1]
    oracle_dir = Path('/tmp/verifier-oracle-module')
    oracle_dir.mkdir(exist_ok=True)
    (oracle_dir / 'go.mod').write_text(
        f'module verifieroracle\n\ngo 1.21\n\nrequire gonum.org/v1/gonum {version}\n'
    )
    (oracle_dir / 'main.go').write_text(r'''package main

import (
    "encoding/csv"
    "flag"
    "fmt"
    "log"
    "math/rand"
    "os"
    "strconv"

    "gonum.org/v1/gonum/mat"
    "gonum.org/v1/gonum/stat"
)

func main() {
    n := flag.Int("n", 1000, "number of samples")
    flag.Parse()
    f, err := os.Open("/tmp/verifier_processed.csv")
    if err != nil { log.Fatal(err) }
    defer f.Close()
    records, err := csv.NewReader(f).ReadAll()
    if err != nil { log.Fatal(err) }
    data := make([]float64, len(records)*3)
    for i, row := range records {
        for j, text := range row {
            value, err := strconv.ParseFloat(text, 64)
            if err != nil { log.Fatal(err) }
            data[i*3+j] = value
        }
    }
    x := mat.NewDense(len(records), 3, data)
    cov := mat.NewSymDense(3, nil)
    stat.CovarianceMatrix(cov, x, nil)
    for i := 0; i < 3; i++ {
        cov.SetSym(i, i, cov.At(i, i)+1e-3)
    }
    var chol mat.Cholesky
    if !chol.Factorize(cov) { log.Fatal("oracle Cholesky failure") }
    var lower mat.Dense
    chol.LTo(&lower)
    rnd := rand.New(rand.NewSource(42))
    sum := 0.0
    for i := 0; i < *n; i++ {
        z := mat.NewVecDense(3, []float64{rnd.NormFloat64(), rnd.NormFloat64(), rnd.NormFloat64()})
        sample := mat.NewVecDense(3, nil)
        sample.MulVec(&lower, z)
        sum += sample.AtVec(2) + 5.5
    }
    fmt.Printf("%f\n", sum/float64(*n))
}
''')
    env = os.environ.copy()
    env.update({'GOPROXY': 'off', 'GOSUMDB': 'off'})
    result = subprocess.run(
        [GO, 'build', '-o', ORACLE, '.'], cwd=oracle_dir,
        env=env, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f'Failed to build verifier oracle: {result.stdout}\n{result.stderr}'


def assert_matches_oracle(binary, n):
    actual = run_number(binary, n)
    expected = run_number(ORACLE, n)
    assert abs(actual - expected) <= 5e-7, (
        f'For n={n}, {binary} produced {actual}, but the simulation with an exact 1e-3 '
        f'diagonal ridge produces {expected}'
    )
    return actual


def test_processed_csv():
    raw_path = '/home/user/raw_data.txt'
    assert os.path.isfile(raw_path), f'File not found: {raw_path}'
    with open(raw_path) as f:
        raw = [[float(value) for value in line.split()] for line in f if line.strip()]
    assert raw == [[float(v) for v in row] for row in RAW_EXPECTED], 'raw_data.txt was altered'

    numeric = read_processed()
    assert numeric == EXPECTED, 'processed.csv must contain every raw row with only Timestamp removed'
    # Preserve the original sampled first-row assertions explicitly.
    assert numeric[0][0] == 2.0
    assert numeric[0][1] == 3.5
    assert numeric[0][2] == 5.5

    with open('/tmp/verifier_processed.csv', 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerows(EXPECTED)


def test_main_go_modified():
    go_file = '/home/user/sim/main.go'
    assert os.path.isfile(go_file), f'File not found: {go_file}'
    content = Path(go_file).read_text()

    has_penalty = '1e-3' in content or '0.001' in content or '1E-3' in content
    assert has_penalty, 'Could not find the ridge penalty (1e-3 or 0.001) in main.go'

    covariance_pos = content.find('stat.CovarianceMatrix')
    factorize_pos = content.find('Factorize', covariance_pos + 1)
    assert covariance_pos >= 0 and factorize_pos > covariance_pos, 'Missing covariance calculation or Cholesky factorization'
    ridge_region = content[covariance_pos:factorize_pos]
    assert re.search(r'(?<![\w.])(?:1e-3|1E-3|0\.001)(?![\w.])', ridge_region), (
        'The exact 1e-3 ridge must be applied after covariance calculation and before Cholesky factorization'
    )
    assert os.path.isfile('/home/user/sim/go.mod'), 'Go module was not initialized'
    build_rebuilt_source()


def test_sim_tool_compiled():
    bin_path = '/home/user/sim/sim_tool'
    assert os.path.isfile(bin_path), f'Compiled binary not found: {bin_path}'
    assert os.access(bin_path, os.X_OK), f'Binary is not executable: {bin_path}'
    with open(bin_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'sim_tool must be a compiled executable, not a script'


def test_simulation_and_convergence_result():
    assert read_processed() == EXPECTED
    Path('/tmp/verifier_processed.csv').write_text(
        ''.join(','.join(str(v) for v in row) + '\n' for row in EXPECTED)
    )
    build_rebuilt_source()
    build_oracle()

    submitted = '/home/user/sim/sim_tool'
    for n in (1, 2, 7, 31, 137, 1000, 2345, 7777):
        assert_matches_oracle(REBUILT, n)
        submitted_value = assert_matches_oracle(submitted, n)
        rebuilt_value = run_number(REBUILT, n)
        assert abs(submitted_value - rebuilt_value) <= 5e-7, (
            f'The submitted sim_tool does not match the compiled main.go for n={n}'
        )

    result_path = '/home/user/convergence_result.txt'
    assert os.path.isfile(result_path), f'File not found: {result_path}'
    content = Path(result_path).read_text().strip()
    assert content.isdigit(), f'Content of {result_path} is not an integer: {content}'
    n = int(content)
    assert n >= 1000, f'n should be at least 1000, got {n}'
    assert n % 1000 == 0, f'n should be a multiple of 1000, got {n}'

    expected_n = None
    for candidate_n in range(1000, 2000001, 1000):
        if abs(run_number(ORACLE, candidate_n) - 5.5) < 0.02:
            expected_n = candidate_n
            break
    assert expected_n is not None, 'No convergence point found within verifier safety bound'
    assert n == expected_n, f'Expected the smallest converged n to be {expected_n}, got {n}'

    mean_n = run_number(submitted, n)
    diff_n = abs(mean_n - 5.5)
    assert diff_n < 0.02, f'For n={n}, difference {diff_n} is not strictly less than 0.02'
    if n > 1000:
        prev_n = n - 1000
        mean_prev = run_number(submitted, prev_n)
        diff_prev = abs(mean_prev - 5.5)
        assert diff_prev >= 0.02, (
            f'For n={prev_n}, difference {diff_prev} is already < 0.02, so {n} is not the smallest.'
        )

    assert read_processed() == EXPECTED, 'The simulation modified processed.csv during verification'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
