#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import pathlib
import random
import re
import shutil
import subprocess
import tempfile

import numpy as np
import pytest

PROJECT_DIR = pathlib.Path('/home/user/matrix_prep')
DATA_DIR = pathlib.Path('/home/user/data')
REPORT_FILE = PROJECT_DIR / 'report.csv'


def run_submission():
    if REPORT_FILE.exists():
        REPORT_FILE.unlink()
    result = subprocess.run(
        ['go', 'run', '.'],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        env={**os.environ, 'GOWORK': 'off'},
    )
    assert result.returncode == 0, f"Go program failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert REPORT_FILE.is_file(), 'Running the Go program did not create report.csv'


def read_report(path=REPORT_FILE):
    with open(path, newline='') as f:
        return list(csv.reader(f))


def oracle_report():
    version_result = subprocess.run(
        ['go', 'list', '-m', '-f', '{{.Version}}', 'gonum.org/v1/gonum'],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        env={**os.environ, 'GOWORK': 'off'},
    )
    assert version_result.returncode == 0, f"Cannot resolve Gonum dependency: {version_result.stderr}"
    version = version_result.stdout.strip()
    assert re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:[-+].*)?', version), f'Invalid Gonum module version: {version!r}'

    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        (td / 'go.mod').write_text(
            f'module verifieroracle\n\ngo 1.19\n\nrequire gonum.org/v1/gonum {version}\n'
        )
        (td / 'main.go').write_text(r'''package main

import (
    "encoding/csv"
    "fmt"
    "math"
    "os"
    "strconv"

    "gonum.org/v1/gonum/mat"
)

func main() {
    fmt.Println("matrix_id,status,error")
    for id := 0; id < 10; id++ {
        f, err := os.Open(fmt.Sprintf("/home/user/data/matrix_%d.csv", id))
        if err != nil { panic(err) }
        records, err := csv.NewReader(f).ReadAll()
        f.Close()
        if err != nil || len(records) != 3 { panic("invalid matrix CSV") }
        values := make([]float64, 0, 9)
        for _, row := range records {
            if len(row) != 3 { panic("invalid matrix row") }
            for _, field := range row {
                value, err := strconv.ParseFloat(field, 64)
                if err != nil { panic(err) }
                values = append(values, value)
            }
        }
        a := mat.NewSymDense(3, values)
        var chol mat.Cholesky
        if !chol.Factorize(a) {
            fmt.Printf("%d,failed,-1.000000e+00\n", id)
            continue
        }
        var l mat.TriDense
        chol.LTo(&l)
        var reconstructed mat.Dense
        reconstructed.Mul(&l, l.T())
        maxError := 0.0
        for i := 0; i < 3; i++ {
            for j := 0; j < 3; j++ {
                difference := math.Abs(a.At(i, j) - reconstructed.At(i, j))
                if difference > maxError { maxError = difference }
            }
        }
        status := "stable"
        if maxError > 1e-8 { status = "unstable" }
        fmt.Printf("%d,%s,%.6e\n", id, status, maxError)
    }
}
''')
        result = subprocess.run(
            ['go', 'run', '.'],
            cwd=td,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            env={**os.environ, 'GOWORK': 'off'},
        )
        assert result.returncode == 0, f"Oracle computation failed: {result.stderr}"
        return list(csv.reader(result.stdout.splitlines()))


def write_hidden_matrices():
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'big'))
    kinds = ['normal'] * 4 + ['indefinite'] * 3 + ['large'] * 3
    random.SystemRandom().shuffle(kinds)

    for matrix_id, kind in enumerate(kinds):
        q, _ = np.linalg.qr(rng.normal(size=(3, 3)))
        if kind == 'normal':
            eigenvalues = rng.uniform(0.5, 8.0, size=3)
        elif kind == 'indefinite':
            eigenvalues = np.array([-rng.uniform(0.5, 3.0), rng.uniform(1.0, 5.0), rng.uniform(5.0, 10.0)])
        else:
            scale = rng.uniform(1e14, 1e16)
            eigenvalues = scale * np.array([1.0, 2.5, 7.0])
        matrix = q @ np.diag(eigenvalues) @ q.T
        matrix = (matrix + matrix.T) / 2
        np.savetxt(DATA_DIR / f'matrix_{matrix_id}.csv', matrix, delimiter=',', fmt='%.17e')


