#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

import numpy as np
from scipy.optimize import minimize_scalar

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "viral_samples.csv")
FASTA_PATH = os.path.join(HOME, "reference.fasta")
REPORT_PATH = os.path.join(HOME, "primer_report.json")
REGIONS = {"A": (100, 200), "B": (300, 400), "C": (500, 600)}


def expected_from_inputs(csv_path, fasta_path):
    with open(csv_path, newline="") as f:
        rows = list(csv.DictReader(f))

    times = np.array([float(row["time_days"]) for row in rows], dtype=float)
    fitted = {}
    for region in REGIONS:
        values = np.array(
            [float(row[f"region_{region}_mut_freq"]) for row in rows],
            dtype=float,
        )

        def objective(k):
            predicted = 1.0 - np.exp(-k * times)
            return float(np.sum((predicted - values) ** 2))

        result = minimize_scalar(objective, bounds=(0.0, 2.0), method="bounded")
        assert result.success
        fitted[region] = float(result.x)

    best_region = min(REGIONS, key=lambda region: fitted[region])

    sequences = []
    current = []
    with open(fasta_path) as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current:
                    sequences.append("".join(current).upper())
                    current = []
            else:
                current.append(line)
        if current:
            sequences.append("".join(current).upper())

    assert sequences, "Reference FASTA has no sequence"
    start, end = REGIONS[best_region]
    window = sequences[0][start:end]
    assert len(window) == 100

    best_primer = None
    best_gc_count = None
    for index in range(len(window) - 19):
        primer = window[index:index + 20]
        gc_count = primer.count("G") + primer.count("C")
        distance = abs(gc_count - 10)
        if best_primer is None or distance < abs(best_gc_count - 10):
            best_primer = primer
            best_gc_count = gc_count

    return {
        "best_region": best_region,
        "k_value": round(fitted[best_region], 4),
        "primer_sequence": best_primer,
        "gc_content": round(best_gc_count * 100.0 / 20.0, 2),
    }


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Missing file: {REPORT_PATH}"
    with open(REPORT_PATH) as f:
        return json.load(f)


def validate_report(report, expected):
    required_keys = {"best_region", "k_value", "primer_sequence", "gc_content"}
    missing_keys = required_keys - set(report)
    assert not missing_keys, f"Missing keys in JSON report: {missing_keys}"

    assert report["best_region"] == expected["best_region"]
    assert isinstance(report["k_value"], (int, float))
    assert not isinstance(report["k_value"], bool)
    assert math.isclose(
        report["k_value"], expected["k_value"], abs_tol=0.00005
    )

    assert isinstance(report["primer_sequence"], str)
    assert report["primer_sequence"] == expected["primer_sequence"]
    assert len(report["primer_sequence"]) == 20
    assert report["primer_sequence"] == report["primer_sequence"].upper()

    assert isinstance(report["gc_content"], (int, float))
    assert not isinstance(report["gc_content"], bool)
    assert math.isclose(
        report["gc_content"], expected["gc_content"], abs_tol=0.005
    )


def make_alternate_inputs():
    times = np.array([0, 3, 7, 12, 18, 25, 33], dtype=float)
    rates = {"A": 0.007, "B": 0.031, "C": 0.080}
    lines = ["time_days,region_A_mut_freq,region_B_mut_freq,region_C_mut_freq"]
    for t in times:
        values = [1.0 - math.exp(-rates[r] * t) for r in ("A", "B", "C")]
        lines.append(f"{t:g},{values[0]:.8f},{values[1]:.8f},{values[2]:.8f}")
    csv_bytes = ("\n".join(lines) + "\n").encode()

    sequence = list("A" * 1000)
    sequence[130:140] = list("CCCCCCCCCC")
    fasta_bytes = (
        ">alternate Dynamic Viral Reference\n" + "".join(sequence) + "\n"
    ).encode()
    return csv_bytes, fasta_bytes


def run_script(path):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", path],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, (
        f"Script {path} failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_complete_solution():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py") and os.path.isfile(path) and not os.path.islink(path):
                scripts.append(path)
    assert scripts, "No Python script was created under /home/user"

    original_csv = open(CSV_PATH, "rb").read()
    original_fasta = open(FASTA_PATH, "rb").read()
    original_report = open(REPORT_PATH, "rb").read() if os.path.isfile(REPORT_PATH) else None

    original_expected = expected_from_inputs(CSV_PATH, FASTA_PATH)
    initial_report = load_report()
    validate_report(initial_report, original_expected)

    # Preserve all assertions made by the original verifier.
    assert initial_report["best_region"] == "B"
    assert isinstance(initial_report["k_value"], (int, float))
    assert math.isclose(initial_report["k_value"], 0.0120, abs_tol=0.0005)
    assert isinstance(initial_report["primer_sequence"], str)
    assert initial_report["primer_sequence"] == "ATCGATCGATCGATCGATCG"
    assert isinstance(initial_report["gc_content"], (int, float))
    assert math.isclose(initial_report["gc_content"], 50.0, abs_tol=0.05)

    alternate_csv, alternate_fasta = make_alternate_inputs()
    selected_script = None
    failures = []
    try:
        for script in sorted(scripts):
            try:
                open(CSV_PATH, "wb").write(alternate_csv)
                open(FASTA_PATH, "wb").write(alternate_fasta)
                alternate_expected = expected_from_inputs(CSV_PATH, FASTA_PATH)
                run_script(script)
                validate_report(load_report(), alternate_expected)
                selected_script = script
                break
            except Exception as exc:
                failures.append(f"{script}: {exc}")
    finally:
        open(CSV_PATH, "wb").write(original_csv)
        open(FASTA_PATH, "wb").write(original_fasta)
        if selected_script is not None:
            run_script(selected_script)
        elif original_report is not None:
            open(REPORT_PATH, "wb").write(original_report)

    assert selected_script is not None, (
        "No submitted Python script recomputed the report for alternate input data. "
        + " | ".join(failures)
    )

    final_report = load_report()
    validate_report(final_report, original_expected)

    # Recheck the original verifier's concrete expectations after executing the script.
    assert final_report["best_region"] == "B"
    assert math.isclose(final_report["k_value"], 0.0120, abs_tol=0.0005)
    assert final_report["primer_sequence"] == "ATCGATCGATCGATCGATCG"
    assert math.isclose(final_report["gc_content"], 50.0, abs_tol=0.05)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
