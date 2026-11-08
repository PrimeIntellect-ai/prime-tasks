#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import subprocess
import sys
import pytest

SCRIPT_PATH = "/home/user/prepare_data.py"
OUTPUT_PATH = "/home/user/output/training_data.csv"
FASTA_PATH = "/home/user/data/sequences.fasta"
SIGNALS_PATH = "/home/user/data/signals.csv"


def parse_fasta(filepath):
    sequences = {}
    with open(filepath, 'r') as f:
        seq_id = None
        seq_data = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if seq_id is not None:
                    sequences[seq_id] = "".join(seq_data)
                seq_id = line[1:]
                seq_data = []
            else:
                seq_data.append(line)
        if seq_id is not None:
            sequences[seq_id] = "".join(seq_data)
    return sequences


def parse_signals(filepath):
    signals = {}
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            seq_id = row['SeqID']
            wn = int(row['wavenumber'])
            intensity = float(row['intensity'])
            if seq_id not in signals:
                signals[seq_id] = []
            signals[seq_id].append((wn, intensity))
    for seq_id in signals:
        signals[seq_id].sort(key=lambda x: x[0])
    return signals


def compute_expected_data():
    if not os.path.exists(FASTA_PATH) or not os.path.exists(SIGNALS_PATH):
        pytest.skip("Input files missing, cannot compute expected data.")

    sequences = parse_fasta(FASTA_PATH)
    signals = parse_signals(SIGNALS_PATH)

    motif = "CGTAGCTACG"
    expected_rows = []

    for seq_id in sorted(sequences.keys()):
        seq = sequences[seq_id]
        primer_idx = seq.find(motif)
        if primer_idx == -1:
            continue

        if seq_id not in signals:
            continue

        signal_data = signals[seq_id]
        wavenumbers = [x[0] for x in signal_data]
        intensities = [x[1] for x in signal_data]

        # Trapezoidal rule
        area = 0.0
        for i in range(len(wavenumbers) - 1):
            dx = wavenumbers[i+1] - wavenumbers[i]
            y_avg = (intensities[i] + intensities[i+1]) / 2.0
            area += dx * y_avg

        # Second derivative and sharp peaks
        sharp_peaks = 0
        for i in range(1, len(intensities) - 1):
            sec_deriv = intensities[i-1] - 2 * intensities[i] + intensities[i+1]
            if sec_deriv < -1.5:
                sharp_peaks += 1

        expected_rows.append({
            "SeqID": seq_id,
            "PrimerIndex": str(primer_idx),
            "TotalArea": f"{round(area, 1):.1f}",
            "SharpPeakCount": str(sharp_peaks)
        })

    return expected_rows


def assert_output_content(expected_rows):
    assert os.path.exists(OUTPUT_PATH), f"Expected output file not found at {OUTPUT_PATH}"

    with open(OUTPUT_PATH, 'r') as f:
        reader = csv.DictReader(f)
        actual_headers = reader.fieldnames
        actual_rows = list(reader)

    expected_headers = ["SeqID", "PrimerIndex", "TotalArea", "SharpPeakCount"]
    assert actual_headers == expected_headers, f"Headers mismatch. Expected {expected_headers}, got {actual_headers}"

    assert len(actual_rows) == len(expected_rows), f"Row count mismatch. Expected {len(expected_rows)} rows, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual["SeqID"] == expected["SeqID"], f"Row {i+1}: SeqID mismatch. Expected {expected['SeqID']}, got {actual['SeqID']}"
        assert actual["PrimerIndex"] == expected["PrimerIndex"], f"Row {i+1}: PrimerIndex mismatch for {expected['SeqID']}. Expected {expected['PrimerIndex']}, got {actual['PrimerIndex']}"

        # Allow some float formatting flexibility
        actual_area = float(actual["TotalArea"])
        expected_area = float(expected["TotalArea"])
        assert abs(actual_area - expected_area) < 0.05, f"Row {i+1}: TotalArea mismatch for {expected['SeqID']}. Expected {expected_area}, got {actual_area}"

        assert actual["SharpPeakCount"] == expected["SharpPeakCount"], f"Row {i+1}: SharpPeakCount mismatch for {expected['SeqID']}. Expected {expected['SharpPeakCount']}, got {actual['SharpPeakCount']}"


def test_00_processing_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected processing script not found at {SCRIPT_PATH}"
    assert os.path.getsize(SCRIPT_PATH) > 0, f"Processing script is empty: {SCRIPT_PATH}"


def test_01_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"Expected output file not found at {OUTPUT_PATH}"


def test_02_output_file_content():
    assert_output_content(compute_expected_data())


def test_03_script_executes_pipeline_on_fresh_inputs():
    paths = [FASTA_PATH, SIGNALS_PATH, OUTPUT_PATH]
    backups = {}
    for path in paths:
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    rng = random.SystemRandom()
    tag = ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(8))
    ids = [f"Zulu_{tag}", f"Alpha_{tag}", f"Middle_{tag}", f"Discard_{tag}"]
    motif = "CGTAGCTACG"
    primer_indexes = [rng.randint(2, 6), rng.randint(1, 5), 0]
    baselines = [rng.randint(0, 5) for _ in range(3)]
    patterns = [
        [0, 2, 5, 2, 0],
        [0, 3, 0, 3, 0],
        [0, 1, 1.5, 1, 0],
    ]
    step = rng.choice([1, 2, 3])
    start = rng.randint(10, 40)

    try:
        os.makedirs(os.path.dirname(FASTA_PATH), exist_ok=True)
        os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

        with open(FASTA_PATH, 'w') as f:
            for seq_id, index in zip(ids[:3], primer_indexes):
                sequence = ("A" * index) + motif + "TTGCA"
                f.write(f">{seq_id}\n{sequence[:8]}\n{sequence[8:]}\n")
            f.write(f">{ids[3]}\nAAAATTTTGGGGCCCC\n")

        signal_rows = []
        for seq_id, baseline, pattern in zip(ids[:3], baselines, patterns):
            for i, delta in enumerate(pattern):
                signal_rows.append((seq_id, start + i * step, baseline + delta))
        # Include a signal for the sequence that lacks the primer.
        for i in range(5):
            signal_rows.append((ids[3], start + i * step, 9))
        rng.shuffle(signal_rows)

        with open(SIGNALS_PATH, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(["SeqID", "wavenumber", "intensity"])
            writer.writerows(signal_rows)

        # Derive the expected answer before invoking the submitted script.
        expected_rows = compute_expected_data()
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"prepare_data.py failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert_output_content(expected_rows)
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
