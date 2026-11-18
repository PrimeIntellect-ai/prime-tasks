#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

SOURCE = Path('/home/user/simulate.go')
DATA = Path('/home/user/data.csv')
OUTPUT = Path('/home/user/output.txt')

CANONICAL_DATA = '''10.2
11.5
9.8
10.5
12.1
9.5
10.8
11.1
10.0
10.9
'''
CANONICAL_EXPECTED = [
    'Mean Initial: 10.6400',
    'Std Initial: 0.8030',
    'Lower CI: 4.9967',
    'Upper CI: 5.0001',
]

REFERENCE_GO = r'''package main

import (
    "bufio"
    "fmt"
    "math"
    "math/rand"
    "os"
    "sort"
    "strconv"
    "strings"
)

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    values := make([]float64, 0)
    for scanner.Scan() {
        text := strings.TrimSpace(scanner.Text())
        if text == "" { continue }
        value, err := strconv.ParseFloat(text, 64)
        if err != nil { panic(err) }
        values = append(values, value)
    }
    if err := scanner.Err(); err != nil { panic(err) }
    if len(values) < 2 { panic("not enough values") }

    var mu float64
    for _, value := range values { mu += value }
    mu /= float64(len(values))

    var sumsq float64
    for _, value := range values {
        d := value - mu
        sumsq += d * d
    }
    s := math.Sqrt(sumsq / float64(len(values)-1))

    rng := rand.New(rand.NewSource(12345))
    finals := make([]float64, 1000)
    f := func(y float64) float64 { return -0.1*y*y + 0.5*y }
    const dt = 0.1
    for i := 0; i < 1000; i++ {
        y := rng.NormFloat64()*s + mu
        for step := 0; step < 50; step++ {
            k1 := f(y)
            k2 := f(y + dt*k1/2)
            k3 := f(y + dt*k2/2)
            k4 := f(y + dt*k3)
            y += dt * (k1 + 2*k2 + 2*k3 + k4) / 6
        }
        finals[i] = y
    }

    medians := make([]float64, 2000)
    sample := make([]float64, 1000)
    for b := 0; b < 2000; b++ {
        for j := 0; j < 1000; j++ {
            sample[j] = finals[rng.Intn(1000)]
        }
        sort.Float64s(sample)
        medians[b] = (sample[499] + sample[500]) / 2
    }
    sort.Float64s(medians)

    fmt.Printf("Mean Initial: %.4f\n", mu)
    fmt.Printf("Std Initial: %.4f\n", s)
    fmt.Printf("Lower CI: %.4f\n", medians[50])
    fmt.Printf("Upper CI: %.4f\n", medians[1950])
}
'''

def cleaned_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]

def read_output():
    assert OUTPUT.exists(), f'The file {OUTPUT} is missing. Did you run the Go program?'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'
    return cleaned_lines(OUTPUT.read_text())

def assert_lines(actual, expected, label):
    assert len(actual) == len(expected), (
        f'{label}: expected {len(expected)} lines in output.txt, got {len(actual)}.'
    )
    for i, (got, wanted) in enumerate(zip(actual, expected), 1):
        assert got == wanted, (
            f'{label}: line {i} mismatch: expected {wanted!r}, got {got!r}.'
        )

def make_random_case(base, count):
    # Runtime-generated inputs prevent a submission from hardcoding test answers.
    values = []
    for i in range(count):
        jitter = (secrets.randbelow(60001) - 30000) / 100000.0
        trend = ((i % 4) - 1.5) * 0.07
        values.append(base + jitter + trend)
    return ''.join(f'{value:.5f}\n' for value in values)

def main():
    assert SOURCE.exists(), f'The file {SOURCE} is missing.'
    assert SOURCE.is_file(), f'{SOURCE} is not a file.'

    with tempfile.TemporaryDirectory(prefix='verify-simulation-') as td:
        td = Path(td)
        reference_source = td / 'reference.go'
        reference_binary = td / 'reference'
        submission_binary = td / 'submission'
        reference_source.write_text(REFERENCE_GO)

        subprocess.run(
            ['go', 'build', '-o', str(reference_binary), str(reference_source)],
            check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )
        subprocess.run(
            ['go', 'build', '-o', str(submission_binary), str(SOURCE)],
            check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )

        cases = [
            make_random_case(2.2, 7),
            make_random_case(6.5, 11),
            make_random_case(11.5, 14),
            CANONICAL_DATA,
        ]

        expected_outputs = []
        for case in cases:
            result = subprocess.run(
                [str(reference_binary)], input=case, check=True, timeout=30,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            expected_outputs.append(cleaned_lines(result.stdout))

        # The original exact-value assertion remains in force.
        assert_lines(expected_outputs[-1], CANONICAL_EXPECTED, 'reference canonical check')

        # Remove the verifier implementation before executing the submission.
        reference_source.unlink()
        reference_binary.unlink()

        for index, (case, expected) in enumerate(zip(cases, expected_outputs), 1):
            DATA.write_text(case)
            if OUTPUT.exists():
                OUTPUT.unlink()
            subprocess.run(
                [str(submission_binary)], cwd='/home/user', check=True, timeout=30,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            actual = read_output()
            assert_lines(actual, expected, f'behavioral case {index}')

        # The canonical case is last, so retain and explicitly recheck the
        # originally required final output state.
        assert_lines(read_output(), CANONICAL_EXPECTED, 'canonical output')

if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
