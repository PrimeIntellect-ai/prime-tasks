#!/bin/bash
mkdir -p /logs/verifier

cat << 'GO_EOF' > /home/user/physics/verifier_behavior_test.go
package physics

import (
    "math"
    "math/rand"
    "testing"
)

func TestVerifierCalculateCenterOfMassBehavior(t *testing.T) {
    fixed := []struct {
        positions []float64
        weights   []float64
        expected  float64
    }{
        {[]float64{1, 2, 3}, []float64{1, 1, 1}, 2},
        {[]float64{0, 10}, []float64{3, 1}, 2.5},
        {[]float64{-5, 5}, []float64{1, 2}, 5.0 / 3.0},
        {[]float64{12.5}, []float64{7.25}, 12.5},
        {[]float64{-9, 4, 17}, []float64{2, 5, 3}, 5.3},
    }

    for _, tc := range fixed {
        got, err := CalculateCenterOfMass(tc.positions, tc.weights)
        if err != nil {
            t.Fatalf("unexpected error for %v and %v: %v", tc.positions, tc.weights, err)
        }
        if math.Abs(got-tc.expected) > 1e-10*math.Max(1, math.Abs(tc.expected)) {
            t.Fatalf("CalculateCenterOfMass(%v, %v) = %v, want %v", tc.positions, tc.weights, got, tc.expected)
        }
    }

    rng := rand.New(rand.NewSource(918273))
    for trial := 0; trial < 100; trial++ {
        n := 1 + rng.Intn(8)
        positions := make([]float64, n)
        weights := make([]float64, n)
        weightedSum, totalWeight := 0.0, 0.0
        for i := range positions {
            positions[i] = rng.Float64()*200 - 100
            weights[i] = rng.Float64()*20 + 0.01
            weightedSum += positions[i] * weights[i]
            totalWeight += weights[i]
        }
        want := weightedSum / totalWeight
        got, err := CalculateCenterOfMass(positions, weights)
        if err != nil {
            t.Fatalf("unexpected error on randomized case: %v", err)
        }
        if math.Abs(got-want) > 1e-10*math.Max(1, math.Abs(want)) {
            t.Fatalf("randomized result %v, want %v", got, want)
        }
    }
}

func TestVerifierZeroWeightSum(t *testing.T) {
    got, err := CalculateCenterOfMass([]float64{3, 8, -2}, []float64{1, -2, 1})
    if got != 0.0 {
        t.Fatalf("zero-weight case returned %v, want 0", got)
    }
    if err == nil || err.Error() != "zero weight sum" {
        t.Fatalf("zero-weight case returned error %v, want exactly %q", err, "zero weight sum")
    }
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess

REPO = '/home/user/physics'


def run_go(*args, timeout=40):
    env = os.environ.copy()
    env['GOMAXPROCS'] = '2'
    proc = subprocess.run(
        ['go', *args], cwd=REPO, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout
    )
    assert proc.returncode == 0, 'Go command failed:\n' + proc.stdout
    return proc.stdout


def test_vectors_json_recovered():
    path = '/home/user/physics/vectors.json'
    assert os.path.isfile(path), f'{path} was not recovered.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{path} does not contain valid JSON.'

    assert isinstance(data, list), 'vectors.json should contain a list of test cases.'
    assert len(data) == 3, 'vectors.json should contain exactly 3 test cases.'
    assert data[0].get('expected') == 2.0, 'The recovered vectors.json content is incorrect.'
    assert data[1].get('expected') == 2.5, 'The recovered vectors.json content is incorrect.'
    expected = [
        {'positions': [1.0, 2.0, 3.0], 'weights': [1.0, 1.0, 1.0], 'expected': 2.0},
        {'positions': [0.0, 10.0], 'weights': [3.0, 1.0], 'expected': 2.5},
        {'positions': [-5.0, 5.0], 'weights': [1.0, 2.0], 'expected': 1.6666666666666667},
    ]
    assert data == expected, 'The recovered vectors.json content is incorrect.'


def test_calc_go_fixed():
    path = '/home/user/physics/calc.go'
    assert os.path.isfile(path), f'{path} is missing.'

    with open(path, 'r') as f:
        content = f.read()

    assert re.search(r'positions\[\w+\]\s*\*\s*weights\[\w+\]|weights\[\w+\]\s*\*\s*positions\[\w+\]', content), \
        'The formula in calc.go was not corrected to multiply positions by weights.'
    assert re.search(r'func\s+CalculateCenterOfMass\s*\(.*?\)\s*\(\s*float64\s*,\s*error\s*\)', content), \
        'The CalculateCenterOfMass function signature was not updated to return (float64, error).'
    assert 'panic(' not in content, 'The panic statement was not removed from calc.go.'
    assert 'zero weight sum' in content, "The 'zero weight sum' error message is missing."
    assert re.search(r'return\s+0(?:\.0)?\s*,\s*(?:errors\.New|fmt\.Errorf)', content), \
        'The code does not return 0.0 and an error when total weight is zero.'


def test_fuzz_test_exists_and_exercises_function():
    path = '/home/user/physics/calc_test.go'
    assert os.path.isfile(path), f'{path} is missing.'
    content = open(path).read()
    match = re.search(r'func\s+FuzzCalculateCenterOfMass\s*\([^)]*\*testing\.F[^)]*\)\s*\{', content)
    assert match, 'calc_test.go does not define FuzzCalculateCenterOfMass with *testing.F.'
    start = match.end() - 1
    depth = 0
    end = None
    for i in range(start, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    assert end is not None, 'FuzzCalculateCenterOfMass has an incomplete body.'
    body = content[start:end]
    assert '.Fuzz(' in body, 'FuzzCalculateCenterOfMass does not register a fuzz target.'
    assert 'CalculateCenterOfMass(' in body, 'The fuzz target does not call CalculateCenterOfMass.'
    assert '.Skip(' not in body and '.Skipf(' not in body and '.SkipNow(' not in body, 'The fuzz test is skipped.'


def test_go_tests_and_fuzzer_really_pass():
    run_go('test', './...', '-count=1')
    output = run_go(
        'test', '-run=^$', '-fuzz=^FuzzCalculateCenterOfMass$',
        '-fuzztime=3s', '-parallel=1', timeout=45
    )
    assert 'fuzz' in output.lower(), 'The Go fuzz command did not report fuzzing activity.'


def test_test_results_log():
    path = '/home/user/physics/test_results.log'
    assert os.path.isfile(path), f'{path} was not created.'

    with open(path, 'r') as f:
        content = f.read().lower()

    assert 'pass' in content, 'The test_results.log does not indicate passing tests.'
    assert 'fuzz' in content, 'The test_results.log does not indicate that fuzzing was executed.'
    assert re.search(r'\bok\s+physics\b', content), 'test_results.log does not contain successful Go test output.'
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
rm -f /home/user/physics/verifier_behavior_test.go
