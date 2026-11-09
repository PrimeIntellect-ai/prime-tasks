#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() (
    set -e

    cat > /tmp/seq_oracle.go <<'GO_EOF'
package main

import (
    "encoding/csv"
    "fmt"
    "math"
    "math/rand"
    "os"
    "sort"
    "strconv"
)

type row struct {
    id string
    x  [5]float64
}

type loading struct {
    id string
    v  float64
}

func main() {
    if len(os.Args) != 4 {
        panic("usage: oracle data.csv top.txt lambda.txt")
    }

    f, err := os.Open(os.Args[1])
    if err != nil { panic(err) }
    records, err := csv.NewReader(f).ReadAll()
    f.Close()
    if err != nil { panic(err) }
    if len(records) < 2 || len(records[0]) != 6 { panic("invalid CSV") }

    rows := make([]row, 0, len(records)-1)
    for _, rec := range records[1:] {
        if len(rec) != 6 { panic("invalid CSV row") }
        var r row
        r.id = rec[0]
        mean := 0.0
        for j := 0; j < 5; j++ {
            r.x[j], err = strconv.ParseFloat(rec[j+1], 64)
            if err != nil { panic(err) }
            mean += r.x[j]
        }
        mean /= 5
        for j := 0; j < 5; j++ { r.x[j] -= mean }
        rows = append(rows, r)
    }

    // Form X^T X and diagonalize the real symmetric 5x5 matrix with Jacobi rotations.
    var a [5][5]float64
    for _, r := range rows {
        for i := 0; i < 5; i++ {
            for j := 0; j < 5; j++ { a[i][j] += r.x[i] * r.x[j] }
        }
    }
    var q [5][5]float64
    for i := 0; i < 5; i++ { q[i][i] = 1 }
    for iter := 0; iter < 10000; iter++ {
        p, qq := 0, 1
        maxOff := 0.0
        for i := 0; i < 5; i++ {
            for j := i + 1; j < 5; j++ {
                if math.Abs(a[i][j]) > maxOff {
                    maxOff, p, qq = math.Abs(a[i][j]), i, j
                }
            }
        }
        if maxOff < 1e-14 { break }
        phi := 0.5 * math.Atan2(2*a[p][qq], a[qq][qq]-a[p][p])
        c, s := math.Cos(phi), math.Sin(phi)
        app, aqq, apq := a[p][p], a[qq][qq], a[p][qq]
        for k := 0; k < 5; k++ {
            if k == p || k == qq { continue }
            akp, akq := a[k][p], a[k][qq]
            a[k][p], a[p][k] = c*akp-s*akq, c*akp-s*akq
            a[k][qq], a[qq][k] = s*akp+c*akq, s*akp+c*akq
        }
        a[p][p] = c*c*app - 2*s*c*apq + s*s*aqq
        a[qq][qq] = s*s*app + 2*s*c*apq + c*c*aqq
        a[p][qq], a[qq][p] = 0, 0
        for k := 0; k < 5; k++ {
            qkp, qkq := q[k][p], q[k][qq]
            q[k][p] = c*qkp - s*qkq
            q[k][qq] = s*qkp + c*qkq
        }
    }

    principal := 0
    for i := 1; i < 5; i++ {
        if a[i][i] > a[principal][principal] { principal = i }
    }
    var v, y [5]float64
    for i := 0; i < 5; i++ { v[i] = q[i][principal] }
    if math.Abs(v[0]) < 1e-12 { panic("dominant component has zero first element") }
    for i := 0; i < 5; i++ { y[i] = v[i] / v[0] }

    loads := make([]loading, len(rows))
    for i, r := range rows {
        projection := 0.0
        for j := 0; j < 5; j++ { projection += r.x[j] * v[j] }
        loads[i] = loading{r.id, math.Abs(projection)}
    }
    sort.Slice(loads, func(i, j int) bool {
        if loads[i].v == loads[j].v { return loads[i].id < loads[j].id }
        return loads[i].v > loads[j].v
    })
    top, err := os.Create(os.Args[2])
    if err != nil { panic(err) }
    for i := 0; i < 3; i++ { fmt.Fprintln(top, loads[i].id) }
    if err := top.Close(); err != nil { panic(err) }

    logLike := func(lambda float64) float64 {
        if lambda < 0 || lambda > 5 { return math.Inf(-1) }
        sum := 0.0
        for t := 0; t < 5; t++ {
            d := y[t] - math.Exp(-lambda*float64(t))
            sum += d*d
        }
        return -sum / (2 * 0.01)
    }

    rng := rand.New(rand.NewSource(42))
    current := 1.0
    currentLog := logLike(current)
    sum := 0.0
    for i := 0; i < 50000; i++ {
        proposal := current + 0.05*rng.NormFloat64()
        proposalLog := logLike(proposal)
        threshold := rng.Float64() // Always drawn after the proposal, including out-of-range proposals.
        if math.Log(threshold) < proposalLog-currentLog {
            current, currentLog = proposal, proposalLog
        }
        if i >= 10000 { sum += current }
    }
    if err := os.WriteFile(os.Args[3], []byte(fmt.Sprintf("%.4f", sum/40000)), 0644); err != nil {
        panic(err)
    }
}
GO_EOF

    cat > /tmp/check_seq_outputs.py <<'PY_EOF'
