#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')
RAW = HOME / 'raw_experiment.csv'
PIPELINE = HOME / 'pipeline'
ARTIFACTS = HOME / 'artifacts'
SCRIPT = HOME / 'run_pipeline.sh'


def run_pipeline(input_bytes):
    RAW.write_bytes(input_bytes)
    if ARTIFACTS.exists():
        shutil.rmtree(ARTIFACTS)

    result = subprocess.run(
        ['bash', str(SCRIPT)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, 'run_pipeline.sh failed:\n' + result.stdout
    assert RAW.read_bytes() == input_bytes, 'The pipeline modified raw_experiment.csv.'
    assert (ARTIFACTS / 'cleaned_data.csv').is_file(), 'cleaned_data.csv is missing.'
    assert (ARTIFACTS / 'metrics.json').is_file(), 'metrics.json is missing.'


def expected_cleaned(raw_path):
    with open(raw_path, newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['ID', 'X1', 'X2', 'Y'], 'Raw CSV has an unexpected header.'

    complete = [row for row in rows[1:] if len(row) == 4 and all(v.strip() for v in row)]
    ys = [float(row[3]) for row in complete]
    mu = sum(ys) / len(ys)
    std = math.sqrt(sum((y - mu) ** 2 for y in ys) / len(ys))
    cleaned = [row for row in complete if abs(float(row[3]) - mu) / std <= 2.0]
    return rows[0], cleaned


def read_and_check_outputs(raw_path):
    expected_header, expected_rows = expected_cleaned(raw_path)

    with open(ARTIFACTS / 'cleaned_data.csv', newline='') as f:
        produced = list(csv.reader(f))
    assert produced, 'cleaned_data.csv is empty.'
    assert produced[0] == expected_header, 'cleaned_data.csv has the wrong header.'
    assert produced[1:] == expected_rows, 'cleaned_data.csv does not contain the correctly filtered rows.'

    try:
        with open(ARTIFACTS / 'metrics.json') as f:
            metrics = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Could not parse metrics.json as valid JSON: {exc}')

    for key in ('cleaned_row_count', 'beta1_estimate', 'beta1_ci_lower', 'beta1_ci_upper'):
        assert key in metrics, f"Missing '{key}' in metrics.json."
    assert metrics['cleaned_row_count'] == len(expected_rows), 'cleaned_row_count does not match cleaned_data.csv.'
    for key in ('beta1_estimate', 'beta1_ci_lower', 'beta1_ci_upper'):
        value = metrics[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f'{key} must be numeric.'
        assert math.isfinite(value), f'{key} must be finite.'
    return metrics


def make_dynamic_csv(case_number):
    rng = secrets.SystemRandom()
    rows = [['ID', 'X1', 'X2', 'Y']]
    for i in range(1, 58 + case_number):
        x1 = rng.uniform(-8.0, 13.0)
        x2 = rng.uniform(-6.0, 11.0)
        noise = rng.uniform(-0.7, 0.7)
        y = (4.0 + case_number) + (2.2 + 0.35 * case_number) * x1 - 1.6 * x2 + noise
        rows.append([str(i), format(x1, '.12g'), format(x2, '.12g'), format(y, '.12g')])

    rows[5][3] = ''
    rows[12][1] = ''
    rows[21][2] = ''
    rows[30][3] = format(250.0 + rng.uniform(0, 20), '.12g')
    rows[42][3] = format(-230.0 - rng.uniform(0, 20), '.12g')

    out = []
    for row in rows:
        out.append(','.join(row))
    return ('\n'.join(out) + '\n').encode()


def build_oracle(path):
    source = r'''
package main

import (
    "encoding/csv"
    "encoding/json"
    "fmt"
    "math"
    "math/rand"
    "os"
    "sort"
    "strconv"
    "strings"
)

type Row struct { x1, x2, y float64 }

func solve(rows []Row) [3]float64 {
    var a [3][4]float64
    for _, r := range rows {
        x := [3]float64{1, r.x1, r.x2}
        for i := 0; i < 3; i++ {
            for j := 0; j < 3; j++ { a[i][j] += x[i] * x[j] }
            a[i][3] += x[i] * r.y
        }
    }
    for col := 0; col < 3; col++ {
        pivot := col
        for i := col + 1; i < 3; i++ {
            if math.Abs(a[i][col]) > math.Abs(a[pivot][col]) { pivot = i }
        }
        a[col], a[pivot] = a[pivot], a[col]
        d := a[col][col]
        if math.Abs(d) < 1e-12 { panic("singular regression") }
        for j := col; j < 4; j++ { a[col][j] /= d }
        for i := 0; i < 3; i++ {
            if i == col { continue }
            f := a[i][col]
            for j := col; j < 4; j++ { a[i][j] -= f * a[col][j] }
        }
    }
    return [3]float64{a[0][3], a[1][3], a[2][3]}
}

func round4(v float64) float64 { return math.Round(v * 10000) / 10000 }

func main() {
    f, err := os.Open(os.Args[1]); if err != nil { panic(err) }
    records, err := csv.NewReader(f).ReadAll(); if err != nil { panic(err) }
    f.Close()
    complete := make([]Row, 0)
    for _, rec := range records[1:] {
        if len(rec) != 4 { continue }
        missing := false
        for _, v := range rec { if strings.TrimSpace(v) == "" { missing = true } }
        if missing { continue }
        x1, e1 := strconv.ParseFloat(rec[1], 64)
        x2, e2 := strconv.ParseFloat(rec[2], 64)
        y, e3 := strconv.ParseFloat(rec[3], 64)
        if e1 != nil || e2 != nil || e3 != nil { panic("bad number") }
        complete = append(complete, Row{x1, x2, y})
    }
    mean := 0.0
    for _, r := range complete { mean += r.y }
    mean /= float64(len(complete))
    variance := 0.0
    for _, r := range complete { d := r.y - mean; variance += d*d }
    std := math.Sqrt(variance / float64(len(complete)))
    clean := make([]Row, 0)
    for _, r := range complete {
        if math.Abs(r.y-mean)/std <= 2.0 { clean = append(clean, r) }
    }
    beta := solve(clean)
    rng := rand.New(rand.NewSource(42))
    estimates := make([]float64, 1000)
    sample := make([]Row, len(clean))
    for b := 0; b < 1000; b++ {
        for i := range sample { sample[i] = clean[rng.Intn(len(clean))] }
        estimates[b] = solve(sample)[1]
    }
    sort.Float64s(estimates)
    result := map[string]interface{}{
        "cleaned_row_count": len(clean),
        "beta1_estimate": round4(beta[1]),
        "beta1_ci_lower": round4(estimates[25]),
        "beta1_ci_upper": round4(estimates[975]),
    }
    enc, _ := json.Marshal(result)
    fmt.Println(string(enc))
}
'''
    src = path.with_suffix('.go')
    src.write_text(source)
    result = subprocess.run(['go', 'build', '-o', str(path), str(src)], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=120)
    assert result.returncode == 0, 'Could not build verifier oracle:\n' + result.stdout
    src.unlink()


def test_complete_pipeline():
    assert RAW.is_file(), f'{RAW} is missing.'
    original_raw = RAW.read_bytes()
    case_dir = Path(tempfile.mkdtemp(prefix='pipeline-cases-'))

    try:
        assert SCRIPT.is_file(), 'The required /home/user/run_pipeline.sh is missing.'
        assert (PIPELINE / 'main.go').is_file(), 'The required /home/user/pipeline/main.go is missing.'

        script_text = SCRIPT.read_text(errors='replace')
        assert re.search(r'\bgo\s+build\b', script_text), 'run_pipeline.sh must build the Go executable.'
        assert re.search(r'\bgo\s+(?:mod\s+(?:init|tidy|download)|get)\b', script_text), \
            'run_pipeline.sh must initialize or download Go module dependencies.'

        main_text = (PIPELINE / 'main.go').read_text(errors='replace')
        assert 'gonum.org/v1/gonum/mat' in main_text, 'main.go must use gonum/mat for matrix operations.'
        assert re.search(r'rand\.New\s*\(\s*rand\.NewSource\s*\(\s*42\s*\)\s*\)', main_text), \
            'main.go must initialize the required reproducible RNG.'
        assert re.search(r'\.Intn\s*\(', main_text), 'main.go must sample bootstrap row indices with Intn.'

        saved_cases = []

        # Execute the submitted pipeline on the original dataset before checking artifacts.
        run_pipeline(original_raw)
        go_mod = PIPELINE / 'go.mod'
        assert go_mod.is_file(), 'The Go module file /home/user/pipeline/go.mod is missing.'
        assert re.search(r'(?m)^\s*module\s+mlops-pipeline\s*$', go_mod.read_text(errors='replace')), \
            'The Go module must be named mlops-pipeline.'

        original_path = case_dir / 'original.csv'
        original_path.write_bytes(original_raw)
        original_metrics = read_and_check_outputs(original_path)

        # Preserve the original verifier's fixed-dataset assertions.
        assert original_metrics['cleaned_row_count'] == 94, \
            f"Expected cleaned_row_count to be 94, got {original_metrics['cleaned_row_count']}."
        tolerance = 0.005
        assert abs(original_metrics['beta1_estimate'] - 5.4850) <= tolerance
        assert abs(original_metrics['beta1_ci_lower'] - 5.3780) <= tolerance
        assert abs(original_metrics['beta1_ci_upper'] - 5.6020) <= tolerance
        saved_cases.append((original_path, original_metrics))

        # Exercise the actual executable pipeline on unpredictable datasets.
        for number in (1, 2):
            raw_bytes = make_dynamic_csv(number)
            case_path = case_dir / f'dynamic-{number}.csv'
            case_path.write_bytes(raw_bytes)
            run_pipeline(raw_bytes)
            metrics = read_and_check_outputs(case_path)
            saved_cases.append((case_path, metrics))

        # Build the independent Go oracle only after all submitted executions are complete.
        oracle = case_dir / 'oracle'
        build_oracle(oracle)
        for case_path, actual in saved_cases:
            result = subprocess.run([str(oracle), str(case_path)], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, timeout=60)
            assert result.returncode == 0, 'Verifier oracle failed:\n' + result.stdout
            expected = json.loads(result.stdout)
            assert actual['cleaned_row_count'] == expected['cleaned_row_count']
            for key in ('beta1_estimate', 'beta1_ci_lower', 'beta1_ci_upper'):
                assert abs(actual[key] - expected[key]) <= 0.00005, \
                    f'{key} is incorrect for {case_path.name}: expected {expected[key]}, got {actual[key]}'
    finally:
        RAW.write_bytes(original_raw)
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
