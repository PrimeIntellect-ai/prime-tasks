#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import stat as pystat
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
RESULT = HOME / 'result.json'
SOURCE = HOME / 'bootstrapper.go'
ORACLE_DIR = Path('/tmp/trusted_bootstrap_oracle')
ORACLE_BIN = ORACLE_DIR / 'oracle'
SUBMITTED_BIN = Path('/tmp/submitted_bootstrapper')

ORACLE_SOURCE = r'''
package main

import (
    "encoding/csv"
    "encoding/json"
    "fmt"
    "math/rand"
    "os"
    "sort"
    "strconv"
    "strings"

    "gonum.org/v1/gonum/mat"
    "gonum.org/v1/gonum/stat"
)

type output struct {
    SuccessRate float64 `json:"success_rate"`
    CILower     float64 `json:"ci_lower"`
    CIUpper     float64 `json:"ci_upper"`
    RefInCI     bool    `json:"ref_in_ci"`
}

func readX(path string) (*mat.Dense, error) {
    f, err := os.Open(path)
    if err != nil { return nil, err }
    defer f.Close()
    records, err := csv.NewReader(f).ReadAll()
    if err != nil { return nil, err }
    if len(records) != 100 { return nil, fmt.Errorf("expected 100 X rows, got %d", len(records)) }
    data := make([]float64, 200)
    for i, row := range records {
        if len(row) != 2 { return nil, fmt.Errorf("expected 2 X columns") }
        for j := 0; j < 2; j++ {
            data[2*i+j], err = strconv.ParseFloat(strings.TrimSpace(row[j]), 64)
            if err != nil { return nil, err }
        }
    }
    return mat.NewDense(100, 2, data), nil
}

func readY(path string) (*mat.VecDense, error) {
    f, err := os.Open(path)
    if err != nil { return nil, err }
    defer f.Close()
    records, err := csv.NewReader(f).ReadAll()
    if err != nil { return nil, err }
    if len(records) != 100 { return nil, fmt.Errorf("expected 100 y rows, got %d", len(records)) }
    data := make([]float64, 100)
    for i, row := range records {
        if len(row) != 1 { return nil, fmt.Errorf("expected 1 y column") }
        data[i], err = strconv.ParseFloat(strings.TrimSpace(row[0]), 64)
        if err != nil { return nil, err }
    }
    return mat.NewVecDense(100, data), nil
}

func main() {
    X, err := readX("/home/user/X.csv")
    if err != nil { panic(err) }
    y, err := readY("/home/user/y.csv")
    if err != nil { panic(err) }

    rng := rand.New(rand.NewSource(42))
    values := make([]float64, 0, 1000)
    for i := 0; i < 1000; i++ {
        xbData := make([]float64, 200)
        ybData := make([]float64, 100)
        for j := 0; j < 100; j++ {
            idx := rng.Intn(100)
            xbData[2*j] = X.At(idx, 0)
            xbData[2*j+1] = X.At(idx, 1)
            ybData[j] = y.AtVec(idx)
        }
        xb := mat.NewDense(100, 2, xbData)
        yb := mat.NewVecDense(100, ybData)
        var w mat.VecDense
        if err := w.SolveVec(xb, yb); err != nil {
            continue
        }
        values = append(values, w.AtVec(0))
    }
    if len(values) == 0 { panic("no successful bootstrap solves") }
    sort.Float64s(values)
    lower := stat.Quantile(0.025, stat.Empirical, values, nil)
    upper := stat.Quantile(0.975, stat.Empirical, values, nil)
    refBytes, err := os.ReadFile("/home/user/ref_w0.txt")
    if err != nil { panic(err) }
    ref, err := strconv.ParseFloat(strings.TrimSpace(string(refBytes)), 64)
    if err != nil { panic(err) }
    result := output{
        SuccessRate: float64(len(values)) / 1000.0,
        CILower: lower,
        CIUpper: upper,
        RefInCI: lower <= ref && ref <= upper,
    }
    if err := json.NewEncoder(os.Stdout).Encode(result); err != nil { panic(err) }
}
'''


def clean_env():
    env = os.environ.copy()
    env['HOME'] = '/tmp/verifier-home'
    env['GOPATH'] = '/tmp/verifier-gopath'
    env['GOWORK'] = 'off'
    env['GOFLAGS'] = '-mod=mod'
    Path(env['HOME']).mkdir(parents=True, exist_ok=True)
    Path(env['GOPATH']).mkdir(parents=True, exist_ok=True)
    return env


