#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
from pathlib import Path

GO_SOURCE = '/home/user/evaluate_distribution.go'
PIPELINE = '/home/user/pipeline.sh'
OUTPUT_CSV = '/home/user/tvd_convergence.csv'

CANONICAL_GO = r'''package main

import (
    "bufio"
    "fmt"
    "math"
    "math/rand"
    "os"
    "strconv"
)

func readFloats(filename string) ([]float64, error) {
    f, err := os.Open(filename)
    if err != nil {
        return nil, err
    }
    defer f.Close()

    values := make([]float64, 0)
    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        v, err := strconv.ParseFloat(scanner.Text(), 64)
        if err != nil {
            return nil, err
        }
        values = append(values, v)
    }
    if err := scanner.Err(); err != nil {
        return nil, err
    }
    return values, nil
}

func distribution(values []float64) [10]float64 {
    var result [10]float64
    for _, v := range values {
        idx := int(v * 10.0)
        if idx >= 10 {
            idx = 9
        }
        result[idx]++
    }
    for i := range result {
        result[i] /= float64(len(values))
    }
    return result
}

func main() {
    if len(os.Args) != 4 {
        os.Exit(2)
    }
    seed, err := strconv.ParseInt(os.Args[3], 10, 64)
    if err != nil {
        os.Exit(2)
    }
    reference, err := readFloats(os.Args[1])
    if err != nil {
        os.Exit(1)
    }
    sample, err := readFloats(os.Args[2])
    if err != nil {
        os.Exit(1)
    }

    rng := rand.New(rand.NewSource(seed))
    rng.Shuffle(len(sample), func(i, j int) {
        sample[i], sample[j] = sample[j], sample[i]
    })

    referenceDist := distribution(reference)
    for n := 100; n <= 1000; n += 100 {
        sampleDist := distribution(sample[:n])
        tvd := 0.0
        for i := 0; i < 10; i++ {
            tvd += math.Abs(referenceDist[i] - sampleDist[i])
        }
        fmt.Printf("%d,%.6f\n", n, 0.5*tvd)
    }
}
'''


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, timeout=60, **kwargs)


def build_canonical(directory):
    source = Path(directory) / 'canonical.go'
    binary = Path(directory) / 'canonical'
    source.write_text(CANONICAL_GO)
    result = run(['go', 'build', '-o', str(binary), str(source)])
    assert result.returncode == 0, f'Failed to build canonical program: {result.stderr}'
    return str(binary)


def write_values(path, values):
    with open(path, 'w') as handle:
        for value in values:
            handle.write(f'{value:.12f}\n')


def make_case(directory, case_number):
    rng = random.Random(81031 + case_number * 1777)
    reference = []
    for i in range(1739 + case_number * 113):
        if i % 4 == 0:
            value = rng.random() * 0.23
        elif i % 4 == 1:
            value = 0.1 + rng.random() * 0.51
        elif i % 4 == 2:
            value = 0.58 + rng.random() * 0.42
        else:
            value = rng.random()
        reference.append(min(value, 1.0))

    sample = []
    for i in range(1000):
        if (i + case_number) % 5 == 0:
            value = rng.random() * 0.12
        elif i % 3 == 0:
            value = 0.31 + rng.random() * 0.18
        else:
            value = 0.67 + rng.random() * 0.33
        sample.append(min(value, 1.0))

    # Exercise every bin boundary, including the special 1.0 case.
    boundaries = [i / 10 for i in range(11)]
    for i, value in enumerate(boundaries):
        reference[i * 7] = value
        sample[i * 13] = value

    reference_path = Path(directory) / f'unseen_reference_{case_number}.dat'
    sample_path = Path(directory) / f'unseen_sample_{case_number}.dat'
    write_values(reference_path, reference)
    write_values(sample_path, sample)
    return str(reference_path), str(sample_path)


def test_go_file_exists():
    assert os.path.isfile(GO_SOURCE), f'Missing {GO_SOURCE}'


def test_pipeline_script_exists():
    assert os.path.isfile(PIPELINE), f'Missing {PIPELINE}'


def test_pipeline_execution_and_output():
    result = run(['bash', PIPELINE])
    assert result.returncode == 0, (
        f'pipeline.sh failed with return code {result.returncode}\nStderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT_CSV), f'Output file {OUTPUT_CSV} was not created.'

    with tempfile.TemporaryDirectory() as directory:
        canonical = build_canonical(directory)
        expected_run = run([
            canonical,
            '/home/user/reference.txt',
            '/home/user/sample.txt',
            '42',
        ])
        assert expected_run.returncode == 0, 'Canonical computation failed.'
        expected_output = 'N,TVD\n' + expected_run.stdout.strip()

    with open(OUTPUT_CSV, 'r') as handle:
        student_output = handle.read().strip()

    assert student_output == expected_output, (
        f'Contents of {OUTPUT_CSV} do not match the expected output.\n'
        f'Expected:\n{expected_output}\n\nGot:\n{student_output}'
    )


def test_go_program_directly_on_unseen_inputs_and_seeds():
    with tempfile.TemporaryDirectory() as directory:
        student_binary = Path(directory) / 'student_evaluator'
        build = run(['go', 'build', '-o', str(student_binary), GO_SOURCE])
        assert build.returncode == 0, (
            f'{GO_SOURCE} is not a buildable Go program.\nStderr: {build.stderr}'
        )

        canonical = build_canonical(directory)
        for case_number, seed in [(1, 7), (2, 918273)]:
            reference_path, sample_path = make_case(directory, case_number)
            arguments = [reference_path, sample_path, str(seed)]

            expected = run([canonical] + arguments)
            assert expected.returncode == 0, f'Canonical case {case_number} failed.'

            actual = run([str(student_binary)] + arguments)
            assert actual.returncode == 0, (
                f'Go program failed on unseen case {case_number} with seed {seed}.\n'
                f'Stderr: {actual.stderr}'
            )
            assert actual.stdout == expected.stdout, (
                f'Go program output is incorrect on unseen case {case_number} '
                f'with seed {seed}.\nExpected:\n{expected.stdout}\nGot:\n{actual.stdout}'
            )

        missing_args = run([str(student_binary)])
        assert missing_args.returncode != 0, 'Go program must require the three command-line arguments.'

        reference_path, sample_path = make_case(directory, 3)
        bad_seed = run([str(student_binary), reference_path, sample_path, 'not-an-integer'])
        assert bad_seed.returncode != 0, 'Go program must reject a non-integer seed.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
