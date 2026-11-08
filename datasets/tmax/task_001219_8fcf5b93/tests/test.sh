#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest

def test_trace_csv_exists():
    trace_path = "/home/user/trace.csv"
    assert os.path.isfile(trace_path), f"File {trace_path} is missing."

def test_trace_csv_correctness():
    trace_path = "/home/user/trace.csv"
    assert os.path.isfile(trace_path), f"{trace_path} is missing."

    # We dynamically generate the expected trace by running a known-good Go implementation
    # that sorts the chunks by ChunkID before accumulating the total log-likelihood.
    correct_go_code = """
package main

import (
	"bufio"
	"encoding/csv"
	"fmt"
	"math"
	"math/rand"
	"os"
	"strconv"
	"sync"
)

type ChunkResult struct {
	ChunkID int
	Val     float64
}

func LogLikelihood(mu float64, data []float64) float64 {
	numChunks := 10
	chunkSize := len(data) / numChunks
	ch := make(chan ChunkResult, numChunks)
	var wg sync.WaitGroup

	for i := 0; i < numChunks; i++ {
		wg.Add(1)
		go func(chunkID int) {
			defer wg.Done()
			start := chunkID * chunkSize
			end := start + chunkSize
			if chunkID == numChunks-1 {
				end = len(data)
			}

			sum := 0.0
			for _, val := range data[start:end] {
				sum -= (val - mu) * (val - mu)
			}
			ch <- ChunkResult{ChunkID: chunkID, Val: sum}
		}(i)
	}

	wg.Wait()
	close(ch)

	results := make([]float64, numChunks)
	for res := range ch {
		results[res.ChunkID] = res.Val
	}

	totalLL := 0.0
	for i := 0; i < numChunks; i++ {
		totalLL += results[i]
	}

	return totalLL
}

func main() {
	rand.Seed(42)

	file, err := os.Open("/home/user/sequences.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var data []float64
	scanner := bufio.NewScanner(file)
	scanner.Scan() // skip header
	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 64)
		data = append(data, val)
	}

	out, err := os.Create("expected_trace.csv")
	if err != nil {
		panic(err)
	}
	defer out.Close()
	writer := csv.NewWriter(out)
	writer.Write([]string{"Iteration", "Mu", "LogLikelihood"})

	mu := 0.0
	currentLL := LogLikelihood(mu, data)

	writer.Write([]string{"0", fmt.Sprintf("%.6f", mu), fmt.Sprintf("%.6f", currentLL)})

	for i := 1; i <= 100; i++ {
		propMu := mu + rand.NormFloat64()*0.1
		propLL := LogLikelihood(propMu, data)

		if propLL > currentLL || math.Log(rand.Float64()) < (propLL-currentLL) {
			mu = propMu
			currentLL = propLL
		}

		writer.Write([]string{strconv.Itoa(i), fmt.Sprintf("%.6f", mu), fmt.Sprintf("%.6f", currentLL)})
	}
	writer.Flush()
}
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        go_file = os.path.join(tmpdir, "correct_mcmc.go")
        with open(go_file, "w") as f:
            f.write(correct_go_code)

        # Run the correct Go program
        try:
            subprocess.run(["go", "run", go_file], cwd=tmpdir, check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to compile and run truth Go code: {e.stderr.decode()}")

        expected_trace_path = os.path.join(tmpdir, "expected_trace.csv")
        with open(expected_trace_path, "r") as f:
            expected_content = f.read().strip().splitlines()

    with open(trace_path, "r") as f:
        actual_content = f.read().strip().splitlines()

    assert len(actual_content) == len(expected_content), f"Expected {len(expected_content)} lines in trace.csv, got {len(actual_content)}."

    for i, (actual, expected) in enumerate(zip(actual_content, expected_content)):
        assert actual == expected, f"Mismatch at line {i+1} in trace.csv: expected '{expected}', got '{actual}'. The reduction order is likely still non-deterministic or incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