def build_binaries():
    assert SOURCE.exists(), f"Missing file: {SOURCE}"
    mode = os.lstat(SOURCE).st_mode
    assert pystat.S_ISREG(mode), 'bootstrapper.go must be a regular file, not a symlink or directory'

    text = SOURCE.read_text(errors='replace')
    for required in ('gonum.org/v1/gonum/mat', 'gonum.org/v1/gonum/stat',
                     'SolveVec', 'stat.Quantile', 'rand.New', 'rand.NewSource(42)'):
        assert required in text, f"bootstrapper.go is missing required use of {required}"
    assert re.search(r'Intn\s*\(\s*100\s*\)', text), 'bootstrapper.go must sample rows with rng.Intn(100)'
    assert (HOME / 'go.mod').is_file(), 'Missing Go module file /home/user/go.mod'

    env = clean_env()
    subprocess.run(
        ['go', 'build', '-mod=mod', '-o', str(SUBMITTED_BIN), './bootstrapper.go'],
        cwd=HOME, env=env, check=True, timeout=180,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )

    if ORACLE_DIR.exists():
        shutil.rmtree(ORACLE_DIR)
    ORACLE_DIR.mkdir(parents=True)
    (ORACLE_DIR / 'go.mod').write_text(
        'module trustedbootstraporacle\n\ngo 1.19\n\nrequire gonum.org/v1/gonum v0.12.0\n'
    )
    (ORACLE_DIR / 'main.go').write_text(ORACLE_SOURCE)
    subprocess.run(
        ['go', 'build', '-mod=mod', '-o', str(ORACLE_BIN), '.'],
        cwd=ORACLE_DIR, env=env, check=True, timeout=180,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )


def run_oracle():
    proc = subprocess.run(
        [str(ORACLE_BIN)], cwd=HOME, check=True, timeout=120,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    return json.loads(proc.stdout)


def run_submission():
    if RESULT.exists():
        RESULT.unlink()
    subprocess.run(
        [str(SUBMITTED_BIN)], cwd=HOME, check=True, timeout=120,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert RESULT.is_file(), 'Executing bootstrapper.go did not create /home/user/result.json'
    with RESULT.open() as f:
        return json.load(f)


def assert_matches(actual, expected):
    assert set(actual) == {'success_rate', 'ci_lower', 'ci_upper', 'ref_in_ci'}
    assert actual['ref_in_ci'] is expected['ref_in_ci']
    for key in ('success_rate', 'ci_lower', 'ci_upper'):
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool)
        assert math.isfinite(actual[key])
        assert math.isclose(actual[key], expected[key], rel_tol=1e-10, abs_tol=1e-10), (
            f"{key} differs from the independently recomputed value: "
            f"got {actual[key]!r}, expected {expected[key]!r}"
        )


def write_generated_case(case):
    x_rows = []
    y_rows = []
    for i in range(100):
        t = i - 49.5
        if case == 1:
            x0 = math.sin(i * 0.173) + t * 0.009
            x1 = math.cos(i * 0.119) - t * 0.004
            y = 1.25 * x0 - 0.7 * x1 + 0.03 * math.sin(i * 0.47)
        else:
            x0 = math.cos(i * 0.071) + t * 0.012
            x1 = 0.45 * x0 + math.sin(i * 0.213)
            y = -2.3 * x0 + 0.35 * x1 + 0.02 * math.cos(i * 0.31)
        x_rows.append(f'{x0:.17g},{x1:.17g}\n')
        y_rows.append(f'{y:.17g}\n')
    (HOME / 'X.csv').write_text(''.join(x_rows))
    (HOME / 'y.csv').write_text(''.join(y_rows))
    (HOME / 'ref_w0.txt').write_text(('1.25\n' if case == 1 else '-2.3\n'))


def test_program_executes_and_matches_bootstrap_oracle():
    build_binaries()
    paths = [HOME / 'X.csv', HOME / 'y.csv', HOME / 'ref_w0.txt']
    originals = {p: p.read_bytes() for p in paths}
    try:
        expected = run_oracle()
        actual = run_submission()
        assert_matches(actual, expected)

        for case in (1, 2):
            write_generated_case(case)
            expected = run_oracle()
            actual = run_submission()
            assert_matches(actual, expected)
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
        if SUBMITTED_BIN.exists():
            try:
                run_submission()
            except Exception:
                if RESULT.exists():
                    RESULT.unlink()


def test_result_json_exists_and_valid():
    """Check that result.json exists and contains the correct structure."""
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"Missing file: {result_path}"

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("result.json is not a valid JSON file.")

    expected_keys = {"success_rate", "ci_lower", "ci_upper", "ref_in_ci"}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, f"Expected keys {expected_keys}, but got {actual_keys}"

    assert isinstance(data["success_rate"], (int, float)), "success_rate must be a number"
    assert 0.0 <= data["success_rate"] <= 1.0, "success_rate must be between 0.0 and 1.0"

    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a number"
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a number"
    assert data["ci_lower"] <= data["ci_upper"], "ci_lower must be less than or equal to ci_upper"

    assert isinstance(data["ref_in_ci"], bool), "ref_in_ci must be a boolean"


def test_result_values_plausible():
    """Check that the values in result.json are plausible for the given dataset."""
    result_path = "/home/user/result.json"
    if not os.path.isfile(result_path):
        pytest.skip("result.json not found")

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Invalid JSON")

    assert data["success_rate"] < 1.0, "Expected success_rate to be < 1.0 due to singular matrices in bootstrap samples"

    ref_w0 = 2.0
    expected_ref_in_ci = data["ci_lower"] <= ref_w0 <= data["ci_upper"]
    assert data["ref_in_ci"] == expected_ref_in_ci, (
        f"ref_in_ci is {data['ref_in_ci']}, but bounds are [{data['ci_lower']}, {data['ci_upper']}] "
        f"and ref_w0 is {ref_w0}"
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