def test_go_artifacts_and_computation():
    go_mod = PROJECT_DIR / 'go.mod'
    assert go_mod.is_file(), 'go.mod is missing'
    mod_text = go_mod.read_text()
    assert re.search(r'(?m)^\s*module\s+matrixprep\s*$', mod_text), 'Go module must be named matrixprep'
    assert 'gonum.org/v1/gonum' in mod_text, 'go.mod must depend on Gonum'
    assert not re.search(r'(?m)^\s*replace\s+gonum.org/v1/gonum\b', mod_text), 'Gonum must not be replaced by a local implementation'

    go_files = list(PROJECT_DIR.glob('*.go'))
    assert go_files, 'No Go source files exist in the module directory'
    source = '\n'.join(path.read_text(errors='replace') for path in go_files)
    assert 'gonum.org/v1/gonum/mat' in source, 'Program does not import Gonum mat'
    assert 'NewSymDense' in source, 'Program does not construct a Gonum symmetric dense matrix'
    assert 'Cholesky' in source, 'Program does not perform a Gonum Cholesky factorization'

    originals = {path: path.read_bytes() for path in sorted(DATA_DIR.glob('matrix_*.csv'))}
    assert set(path.name for path in originals) == {f'matrix_{i}.csv' for i in range(10)}

    try:
        write_hidden_matrices()
        run_submission()
        assert read_report() == oracle_report(), 'Report does not match Cholesky results for verifier-generated matrices'
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
        run_submission()

    assert read_report() == oracle_report(), 'Report does not match recomputed Cholesky results for the supplied matrices'


def test_report_file_exists():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."


def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."

    with open(REPORT_FILE, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 11, f"Expected 11 rows (1 header + 10 data), found {len(rows)}"
    assert rows[0] == ['matrix_id', 'status', 'error'], f"Invalid header: {rows[0]}"

    expected_stable = {0, 3, 6, 9}
    expected_failed = {2, 5, 8}

    found_ids = set()

    for row in rows[1:]:
        assert len(row) == 3, f"Row does not have 3 columns: {row}"
        try:
            mid = int(row[0])
        except ValueError:
            pytest.fail(f"matrix_id must be an integer, got: {row[0]}")

        status = row[1]
        assert status in {'stable', 'unstable', 'failed'}, f"Invalid status: {status}"

        try:
            err = float(row[2])
        except ValueError:
            pytest.fail(f"error must be a float, got: {row[2]}")

        assert 'e' in row[2].lower(), f"error must be in scientific notation, got: {row[2]}"
        assert re.fullmatch(r'-?[0-9]\.[0-9]{6}e[+-][0-9]{2,}', row[2]), f"error must have 6 decimal places in scientific notation, got: {row[2]}"

        found_ids.add(mid)

        if mid in expected_stable:
            assert status == 'stable', f"Matrix {mid} should be stable, got {status}"
            assert 0 <= err <= 1e-8, f"Matrix {mid} has invalid error for stable status: {err}"

        if mid in expected_failed:
            assert status == 'failed', f"Matrix {mid} should be failed, got {status}"
            assert err == -1.0, f"Matrix {mid} error should be -1.0, got {err}"

        if status == 'failed':
            assert err == -1.0, f"Failed matrix {mid} error should be -1.0, got {err}"
        elif status == 'stable':
            assert 0 <= err <= 1e-8, f"Stable matrix {mid} has invalid error: {err}"
        elif status == 'unstable':
            assert err > 1e-8, f"Unstable matrix {mid} has invalid error: {err}"

    assert found_ids == set(range(10)), f"Missing or extra matrix IDs. Found: {found_ids}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
