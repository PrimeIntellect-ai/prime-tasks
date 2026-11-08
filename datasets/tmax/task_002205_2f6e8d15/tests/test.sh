#!/bin/bash
set -e
mkdir -p /logs/verifier

SIM_BACKUP=/tmp/verifier_sim_spectrometer.orig
REF_BACKUP=/tmp/verifier_reference_freqs.orig
cp -p /app/sim_spectrometer "$SIM_BACKUP"
cp -p /app/reference_freqs.csv "$REF_BACKUP"

restore_files() {
    cp -p "$SIM_BACKUP" /app/sim_spectrometer
    cp -p "$REF_BACKUP" /app/reference_freqs.csv
    rm -f /tmp/verifier_sim_count /tmp/verifier_sim_log
}
trap restore_files EXIT

cat << 'WRAPPER_EOF' > /app/sim_spectrometer
#!/usr/bin/env python3
import json
import math
import os
import sys

COUNT_FILE = "/tmp/verifier_sim_count"
LOG_FILE = "/tmp/verifier_sim_log"

if len(sys.argv) != 3:
    sys.exit(1)

input_path, output_path = sys.argv[1], sys.argv[2]
try:
    with open(COUNT_FILE) as f:
        invocation = int(f.read().strip())
except (FileNotFoundError, ValueError):
    invocation = 0

with open(COUNT_FILE, "w") as f:
    f.write(str(invocation + 1))

with open(input_path) as f:
    fasta = f.read()

with open(LOG_FILE, "a") as f:
    f.write(json.dumps({
        "invocation": invocation,
        "input_path": input_path,
        "output_path": output_path,
        "fasta": fasta,
    }) + "\n")

sequence = "".join(
    line.strip() for line in fasta.splitlines()
    if line.strip() and not line.startswith(">")
)
if not sequence or any(not ("A" <= c <= "Z") for c in sequence):
    sys.exit(2)

# Integer-bin frequencies make the expected FFT result unambiguous for a
# 1000-sample signal sampled at 1000 Hz. Each of the 15 invocations differs.
base_frequency = 70 + (sum(ord(c) for c in sequence) % 40)
frequency = base_frequency + invocation

with open(output_path, "w") as f:
    f.write("time,amplitude\n")
    for i in range(1000):
        t = i * 0.001
        amplitude = math.sin(2.0 * math.pi * frequency * t)
        f.write(f"{t:.6f},{amplitude:.12f}\n")
WRAPPER_EOF
chmod 755 /app/sim_spectrometer
rm -f /tmp/verifier_sim_count /tmp/verifier_sim_log

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import pytest
import requests
from scipy.stats import ttest_ind

URL = "http://127.0.0.1:8000/process"
COUNT_FILE = "/tmp/verifier_sim_count"
LOG_FILE = "/tmp/verifier_sim_log"


def write_reference(values):
    with open("/app/reference_freqs.csv", "w") as f:
        f.write("frequency\n")
        for value in values:
            f.write(f"{value}\n")


def reset_instrumentation():
    for path in (COUNT_FILE, LOG_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def validate_response(response, expected_mean, expected_p):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except (requests.exceptions.JSONDecodeError, json.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "mean_dominant_freq" in data, (
        f"Key 'mean_dominant_freq' missing in response: {data}"
    )
    assert "p_value" in data, f"Key 'p_value' missing in response: {data}"
    assert set(data) == {"mean_dominant_freq", "p_value"}, (
        f"Response must contain exactly the required fields, got: {data}"
    )
    assert isinstance(data["mean_dominant_freq"], (int, float)), (
        f"mean_dominant_freq must be a number, got "
        f"{type(data['mean_dominant_freq'])}"
    )
    assert isinstance(data["p_value"], (int, float)), (
        f"p_value must be a number, got {type(data['p_value'])}"
    )
    assert data["mean_dominant_freq"] > 0, (
        f"mean_dominant_freq should be positive, got "
        f"{data['mean_dominant_freq']}"
    )
    assert 0.0 <= data["p_value"] <= 1.0, (
        f"p_value should be between 0 and 1, got {data['p_value']}"
    )
    assert math.isclose(data["mean_dominant_freq"], expected_mean,
                        rel_tol=1e-7, abs_tol=1e-7), (
        f"Wrong mean dominant frequency: expected {expected_mean}, got "
        f"{data['mean_dominant_freq']}"
    )
    assert math.isclose(data["p_value"], expected_p,
                        rel_tol=1e-6, abs_tol=1e-9), (
        f"Wrong Welch t-test p-value: expected {expected_p}, got "
        f"{data['p_value']}"
    )


def validate_invocations(expected_sequence):
    assert os.path.exists(COUNT_FILE), "The required simulator was not invoked"
    with open(COUNT_FILE) as f:
        count = int(f.read().strip())
    assert count == 15, f"Simulator must be invoked exactly 15 times, got {count}"

    assert os.path.exists(LOG_FILE), "Simulator invocation log was not created"
    with open(LOG_FILE) as f:
        records = [json.loads(line) for line in f if line.strip()]
    assert len(records) == 15, f"Expected 15 simulator records, got {len(records)}"
    assert [r["invocation"] for r in records] == list(range(15))

    output_paths = [r["output_path"] for r in records]
    assert len(set(output_paths)) == 15, (
        "The 15 simulator runs must generate 15 distinct signal CSV files"
    )

    input_paths = [r["input_path"] for r in records]
    for record in records:
        fasta = record["fasta"]
        lines = [line.strip() for line in fasta.splitlines() if line.strip()]
        assert lines and lines[0].startswith(">"), (
            f"Simulator input is not standard FASTA: {fasta!r}"
        )
        parsed_sequence = "".join(
            line for line in lines[1:] if not line.startswith(">")
        )
        assert parsed_sequence == expected_sequence, (
            f"SEQRES was not converted correctly: expected {expected_sequence}, "
            f"got {parsed_sequence}"
        )


def run_case(pdb_data, expected_sequence, references):
    reset_instrumentation()
    write_reference(references)

    base = 70 + (sum(ord(c) for c in expected_sequence) % 40)
    dominant_frequencies = [float(base + i) for i in range(15)]
    expected_mean = sum(dominant_frequencies) / len(dominant_frequencies)
    expected_p = float(ttest_ind(
        dominant_frequencies, references, equal_var=False
    ).pvalue)

    try:
        response = requests.post(
            URL, json={"pdb_data": pdb_data}, timeout=60
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(
            f"Failed to connect to or read from API at {URL}. "
            f"Ensure the service is running. Error: {exc}"
        )

    validate_response(response, expected_mean, expected_p)
    validate_invocations(expected_sequence)


def test_api_process_endpoint_full_pipeline():
    cases = [
        (
            """HEADER    FIRST MOCK PDB
SEQRES   1 A   10  ALA CYS ASP GLU PHE GLY HIS ILE LYS LEU
""",
            "ACDEFGHIKL",
            [94.0 + (i % 13) * 0.75 for i in range(50)],
        ),
        (
            """HEADER    SECOND MOCK PDB
SEQRES   1 A   10  MET ASN PRO GLN ARG SER THR VAL TRP TYR
""",
            "MNPQRSTVWY",
            [105.0 + (i % 9) * 0.6 for i in range(50)],
        ),
    ]
    for pdb_data, sequence, references in cases:
        run_case(pdb_data, sequence, references)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
