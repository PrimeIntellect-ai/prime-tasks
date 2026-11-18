#!/bin/bash
set +e
mkdir -p /logs/verifier
ok=1
workdir=$(mktemp -d)

cat << 'PY_EOF' > "$workdir/test_original.py"
import os
import json
import csv
import pytest

def test_processed_metrics_csv():
    file_path = "/home/user/processed_metrics.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    raw_data = [
        (1, 45.0, 60.0, 120.0, 15.2),
        (2, 85.0, 90.0, 80.0, 45.5),
        (3, 20.0, 30.0, 200.0, 5.0),
        (4, 95.0, 88.0, 50.0, 80.1),
        (5, 50.0, 50.0, 150.0, 20.0),
        (6, 70.0, 75.0, 100.0, 35.4),
        (7, 10.0, 20.0, 250.0, 2.1),
        (8, 65.0, 70.0, 110.0, 28.9),
        (9, 90.0, 85.0, 60.0, 65.2),
        (10, 35.0, 40.0, 180.0, 10.5)
    ]

    cpu_min, cpu_max = 10.0, 95.0
    mem_min, mem_max = 20.0, 90.0
    disk_min, disk_max = 50.0, 250.0
    load_indices = [(cpu * mem) / disk for _, cpu, mem, disk, _ in raw_data]
    li_min, li_max = min(load_indices), max(load_indices)

    expected_rows = []
    for i, row in enumerate(raw_data):
        id_val, cpu, mem, disk, latency = row
        li = load_indices[i]
        expected_rows.append([
            str(id_val),
            f"{(cpu-cpu_min)/(cpu_max-cpu_min):.4f}",
            f"{(mem-mem_min)/(mem_max-mem_min):.4f}",
            f"{(disk-disk_min)/(disk_max-disk_min):.4f}",
            f"{(li-li_min)/(li_max-li_min):.4f}",
            f"{latency:.4f}" if isinstance(latency, float) else str(latency)
        ])

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        expected_header = ["ID", "CPU_scaled", "Memory_scaled", "DiskIO_scaled", "LoadIndex_scaled", "Latency"]
        assert [h.strip() for h in header] == expected_header, "CSV header is incorrect."
        actual_rows = list(reader)
        assert len(actual_rows) == len(expected_rows), "Incorrect number of rows in processed_metrics.csv."
        for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
            assert actual[0] == expected[0], f"Row {i+1} ID mismatch: expected {expected[0]}, got {actual[0]}"
            assert actual[1] == expected[1], f"Row {i+1} CPU_scaled mismatch: expected {expected[1]}, got {actual[1]}"
            assert actual[2] == expected[2], f"Row {i+1} Memory_scaled mismatch: expected {expected[2]}, got {actual[2]}"
            assert actual[3] == expected[3], f"Row {i+1} DiskIO_scaled mismatch: expected {expected[3]}, got {actual[3]}"
            assert actual[4] == expected[4], f"Row {i+1} LoadIndex_scaled mismatch: expected {expected[4]}, got {actual[4]}"
            actual_lat = float(actual[5])
            expected_lat = float(expected[5])
            assert abs(actual_lat - expected_lat) < 1e-4, f"Row {i+1} Latency mismatch: expected {expected[5]}, got {actual[5]}"

def test_bootstrap_means_json():
    file_path = "/home/user/bootstrap_means.json"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    with open(file_path, "r") as f:
        try:
            means = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")
    assert isinstance(means, list), "JSON output should be a list."
    assert len(means) == 5, "JSON output should contain exactly 5 means."
    expected_means = [36.82, 19.01, 18.99, 29.50, 15.90]
    for i, (actual, expected) in enumerate(zip(means, expected_means)):
        assert isinstance(actual, (int, float)), f"Mean at index {i} is not a number."
        assert abs(actual - expected) < 1e-2, f"Bootstrap mean {i+1} mismatch: expected ~{expected}, got {actual}"
PY_EOF

# Preserve all original output assertions before rerunning the submitted program.
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$workdir/test_original.py" -x --tb=short >/dev/null 2>&1 || ok=0

# The requested artifact must be a real Go source file and must compile.
if [ ! -f /home/user/pipeline.go ] || [ -L /home/user/pipeline.go ] || [ ! -s /home/user/pipeline.go ]; then
    ok=0
elif ! go build -o "$workdir/pipeline_under_test" /home/user/pipeline.go >/dev/null 2>&1; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    cp /home/user/raw_metrics.csv "$workdir/original_raw.csv"
    cp /home/user/processed_metrics.csv "$workdir/original_processed.csv"
    cp /home/user/bootstrap_means.json "$workdir/original_bootstrap.json"

    # Generate a fresh dataset so fixed precomputed artifacts cannot satisfy the verifier.
    python3 - "$workdir/dynamic_raw.csv" << 'PY_EOF'
