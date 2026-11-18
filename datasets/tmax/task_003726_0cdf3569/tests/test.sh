#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import subprocess

HOME = "/home/user"
GO_FILE = f"{HOME}/integrate_fixed.go"
CSV_FILE = f"{HOME}/partials.csv"
PROFILE_FILE = f"{HOME}/cpu.prof"
RESULT_FILE = f"{HOME}/result.txt"
PLOT_SCRIPT = f"{HOME}/plot.py"
PNG_FILE = f"{HOME}/partials.png"


def run(cmd, timeout=600, env=None):
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
    assert proc.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return proc


def read_csv(path):
    with open(path, "r", encoding="utf-8") as f:
        raw_lines = f.readlines()

    assert len(raw_lines) == 16, f"Expected exactly 16 lines in {path}, found {len(raw_lines)}."
    parsed = []
    pattern = re.compile(r"^(\d+),(-?(?:\d+\.\d{15}))\n?$")
    for i, line in enumerate(raw_lines):
        match = pattern.fullmatch(line)
        assert match, f"Line {i} is not formatted exactly as %d,%.15f: {line!r}"
        assert match.group(1) == str(i), (
            f"Expected line {i} to start with chunk ID {i}, got {match.group(1)}."
        )
        value = float(match.group(2))
        assert value == value and abs(value) != float("inf"), f"Non-finite partial on line {i}."
        parsed.append((i, match.group(2)))
    return parsed


def validate_profile():
    assert os.path.isfile(PROFILE_FILE), "The Go run did not create cpu.prof."
    assert os.path.getsize(PROFILE_FILE) > 100, "cpu.prof is empty or implausibly small."
    proc = run(["go", "tool", "pprof", "-top", PROFILE_FILE], timeout=60)
    combined = proc.stdout + proc.stderr
    assert "Type: cpu" in combined or "Duration:" in combined, "cpu.prof is not a usable CPU profile."


def run_submission():
    for path in (PROFILE_FILE, CSV_FILE):
        if os.path.exists(path):
            os.remove(path)
    proc = run(["go", "run", GO_FILE])
    output = proc.stdout.strip()
    assert re.fullmatch(r"-?\d+\.\d{15}", output), (
        f"Program must print exactly one number using %.15f; got {proc.stdout!r}"
    )
    csv_rows = read_csv(CSV_FILE)
    validate_profile()
    return output, csv_rows


def test_complete_solution():
    expected_files = [
        GO_FILE,
        PROFILE_FILE,
        CSV_FILE,
        PNG_FILE,
        RESULT_FILE,
        PLOT_SCRIPT,
    ]
    for path in expected_files:
        assert os.path.exists(path), f"Expected file {path} is missing."
        assert os.path.isfile(path), f"Expected {path} to be a file."

    with open(RESULT_FILE, "r", encoding="utf-8") as f:
        saved_result = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{15}", saved_result), (
        f"Expected result.txt to contain one %.15f number, got {saved_result!r}."
    )

    with open(GO_FILE, "r", encoding="utf-8") as f:
        source = f.read()
    # These checks retain implementation requirements that cannot be inferred solely
    # from the final rounded number.
    for required in (
        '"runtime/pprof"', "StartCPUProfile", "StopCPUProfile",
        "10000000", "16", "math.Sin", "sync.WaitGroup",
        "partials.csv", "cpu.prof",
    ):
        assert required in source, f"integrate_fixed.go is missing required implementation element {required!r}."
    assert re.search(r"\bgo\s+func\b", source), "The integration must use worker goroutines."

    # Execute twice, preserving the original determinism assertion while also
    # requiring each execution to regenerate the CSV and a parseable CPU profile.
    out1, rows1 = run_submission()
    out2, rows2 = run_submission()
    assert out1 == out2, "The Go program is not deterministic. Output differs between runs."
    assert rows1 == rows2, "Ordered partial sums differ between runs."
    assert out1 == saved_result, (
        f"The output of the Go program ({out1}) does not match result.txt ({saved_result})."
    )

    # Build and execute an independent ordered-reduction implementation in the
    # verifier, then compare every partial and the final formatted result exactly.
    reference_source = r'''package main
import (
    "fmt"
    "math"
    "os"
    "sync"
)
func signal(x float64) float64 {
    sum := 0.0
    for k := 1.0; k <= 100.0; k++ {
        sum += math.Sin(k*x) / k
    }
    return sum
}
func main() {
    N := 10000000
    G := 16
    a, b := 0.0, math.Pi
    dx := (b-a)/float64(N)
    partials := make([]float64, G)
    var wg sync.WaitGroup
    chunk := N/G
    for i := 0; i < G; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            startIdx := id*chunk
            endIdx := startIdx+chunk
            if id == G-1 { endIdx = N }
            partial := 0.0
            for j := startIdx; j < endIdx; j++ {
                x1 := a+float64(j)*dx
                x2 := a+float64(j+1)*dx
                partial += (signal(x1)+signal(x2))/2.0*dx
            }
            partials[id] = partial
        }(i)
    }
    wg.Wait()
    f, err := os.Create("/tmp/reference_partials.csv")
    if err != nil { panic(err) }
    total := 0.0
    for i := 0; i < G; i++ {
        fmt.Fprintf(f, "%d,%.15f\n", i, partials[i])
        total += partials[i]
    }
    if err := f.Close(); err != nil { panic(err) }
    fmt.Printf("%.15f\n", total)
}
'''
    reference_file = "/tmp/reference_integrate.go"
    with open(reference_file, "w", encoding="utf-8") as f:
        f.write(reference_source)
    ref_proc = run(["go", "run", reference_file])
    reference_output = ref_proc.stdout.strip()
    reference_rows = read_csv("/tmp/reference_partials.csv")

    assert out2 == reference_output, (
        f"Computed total {out2} does not equal the required ordered reduction {reference_output}."
    )
    assert rows2 == reference_rows, "partials.csv does not contain the actual per-chunk trapezoidal sums."

    # Require plot.py itself to regenerate a real PNG from the CSV.
    with open(PLOT_SCRIPT, "r", encoding="utf-8") as f:
        plot_source = f.read()
    assert "partials.csv" in plot_source, "plot.py must read partials.csv."
    assert "partials.png" in plot_source, "plot.py must write partials.png."
    assert "bar" in plot_source, "plot.py must generate a bar chart."
    if os.path.exists(PNG_FILE):
        os.remove(PNG_FILE)
    run(["python3", PLOT_SCRIPT], timeout=120)
    assert os.path.isfile(PNG_FILE), "Running plot.py did not create partials.png."
    assert os.path.getsize(PNG_FILE) > 1000, "partials.png is implausibly small."
    with open(PNG_FILE, "rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "partials.png is not a PNG file."
    width, height = struct.unpack(">II", header[16:24])
    assert width > 0 and height > 0, "partials.png has invalid dimensions."
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
