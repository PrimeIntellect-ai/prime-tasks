#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    test -f /home/user/Makefile
    test -f /home/user/analyze.go
    test -f /home/user/sequence_scores.txt

    # Verify that the default target and explicit all target build the required executable.
    rm -f /home/user/analyze /home/user/pipeline_output.tsv
    make -C /home/user
    test -x /home/user/analyze
    make -C /home/user all
    test -x /home/user/analyze

    # Independently compile and execute the submitted Go source, rather than trusting
    # a pre-created TSV or an unrelated executable produced by the Makefile.
    rm -f /tmp/submission-analyze /home/user/pipeline_output.tsv
    go build -o /tmp/submission-analyze /home/user/analyze.go
    /tmp/submission-analyze
    test -f /home/user/pipeline_output.tsv
    cp /home/user/pipeline_output.tsv /tmp/direct_output.tsv

    # Verify that the Makefile's run target also creates the required output.
    rm -f /home/user/pipeline_output.tsv
    make -C /home/user run
    test -f /home/user/pipeline_output.tsv
    cp /home/user/pipeline_output.tsv /tmp/make_output.tsv

    # Compute the complete expected mesh, means, and seeded bootstrap intervals
    # independently using the specified Go RNG and percentile indexing.
    cat > /tmp/bootstrap_oracle.go <<'GO_EOF'
package main

import (
    "bufio"
    "fmt"
    "math/rand"
    "os"
    "sort"
    "strconv"
    "strings"
)

type Bin struct {
    start int
    end   int
}

func mean(values []float64) float64 {
    total := 0.0
    for _, value := range values {
        total += value
    }
    return total / float64(len(values))
}

func variance(values []float64) float64 {
    m := mean(values)
    total := 0.0
    for _, value := range values {
        delta := value - m
        total += delta * delta
    }
    return total / float64(len(values))
}

func main() {
    file, err := os.Open("/home/user/sequence_scores.txt")
    if err != nil {
        panic(err)
    }
    defer file.Close()

    scores := make([]float64, 0, 1000)
    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        text := strings.TrimSpace(scanner.Text())
        if text == "" {
            continue
        }
        value, err := strconv.ParseFloat(text, 64)
        if err != nil {
            panic(err)
        }
        scores = append(scores, value)
    }
    if err := scanner.Err(); err != nil {
        panic(err)
    }
    if len(scores) != 1000 {
        panic(fmt.Sprintf("expected 1000 scores, got %d", len(scores)))
    }

    bins := make([]Bin, 0, 20)
    for start := 0; start < 1000; start += 100 {
        end := start + 100
        if variance(scores[start:end]) > 0.5 {
            middle := start + 50
            bins = append(bins, Bin{start, middle}, Bin{middle, end})
        } else {
            bins = append(bins, Bin{start, end})
        }
    }

    fmt.Println("Start\tEnd\tMean\tLower95\tUpper95")
    for _, bin := range bins {
        values := scores[bin.start:bin.end]
        rng := rand.New(rand.NewSource(int64(bin.start)))
        bootstrapMeans := make([]float64, 1000)
        for iteration := 0; iteration < 1000; iteration++ {
            total := 0.0
            for sample := 0; sample < len(values); sample++ {
                total += values[rng.Intn(len(values))]
            }
            bootstrapMeans[iteration] = total / float64(len(values))
        }
        sort.Float64s(bootstrapMeans)
        fmt.Printf("%d\t%d\t%.4f\t%.4f\t%.4f\n",
            bin.start, bin.end, mean(values),
            bootstrapMeans[25], bootstrapMeans[974])
    }
}
GO_EOF
    go run /tmp/bootstrap_oracle.go > /tmp/expected_output.tsv

    cat > /tmp/test_final_state.py <<'PY_EOF'
import os

EXPECTED_STARTS = [0, 100, 200, 250, 300, 400, 500, 550, 600, 700, 800, 850, 900]
EXPECTED_ENDS = [100, 200, 250, 300, 400, 500, 550, 600, 700, 800, 850, 900, 1000]
EXPECTED_HEADER = ["Start", "End", "Mean", "Lower95", "Upper95"]

assert os.path.isfile("/home/user/Makefile"), "Makefile is missing."
assert os.path.isfile("/home/user/analyze.go"), "analyze.go is missing."
assert os.path.isfile("/home/user/pipeline_output.tsv"), "pipeline_output.tsv is missing."
assert os.path.isfile("/home/user/sequence_scores.txt"), "sequence_scores.txt is missing."

with open("/home/user/sequence_scores.txt") as handle:
    scores = [float(line.strip()) for line in handle if line.strip()]
assert len(scores) == 1000, "Expected 1000 scores in sequence_scores.txt"


def read_rows(path):
    with open(path) as handle:
        return [line.strip().split("\t") for line in handle if line.strip()]

expected_rows = read_rows("/tmp/expected_output.tsv")
assert expected_rows and expected_rows[0] == EXPECTED_HEADER

for output_path in ("/tmp/direct_output.tsv", "/tmp/make_output.tsv"):
    rows = read_rows(output_path)
    assert rows, f"{output_path} is empty"
    assert rows[0] == EXPECTED_HEADER, (
        f"Expected header {EXPECTED_HEADER}, got {rows[0]}"
    )

    data_rows = rows[1:]
    assert len(data_rows) == len(EXPECTED_STARTS), (
        f"Expected {len(EXPECTED_STARTS)} rows, got {len(data_rows)}"
    )

    for i, row in enumerate(data_rows):
        assert len(row) == 5, f"Row {i + 1} does not have exactly 5 columns"
        start = int(row[0])
        end = int(row[1])
        mean_val = float(row[2])
        lower = float(row[3])
        upper = float(row[4])

        assert start == EXPECTED_STARTS[i], (
            f"Row {i + 1}: expected Start {EXPECTED_STARTS[i]}, got {start}"
        )
        assert end == EXPECTED_ENDS[i], (
            f"Row {i + 1}: expected End {EXPECTED_ENDS[i]}, got {end}"
        )

        bin_scores = scores[start:end]
        expected_mean = sum(bin_scores) / len(bin_scores)
        assert abs(mean_val - expected_mean) < 1e-3, (
            f"Row {i + 1}: expected Mean ~{expected_mean:.4f}, got {mean_val}"
        )
        assert lower <= upper, (
            f"Row {i + 1}: Lower95 ({lower}) is greater than Upper95 ({upper})"
        )
        assert lower - 0.1 <= mean_val <= upper + 0.1, (
            f"Row {i + 1}: Mean {mean_val} is far outside CI [{lower}, {upper}]"
        )

    # Exact textual comparison enforces four-decimal formatting and the specified
    # 1000-iteration, per-bin-seeded bootstrap bounds.
    assert rows == expected_rows, (
        f"{output_path} does not match the required seeded bootstrap results"
    )
PY_EOF

    python3 /tmp/test_final_state.py
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