import pathlib
import re
import sys

expected_top = {x.strip() for x in pathlib.Path(sys.argv[1]).read_text().splitlines() if x.strip()}
expected_lambda = pathlib.Path(sys.argv[2]).read_text().strip()
require_original_fixed_assertion = sys.argv[3] == "original"

top_path = pathlib.Path("/home/user/top_sequences.txt")
lambda_path = pathlib.Path("/home/user/lambda_mean.txt")
assert top_path.is_file(), f"The file {top_path} does not exist."
assert lambda_path.is_file(), f"The file {lambda_path} does not exist."

top_lines = [x.strip() for x in top_path.read_text().splitlines() if x.strip()]
assert len(top_lines) == 3, f"Expected 3 sequences, found {len(top_lines)}"
assert len(set(top_lines)) == 3, "Top sequence IDs must be unique"
assert set(top_lines) == expected_top, f"Expected {expected_top}, got {set(top_lines)}"
if require_original_fixed_assertion:
    assert set(top_lines) == {"SEQ_003", "SEQ_005", "SEQ_001"}

raw_lambda = lambda_path.read_text()
value = raw_lambda.strip()
assert re.fullmatch(r"(?:[0-4]\.\d{4}|5\.0000)", value), \
    f"lambda_mean.txt is not formatted to exactly four decimal places: {raw_lambda!r}"
float(value)  # Retains the original parseability assertion.
assert value == expected_lambda, f"Expected posterior mean {expected_lambda}, got {value}"
PY_EOF

    go build -o /tmp/seq_oracle /tmp/seq_oracle.go

    test -f /home/user/seq_analysis/analyze.go
    test -f /home/user/seq_analysis/go.mod
    grep -q 'gonum.org/v1/gonum' /home/user/seq_analysis/go.mod

    backup=$(mktemp)
    cp /home/user/sequence_data.csv "$backup"
    trap 'cp "$backup" /home/user/sequence_data.csv; rm -f "$backup"' EXIT

    run_case() {
        case_name=$1
        rm -f /home/user/top_sequences.txt /home/user/lambda_mean.txt
        /tmp/seq_oracle /home/user/sequence_data.csv /tmp/expected_top.txt /tmp/expected_lambda.txt
        (cd /home/user/seq_analysis && timeout 120s go run ./analyze.go)
        python3 /tmp/check_seq_outputs.py /tmp/expected_top.txt /tmp/expected_lambda.txt "$case_name"
    }

    run_case original

    cat > /home/user/sequence_data.csv <<'CSV_EOF'
SeqID,T0,T1,T2,T3,T4
SEQ_001,30.0,15.0,7.0,3.0,1.0
SEQ_002,0.0,4.0,10.0,4.0,0.0
SEQ_003,5.0,4.0,3.0,2.0,1.0
SEQ_004,9.0,9.0,9.0,9.0,9.0
SEQ_005,-2.0,-1.0,0.0,1.0,2.0
SEQ_006,100.0,70.0,45.0,20.0,5.0
CSV_EOF
    run_case derived
)

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