import csv, secrets, sys
path = sys.argv[1]
n = 7 + secrets.randbelow(4)
start_id = 1000 + secrets.randbelow(8000)
with open(path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["ID", "CPU", "Memory", "DiskIO", "Latency"])
    for i in range(n):
        cpu = 11.0 + 7.1*i + secrets.randbelow(70)/100.0
        memory = 24.0 + 5.3*i + secrets.randbelow(80)/100.0
        disk = 55.0 + 11.7*((i*3) % n) + secrets.randbelow(90)/100.0
        latency = 3.0 + 4.9*i + secrets.randbelow(500)/100.0
        w.writerow([start_id+i, f"{cpu:.2f}", f"{memory:.2f}", f"{disk:.2f}", f"{latency:.2f}"])
PY_EOF

    cat << 'GO_EOF' > "$workdir/expected_means.go"
package main
import (
    "encoding/csv"
    "encoding/json"
    "os"
    "math/rand"
    "strconv"
)
func main() {
    f, err := os.Open(os.Args[1]); if err != nil { panic(err) }
    rows, err := csv.NewReader(f).ReadAll(); if err != nil { panic(err) }
    vals := make([]float64, len(rows)-1)
    for i, row := range rows[1:] {
        vals[i], err = strconv.ParseFloat(row[4], 64); if err != nil { panic(err) }
    }
    rng := rand.New(rand.NewSource(12345))
    means := make([]float64, 5)
    for s := 0; s < 5; s++ {
        sum := 0.0
        for i := 0; i < len(vals); i++ { sum += vals[rng.Intn(len(vals))] }
        means[s] = sum / float64(len(vals))
    }
    out, err := os.Create(os.Args[2]); if err != nil { panic(err) }
    defer out.Close()
    if err = json.NewEncoder(out).Encode(means); err != nil { panic(err) }
}
GO_EOF

    if ! go run "$workdir/expected_means.go" "$workdir/dynamic_raw.csv" "$workdir/expected_means.json" >/dev/null 2>&1; then
        ok=0
    else
        cp "$workdir/dynamic_raw.csv" /home/user/raw_metrics.csv
        rm -f /home/user/processed_metrics.csv /home/user/bootstrap_means.json
        if ! timeout 30s "$workdir/pipeline_under_test" >/dev/null 2>&1; then
            ok=0
        fi
    fi

    cat << 'PY_EOF' > "$workdir/test_dynamic.py"
import csv, json, math, os, re

RAW = os.environ["DYNAMIC_RAW"]
EXPECTED_MEANS = os.environ["EXPECTED_MEANS"]
FOUR_DP = re.compile(r"^-?\d+\.\d{4}$")

def test_dynamic_processed_output():
    with open(RAW, newline="") as f:
        source = list(csv.reader(f))
    rows = source[1:]
    parsed = [(r[0], float(r[1]), float(r[2]), float(r[3]), float(r[4])) for r in rows]
    cpus = [r[1] for r in parsed]
    memories = [r[2] for r in parsed]
    disks = [r[3] for r in parsed]
    loads = [r[1] * r[2] / r[3] for r in parsed]
    columns = (cpus, memories, disks, loads)

    path = "/home/user/processed_metrics.csv"
    assert os.path.isfile(path)
    with open(path, newline="") as f:
        actual = list(csv.reader(f))
    assert actual[0] == ["ID", "CPU_scaled", "Memory_scaled", "DiskIO_scaled", "LoadIndex_scaled", "Latency"]
    assert len(actual[1:]) == len(parsed)

    for i, out in enumerate(actual[1:]):
        assert len(out) == 6
        assert out[0] == parsed[i][0]
        for j, values in enumerate(columns, start=1):
            expected = (values[i] - min(values)) / (max(values) - min(values))
            assert FOUR_DP.fullmatch(out[j]), f"row {i+1}, column {j} is not formatted to four decimals"
            assert abs(float(out[j]) - expected) <= 5.1e-5
        assert abs(float(out[5]) - parsed[i][4]) < 1e-4

def test_dynamic_bootstrap_output():
    with open(EXPECTED_MEANS) as f:
        expected = json.load(f)
    with open("/home/user/bootstrap_means.json") as f:
        actual = json.load(f)
    assert isinstance(actual, list)
    assert len(actual) == 5
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert isinstance(got, (int, float)), f"Mean at index {i} is not a number."
        assert math.isfinite(float(got))
        assert abs(got - want) < 1e-2
PY_EOF

    if [ "$ok" -eq 1 ]; then
        DYNAMIC_RAW="$workdir/dynamic_raw.csv" EXPECTED_MEANS="$workdir/expected_means.json" \
            python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$workdir/test_dynamic.py" -x --tb=short >/dev/null 2>&1 || ok=0
    fi

    cp "$workdir/original_raw.csv" /home/user/raw_metrics.csv
    cp "$workdir/original_processed.csv" /home/user/processed_metrics.csv
    cp "$workdir/original_bootstrap.json" /home/user/bootstrap_means.json
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
rm -rf "$workdir"
