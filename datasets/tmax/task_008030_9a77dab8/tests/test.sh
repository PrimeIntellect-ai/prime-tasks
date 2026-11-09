#!/bin/bash
set +e
mkdir -p /logs/verifier

python3 <<'PY'
import csv
import math
import os
import re
import subprocess
import sys
from collections import defaultdict

SOURCE = "/home/user/inference.rs"
EXECUTABLE = "/home/user/inference"
OUTPUT = "/home/user/best_category.txt"
DATASET = "/home/user/embeddings.csv"
VERIFIED_EXECUTABLE = "/tmp/verified_inference"

try:
    # Preserve the original assertions.
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing. Did you write the Rust program?"
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing. Did you run your Rust program to generate the output?"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        original_content = f.read().strip()
    expected_original = "gamma,5.0000"
    assert expected_original in original_content, \
        f"Expected '{expected_original}' in {OUTPUT}, but got '{original_content}'"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), \
        f"Executable {EXECUTABLE} not found or not executable. Did you compile with rustc?"

    # A Rust compilation must produce a native executable, not an arbitrary executable script.
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled native executable"

    # Derive the required winner from the supplied CSV rather than trusting a fixed answer.
    totals = defaultdict(lambda: [0.0, 0.0, 0.0, 0])
    with open(DATASET, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if len(row) != 4:
                continue
            try:
                values = [float(row[1]), float(row[2]), float(row[3])]
            except ValueError:
                continue
            if not all(math.isfinite(v) for v in values):
                continue
            entry = totals[row[0]]
            for i, value in enumerate(values):
                entry[i] += value
            entry[3] += 1

    assert totals, "No valid rows were found in embeddings.csv"
    scores = {}
    for category, (v1, v2, v3, count) in totals.items():
        means = (v1 / count, v2 / count, v3 / count)
        scores[category] = means[0] * 0.25 + means[1] * 0.5 - means[2] * 0.25
    winner = max(scores, key=scores.get)
    expected = f"{winner},{scores[winner]:.4f}"

    # Check that the requested benchmark and fixed weights are represented in the program.
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    compact = re.sub(r"[\s_]", "", source_text.lower())
    has_million = any(token in compact for token in (
        "1000000", "1e6", "1000*1000", "10usize.pow(6)", "10u64.pow(6)", "10u32.pow(6)"
    ))
    assert has_million, "The Rust source does not define the required 1,000,000 benchmark iterations"
    assert re.search(r"(?<![\d.])(?:0?\.25)(?!\d)", source_text), \
        "The Rust source does not contain the 0.25 weight"
    assert re.search(r"(?<![\d.])(?:0?\.5)(?!\d)", source_text), \
        "The Rust source does not contain the 0.5 weight"
    assert re.search(r"-\s*(?:0?\.25)(?!\d)", source_text), \
        "The Rust source does not contain the -0.25 weight"

    # Compile the submitted source ourselves and execute that fresh artifact. Remove the
    # old answer first so a stale or manually-created file cannot satisfy verification.
    compile_result = subprocess.run(
        ["rustc", SOURCE, "-O", "-o", VERIFIED_EXECUTABLE],
        cwd="/home/user", text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60
    )
    assert compile_result.returncode == 0, f"Rust compilation failed:\n{compile_result.stderr}"
    with open(VERIFIED_EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Freshly compiled artifact is not an ELF executable"

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_result = subprocess.run(
        [VERIFIED_EXECUTABLE], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert run_result.returncode == 0, \
        f"The compiled Rust program failed with status {run_result.returncode}:\n{run_result.stderr}"
    assert os.path.isfile(OUTPUT), \
        f"Running the compiled program did not create {OUTPUT}"

    with open(OUTPUT, "r", encoding="utf-8") as f:
        generated = f.read().strip()
    assert generated == expected, f"Expected exact generated output '{expected}', but got '{generated}'"

    stdout = run_result.stdout.strip()
    assert stdout, "The Rust program did not print the benchmark elapsed time to stdout"
    time_pattern = re.compile(
        r"(?:\b(?:elapsed|duration|time)\b[^\n]*\d|\d+(?:\.\d+)?\s*(?:ns|us|µs|ms|s|sec|secs|second|seconds)\b)",
        re.IGNORECASE,
    )
    assert time_pattern.search(stdout), \
        f"Stdout does not appear to contain an elapsed-time measurement: {stdout!r}"

except Exception as exc:
    print(f"VERIFICATION FAILED: {exc}", file=sys.stderr)
    sys.exit(1)

print("All verification checks passed.")
PY
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
