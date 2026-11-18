#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import textwrap

BASE = "/home/user/spectro_sim"
HEADER = ["BinIndex", "BinCenter", "SmoothedCount"]

REFERENCE_GO = r'''
package main

import (
    "bufio"
    "flag"
    "fmt"
    "math/rand"
    "os"
)

func main() {
    seed := flag.Int64("seed", 1, "random seed")
    samples := flag.Int("samples", 10000, "number of samples")
    flag.Parse()

    rng := rand.New(rand.NewSource(*seed))
    hist := make([]int, 100)
    for n := 0; n < *samples; n++ {
        r := rng.Float64()
        var energy float64
        if r < 0.7 {
            energy = rng.Float64() * 10.0
        } else if r < 0.9 {
            energy = 4.5 + 0.2*rng.NormFloat64()
        } else {
            energy = 7.5 + 0.1*rng.NormFloat64()
        }
        if energy >= 0.0 && energy < 10.0 {
            hist[int(energy/0.1)]++
        }
    }

    smooth := make([]float64, 100)
    for i := 0; i < 100; i++ {
        total := hist[i]
        if i > 0 {
            total += hist[i-1]
        }
        if i < 99 {
            total += hist[i+1]
        }
        smooth[i] = float64(total) / 3.0
    }

    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    fmt.Fprintln(out, "BinIndex,BinCenter,SmoothedCount")
    for i := 0; i < 100; i++ {
        left, right := 0.0, 0.0
        if i > 0 {
            left = smooth[i-1]
        }
        if i < 99 {
            right = smooth[i+1]
        }
        if smooth[i] > left && smooth[i] > right && smooth[i] > 100.0 {
            fmt.Fprintf(out, "%d,%.3f,%.3f\n", i, float64(i)*0.1+0.05, smooth[i])
        }
    }
}
'''


def run_checked(args, cwd=None, timeout=120):
    result = subprocess.run(
        args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(args)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def read_csv_text(text):
    return list(csv.reader(text.splitlines()))


def read_csv_file(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def expected_csv(reference, seed=None, samples=None):
    args = [reference]
    if seed is not None:
        args += ["-seed", str(seed)]
    if samples is not None:
        args += ["-samples", str(samples)]
    return read_csv_text(run_checked(args).stdout)


def assert_csv_matches(expected):
    actual = read_csv_file(os.path.join(BASE, "peaks.csv"))
    assert actual == expected, (
        "peaks.csv does not match the required seeded simulation, histogram, "
        "smoothing, peak detection, and formatting"
    )


def assert_original_state_checks():
    assert os.path.isdir(BASE), f"Directory {BASE} does not exist."
    expected_files = ["go.mod", "simulate.go", "run_pipeline.sh", "peaks.csv", "top_peaks.txt", "simulator"]
    for name in expected_files:
        assert os.path.isfile(os.path.join(BASE, name)), f"Expected file {name} does not exist."

    script_path = os.path.join(BASE, "run_pipeline.sh")
    assert os.access(script_path, os.X_OK), "run_pipeline.sh is not executable."

    with open(os.path.join(BASE, "go.mod")) as f:
        content = f.read()
    assert "module spectro_sim" in content, "go.mod does not contain 'module spectro_sim'."

    with open(os.path.join(BASE, "peaks.csv")) as f:
        lines = f.readlines()
    assert len(lines) > 1, "peaks.csv should have a header and at least one data row."
    assert lines[0].strip() == "BinIndex,BinCenter,SmoothedCount", "peaks.csv header is incorrect."

    with open(os.path.join(BASE, "top_peaks.txt")) as f:
        content = f.read().strip()
    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) == 2, f"top_peaks.txt should contain exactly 2 lines, found {len(lines)}."
    vals = []
    for line in lines:
        try:
            vals.append(float(line))
        except ValueError:
            assert False, f"Could not parse '{line}' as float in top_peaks.txt."
    assert any(4.4 <= v <= 4.6 for v in vals), f"Expected a peak near 4.5 in top_peaks.txt, got: {vals}"
    assert any(7.4 <= v <= 7.6 for v in vals), f"Expected a peak near 7.5 in top_peaks.txt, got: {vals}"


def assert_top_peaks(expected):
    rows = expected[1:]
    assert len(rows) >= 2, "Reference pipeline unexpectedly produced fewer than two peaks"
    by_center = {row[1]: float(row[2]) for row in rows}
    ranked_counts = sorted((float(row[2]) for row in rows), reverse=True)

    with open(os.path.join(BASE, "top_peaks.txt")) as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]
    assert len(lines) == 2, f"top_peaks.txt should contain exactly 2 lines, found {len(lines)}."
    assert all(line in by_center for line in lines), "top_peaks.txt contains a center not present in peaks.csv"
    assert len(set(lines)) == 2, "top_peaks.txt must contain two distinct peak centers"
    counts = [by_center[line] for line in lines]
    assert counts[0] >= counts[1], "top_peaks.txt is not sorted by SmoothedCount descending"
    assert counts[0] == ranked_counts[0] and counts[1] == ranked_counts[1], (
        "top_peaks.txt does not contain the two highest SmoothedCount peaks"
    )


def validate_pipeline(reference):
    expected = expected_csv(reference, 12345, 500000)
    assert_csv_matches(expected)
    assert_top_peaks(expected)
    simulator = os.path.join(BASE, "simulator")
    assert os.path.isfile(simulator), "Pipeline did not create simulator"
    assert os.access(simulator, os.X_OK), "Pipeline simulator is not executable"
    with open(simulator, "rb") as f:
        assert f.read(4) == b"\x7fELF", "simulator is not a compiled executable"
    return expected


def test_complete_simulation_pipeline():
    # Preserve all checks made by the original verifier against the submitted state.
    assert_original_state_checks()

    ref_source = "/tmp/spectro_reference.go"
    reference = "/tmp/spectro_reference"
    with open(ref_source, "w") as f:
        f.write(textwrap.dedent(REFERENCE_GO))
    run_checked(["go", "build", "-o", reference, ref_source], cwd="/tmp")

    # Independently compile and exercise the submitted Go source, including defaults
    # and unpredictable seeds/sample counts.
    submitted = "/tmp/submitted_simulator"
    run_checked(["go", "build", "-o", submitted, "simulate.go"], cwd=BASE)
    run_checked([submitted], cwd=BASE)
    assert_csv_matches(expected_csv(reference))

    for _ in range(2):
        seed = secrets.randbelow(2_000_000_000) + 1
        samples = secrets.randbelow(70001) + 50000
        run_checked([submitted, "-seed", str(seed), "-samples", str(samples)], cwd=BASE)
        assert_csv_matches(expected_csv(reference, seed, samples))

    # Delete generated artifacts so the automation script must recreate them.
    for name in ("simulator", "peaks.csv", "top_peaks.txt"):
        path = os.path.join(BASE, name)
        if os.path.lexists(path):
            os.remove(path)
    run_checked(["bash", "./run_pipeline.sh"], cwd=BASE)
    validate_pipeline(reference)

    # Exercise the exact simulator produced by the pipeline on a fresh case.
    seed = secrets.randbelow(2_000_000_000) + 1
    samples = secrets.randbelow(70001) + 50000
    run_checked([os.path.join(BASE, "simulator"), "-seed", str(seed), "-samples", str(samples)], cwd=BASE)
    assert_csv_matches(expected_csv(reference, seed, samples))

    # Restore and revalidate the required final pipeline outputs.
    run_checked(["bash", "./run_pipeline.sh"], cwd=BASE)
    validate_pipeline(reference)
    assert_original_state_checks()
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
